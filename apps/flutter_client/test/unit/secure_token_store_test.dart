import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';

/// In-memory secure storage double whose contents a test can corrupt directly.
class _FakeSecureStorage implements FlutterSecureStorage {
  _FakeSecureStorage([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(values);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.clear();

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const key = 'planner.native_session.v1';

  test('a stored refresh token is reloaded after a restart', () async {
    final storage = _FakeSecureStorage({key: jsonEncode({'refreshToken': 'r-1'})});
    final store = SecureTokenStore(storage: storage);
    final tokens = await store.read();
    expect(tokens?.refreshToken, 'r-1');
    // The access token is never persisted.
    expect(tokens?.accessToken, isEmpty);
    // A persisted pair is treated as expired so the first request refreshes it.
    expect(tokens!.expiresAt.isBefore(DateTime.now()), isTrue);
  });

  test('an empty storage reports no session', () async {
    expect(await SecureTokenStore(storage: _FakeSecureStorage()).read(), isNull);
  });

  test('a truncated payload reports no session instead of throwing', () async {
    final storage = _FakeSecureStorage({key: '{"refreshToken": "r-1"'});
    final store = SecureTokenStore(storage: storage);
    // Session restore must survive a damaged secure-storage entry: the client has
    // to reach the login page, not crash while checking the session.
    expect(await store.read(), isNull);
  });

  test('a payload without a refresh token reports no session', () async {
    final storage = _FakeSecureStorage({
      key: jsonEncode({'accessToken': 'leaked'}),
    });
    expect(await SecureTokenStore(storage: _FakeSecureStorage(
      {key: jsonEncode({'refreshToken': 42})},
    )).read(), isNull);
    expect(await SecureTokenStore(storage: storage).read(), isNull);
  });

  test('an empty refresh token is rejected', () async {
    final storage = _FakeSecureStorage({key: jsonEncode({'refreshToken': ''})});
    expect(await SecureTokenStore(storage: storage).read(), isNull);
  });

  test('write then read keeps the access token in memory only', () async {
    final storage = _FakeSecureStorage();
    final store = SecureTokenStore(storage: storage);
    final pair = TokenPair(
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    await store.write(pair);
    expect(await store.read(), pair);
    expect(storage.values.values.join(), isNot(contains('access-secret')));
    final reloaded = await SecureTokenStore(storage: storage).read();
    expect(reloaded?.refreshToken, 'refresh-secret');
    expect(reloaded?.accessToken, isEmpty);
  });

  test('clear removes the persisted record and the cached session', () async {
    final storage = _FakeSecureStorage();
    final store = SecureTokenStore(storage: storage);
    await store.write(
      TokenPair(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      ),
    );
    await store.clear();
    expect(storage.values, isEmpty);
    expect(await store.read(), isNull);
  });

  test('the memory store used on Web keeps the pair for the process only', () async {
    final store = MemoryTokenStore();
    expect(await store.read(), isNull);
    final pair = TokenPair(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    await store.write(pair);
    expect(await store.read(), pair);
    await store.clear();
    expect(await store.read(), isNull);
  });
}
