import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.maybeOf(this) ??
      const AppLocalizations(Locale('zh', 'CN'));

  String tr(
    String source, [
    Map<String, Object?> values = const <String, Object?>{},
  ]) => l10n.translate(source, values);
}
