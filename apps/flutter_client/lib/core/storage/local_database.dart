import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'database_factory.dart';

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

  /// 测试会注入 opener/backup；只有真实文件数据库或显式 backup 才能做物理备份。
  bool get _canBackup => backup != null || _opener == null;

  Future<Database> get database =>
      _database ??= _open().catchError((Object error) {
        _database = null;
        throw error;
      });
  Future<Database> _open() async {
    if (_opener != null) return _opener();
    return openPlannerDatabase(
      kIsWeb
          ? name
          : path.join((await getApplicationSupportDirectory()).path, name),
    );
  }

  Future<Database> _recover() async {
    if (_opener != null) return _opener();
    return recoverPlannerDatabase(
      kIsWeb
          ? name
          : path.join((await getApplicationSupportDirectory()).path, name),
    );
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

  Future<T> write<T>(
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
      // 恢复类写入必须留下写入前的原始快照；普通写入按阈值节流。
      await _backupIfNeeded(db, force: recovery);
      return action(db);
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> close() async {
    await _writes;
    if (_database == null) return;
    final db = await _database!;
    await _flushBackupOnClose(db);
    await db.close();
  }
}
