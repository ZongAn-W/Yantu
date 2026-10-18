import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/storage/database_factory_io.dart';
import 'package:sjtu_study_planner_client/core/storage/atomic_file_io.dart';
import 'dart:typed_data';
import '../support/planner_fixture.dart';

void main() {
  var sequence = 0;
  late LocalDatabase database;
  late SembastStorageRepository storage;
  setUp(() {
    database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase('storage-${sequence++}'),
    );
    storage = SembastStorageRepository(database: database);
  });
  tearDown(() async {
    await database.close();
  });
  test(
    'data, pending and baseline reopen together and per-account slots stay isolated',
    () async {
      final data = plannerFixture();
      final metadata = StorageMetadata(
        revision: 7,
        pending: true,
        base: data,
        updatedAt: DateTime.utc(2026),
      );
      await storage.save('a', data, metadata);
      final reopened = await SembastStorageRepository(
        database: database,
      ).load('a');
      expect(reopened.data, data);
      expect(reopened.metadata, metadata);
      expect((await storage.load('b')).data, isNull);
      await storage.markPending('a', false);
      expect((await storage.load('a')).metadata.pending, isFalse);
    },
  );
  test(
    'corrupt main falls back to valid backup without destroying damaged record',
    () async {
      final original = plannerFixture();
      await storage.save('a', original, const StorageMetadata(revision: 2));
      await storage.save(
        'a',
        original.copyWith(phases: []),
        const StorageMetadata(revision: 3),
      );
      final db = await database.database;
      await storage.store.record('a').put(db, {'invalid': 'preserve me'});
      final recovered = await storage.load('a');
      expect(recovered.recovered, isTrue);
      expect(recovered.data, original);
      expect(recovered.metadata.revision, 2);
      expect(await storage.store.record('a').get(db), {
        'invalid': 'preserve me',
      });
      await storage.save('a', original, const StorageMetadata(revision: 2));
      expect((await storage.load('a')).data, original);
      expect(
        (await storage.store.find(
          db,
        )).where((row) => row.key.contains(':corrupt:')),
        hasLength(1),
      );
    },
  );
  test(
    'both corrupt block normal writes; explicit JSON restore retains corrupt originals',
    () async {
      final db = await database.database;
      await storage.store.record('a').put(db, {'broken': 'main'});
      await storage.store.record('a:backup').put(db, {'broken': 'backup'});
      expect((await storage.load('a')).error, isNotNull);
      await expectLater(
        storage.save('a', plannerFixture(), const StorageMetadata()),
        throwsA(anything),
      );
      expect(await storage.store.record('a').get(db), {'broken': 'main'});
      await storage.restore('a', plannerFixture());
      expect((await storage.load('a')).data, plannerFixture());
      expect((await storage.load('a')).metadata.pending, isTrue);
      expect(await storage.store.record('a:backup').get(db), {
        'broken': 'backup',
      });
    },
  );
  test('explicit backup recovery preserves the newer main', () async {
    final data = plannerFixture();
    await storage.save('a', data, const StorageMetadata());
    await storage.save(
      'a',
      data.copyWith(phases: []),
      const StorageMetadata(pending: true),
    );
    final result = await storage.recoverFromBackup('a');
    expect(result.data, data);
    expect(result.recovered, isTrue);
    final rows = await storage.store.find(await database.database);
    expect(
      rows.where((row) => row.key.contains(':before-recovery:')),
      hasLength(1),
    );
  });
  test(
    'raw/envelope import and export retain all planner fields; invalid references reject',
    () async {
      final data = plannerFixture(), json = await storage.exportJson(data);
      expect(parsePlannerJson(json!), data);
      expect(
        parsePlannerJson(
          jsonEncode({'version': 1, 'data': data.toJson(), 'metadata': {}}),
        ),
        data,
      );
      final invalid = data.toJson();
      (invalid['blocks'] as List).single['task_id'] = 'missing';
      expect(() => parsePlannerJson(jsonEncode(invalid)), throwsA(anything));
      expect(() => parsePlannerJson('{broken'), throwsA(anything));
      final migrated = forAccount(data, 'new-account');
      validatePlanner(migrated);
      expect(migrated.tasks.single.id, isNot(data.tasks.single.id));
      expect(migrated.blocks.single.taskId, migrated.tasks.single.id);
      expect(
        migrated.replanRuns.single.changes.single.after!.userId,
        'new-account',
      );
    },
  );
  test(
    'Windows file replacement and file-database corruption recovery preserve original bytes',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'planner-storage-phase4-',
      );
      final exportPath = '${temp.path}/export.json';
      await atomicWrite(exportPath, Uint8List.fromList(utf8.encode('first')));
      await atomicWrite(exportPath, Uint8List.fromList(utf8.encode('second')));
      expect(await File(exportPath).readAsString(), 'second');
      final path = '${temp.path}/planner.db';
      final db = await openPlannerDatabase(path);
      final records = StoreRef<String, String>.main();
      await records.record('test').put(db, 'valid backup');
      await backupPlannerDatabase(db);
      await db.close();
      await File(path).writeAsString('{broken', flush: true);
      final restored = await openPlannerDatabase(path);
      expect(await records.record('test').get(restored), 'valid backup');
      await restored.close();
      expect(
        await temp
            .list()
            .where((file) => file.path.contains('.corrupt-'))
            .length,
        1,
      );
    },
  );
  test(
    'both damaged files remain intact until explicit physical recovery',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'planner-both-damaged-',
      );
      final path = '${temp.path}/planner.db';
      await File(path).writeAsString('broken main');
      await File('$path.recovery.json').writeAsString('broken backup');
      await expectLater(openPlannerDatabase(path), throwsA(anything));
      expect(await File(path).readAsString(), 'broken main');
      expect(await File('$path.recovery.json').readAsString(), 'broken backup');
      final db = await recoverPlannerDatabase(path);
      await db.close();
      expect(
        await temp
            .list()
            .where((entry) => entry.path.contains('.corrupt-'))
            .length,
        2,
      );
    },
  );
  test('physical backups are throttled by write count without losing data', () async {
    final clock = _FakeClock();
    var backups = 0;
    final records = StoreRef<String, int>.main();
    final database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase('throttle-${sequence++}'),
      backup: (_) async => backups++,
      backupInterval: const Duration(minutes: 2),
      maxWritesBetweenBackups: 20,
      now: clock.now,
    );
    addTearDown(database.close);
    for (var index = 0; index < 30; index++) {
      clock.advance(const Duration(seconds: 1));
      await database.write((db) => records.record('counter').put(db, index));
    }
    // 第 1 次写入强制备份；20 次写入阈值在第 22 次写入前再次触发：30 次写入只有 2 次备份。
    expect(backups, 2);
    expect(await records.record('counter').get(await database.database), 29);
  });
  test('physical backups are throttled by elapsed time', () async {
    final clock = _FakeClock();
    var backups = 0;
    final records = StoreRef<String, int>.main();
    final database = LocalDatabase(
      open: () =>
          databaseFactoryMemory.openDatabase('throttle-time-${sequence++}'),
      backup: (_) async => backups++,
      backupInterval: const Duration(minutes: 2),
      maxWritesBetweenBackups: 1000,
      now: clock.now,
    );
    addTearDown(database.close);
    await database.write((db) => records.record('value').put(db, 1));
    await database.write((db) => records.record('value').put(db, 2));
    await database.write((db) => records.record('value').put(db, 3));
    expect(backups, 1); // 首次写入后 2 分钟内的写入不重复备份。
    clock.advance(const Duration(minutes: 2));
    await database.write((db) => records.record('value').put(db, 4));
    expect(backups, 2);
  });
  test('recovery writes force a backup of the original data', () async {
    final clock = _FakeClock();
    final observed = <int?>[];
    final records = StoreRef<String, int>.main();
    final database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase(
        'throttle-recovery-${sequence++}',
      ),
      backup: (db) async =>
          observed.add(await records.record('state').get(db)),
      backupInterval: const Duration(hours: 1),
      maxWritesBetweenBackups: 1000,
      now: clock.now,
    );
    addTearDown(database.close);
    await database.write((db) => records.record('state').put(db, 1));
    await database.write((db) => records.record('state').put(db, 2));
    await database.write(
      (db) => records.record('state').put(db, 3),
      recovery: true,
    );
    // 第一次写入与恢复写入各强制备份；恢复备份看到的是写入前的原始数据。
    expect(observed, [null, 2]);
    expect(await records.record('state').get(await database.database), 3);
  });
  test(
    'closing flushes a throttled backup so the recovery snapshot is current',
    () async {
      final clock = _FakeClock();
      final observed = <int?>[];
      var backups = 0;
      final records = StoreRef<String, int>.main();
      final database = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase(
          'throttle-close-${sequence++}',
        ),
        backup: (db) async {
          backups++;
          observed.add(await records.record('state').get(db));
        },
        backupInterval: const Duration(hours: 1),
        maxWritesBetweenBackups: 1000,
        now: clock.now,
      );
      await database.write((db) => records.record('state').put(db, 1));
      await database.write((db) => records.record('state').put(db, 2));
      expect(backups, 1);
      await database.close();
      // 关闭时补一次备份，快照包含全部已落盘写入。
      expect(backups, 2);
      expect(observed.last, 2);
    },
  );
  test(
    'throttled backup file stays a valid snapshot and close refreshes it',
    () async {
      final temp = await Directory.systemTemp.createTemp('planner-throttle-');
      final path = '${temp.path}/planner.db';
      final clock = _FakeClock();
      final records = StoreRef<String, int>.main();
      final database = LocalDatabase(
        open: () => openPlannerDatabase(path),
        backup: backupPlannerDatabase,
        backupInterval: const Duration(minutes: 2),
        maxWritesBetweenBackups: 20,
        now: clock.now,
      );
      await database.write((db) => records.record('a').put(db, 1));
      await database.write((db) => records.record('b').put(db, 2));
      final recovery = File('$path.recovery.json');
      expect(await recovery.exists(), isTrue);
      // 节流期间写出的恢复文件必须是可导入的完整快照。
      final snapshot = await importDatabase(
        jsonDecode(await recovery.readAsString()) as Map,
        databaseFactoryMemory,
        'throttle-validate-${sequence++}',
      );
      await snapshot.close();
      await database.close();
      // 关闭补写后恢复文件包含全部已落盘数据。
      final refreshed = await importDatabase(
        jsonDecode(await recovery.readAsString()) as Map,
        databaseFactoryMemory,
        'throttle-validate-${sequence++}',
      );
      expect(await records.record('a').get(refreshed), 1);
      expect(await records.record('b').get(refreshed), 2);
      await refreshed.close();
    },
  );
}

class _FakeClock {
  DateTime _value = DateTime.utc(2026, 1, 1);

  DateTime now() => _value;

  void advance(Duration duration) => _value = _value.add(duration);
}
