import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef Respond = Future<ResponseBody> Function(RequestOptions options);

class TestAdapter implements HttpClientAdapter {
  TestAdapter(this.respond);
  final Respond respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object body, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );

const testUser = {
  'id': 'user-1',
  'email': 'student@example.com',
  'username': '小明_408',
};
