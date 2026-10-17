import 'package:sembast/sembast.dart';

import '../../shared/models/planner_models.dart';
import 'local_database.dart';

abstract interface class StudyTimerStore {
  Future<JsonMap?> load(String key);

  /// Atomically writes the next revision, or throws with the newer checkpoint.
  Future<void> save(String key, JsonMap value);
}

class StudyTimerConflict implements Exception {
  const StudyTimerConflict(this.latest);
  final JsonMap? latest;

  @override
  String toString() => '计时已在另一个窗口更新，已载入最新记录';
}

/// Seconds and the active checkpoint live beside the minute-based plan snapshot.
class LocalStudyTimerStore implements StudyTimerStore {
  LocalStudyTimerStore(this.database);

  final LocalDatabase database;
  final _store = StoreRef<String, Map<String, Object?>>('study-timers');

  @override
  Future<JsonMap?> load(String key) async {
    final value = await _store.record(key).get(await database.database);
    return value == null ? null : JsonMap.from(value);
  }

  @override
  Future<void> save(String key, JsonMap value) => database.write(
    (db) => db.transaction((transaction) async {
      final record = _store.record(key);
      final current = await record.get(transaction);
      final revision = (current?['revision'] as int?) ?? 0;
      final requested = (value['revision'] as int?) ?? 1;
      if (requested != revision + 1) {
        throw StudyTimerConflict(
          current == null ? null : JsonMap.from(current),
        );
      }
      await record.put(transaction, {...value, 'revision': requested});
    }),
  );
}
