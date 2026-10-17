import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

Future<void> atomicWrite(String path, Uint8List bytes) async {
  final target = File(path);
  await target.parent.create(recursive: true);
  final temp = File('$path.tmp-${DateTime.now().microsecondsSinceEpoch}');
  await temp.writeAsBytes(bytes, flush: true);
  if (Platform.isWindows) {
    final source = temp.path.toNativeUtf16(),
        destination = path.toNativeUtf16();
    try {
      if (MoveFileEx(
            source,
            destination,
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
          ) ==
          0) {
        throw FileSystemException(
          '原子替换失败，原文件和临时文件已保留',
          path,
          OSError('MoveFileEx', GetLastError()),
        );
      }
    } finally {
      calloc.free(source);
      calloc.free(destination);
    }
  } else {
    await temp.rename(path);
  }
}
