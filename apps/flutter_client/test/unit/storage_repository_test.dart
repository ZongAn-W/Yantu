import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
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
}
