import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromEnvironment()),
      ],
      child: const PlannerApp(),
    ),
  );
}
