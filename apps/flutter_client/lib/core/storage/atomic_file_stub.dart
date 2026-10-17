import 'dart:typed_data';

Future<void> atomicWrite(String path, Uint8List bytes) =>
    throw UnsupportedError('浏览器不能直接写入文件路径');
