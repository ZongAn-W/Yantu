import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:sjtu_study_planner_client/core/storage/account_data_store.dart';
import 'package:sjtu_study_planner_client/core/storage/database_factory_io.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';

const _scope = 'https://planner.example/api';
const _otherScope = 'https://another.example/api';
const _user = 'user-a';

String _key(String scope, String userId) =>
    'sjtu-study-planner:items-v2:${Uri.encodeComponent(scope)}:cloud:$userId';

final _planner = StoreRef<String, Object?>('planner');
final _timers = StoreRef<String, Object?>('study-timers');
final _identity = StoreRef<String, Object?>('identity');

Future<void> _seed(Database db) async {
  for (final store in [_planner, _timers]) {
    for (final suffix in [
      '',
      ':backup',
      ':corrupt:123',
      ':before-recovery:456',
    ]) {
      await store.record('${_key(_scope, _user)}$suffix').put(db, {
        'secret': 'deleted-account-secret',
      });
      await store.record('${_key(_scope, 'user-b')}$suffix').put(db, {
        'secret': 'another-user-secret',
      });
      await store.record('${_key(_otherScope, _user)}$suffix').put(db, {
        'secret': 'another-endpoint-secret',
      });
    }
  }
  await _identity.record(_scope).put(db, {'id': _user});
  await _identity.record(_otherScope).put(db, {'id': _user});
}

Future<void> _expectPurged(Database db) async {
  for (final store in [_planner, _timers]) {
    final rows = await store.find(db);
    expect(rows, hasLength(8));
    expect(
      rows.where((row) => row.key.startsWith(_key(_scope, _user))),
      isEmpty,
    );
    expect(await store.record(_key(_scope, 'user-b')).get(db), isNotNull);
    expect(await store.record(_key(_otherScope, _user)).get(db), isNotNull);
  }
  expect(await _identity.record(_scope).get(db), isNull);
  expect(await _identity.record(_otherScope).get(db), {'id': _user});
}

