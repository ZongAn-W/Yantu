/// The two day graphics, displayed in this order and never written into the
/// study plan. Stored values are retained for older single-chart preferences.
enum CalendarView {
  growth('生长轨道'),
  rivers('计划与实际双河道');

  const CalendarView(this.label);
  final String label;

  static CalendarView fromStored(Object? value) => values.firstWhere(
    (view) => view.name == value,
    orElse: () => CalendarView.rivers,
  );
}

/// Day, week and month are read-only windows on the same study facts.
///
/// The mode is a page-local switch: opening the calendar always starts on the
/// stacked day view, while the selected date and the week graphic are kept when
/// the scope changes.
enum CalendarMode {
  day('日'),
  week('周'),
  month('月');

  const CalendarMode(this.label);
  final String label;
}

/// The two whole-week visualizations. Both consume one shared week snapshot.
enum CalendarWeekView {
  mirror('上下镜像'),
  mountain('学习山脉');

  const CalendarWeekView(this.label);
  final String label;

  static CalendarWeekView fromStored(Object? value) => values.firstWhere(
    (view) => view.name == value,
    orElse: () => CalendarWeekView.mirror,
  );
}
