import 'package:flutter_test/flutter_test.dart';

/// Polls [predicate] until it holds or [timeout] elapses.
///
/// Async restore paths resolve through real timers and I/O, so a fixed delay makes
/// tests flaky on a loaded machine. Polling asserts the observable condition.
Future<void> waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 5),
  String reason = '条件未在超时前满足',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail(reason);
    await Future<void>.delayed(interval);
  }
}
