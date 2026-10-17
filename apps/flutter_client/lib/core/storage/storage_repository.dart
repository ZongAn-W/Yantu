import '../../shared/models/planner_models.dart';

typedef StorageMetadata = SyncMetadata;

class StorageSnapshot {
  const StorageSnapshot({
    required this.data,
    required this.metadata,
    this.recovered = false,
    this.error,
  });

  final PlannerData? data;
  final StorageMetadata metadata;
  final bool recovered;
  final String? error;
}

abstract interface class StorageRepository {
  Future<StorageSnapshot> load(String userKey);

  Future<void> save(
    String userKey,
    PlannerData data,
    StorageMetadata metadata, {
    bool recovery = false,
  });

  Future<String?> exportJson(PlannerData data);

  Future<PlannerData?> importJson();

  Future<void> restore(String userKey, PlannerData data);

  Future<void> markPending(String userKey, bool pending);

  Future<StorageSnapshot> recoverFromBackup(String userKey);
}

class MemoryStorageRepository implements StorageRepository {
  final Map<String, StorageSnapshot> _values = {};

  @override
  Future<StorageSnapshot> load(String userKey) async =>
      _values[userKey] ??
      const StorageSnapshot(data: null, metadata: StorageMetadata());

  @override
  Future<void> save(
    String userKey,
    PlannerData data,
    StorageMetadata metadata, {
    bool recovery = false,
  }) async {
    _values[userKey] = StorageSnapshot(data: data, metadata: metadata);
  }

  @override
  Future<String?> exportJson(PlannerData data) async => data.toJsonString();

  @override
  Future<PlannerData?> importJson() async => null;

  @override
  Future<void> restore(String userKey, PlannerData data) async {
    await save(userKey, data, const StorageMetadata(), recovery: true);
  }

  @override
  Future<void> markPending(String userKey, bool pending) async {
    final snapshot = await load(userKey);
    _values[userKey] = StorageSnapshot(
      data: snapshot.data,
      metadata: snapshot.metadata.copyWith(pending: pending),
    );
  }

  @override
  Future<StorageSnapshot> recoverFromBackup(String userKey) => load(userKey);
}
