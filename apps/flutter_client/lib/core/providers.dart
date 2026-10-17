import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import 'auth/token_store.dart';
import 'config/app_config.dart';
import 'http/api_client.dart';
import 'storage/sembast_storage_repository.dart';
import 'storage/storage_repository.dart';
import 'storage/local_database.dart';
import 'storage/platform_file_transfer.dart';
import 'storage/identity_store.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => kIsWeb ? MemoryTokenStore() : SecureTokenStore(),
);

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final db = LocalDatabase();
  ref.onDispose(db.close);
  return db;
});
final identityStoreProvider = Provider<IdentityStore>(
  (ref) => LocalIdentityStore(
    ref.watch(localDatabaseProvider),
    ref.watch(appConfigProvider).apiBaseUrl,
  ),
);
final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => SembastStorageRepository(
    database: ref.watch(localDatabaseProvider),
    transfer: PlatformFileTransfer(),
  ),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    config: ref.watch(appConfigProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(client.close);
  return client;
});
