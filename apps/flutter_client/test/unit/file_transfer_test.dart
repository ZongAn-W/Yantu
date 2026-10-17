import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:sjtu_study_planner_client/core/storage/platform_file_transfer.dart';
import '../support/planner_fixture.dart';

class TestFilePicker extends FilePicker {
  FilePickerResult? selection;
  String? destination;
  Uint8List? exported;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => selection;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    exported = bytes;
    return destination;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('file picker JSON round-trip and invalid/cancelled import', () async {
    final data = plannerFixture(), picker = TestFilePicker();
    final transfer = PlatformFileTransfer(picker: picker);
    expect(await transfer.importJson(), isNull);
    final bytes = Uint8List.fromList(utf8.encode(data.toJsonString()));
    picker.selection = FilePickerResult([
      PlatformFile(name: 'plan.json', size: bytes.length, bytes: bytes),
    ]);
    expect(await transfer.importJson(), data);
    picker.selection = FilePickerResult([
      PlatformFile(name: 'bad.json', size: 1, bytes: Uint8List.fromList([123])),
    ]);
    await expectLater(transfer.importJson(), throwsA(anything));
    final dir = await Directory.systemTemp.createTemp(
      'planner-transfer-phase4-',
    );
    picker.destination = '${dir.path}/plan.json';
    expect(await transfer.exportJson(data), isTrue);
    expect(
      jsonDecode(await File(picker.destination!).readAsString()),
      data.toJson(),
    );
    picker.destination = null;
    expect(await transfer.exportJson(data), isFalse);
  });
}
