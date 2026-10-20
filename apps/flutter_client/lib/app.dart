import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/settings/application/theme_preference.dart';
import 'core/widgets.dart';
import 'router/app_router.dart';

class PlannerApp extends ConsumerWidget {
  const PlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '不白学 · 学习执行台',
      debugShowCheckedModeBanner: false,
      theme: plannerTheme(),
      darkTheme: plannerDarkTheme(),
      themeMode: ref.watch(plannerThemeModeProvider).themeMode,
      scrollBehavior: const PlannerScrollBehavior(),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
