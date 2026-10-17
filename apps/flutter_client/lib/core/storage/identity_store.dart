import 'package:sembast/sembast.dart';
import '../../shared/models/planner_models.dart';
import 'local_database.dart';

abstract interface class IdentityStore {
  Future<JsonMap?> load();
  Future<void> save(JsonMap? user);
}

class LocalIdentityStore implements IdentityStore {
  LocalIdentityStore(this.database, this.scope);
  final LocalDatabase database;
  final String scope;
  final _store = StoreRef<String, Map<String, Object?>>('identity');
  @override
  Future<JsonMap?> load() async {
    final value = await _store.record(scope).get(await database.database);
    return value == null ? null : JsonMap.from(value);
  }

  @override
  Future<void> save(JsonMap? user) => database.write((db) async {
    if (user == null) {
      await _store.record(scope).delete(db);
    } else {
      await _store.record(scope).put(db, user);
    }
  });
}

class MemoryIdentityStore implements IdentityStore {
  JsonMap? user;
  @override
  Future<JsonMap?> load() async => user;
  @override
  Future<void> save(JsonMap? value) async {
    user = value;
  }
}
