import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';

void main() {
  test(
    'defaults to rivers and restores a choice from the local database',
    () async {
      final db = LocalDatabase(
        open: () =>
            databaseFactoryMemory.openDatabase('calendar-preferences-test'),
      );
      addTearDown(db.close);
      final store = LocalCalendarViewPreferenceStore(db);
      final first = CalendarViewController(store);
      await first.ready;
      expect(first.state, CalendarView.rivers);
      await first.select(CalendarView.growth);
      first.dispose();

      final restored = CalendarViewController(
        LocalCalendarViewPreferenceStore(db),
      );
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.state, CalendarView.growth);
    },
  );

  test('invalid saved values use the default view', () {
    expect(CalendarView.fromStored('old-week-view'), CalendarView.rivers);
    expect(CalendarView.fromStored(null), CalendarView.rivers);
    // The removed 学习日轮 graphic must fall back to the default, not crash.
    expect(CalendarView.fromStored('wheel'), CalendarView.rivers);
  });

  test('a delayed restore cannot overwrite a new selection', () async {
    final store = _DelayedStore();
    final controller = CalendarViewController(store);
    addTearDown(controller.dispose);
    await controller.select(CalendarView.growth);
    store.loaded.complete(CalendarView.rivers);
    await controller.ready;
    expect(controller.state, CalendarView.growth);
    expect(store.saved, [CalendarView.growth]);
  });

  test(
    'rapid selections persist in order, including the last choice',
    () async {
      final store = _DelayedStore()..loaded.complete(CalendarView.rivers);
      final controller = CalendarViewController(store);
      addTearDown(controller.dispose);
      await controller.ready;
      final first = controller.select(CalendarView.growth);
      final second = controller.select(CalendarView.rivers);
      final third = controller.select(CalendarView.growth);
      await Future.wait([first, second, third]);
      expect(store.saved, [
        CalendarView.growth,
        CalendarView.rivers,
        CalendarView.growth,
      ]);
      expect(controller.state, CalendarView.growth);
    },
  );
}

class _DelayedStore implements CalendarViewPreferenceStore {
  final loaded = Completer<CalendarView>();
  final saved = <CalendarView>[];

  @override
  Future<CalendarView> load() => loaded.future;

  @override
  Future<void> save(CalendarView view) async {
    saved.add(view);
  }
}
