import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

void downloadJson(Uint8List bytes, String name) {
  final blob = Blob(
    [bytes.toJS].toJS,
    BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = name;
  document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => URL.revokeObjectURL(url));
}
