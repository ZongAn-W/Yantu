Map<String, dynamic> onboardingFixture({
  String stage = 'interview',
  int answers = 0,
}) => {
  'revision': answers,
  'stage': stage,
  'question': answers == 0 ? '你的长期目标是什么？' : '你目前的基础和准备情况如何？',
  'answers': [
    for (var i = 0; i < answers; i++)
      {'question': '问题${i + 1}', 'answer': '回答${i + 1}'},
  ],
  'profile': {
    'goal_text': '准备计算机专业研究生考试',
    'goal_type': 'exam',
    'goal_subtype': '考研',
    'weekly_minutes': {for (var i = 0; i < 7; i++) '$i': 120},
  },
  'courses': <Map<String, dynamic>>[],
  'items': <Map<String, dynamic>>[],
  'summary': '',
  'assumptions': <String>[],
  'warnings': <String>[],
  'start_date': '',
};
