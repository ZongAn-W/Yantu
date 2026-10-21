import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_month_mosaic.dart';

void main() {
  test('one block fills the whole tile', () {
    final blocks = layoutMosaicBlocks([90]);
    expect(blocks, hasLength(1));
    expect(blocks.single.itemIndex, 0);
    expect(blocks.single.left, 0);
    expect(blocks.single.top, 0);
    expect(blocks.single.width, 1);
    expect(blocks.single.height, 1);
  });

  test('two blocks split the tile left/right by minutes', () {
    final blocks = layoutMosaicBlocks([120, 60]);
    expect(blocks, hasLength(2));
    expect(blocks[0].width, closeTo(2 / 3, 0.0001));
    expect(blocks[0].height, 1);
    expect(blocks[1].left, closeTo(2 / 3, 0.0001));
    expect(blocks[1].width, closeTo(1 / 3, 0.0001));
    expect(blocks[1].height, 1);
    expect(blocks[0].top + blocks[0].height, closeTo(1, 0.0001));
  });

  test('three blocks use an L shape and preserve every area', () {
    final blocks = layoutMosaicBlocks([90, 60, 30]);
    expect(blocks, hasLength(3));
    final totalArea = blocks.fold<double>(
      0,
      (sum, block) => sum + block.width * block.height,
    );
    expect(totalArea, closeTo(1, 0.0001));
    expect(blocks[0].width, closeTo(90 / 180, 0.0001));
    expect(blocks[1].left, closeTo(90 / 180, 0.0001));
    expect(blocks[2].top, closeTo(60 / 90, 0.0001));
    expect(blocks[1].left + blocks[1].width, closeTo(1, 0.0001));
  });

  test('four blocks use two proportional columns', () {
    final blocks = layoutMosaicBlocks([120, 60, 90, 30]);
    expect(blocks, hasLength(4));
    final totalArea = blocks.fold<double>(
      0,
      (sum, block) => sum + block.width * block.height,
    );
    expect(totalArea, closeTo(1, 0.0001));
    expect(blocks[0].width, closeTo(180 / 300, 0.0001));
    expect(blocks[2].left, closeTo(180 / 300, 0.0001));
  });

  test('more than four items fold the tail into the last block', () {
    final blocks = layoutMosaicBlocks([100, 80, 60, 40, 30, 20]);
    expect(blocks, hasLength(maxMosaicBlocks));
    expect(blocks.last.itemIndex, maxMosaicBlocks - 1);
    expect(blocks.last.minutes, 40 + 30 + 20);
    expect(
      blocks.fold<int>(0, (sum, block) => sum + block.minutes),
      100 + 80 + 60 + 40 + 30 + 20,
    );
  });

  test('zero and negative minutes are ignored', () {
    expect(layoutMosaicBlocks(const [0, -5]), isEmpty);
    final blocks = layoutMosaicBlocks(const [0, 60, 0, 30]);
    expect(blocks, hasLength(2));
    expect(blocks[0].minutes, 60);
    expect(blocks[1].minutes, 30);
  });

  test('fill ratio clamps and handles zero capacity', () {
    expect(mosaicFillRatio(plannedMinutes: 0, capacityMinutes: 180), 0);
    expect(mosaicFillRatio(plannedMinutes: 45, capacityMinutes: 180), 0.25);
    expect(mosaicFillRatio(plannedMinutes: 270, capacityMinutes: 240), 1);
    expect(mosaicFillRatio(plannedMinutes: 60, capacityMinutes: 0), 1);
    expect(mosaicFillRatio(plannedMinutes: 0, capacityMinutes: 0), 0);
  });

  test('over-capacity rule matches the month snapshot rule', () {
    expect(
      mosaicOverCapacity(plannedMinutes: 270, capacityMinutes: 240),
      isTrue,
    );
    expect(
      mosaicOverCapacity(plannedMinutes: 240, capacityMinutes: 240),
      isFalse,
    );
    expect(mosaicOverCapacity(plannedMinutes: 60, capacityMinutes: 0), isTrue);
    expect(mosaicOverCapacity(plannedMinutes: 0, capacityMinutes: 0), isFalse);
  });
}
