/// One course block inside a day tile, expressed as fractions of the tile's
/// filled area (`0..1`, origin top-left).
class MosaicBlock {
  const MosaicBlock({
    required this.itemIndex,
    required this.minutes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Index of the first source item represented by this block.
  ///
  /// The painter uses it to pick the course colour. When more than
  /// [maxMosaicBlocks] items exist the trailing minutes are folded into the
  /// last block, so the index still points at a real item.
  final int itemIndex;

  /// Planned minutes represented by this block (folded minutes included).
  final int minutes;

  final double left;
  final double top;
  final double width;
  final double height;
}

/// How many colour blocks a single day tile draws before folding the rest.
const int maxMosaicBlocks = 4;

/// Fills of the capacity tile: `planned / capacity`, clamped to `0..1`.
///
/// A zero-capacity day with a plan cannot be represented proportionally, so it
/// fills the whole tile; a rest day without a plan stays empty.
double mosaicFillRatio({
  required int plannedMinutes,
  required int capacityMinutes,
}) {
  if (plannedMinutes <= 0) return 0;
  if (capacityMinutes <= 0) return 1;
  return (plannedMinutes / capacityMinutes).clamp(0.0, 1.0);
}

/// Lays out proportional colour blocks covering the unit square exactly.
///
/// [minutes] is the planned-minute list of one day, sorted descending by the
/// caller. Non-positive entries are ignored. At most [maxMosaicBlocks] blocks
/// are rendered; when the day has more courses, the trailing minutes are folded
/// into the last block so the total area still represents every planned minute.
///
/// Shapes: one block fills the tile; two split it left/right; three use an L
/// (largest left, two stacked right); four use two proportional columns with two
/// stacked blocks each. All rects are exact area proportions.
List<MosaicBlock> layoutMosaicBlocks(List<int> minutes) {
  final values = <int>[];
  for (final value in minutes) {
    if (value > 0) values.add(value);
  }
  if (values.isEmpty) return const [];
  if (values.length <= maxMosaicBlocks) {
    return _layout(values);
  }
  final folded = <int>[...values.take(maxMosaicBlocks - 1)];
  final rest = values
      .skip(maxMosaicBlocks - 1)
      .fold<int>(0, (sum, v) => sum + v);
  folded.add(rest);
  return _layout(folded);
}

List<MosaicBlock> _layout(List<int> values) {
  final total = values.fold<int>(0, (sum, v) => sum + v);
  if (total <= 0) return const [];
  switch (values.length) {
    case 1:
      return [
        MosaicBlock(
          itemIndex: 0,
          minutes: values[0],
          left: 0,
          top: 0,
          width: 1,
          height: 1,
        ),
      ];
    case 2:
      final width = values[0] / total;
      return [
        MosaicBlock(
          itemIndex: 0,
          minutes: values[0],
          left: 0,
          top: 0,
          width: width,
          height: 1,
        ),
        MosaicBlock(
          itemIndex: 1,
          minutes: values[1],
          left: width,
          top: 0,
          width: 1 - width,
          height: 1,
        ),
      ];
    case 3:
      final firstWidth = values[0] / total;
      final restTotal = values[1] + values[2];
      final secondHeight = values[1] / restTotal;
      return [
        MosaicBlock(
          itemIndex: 0,
          minutes: values[0],
          left: 0,
          top: 0,
          width: firstWidth,
          height: 1,
        ),
        MosaicBlock(
          itemIndex: 1,
          minutes: values[1],
          left: firstWidth,
          top: 0,
          width: 1 - firstWidth,
          height: secondHeight,
        ),
        MosaicBlock(
          itemIndex: 2,
          minutes: values[2],
          left: firstWidth,
          top: secondHeight,
          width: 1 - firstWidth,
          height: 1 - secondHeight,
        ),
      ];
    default:
      final leftMinutes = values[0] + values[1];
      final rightMinutes = values[2] + values[3];
      final leftWidth = leftMinutes / total;
      final firstHeight = values[0] / leftMinutes;
      return [
        MosaicBlock(
          itemIndex: 0,
          minutes: values[0],
          left: 0,
          top: 0,
          width: leftWidth,
          height: firstHeight,
        ),
        MosaicBlock(
          itemIndex: 1,
          minutes: values[1],
          left: 0,
          top: firstHeight,
          width: leftWidth,
          height: 1 - firstHeight,
        ),
        MosaicBlock(
          itemIndex: 2,
          minutes: values[2],
          left: leftWidth,
          top: 0,
          width: 1 - leftWidth,
          height: values[2] / rightMinutes,
        ),
        MosaicBlock(
          itemIndex: 3,
          minutes: values[3],
          left: leftWidth,
          top: values[2] / rightMinutes,
          width: 1 - leftWidth,
          height: values[3] / rightMinutes,
        ),
      ];
  }
}

/// True when a plan cannot fit into the confirmed daily capacity.
bool mosaicOverCapacity({
  required int plannedMinutes,
  required int capacityMinutes,
}) =>
    plannedMinutes > 0 &&
    (capacityMinutes <= 0 || plannedMinutes > capacityMinutes);
