import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

abstract interface class TokenStore {
  Future<TokenPair?> read();

  Future<void> write(TokenPair tokens);

  Future<void> clear();
}

class MemoryTokenStore implements TokenStore {
  TokenPair? _tokens;

  @override
  Future<TokenPair?> read() async => _tokens;

  @override
  Future<void> write(TokenPair tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> clear() async {
    _tokens = null;
  }
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'planner.native_session.v1';
  final FlutterSecureStorage _storage;
  TokenPair? _memory;

  /// Reads the persisted refresh token.
  ///
  /// A damaged or incomplete record must not break session restore: the client has
  /// to reach the login page instead of failing while checking the session. Such a
  /// record is removed and reported as "no session", which also stops a refresh
  /// request from being sent with an unusable token.
  @override
  Future<TokenPair?> read() async {
    if (_memory != null) return _memory;
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    final String refreshToken;
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['refreshToken'] is! String) {
        throw const FormatException('会话记录缺少刷新令牌');
      }
      refreshToken = value['refreshToken'] as String;
    } on FormatException {
      await clear();
      return null;
    }
    if (refreshToken.isEmpty) {
      await clear();
      return null;
    }
    return _memory = TokenPair(
      accessToken: '',
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Future<void> write(TokenPair tokens) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({'refreshToken': tokens.refreshToken}),
    );
    _memory = tokens;
  }

  @override
  Future<void> clear() async {
    _memory = null;
    await _storage.delete(key: _sessionKey);
  }
}
