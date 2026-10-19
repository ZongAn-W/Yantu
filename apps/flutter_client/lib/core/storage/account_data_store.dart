import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'local_database.dart';

export 'local_database.dart' show LocalAccountCleanupIncomplete;

final accountDataStoreProvider = Provider<AccountDataStore>(
  (ref) => LocalAccountDataStore(ref.watch(localDatabaseProvider)),
);

abstract interface class AccountDataStore {
  /// [scope] is the unencoded API base URL used by the identity store.
  Future<void> purge({required String scope, required String userId});
}

class LocalAccountDataStore implements AccountDataStore {
  LocalAccountDataStore(this.database);

  final LocalDatabase database;

  @override
  Future<void> purge({required String scope, required String userId}) =>
      database.purgeAccountData(scope: scope, userId: userId);
}
