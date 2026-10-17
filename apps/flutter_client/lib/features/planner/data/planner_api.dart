import 'package:dio/dio.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/http/api_client.dart';
import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/scheduler/planner_scheduler.dart' as scheduler;

class PlannerApi {
  PlannerApi(this.client);
  final ApiClient client;

  /// Fresh idempotency key for one AI draft request.
  String newRequestId() => scheduler.newUuid();

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } catch (_) {
      throw const ResponseFailure();
    }
  }

  Future<PlannerData?> snapshot() async {
    try {
      final response = await client.get('/api/planner/snapshot');
      return _parse<PlannerData>(
        () => PlannerData.fromJson(JsonMap.from(response.data['data'] as Map)),
      );
    } on ValidationFailure catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<OnboardingProfile?> profile() async {
    final response = await client.get('/api/onboarding/profile');
    return _parse(() {
      final value = response.data['profile'];
      return value == null
          ? null
          : OnboardingProfile.fromJson(JsonMap.from(value as Map));
    });
  }

  Future<OnboardingProfile> saveProfile(OnboardingProfile profile) async {
    final response = await client.post(
      '/api/onboarding/profile',
      data: profile.toJson(),
    );
    return _parse(
      () => OnboardingProfile.fromJson(
        JsonMap.from(response.data['profile'] as Map),
      ),
    );
  }

  Future<DraftResponse> createDraft(
    OnboardingProfile profile, {
    required String requestId,
  }) async {
    final response = await client.post(
      '/api/ai/plan-drafts',
      data: profile.toJson(),
      options: Options(headers: {'Idempotency-Key': requestId}),
    );
    return _parse(
      () => DraftResponse.fromJson(JsonMap.from(response.data as Map)),
    );
  }

  Future<DraftResponse> getDraft(String id) async {
    final response = await client.get(
      '/api/ai/plan-drafts/${Uri.encodeComponent(id)}',
    );
    return _parse(
      () => DraftResponse.fromJson(JsonMap.from(response.data as Map)),
    );
  }

  Future<void> confirmDraft(String id, PlanDraft draft) async {
    final response = await client.post(
      '/api/ai/plan-drafts/${Uri.encodeComponent(id)}/confirm',
      data: {'draft': draft.toJson()},
    );
    if (response.data is! Map || response.data['confirmed'] != true) {
      throw const ResponseFailure();
    }
  }

  Future<void> recordLog({
    required String itemId,
    required String date,
    required int minutes,
    String feedback = '',
  }) async {
    await client.post(
      '/api/study-logs',
      data: {
        'item_id': itemId,
        'date': date,
        'minutes': minutes,
        'feedback': feedback,
      },
    );
  }

  Future<String> settleDay(String date, DailyReview review) async {
    final response = await client.post(
      '/api/daily-reviews/${Uri.encodeComponent(date)}/settle',
      data: review.toJson(),
    );
    return _parse(() => response.data['runId'] as String);
  }
}
