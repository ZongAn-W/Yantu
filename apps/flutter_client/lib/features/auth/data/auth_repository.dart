import '../../../core/http/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../../../shared/models/planner_models.dart';
import '../../../core/storage/identity_store.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.username,
  });

  factory AuthUser.fromJson(JsonMap json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    username: json['username'] as String,
  );

  final String id;
  final String email;
  final String username;
}

class AuthRepository {
  AuthRepository(this.client, this.identity);

  final ApiClient client;
  final IdentityStore identity;
  Future<void> _remember(AuthUser user) async {
    try {
      await identity.save({
        'id': user.id,
        'email': user.email,
        'username': user.username,
      });
    } catch (_) {
      /* The workspace recovery screen remains available when local storage is broken. */
    }
  }

  Future<AuthUser> login(String email, String password) async {
    final response = await client.post(
      '/api/auth/login',
      data: {'email': email.trim(), 'password': password},
    );
    return _decodeSession(response.data);
  }

  Future<AuthUser> register({
    required String email,
    required String username,
    required String password,
    required String code,
  }) async {
    final response = await client.post(
      '/api/auth/register',
      data: {
        'email': email.trim(),
        'username': username.trim(),
        'password': password,
        'code': code.trim(),
      },
    );
    return _decodeSession(response.data);
  }

  Future<int> requestRegistrationCode(String email) async {
    final response = await client.post(
      '/api/auth/registration-code',
      data: {'email': email.trim()},
    );
    return (response.data['retryAfter'] as num?)?.toInt() ?? 60;
  }

  Future<AuthUser?> currentUser() async {
    try {
      final response = await client.get('/api/me');
      final user = AuthUser.fromJson(
        JsonMap.from(response.data['user'] as Map),
      );
      await _remember(user);
      return user;
    } on UnauthorizedFailure {
      return null;
    }
  }

  Future<AuthUser> _decodeSession(Object? value) async {
    final body = JsonMap.from(value as Map);
    final user = AuthUser.fromJson(JsonMap.from(body['user'] as Map));
    await client.acceptSession(body);
    await _remember(user);
    return user;
  }

  Future<void> signOut() async {
    try {
      if (client.usesBearer) {
        final tokens = await client.tokenStore.read();
        if (tokens != null) {
          await client.post(
            '/api/auth/token/revoke',
            data: {'refreshToken': tokens.refreshToken},
          );
        }
      } else {
        await client.post('/api/auth/logout');
      }
    } finally {
      // The local session must end even when the server is unreachable; an
      // offline user still gets a reliable local sign-out.
      await client.clearSession();
    }
  }
}
