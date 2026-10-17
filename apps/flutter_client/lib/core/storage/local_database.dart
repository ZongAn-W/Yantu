import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'database_factory.dart';

class LocalDatabase {
  LocalDatabase({
    this.name = 'sjtu-study-planner.db',
    Future<Database> Function()? open,
    this.backup,
  }) : _opener = open;
  final String name;
  final Future<Database> Function()? _opener;
  final Future<void> Function(Database)? backup;
  Future<Database>? _database;
  Future<void> _writes = Future.value();

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
      if (backup != null) {
        await backup!(db);
      } else if (_opener == null) {
        await backupPlannerDatabase(db);
      }
      return action(db);
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> close() async {
    await _writes;
    if (_database != null) await (await _database!).close();
  }
}
