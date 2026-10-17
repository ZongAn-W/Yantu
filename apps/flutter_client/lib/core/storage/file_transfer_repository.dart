import '../../shared/models/planner_models.dart';

abstract interface class FileTransferRepository {
  Future<PlannerData?> importJson();

  Future<bool> exportJson(PlannerData data);
}
