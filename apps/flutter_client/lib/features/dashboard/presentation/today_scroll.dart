/// 一次性请求：从「调整」页跳到「今日」时，自动滚动到「全部事项」。
///
/// 页面消费一次后立刻重置，避免以后每次进入今日页都自动滚动。
abstract final class TodayItemsScrollRequest {
  static bool _pending = false;

  static void request() => _pending = true;

  static bool consume() {
    final pending = _pending;
    _pending = false;
    return pending;
  }
}
