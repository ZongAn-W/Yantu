import 'dart:convert';
import 'dart:io';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

PlannerData plannerFixture() => PlannerData.fromJson(
  jsonDecode(File('test/fixtures/planner_v1.json').readAsStringSync())
      as JsonMap,
);
