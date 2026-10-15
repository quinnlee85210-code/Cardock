import 'dart:io';

import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stage3 account UI static Chinese copy has explicit English and Japanese translations',
    () {
      const paths = [
        'lib/features/accounts/presentation/account_custom_fields_card.dart',
        'lib/features/accounts/presentation/account_custom_fields_editor.dart',
        'lib/features/accounts/presentation/account_duplicate_dialog.dart',
        'lib/features/accounts/presentation/binding_center_page.dart',
        'lib/features/accounts/presentation/password_generator_sheet.dart',
        'lib/features/accounts/presentation/password_health_center_page.dart',
        'lib/features/accounts/domain/account_analysis.dart',
        'lib/features/accounts/domain/account_custom_field.dart',
      ];
      final literals = RegExp(r"'((?:\\.|[^'\\])*)'");
      final han = RegExp(r'[\u3400-\u9fff]');
      final missing = <String>{};
      for (final path in paths) {
        final source = File(path).readAsStringSync();
        for (final match in literals.allMatches(source)) {
          final value = match.group(1)!;
          if (!han.hasMatch(value) ||
              value.contains(r'$') ||
              value.contains('\\')) {
            continue;
          }
          for (final locale in [const Locale('en'), const Locale('ja')]) {
            if (!AppLocalizations(locale).hasTranslation(value)) {
              missing.add('${locale.languageCode}: $value');
            }
          }
        }
      }
      expect(missing, isEmpty);
    },
  );
}
