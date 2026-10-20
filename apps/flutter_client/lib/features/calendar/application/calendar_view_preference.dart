import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../../../core/providers.dart';
import '../../../core/storage/local_database.dart';
import '../domain/calendar_view.dart';

abstract interface class CalendarViewPreferenceStore {
  Future<CalendarView> load();
  Future<void> save(CalendarView view);
}

abstract interface class CalendarWeekViewPreferenceStore {
  Future<CalendarWeekView> load();
  Future<void> save(CalendarWeekView view);
}

/// Both scopes share the existing local Sembast store but use separate records:
/// changing the week graphic never rewrites the day graphic.
abstract final class _CalendarPreferenceKeys {
  static const dayView = 'day-view';
  static const weekView = 'week-view';
}

class LocalCalendarViewPreferenceStore implements CalendarViewPreferenceStore {
  LocalCalendarViewPreferenceStore(this.database);

  final LocalDatabase database;
  static final _store = StoreRef<String, String>('calendar-preferences');

  @override
  Future<CalendarView> load() async => CalendarView.fromStored(
    await _store.record(_CalendarPreferenceKeys.dayView).get(
      await database.database,
    ),
  );

  @override
  Future<void> save(CalendarView view) => database.write(
    (db) => _store.record(_CalendarPreferenceKeys.dayView).put(db, view.name),
  );
}

class LocalCalendarWeekViewPreferenceStore
    implements CalendarWeekViewPreferenceStore {
  LocalCalendarWeekViewPreferenceStore(this.database);

  final LocalDatabase database;
  static final _store = StoreRef<String, String>('calendar-preferences');

  @override
  Future<CalendarWeekView> load() async => CalendarWeekView.fromStored(
    await _store.record(_CalendarPreferenceKeys.weekView).get(
      await database.database,
    ),
  );

  @override
  Future<void> save(CalendarWeekView view) => database.write(
    (db) =>
        _store.record(_CalendarPreferenceKeys.weekView).put(db, view.name),
  );
}

final calendarViewPreferenceStoreProvider =
    Provider<CalendarViewPreferenceStore>(
      (ref) =>
          LocalCalendarViewPreferenceStore(ref.watch(localDatabaseProvider)),
    );

final calendarWeekViewPreferenceStoreProvider =
    Provider<CalendarWeekViewPreferenceStore>(
      (ref) => LocalCalendarWeekViewPreferenceStore(
        ref.watch(localDatabaseProvider),
      ),
    );

final calendarViewProvider =
    StateNotifierProvider<CalendarViewController, CalendarView>(
      (ref) => CalendarViewController(
        ref.watch(calendarViewPreferenceStoreProvider),
      ),
    );

final calendarWeekViewProvider =
    StateNotifierProvider<CalendarWeekViewController, CalendarWeekView>(
      (ref) => CalendarWeekViewController(
        ref.watch(calendarWeekViewPreferenceStoreProvider),
      ),
    );

/// Restores one saved chart choice and serializes subsequent saves.
///
/// A slow local read must not undo a choice made after the page opened, and
/// rapid switches are persisted in the same order the user made them.
abstract class CalendarChartPreferenceController<T> extends StateNotifier<T> {
  // StateNotifier's positional constructor parameter is library-private, so it
  // cannot be forwarded as a super parameter even though the lint suggests it.
  // ignore: use_super_parameters
  CalendarChartPreferenceController(
    T initial,
    this._load,
    this._save,
    this._label,
  ) : super(initial) {
    ready = _restore();
  }

  final Future<T> Function() _load;
  final Future<void> Function(T) _save;
  final String _label;
  late final Future<void> ready;
  Future<void> _writes = Future.value();
  bool _selected = false;

  Future<void> _restore() async {
    try {
      final saved = await _load();
      if (mounted && !_selected) state = saved;
    } catch (error) {
      debugPrint('读取$_label偏好失败：$error');
    }
  }

  Future<void> select(T view) {
    _selected = true;
    state = view;
    final next = _writes.then((_) => _save(view));
    _writes = next.catchError((Object error) {
      debugPrint('保存$_label偏好失败：$error');
    });
    return _writes;
  }
}

class CalendarViewController
    extends CalendarChartPreferenceController<CalendarView> {
  CalendarViewController(CalendarViewPreferenceStore store)
    : super(CalendarView.rivers, store.load, store.save, '日历图形');
}

class CalendarWeekViewController
    extends CalendarChartPreferenceController<CalendarWeekView> {
  CalendarWeekViewController(CalendarWeekViewPreferenceStore store)
    : super(
        CalendarWeekView.mirror,
        store.load,
        store.save,
        '日历周视图图形',
      );
}
