import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'database_factory.dart';

/// Live records and current recovery data are clean, but damaged historical
/// files need an explicit manual decision because their content is unreadable.
class LocalAccountCleanupIncomplete implements Exception {
  LocalAccountCleanupIncomplete(Iterable<String> archivePaths)
    : archivePaths = List.unmodifiable(archivePaths);

  final List<String> archivePaths;

  @override
  String toString() => '账号数据已清理，但有 ${archivePaths.length} 个历史损坏文件需要手动清理';
}

/// 本机 Sembast 数据库入口：串行化写入，并在写前提供“物理全库备份”作为损坏恢复兜底。
///
/// 物理备份（导出整库 + 原子替换 `*.recovery.json`）在历史数据较大时开销明显，
/// 而计时 checkpoint 每分钟都会写本机快照，因此备份按 [backupInterval] 与
/// [maxWritesBetweenBackups] 双重阈值节流：
///
/// - 数据本身仍然逐次写入（事务性），计时 checkpoint 的落盘可靠性不依赖备份；
/// - 首次写入、恢复类写入（`recovery: true`）、数据库重建后的写入会强制备份，
///   保证恢复/损坏修复前有一份有效快照；
/// - 正常写入期间恢复文件最多滞后 [backupInterval] 或
///   [maxWritesBetweenBackups] 次写入；
/// - [close] 会为仍然滞后的恢复文件补做一次尽力而为的备份。
class LocalDatabase {
  LocalDatabase({
    this.name = 'sjtu-study-planner.db',
    Future<Database> Function()? open,
    this.backup,
    this.backupInterval = const Duration(minutes: 2),
    this.maxWritesBetweenBackups = 20,
    DateTime Function()? now,
  }) : _opener = open,
       _now = now ?? DateTime.now;
  final String name;
  final Future<Database> Function()? _opener;
  final Future<void> Function(Database)? backup;

  /// 两次物理备份之间的最小时间间隔。
  final Duration backupInterval;

  /// 两次物理备份之间允许的最大写入次数（限制恢复文件滞后写入量）。
  final int maxWritesBetweenBackups;

  final DateTime Function() _now;
  Future<Database>? _database;
  Future<void> _writes = Future.value();
  DateTime? _lastBackupAt;
  int _writesSinceBackup = 0;
  Database? _lastBackupDatabase;
  Object? _accountCleanupFailure;
  static final _deletedAccounts = StoreRef<String, Map<String, Object?>>(
    '__deleted-accounts',
  );

  /// 测试会注入 opener/backup；只有真实文件数据库或显式 backup 才能做物理备份。
  bool get _canBackup => backup != null || _opener == null;

  /// Startup keeps the sanitized live database available even if refreshing an
  /// archive fails. Explicit [purgeAccountData] still throws to its caller.
  Object? get accountCleanupFailure => _accountCleanupFailure;

  Future<Database> get database =>
      _database ??= _open().catchError((Object error) {
        _database = null;
        throw error;
      });
  Future<Database> _open() async {
    final db = _opener != null
        ? await _opener()
        : await openPlannerDatabase(
            kIsWeb
                ? name
                : path.join(
                    (await getApplicationSupportDirectory()).path,
                    name,
                  ),
          );
    return _prepareDatabase(db);
  }

  Future<Database> _recover() async {
    final db = _opener != null
        ? await _opener()
        : await recoverPlannerDatabase(
            kIsWeb
                ? name
                : path.join(
                    (await getApplicationSupportDirectory()).path,
                    name,
                  ),
          );
    return _prepareDatabase(db);
  }

  Future<Database> _prepareDatabase(Database db) async {
    try {
      await db.checkForChanges();
      if ((await _deletedAccounts.find(db)).isEmpty) return db;
      // Never expose a handle if even live-record sanitization cannot finish.
      await _sanitizeDeletedAccounts(db);
    } catch (_) {
      await db.close();
      rethrow;
    }
    // This uses the opened handle directly, never the [database] getter, so
    // startup retry cannot recursively attempt to open itself.
    try {
      await _finishAccountCleanup(db);
    } catch (error) {
      _accountCleanupFailure = error;
      debugPrint('本地账号清理仍待完成，保留删除标记并将在下次打开时重试：$error');
    }
    return db;
  }

  Future<void> _runBackup(Database db) async {
    if (backup != null) {
      await backup!(db);
    } else {
      await backupPlannerDatabase(db);
    }
    _lastBackupAt = _now();
    _lastBackupDatabase = db;
    _writesSinceBackup = 0;
  }

  Future<void> _backupIfNeeded(Database db, {required bool force}) async {
    if (!_canBackup) return;
    final last = _lastBackupAt;
    final due =
        force ||
        last == null ||
        !identical(_lastBackupDatabase, db) ||
        _writesSinceBackup >= maxWritesBetweenBackups ||
        _now().difference(last) >= backupInterval;
    if (!due) {
      _writesSinceBackup++;
      return;
    }
    await _runBackup(db);
  }

  /// 关闭前为仍滞后的恢复文件补一次备份；失败不阻塞退出（主数据已逐次落盘）。
  Future<void> _flushBackupOnClose(Database db) async {
    if (!_canBackup || _writesSinceBackup == 0) return;
    try {
      await _runBackup(db);
    } catch (error) {
      debugPrint('关闭时刷新本地备份失败，主数据库保持可用：$error');
    }
  }

