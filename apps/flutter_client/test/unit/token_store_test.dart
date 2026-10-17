import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'refresh persists while access token remains in memory, and clearing removes the session',
    () async {
      final first = SecureTokenStore();
      final tokens = TokenPair(
        accessToken: 'secret-access',
        refreshToken: 'secret-refresh',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      await first.write(tokens);
      expect(await first.read(), tokens);
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.values.join(), isNot(contains('secret-access')));
      expect(
        jsonDecode(stored.values.single)['refreshToken'],
        'secret-refresh',
      );
      final restarted = await SecureTokenStore().read();
      expect(restarted!.refreshToken, 'secret-refresh');
      expect(restarted.accessToken, isEmpty);
      expect(restarted.expiresAt.isBefore(DateTime.now()), isTrue);
      await first.clear();
      expect(await SecureTokenStore().read(), isNull);
    },
  );
}
