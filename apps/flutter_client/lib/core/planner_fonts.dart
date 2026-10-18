import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const plannerFullFontFamily = 'NotoSansSCFull';

Future<void>? _fullFontLoad;

/// Kept out of FontManifest so the large font cannot delay the web's first frame.
Future<void> loadFullPlannerFont() => _fullFontLoad ??= _loadFullFont();

Future<void> _loadFullFont() async {
  try {
    final loader = FontLoader(plannerFullFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
    await loader.load();
  } catch (_) {
    _fullFontLoad = null;
    rethrow;
  }
}

Future<void> loadFullPlannerFontInBackground() async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await loadFullPlannerFont();
      // FontLoader notifies Flutter's text renderers to relayout missing glyphs.
      return;
    } catch (error) {
      debugPrint('Full Chinese font download failed: $error');
      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: 5 * (attempt + 1)));
      }
    }
  }
}
