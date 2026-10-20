import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../../../core/providers.dart';
import '../../../core/storage/local_database.dart';
import '../../../core/theme/theme_mode.dart';

/// Persists the appearance choice in the same local Sembast database as the
/// other device preferences, so it survives a reload and never touches the
/// planner data that syncs to the server.
abstract interface class ThemePreferenceStore {
  Future<PlannerThemeMode> load();
  Future<void> save(PlannerThemeMode mode);
}

class LocalThemePreferenceStore implements ThemePreferenceStore {
  LocalThemePreferenceStore(this.database);

  final LocalDatabase database;
  static final _store = StoreRef<String, String>('app-preferences');
  static const _key = 'theme-mode';

  @override
  Future<PlannerThemeMode> load() async => PlannerThemeMode.fromStored(
    await _store.record(_key).get(await database.database),
  );

  @override
  Future<void> save(PlannerThemeMode mode) =>
      database.write((db) => _store.record(_key).put(db, mode.storedValue));
}

final themePreferenceStoreProvider = Provider<ThemePreferenceStore>(
  (ref) => LocalThemePreferenceStore(ref.watch(localDatabaseProvider)),
);

final plannerThemeModeProvider =
    StateNotifierProvider<PlannerThemeModeController, PlannerThemeMode>(
      (ref) =>
          PlannerThemeModeController(ref.watch(themePreferenceStoreProvider)),
    );

/// Restores the saved appearance once; a choice made before the read finishes
/// always wins, so opening settings quickly never flips the theme back.
class PlannerThemeModeController extends StateNotifier<PlannerThemeMode> {
  PlannerThemeModeController(this._store) : super(PlannerThemeMode.system) {
    _restore();
  }

  final ThemePreferenceStore _store;
  bool _userChose = false;

  Future<void> _restore() async {
    try {
      final saved = await _store.load();
      if (!_userChose && mounted) state = saved;
    } catch (_) {
      // A broken local store keeps the default (follow system).
    }
  }

  Future<void> setMode(PlannerThemeMode mode) async {
    _userChose = true;
    if (state == mode) return;
    state = mode;
    try {
      await _store.save(mode);
    } catch (_) {
      // Keep the in-memory choice; the next reload falls back to the default.
    }
  }
}
