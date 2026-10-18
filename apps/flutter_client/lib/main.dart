import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/planner_fonts.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await loadFullPlannerFont();
  }
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromEnvironment()),
      ],
      child: const PlannerApp(),
    ),
  );
  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(loadFullPlannerFontInBackground());
    });
  }
}
