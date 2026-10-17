import 'package:sembast/sembast_io.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:sembast/sembast_memory.dart';
import 'atomic_file_io.dart';

Future<Database> openPlannerDatabase(String path) async {
  await File(path).parent.create(recursive: true);
  try {
    final main = File(path);
    if (await main.exists()) {
      final lines = await main.readAsLines();
      if (lines.isEmpty) throw const FormatException('本地数据库意外为空');
      for (final line in lines.where((line) => line.trim().isNotEmpty)) {
        if (jsonDecode(line) is! Map) throw const FormatException('数据库记录格式异常');
      }
      final header = jsonDecode(lines.first);
      if (header is! Map || header['sembast'] != 1) {
        throw const FormatException('数据库头损坏');
      }
    } else if (await File('$path.recovery.json').exists()) {
      throw const FormatException('主数据库丢失，正在恢复备份');
    }
    return await databaseFactoryIo.openDatabase(path);
  } catch (error) {
    final backup = File('$path.recovery.json');
    if (!await backup.exists()) rethrow;
    final exported = jsonDecode(await backup.readAsString()) as Map;
    // Validate in memory before moving the damaged database.
    final checked = await importDatabase(
      exported,
      databaseFactoryMemory,
      'recovery-validation',
    );
    await checked.close();
    final main = File(path);
    if (await main.exists()) {
      await main.rename(
        '$path.corrupt-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
    final restored = await importDatabase(exported, databaseFactoryIo, path);
    await StoreRef<String, bool>.main()
        .record('__database_recovered')
        .put(restored, true);
    return restored;
  }
}

Future<void> backupPlannerDatabase(Database database) async {
  final exported = await exportDatabase(database);
  await atomicWrite(
    '${database.path}.recovery.json',
    Uint8List.fromList(utf8.encode(jsonEncode(exported))),
  );
}

Future<Database> recoverPlannerDatabase(String path) async {
  // Explicit JSON recovery preserves both damaged files instead of deleting them.
  for (final filePath in [path, '$path.recovery.json']) {
    final file = File(filePath);
    if (await file.exists()) {
      await file.rename(
        '$filePath.corrupt-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
  }
  return databaseFactoryIo.openDatabase(path);
}
