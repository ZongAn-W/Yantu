import '../../../core/http/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/onboarding_session.dart';

class OnboardingApi {
  OnboardingApi(this.client);
  final ApiClient client;

  OnboardingSession _parse(dynamic data) {
    try {
      return OnboardingSession.fromJson(JsonMap.from(data['session'] as Map));
    } catch (_) {
      throw const ResponseFailure();
    }
  }

  Future<OnboardingSession> load() async =>
      _parse((await client.get('/api/onboarding/session')).data);
  Future<OnboardingSession> advance(int revision, JsonMap action) async =>
      _parse(
        (await client.post(
          '/api/ai/onboarding/advance',
          data: {'revision': revision, 'action': action},
        )).data,
      );
}
