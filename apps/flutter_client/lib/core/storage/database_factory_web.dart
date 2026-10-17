import 'package:sembast_web/sembast_web.dart';

Future<Database> openPlannerDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);

Future<void> backupPlannerDatabase(Database database) async {}

Future<Database> recoverPlannerDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);
