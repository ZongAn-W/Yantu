import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';

void main() {
  Future<LocalDatabase> createDatabase(String name) async {
    final db = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase(name),
    );
    addTearDown(db.close);
    return db;
  }

  test('defaults to mirror and restores a week choice from local storage',
      () async {
    final database = await createDatabase('week-preference-restore');
    final first = CalendarWeekViewController(
      LocalCalendarWeekViewPreferenceStore(database),
    );
    await first.ready;
    expect(first.state, CalendarWeekView.mirror);
    await first.select(CalendarWeekView.mountain);
    first.dispose();

    final restored = CalendarWeekViewController(
      LocalCalendarWeekViewPreferenceStore(database),
    );
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state, CalendarWeekView.mountain);
  });

  test('day and week chart preferences are stored independently', () async {
    final database = await createDatabase('week-preference-independent');
    final dayStore = LocalCalendarViewPreferenceStore(database);
    final weekStore = LocalCalendarWeekViewPreferenceStore(database);
    await dayStore.save(CalendarView.growth);
    await weekStore.save(CalendarWeekView.mountain);

    // Changing the week graphic must not rewrite the day graphic.
    await weekStore.save(CalendarWeekView.mirror);
    expect(await dayStore.load(), CalendarView.growth);
    expect(await weekStore.load(), CalendarWeekView.mirror);

    await dayStore.save(CalendarView.rivers);
    expect(await dayStore.load(), CalendarView.rivers);
    expect(await weekStore.load(), CalendarWeekView.mirror);
  });

  test('invalid stored week values use the mirror default', () {
    expect(CalendarWeekView.fromStored('old-week-view'), CalendarWeekView.mirror);
    expect(CalendarWeekView.fromStored(null), CalendarWeekView.mirror);
    expect(CalendarWeekView.fromStored(7), CalendarWeekView.mirror);
    expect(
      CalendarWeekView.fromStored('mountain'),
      CalendarWeekView.mountain,
    );
  });

  test('a delayed week restore cannot overwrite a new selection', () async {
    final store = _DelayedWeekStore();
    final controller = CalendarWeekViewController(store);
    addTearDown(controller.dispose);
    await controller.select(CalendarWeekView.mountain);
    store.loaded.complete(CalendarWeekView.mirror);
    await controller.ready;
    expect(controller.state, CalendarWeekView.mountain);
    expect(store.saved, [CalendarWeekView.mountain]);
  });

  test('rapid week selections persist in order, including the last choice',
      () async {
    final store = _DelayedWeekStore()
      ..loaded.complete(CalendarWeekView.mirror);
    final controller = CalendarWeekViewController(store);
    addTearDown(controller.dispose);
    await controller.ready;
    final first = controller.select(CalendarWeekView.mountain);
    final second = controller.select(CalendarWeekView.mirror);
    final third = controller.select(CalendarWeekView.mountain);
    await Future.wait([first, second, third]);
    expect(store.saved, [
      CalendarWeekView.mountain,
      CalendarWeekView.mirror,
      CalendarWeekView.mountain,
    ]);
    expect(controller.state, CalendarWeekView.mountain);
  });
}

class _DelayedWeekStore implements CalendarWeekViewPreferenceStore {
  final loaded = Completer<CalendarWeekView>();
  final saved = <CalendarWeekView>[];

  @override
  Future<CalendarWeekView> load() => loaded.future;

  @override
  Future<void> save(CalendarWeekView view) async {
    saved.add(view);
  }
}
