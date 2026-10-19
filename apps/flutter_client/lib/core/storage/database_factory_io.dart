import 'package:sembast/sembast_io.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:sembast/sembast_memory.dart';
import 'atomic_file_io.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;

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

/// 导出一份完整全库快照并原子替换 `<db>.recovery.json`。
///
/// 由 LocalDatabase 按时间/写入次数阈值节流调用：第一次写入、恢复类写入
/// （recovery: true）以及关闭前的补写仍会强制执行，因此恢复文件始终是一个
/// 可导入的完整快照；普通高频写入（例如每分钟的计时 checkpoint）不会每次都
/// 导出整库。
Future<void> backupPlannerDatabase(Database database) async {
  final exported = await exportDatabase(database);
  await atomicWrite(
    '${database.path}.recovery.json',
    Uint8List.fromList(utf8.encode(jsonEncode(exported))),
  );
}

/// Scrub valid exported recovery archives in place. Corrupt native journals are
/// deliberately retained: their damaged bytes cannot be safely reconstructed.
/// No archive or directory is removed.
Future<List<String>> scrubPlannerDatabaseArchives(
  Database database,
  Map<String, Object?> Function(Map<String, Object?>) sanitize,
) async {
  final main = File(database.path);
  if (!await main.parent.exists()) return [];
  final unreadable = <String>[];
  final base = RegExp.escape(path.basename(main.path));
  final pattern = RegExp(
    '^$base(?:\\.recovery\\.json)?(?:\\.(?:corrupt|tmp)-[0-9]+)+\$',
  );
  await for (final entity in main.parent.list(followLinks: false)) {
    if (entity is! File || !pattern.hasMatch(path.basename(entity.path))) {
      continue;
    }
    Map<String, Object?> sanitized;
    try {
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map || decoded['sembast_export'] != 1) {
        unreadable.add(entity.path);
        continue;
      }
      sanitized = sanitize(Map<String, Object?>.from(decoded));
    } on FormatException {
      unreadable.add(entity.path);
      debugPrint('历史损坏文件无法解析，保留原文件：${entity.path}');
      continue;
    }
    await atomicWrite(
      entity.path,
      Uint8List.fromList(utf8.encode(jsonEncode(sanitized))),
    );
  }
  return unreadable;
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