void main() {
  var sequence = 0;

  test(
    'purge removes only this account including backups and timers',
    () async {
      final database = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase('purge-${sequence++}'),
      );
      addTearDown(database.close);
      final db = await database.database;
      await _seed(db);
      await LocalAccountDataStore(database).purge(scope: _scope, userId: _user);
      await _expectPurged(db);

      // The endpoint's cached identity can already belong to a different user.
      await _identity.record(_scope).put(db, {'id': 'user-b'});
      await LocalAccountDataStore(database).purge(scope: _scope, userId: _user);
      expect(await _identity.record(_scope).get(db), {'id': 'user-b'});
    },
  );

  test(
    'purge replaces recovery snapshot and compacts native journal',
    () async {
      final directory = await Directory.systemTemp.createTemp('account-purge-');
      final filePath = '${directory.path}/planner.db';
      final database = LocalDatabase(
        open: () => openPlannerDatabase(filePath),
        backup: backupPlannerDatabase,
      );
      addTearDown(database.close);
      final db = await database.database;
      await _seed(db);
      await backupPlannerDatabase(db);
      final archive = File('$filePath.recovery.json.corrupt-123');
      await archive.writeAsString(
        await File('$filePath.recovery.json').readAsString(),
      );

      await LocalAccountDataStore(database).purge(scope: _scope, userId: _user);
      expect(
        await File(filePath).readAsString(),
        isNot(contains('deleted-account-secret')),
      );
      for (final snapshotPath in ['$filePath.recovery.json', archive.path]) {
        final snapshot = await importDatabase(
          jsonDecode(await File(snapshotPath).readAsString()) as Map,
          databaseFactoryMemory,
          'purge-snapshot-${sequence++}',
        );
        await _expectPurged(snapshot);
        await snapshot.close();
      }
    },
  );

  test(
    'failed backup leaves durable deletion and retry finishes cleanup',
    () async {
      var fail = true;
      Map<String, Object?>? backup;
      final database = LocalDatabase(
        open: () =>
            databaseFactoryMemory.openDatabase('purge-retry-${sequence++}'),
        backup: (db) async {
          if (fail) throw const FileSystemException('backup failed');
          backup = await exportDatabase(db);
        },
      );
      addTearDown(database.close);
      final db = await database.database;
      await _seed(db);
      final accounts = LocalAccountDataStore(database);
      await expectLater(
        accounts.purge(scope: _scope, userId: _user),
        throwsA(isA<FileSystemException>()),
      );
      await _expectPurged(db);
      fail = false;
      await accounts.purge(scope: _scope, userId: _user);
      expect(backup, isNotNull);
      expect(jsonEncode(backup), isNot(contains('deleted-account-secret')));
      await _expectPurged(db);
    },
  );

  test(
    'queued stale writes and another database wrapper honor tombstone',
    () async {
      final name = 'purge-queued-${sequence++}';
      final database = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase(name),
      );
      addTearDown(database.close);
      final db = await database.database;
      await _seed(db);
      final started = Completer<void>(), release = Completer<void>();
      final blocking = database.write((_) async {
        started.complete();
        await release.future;
      });
      await started.future;
      final purge = LocalAccountDataStore(
        database,
      ).purge(scope: _scope, userId: _user);
      final stale = database.write((db) async {
        await _planner.record(_key(_scope, _user)).put(db, {'stale': true});
        await _timers.record(_key(_scope, _user)).put(db, {'revision': 1});
        await _identity.record(_scope).put(db, {'id': _user});
      });
      release.complete();
      await Future.wait([blocking, purge, stale]);
      await _expectPurged(db);

      final otherWindow = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase(name),
      );
      // Both wrappers share the same physical database, so close only once.
      await otherWindow.write((db) async {
        await _planner.record(_key(_scope, _user)).put(db, {'stale': 'window'});
      });
      await _expectPurged(db);
    },
  );

  test(
    'opening a database retries failed backup cleanup from durable marker',
    () async {
      final name = 'purge-startup-${sequence++}';
      var fail = true;
      var backupCount = 0;
      Map<String, Object?>? snapshot;
      Future<void> backup(Database db) async {
        backupCount++;
        if (fail) throw const FileSystemException('temporarily unavailable');
        snapshot = await exportDatabase(db);
      }

      final first = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase(name),
        backup: backup,
      );
      await _seed(await first.database);
      await expectLater(
        LocalAccountDataStore(first).purge(scope: _scope, userId: _user),
        throwsA(isA<FileSystemException>()),
      );
      await first.close();
      fail = false;
      final reopened = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase(name),
        backup: backup,
      );
      addTearDown(reopened.close);
      await _expectPurged(await reopened.database);
      expect(backupCount, 2);
      expect(reopened.accountCleanupFailure, isNull);
      expect(jsonEncode(snapshot), isNot(contains('deleted-account-secret')));
    },
  );

  test(
    'unreadable archives report partial cleanup and remain unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'account-archive-',
      );
      final filePath = '${directory.path}/planner.db';
      final first = LocalDatabase(
        open: () => openPlannerDatabase(filePath),
        backup: backupPlannerDatabase,
      );
      await _seed(await first.database);
      final archive = File('$filePath.corrupt-123');
      const damagedBytes = '{broken deleted-account-secret';
      await archive.writeAsString(damagedBytes);
      await expectLater(
        LocalAccountDataStore(first).purge(scope: _scope, userId: _user),
        throwsA(
          isA<LocalAccountCleanupIncomplete>().having(
            (error) => error.archivePaths
                .map((filePath) => filePath.replaceAll('\\', '/'))
                .toList(),
            'unreadable archives',
            [archive.path.replaceAll('\\', '/')],
          ),
        ),
      );
      await _expectPurged(await first.database);
      expect(await archive.readAsString(), damagedBytes);
      await first.close();

      final reopened = LocalDatabase(
        open: () => openPlannerDatabase(filePath),
        backup: backupPlannerDatabase,
      );
      addTearDown(reopened.close);
      await _expectPurged(await reopened.database);
      expect(
        reopened.accountCleanupFailure,
        isA<LocalAccountCleanupIncomplete>(),
      );
      expect(await archive.readAsString(), damagedBytes);
    },
  );
}
