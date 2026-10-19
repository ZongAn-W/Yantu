import 'package:sembast_web/sembast_web.dart';

Future<Database> openPlannerDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);

Future<void> backupPlannerDatabase(Database database) async {}

Future<List<String>> scrubPlannerDatabaseArchives(
  Database database,
  Map<String, Object?> Function(Map<String, Object?>) sanitize,
) async => [];

Future<Database> recoverPlannerDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);
