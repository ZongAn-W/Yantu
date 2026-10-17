import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../../shared/models/planner_models.dart';
import 'atomic_file.dart';
import 'file_transfer_repository.dart';
import 'planner_json.dart';
import 'browser_download.dart';

class PlatformFileTransfer implements FileTransferRepository {
  PlatformFileTransfer({FilePicker? picker})
    : picker = picker ?? FilePicker.platform;
  final FilePicker picker;
  @override
  Future<PlannerData?> importJson() async {
    final selected = await picker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (selected == null) return null;
    final bytes = selected.files.single.bytes;
    if (bytes == null) throw const FormatException('无法读取所选文件');
    return parsePlannerJson(utf8.decode(bytes));
  }

  @override
  Future<bool> exportJson(PlannerData data) async {
    validatePlanner(data);
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data.toJson())),
    );
    final name =
        '不白学-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    if (kIsWeb) {
      downloadJson(bytes, name);
      return true;
    }
    final desktop =
        !kIsWeb &&
        [
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform);
    final selected = await picker.saveFile(
      dialogTitle: '导出本地数据',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: desktop ? null : bytes,
    );
    if (desktop) {
      if (selected == null) return false;
      await atomicWrite(selected, bytes);
      return true;
    }
    return kIsWeb || selected != null;
  }
}
