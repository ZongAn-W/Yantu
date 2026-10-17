import 'package:sembast/sembast.dart';
import '../../shared/models/planner_models.dart';
import 'file_transfer_repository.dart';
import 'local_database.dart';
import 'planner_json.dart';
import 'storage_repository.dart';

class SembastStorageRepository implements StorageRepository {
  SembastStorageRepository({LocalDatabase? database, this.transfer})
    : database = database ?? LocalDatabase();
  final LocalDatabase database;
  final FileTransferRepository? transfer;
  final store = StoreRef<String, Object?>('planner');

  StorageSnapshot _decode(Object? raw) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['data'] is! Map ||
        raw['metadata'] is! Map) {
      throw const FormatException('本地数据或同步元数据格式异常');
    }
    final data = PlannerData.fromJson(JsonMap.from(raw['data'] as Map));
    validatePlanner(data);
    final metadata = StorageMetadata.fromJson(
      JsonMap.from(raw['metadata'] as Map),
    );
    if (metadata.base != null) validatePlanner(metadata.base!);
    return StorageSnapshot(data: data, metadata: metadata);
  }

  JsonMap _encode(PlannerData data, StorageMetadata metadata) => {
    'version': 1,
    'data': data.toJson(),
    'metadata': metadata.toJson(),
  };

  Future<StorageSnapshot> _load(DatabaseClient db, String key) async {
    final raw = await store.record(key).get(db),
        backup = await store.record('$key:backup').get(db);
    if (raw == null && backup == null) {
      return const StorageSnapshot(data: null, metadata: StorageMetadata());
    }
    try {
      return _decode(raw);
    } catch (mainError) {
      try {
        final restored = _decode(backup);
        return StorageSnapshot(
          data: restored.data,
          metadata: restored.metadata,
          recovered: true,
          error: '主数据无法读取，已载入最近备份。',
        );
      } catch (_) {
        return StorageSnapshot(
          data: null,
          metadata: const StorageMetadata(),
          error: '主数据和备份都无法读取，已停止编辑和同步：$mainError',
        );
      }
    }
  }

  @override
  Future<StorageSnapshot> load(String userKey) async {
    try {
      final db = await database.database;
      final result = await db.transaction((txn) => _load(txn, userKey));
      final recovered = await StoreRef<String, bool>.main()
          .record('__database_recovered')
          .get(db);
      return recovered == true
          ? StorageSnapshot(
              data: result.data,
              metadata: result.metadata,
              recovered: true,
              error: '本地文件损坏，已从数据库备份恢复。',
            )
          : result;
    } catch (error) {
      return StorageSnapshot(
        data: null,
        metadata: const StorageMetadata(),
        error: '本地数据库不可读取：$error',
      );
    }
  }

  @override
  Future<void> save(
    String userKey,
    PlannerData data,
    StorageMetadata metadata, {
    bool recovery = false,
  }) async {
    validatePlanner(data);
    await database.write(
      (db) => db.transaction((txn) async {
        final record = store.record(userKey),
            previous = await store.record(userKey).get(txn);
        if (previous != null) {
          try {
            final valid = _decode(previous);
            if (valid.data != data) {
              await store.record('$userKey:backup').put(txn, previous);
            }
          } catch (_) {
            if (!recovery) {
              final backup = await store.record('$userKey:backup').get(txn);
              _decode(backup);
            }
            await store
                .record(
                  '$userKey:corrupt:${DateTime.now().microsecondsSinceEpoch}',
                )
                .put(txn, previous);
          }
        } else if (!recovery) {
          final backup = await store.record('$userKey:backup').get(txn);
          if (backup != null) _decode(backup);
        }
        await record.put(txn, _encode(data, metadata));
      }),
      recovery: recovery,
    );
  }

  @override
  Future<String?> exportJson(PlannerData data) async {
    validatePlanner(data);
    if (transfer != null && !await transfer!.exportJson(data)) return null;
    return data.toJsonString();
  }

  @override
  Future<PlannerData?> importJson() async => transfer?.importJson();

  @override
  Future<void> restore(String userKey, PlannerData data) async {
    final previous = await load(userKey);
    await save(
      userKey,
      data,
      previous.metadata.copyWith(
        pending: true,
        updatedAt: DateTime.now().toUtc(),
      ),
      recovery: true,
    );
  }

  @override
  Future<void> markPending(String userKey, bool pending) async {
    await database.write(
      (db) => db.transaction((txn) async {
        final snapshot = await _load(txn, userKey);
        if (snapshot.data == null) {
          throw StateError(snapshot.error ?? '没有可保存的计划');
        }
        await store
            .record(userKey)
            .put(
              txn,
              _encode(
                snapshot.data!,
                snapshot.metadata.copyWith(
                  pending: pending,
                  updatedAt: DateTime.now().toUtc(),
                ),
              ),
            );
      }),
    );
  }

  @override
  Future<StorageSnapshot> recoverFromBackup(String userKey) async {
    await database.write(
      (db) => db.transaction((txn) async {
        final backup = await store.record('$userKey:backup').get(txn);
        final checked = _decode(backup);
        final current = await store.record(userKey).get(txn);
        if (current != null) {
          await store
              .record(
                '$userKey:before-recovery:${DateTime.now().microsecondsSinceEpoch}',
              )
              .put(txn, current);
        }
        await store
            .record(userKey)
            .put(txn, _encode(checked.data!, checked.metadata));
      }),
    );
    final restored = await load(userKey);
    return StorageSnapshot(
      data: restored.data,
      metadata: restored.metadata,
      recovered: true,
    );
  }
}
