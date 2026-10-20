/// Vendored third-party UI code adapted into the planner client.
///
/// W1 vendors only the Lucide icon font and the subset of icon codepoints the
/// client uses: the upstream `lucide_icons_flutter` package declares seven
/// font families (default + weight variants 100-600), and Flutter bundles all
/// package fonts even when only the default family is referenced. See
/// `lucide/` for the license texts and README.md for the import rules.
library;

export 'lucide.dart';
