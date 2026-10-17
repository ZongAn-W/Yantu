import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/features/auth/application/auth_controller.dart';
import '../support/http_adapter.dart';
import '../support/async_wait.dart';

void main() {
  test(
    'previously authenticated Web account restores offline, while 401 clears cached identity',
    () async {
      final identity = MemoryIdentityStore();
      await identity.save(testUser);
      var offline = true;
      final adapter = TestAdapter((request) async {
        if (offline) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          );
        }
        return jsonResponse({'error': 'expired'}, 401);
      });
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        usesBearer: false,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          identityStoreProvider.overrideWithValue(identity),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.close);
      container.read(authControllerProvider);
      // Wait for the observable state instead of a fixed delay: the offline restore
      // resolves through an HTTP failure and a cached identity read.
      await waitUntil(
        () => container.read(authControllerProvider).user?.id == 'user-1',
        reason: '离线恢复没有在超时前载入本机账号',
      );
      expect(container.read(authControllerProvider).user?.id, 'user-1');
      offline = false;
      await container.read(authControllerProvider.notifier).restoreSession();
      expect(container.read(authControllerProvider).user, isNull);
      expect(await identity.load(), isNull);
    },
  );
}