  Future<T> _enqueue<T>(
    Future<T> Function(Database) action, {
    bool recovery = false,
  }) {
    final next = _writes.then((_) async {
      Database db;
      try {
        db = await database;
      } catch (_) {
        if (!recovery) rethrow;
        db = await _recover();
        _database = Future.value(db);
      }
      return action(db);
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// All writers share this guard, including writes queued before deletion and
  /// writes from another tab using the same persisted database.
  Future<T> write<T>(
    Future<T> Function(Database) action, {
    bool recovery = false,
  }) => _enqueue((db) async {
    await db.checkForChanges();
    final sanitizedBefore = await _sanitizeDeletedAccounts(db);
    // 恢复类写入必须留下写入前的原始快照；普通写入按阈值节流。
    await _backupIfNeeded(db, force: recovery);
    try {
      return await action(db);
    } finally {
      final sanitizedAfter = await _sanitizeDeletedAccounts(db);
      if (sanitizedBefore || sanitizedAfter) {
        await db.compact();
        if (_canBackup) await _runBackup(db);
      }
    }
  }, recovery: recovery);

  /// Commit the deletion marker first so failed backup work can be retried and
  /// future stale writes cannot persist this account's data again.
  Future<void> purgeAccountData({
    required String scope,
    required String userId,
  }) => _enqueue((db) async {
    await db.checkForChanges();
    await db.transaction((txn) async {
      await _deletedAccounts.record(jsonEncode([scope, userId])).put(txn, {
        'scope': scope,
        'userId': userId,
      });
      await _sanitizeDeletedAccountsIn(txn);
    });
    try {
      await _finishAccountCleanup(db);
    } catch (error) {
      _accountCleanupFailure = error;
      rethrow;
    }
  });

  Future<void> _finishAccountCleanup(Database db) async {
    await _sanitizeDeletedAccounts(db);
    // Sembast's append-only native journal otherwise retains old record values.
    await db.compact();
    if (_canBackup) await _runBackup(db);
    final deleted = await _deletedAccounts.find(db);
    final unreadable = await scrubPlannerDatabaseArchives(
      db,
      (exported) => _sanitizeExport(
        exported,
        deleted.map((record) => record.value).toList(),
      ),
    );
    if (unreadable.isNotEmpty) {
      throw LocalAccountCleanupIncomplete(unreadable);
    }
    _accountCleanupFailure = null;
  }

  static bool _belongsToAccount(
    String store,
    Object? key,
    Object? value,
    Map<String, Object?> account,
  ) {
    final scope = account['scope'], userId = account['userId'];
    if (scope is! String || userId is! String) return false;
    if (store == 'identity') {
      return key == scope && value is Map && value['id'] == userId;
    }
    if (store != 'planner' && store != 'study-timers') return false;
    final prefix =
        'sjtu-study-planner:items-v2:${Uri.encodeComponent(scope)}:cloud:$userId';
    return key == prefix || (key is String && key.startsWith('$prefix:'));
  }

  Future<bool> _sanitizeDeletedAccounts(Database db) =>
      db.transaction(_sanitizeDeletedAccountsIn);

  Future<bool> _sanitizeDeletedAccountsIn(DatabaseClient client) async {
    final deleted = await _deletedAccounts.find(client);
    if (deleted.isEmpty) return false;
    var changed = false;
    for (final name in ['planner', 'study-timers', 'identity']) {
      final store = StoreRef<String, Object?>(name);
      for (final record in await store.find(client)) {
        if (deleted.any(
          (account) =>
              _belongsToAccount(name, record.key, record.value, account.value),
        )) {
          await store.record(record.key).delete(client);
          changed = true;
        }
      }
    }
    return changed;
  }

  static Map<String, Object?> _sanitizeExport(
    Map<String, Object?> exported,
    List<Map<String, Object?>> deleted,
  ) {
    if (exported['sembast_export'] != 1 || exported['stores'] is! List) {
      throw const FormatException('无法清理未知格式的历史数据库备份');
    }
    final stores = <Map<String, Object?>>[];
    for (final raw in exported['stores'] as List) {
      final store = Map<String, Object?>.from(raw as Map);
      final name = store['name'] as String;
      final keys = store['keys'] as List, values = store['values'] as List;
      if (keys.length != values.length) {
        throw const FormatException('历史数据库备份记录不完整');
      }
      final keptKeys = <Object?>[], keptValues = <Object?>[];
      for (var i = 0; i < keys.length; i++) {
        if (!deleted.any(
          (account) => _belongsToAccount(name, keys[i], values[i], account),
        )) {
          keptKeys.add(keys[i]);
          keptValues.add(values[i]);
        }
      }
      stores.add({...store, 'keys': keptKeys, 'values': keptValues});
    }
    // A restored historical snapshot must also reject future stale writes.
    final tombstones = stores.where(
      (store) => store['name'] == '__deleted-accounts',
    );
    final marker = tombstones.isEmpty
        ? <String, Object?>{
            'name': '__deleted-accounts',
            'keys': <Object?>[],
            'values': <Object?>[],
          }
        : tombstones.single;
    if (tombstones.isEmpty) stores.add(marker);
    final keys = marker['keys'] as List, values = marker['values'] as List;
    for (final account in deleted) {
      final key = jsonEncode([account['scope'], account['userId']]);
      if (!keys.contains(key)) {
        keys.add(key);
        values.add(account);
      }
    }
    return {...exported, 'stores': stores};
  }

  Future<void> close() async {
    await _writes;
    if (_database == null) return;
    final db = await _database!;
    await _flushBackupOnClose(db);
    await db.close();
  }
}
