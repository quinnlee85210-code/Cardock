import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/preferences/language_preferences.dart';
import 'translations_app_state_general.dart';
import 'translations_app_state_backup.dart';
import 'translations_app_state_recovery.dart';
import 'translations_core.dart';
import 'translations_ios_phase1.dart';
import 'translations_commercial.dart';
import 'translations_cost_password.dart';
import 'translations_data_import.dart';
import 'translations_domain.dart';
import 'translations_platform.dart';
import 'translations_purchase_credential.dart';
import 'translations_records.dart';
import 'translations_settings.dart';
import 'translations_share_intake.dart';
import 'translations_stage1.dart';
import 'translations_stage2.dart';
import 'translations_stage3.dart';
import 'translations_stage4.dart';
import 'translations_stage3_portability.dart';

final Map<String, String> _englishCatalog =
    Map<String, String>.unmodifiable(<String, String>{
      ...shareIntakeEnglishTranslations,
      ...stage1EnglishTranslations,
      ...stage2EnglishTranslations,
      ...stage3EnglishTranslations,
      ...stage3PortabilityEnglishTranslations,
      ...dataImportEnglishTranslations,
      ...coreEnglishTranslations,
      ...costPasswordEnglishTranslations,
      ...appStateGeneralEnglishTranslations,
      ...appStateBackupEnglishTranslations,
      ...appStateRecoveryEnglishTranslations,
      ...domainEnglishTranslations,
      ...purchaseCredentialEnglishTranslations,
      ...settingsEnglishTranslations,
      ...recordsEnglishTranslations,
      ...platformEnglishTranslations,
      ...stage4EnglishTranslations,
      ...commercialEnglishTranslations,
      ...iosPhase1EnglishTranslations,
    });

final Map<String, String> _japaneseCatalog =
    Map<String, String>.unmodifiable(<String, String>{
      ...shareIntakeJapaneseTranslations,
      ...stage1JapaneseTranslations,
      ...stage2JapaneseTranslations,
      ...stage3JapaneseTranslations,
      ...stage3PortabilityJapaneseTranslations,
      ...dataImportJapaneseTranslations,
      ...coreJapaneseTranslations,
      ...costPasswordJapaneseTranslations,
      ...appStateGeneralJapaneseTranslations,
      ...appStateBackupJapaneseTranslations,
      ...appStateRecoveryJapaneseTranslations,
      ...domainJapaneseTranslations,
      ...purchaseCredentialJapaneseTranslations,
      ...settingsJapaneseTranslations,
      ...recordsJapaneseTranslations,
      ...platformJapaneseTranslations,
      ...stage4JapaneseTranslations,
      ...commercialJapaneseTranslations,
      ...iosPhase1JapaneseTranslations,
    });

final List<_TemplateTranslation> _englishTemplates = _buildTemplateTranslations(
  {...stage4EnglishTranslations, ..._englishCatalog},
);
final List<_TemplateTranslation> _japaneseTemplates =
    _buildTemplateTranslations({
      ...stage4JapaneseTranslations,
      ...commercialJapaneseTranslations,
      ...iosPhase1JapaneseTranslations,
      ..._japaneseCatalog,
    });

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('en'),
    Locale('ja'),
  ];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];

  static AppLocalizations of(BuildContext context) {
    final localizations = maybeOf(context);
    assert(localizations != null, 'AppLocalizations is missing.');
    return localizations!;
  }

  static AppLocalizations? maybeOf(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations);

  CardockLanguage get language => switch (locale.languageCode) {
    'en' => CardockLanguage.english,
    'ja' => CardockLanguage.japanese,
    _ => CardockLanguage.simplifiedChinese,
  };

  Map<String, String> get catalog => switch (language) {
    CardockLanguage.simplifiedChinese => const <String, String>{},
    CardockLanguage.english => _englishCatalog,
    CardockLanguage.japanese => _japaneseCatalog,
  };

  String translate(
    String source, [
    Map<String, Object?> values = const <String, Object?>{},
  ]) {
    var result = catalog[source];
    if (result == null && language != CardockLanguage.simplifiedChinese) {
      final templates = language == CardockLanguage.english
          ? _englishTemplates
          : _japaneseTemplates;
      for (final template in templates) {
        final match = template.pattern.firstMatch(source);
        if (match == null) continue;
        var translated = template.translation;
        for (var index = 0; index < template.placeholders.length; index++) {
          final value = _localizeCapturedValue(match.group(index + 1)!);
          translated = translated.replaceAll(
            '{${template.placeholders[index]}}',
            value,
          );
        }
        result = translated;
        break;
      }
    }
    var resolved = result ?? source;
    for (final entry in values.entries) {
      resolved = resolved.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return resolved;
  }

  String plural({
    required int count,
    required String one,
    required String other,
    String? zero,
    Map<String, Object?> values = const <String, Object?>{},
  }) {
    final source = count == 0 && zero != null
        ? zero
        : language == CardockLanguage.english && count == 1
        ? one
        : other;
    return translate(source, <String, Object?>{'count': count, ...values});
  }

  bool hasTranslation(String source) => catalog.containsKey(source);

  String get appTitle => translate('Cardock');

  String _localizeCapturedValue(String value) {
    final duration = RegExp(r'^(\d+)(秒|分钟)$').firstMatch(value);
    if (duration == null) return value;
    final amount = duration.group(1)!;
    final unit = duration.group(2)!;
    return switch (language) {
      CardockLanguage.english => unit == '秒' ? '$amount sec' : '$amount min',
      CardockLanguage.japanese => unit == '秒' ? '$amount秒' : '$amount分',
      CardockLanguage.simplifiedChinese => value,
    };
  }
}

class _TemplateTranslation {
  const _TemplateTranslation({
    required this.pattern,
    required this.placeholders,
    required this.translation,
  });

  final RegExp pattern;
  final List<String> placeholders;
  final String translation;
}

List<_TemplateTranslation> _buildTemplateTranslations(
  Map<String, String> catalog,
) {
  final translations = <_TemplateTranslation>[];
  final placeholderPattern = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');
  for (final entry in catalog.entries) {
    final matches = placeholderPattern.allMatches(entry.key).toList();
    if (matches.isEmpty) continue;
    final pattern = StringBuffer('^');
    var offset = 0;
    for (final match in matches) {
      pattern
        ..write(RegExp.escape(entry.key.substring(offset, match.start)))
        ..write('(.+?)');
      offset = match.end;
    }
    pattern
      ..write(RegExp.escape(entry.key.substring(offset)))
      ..write(r'$');
    translations.add(
      _TemplateTranslation(
        pattern: RegExp(pattern.toString(), dotAll: true),
        placeholders: matches
            .map((match) => match.group(1)!)
            .toList(growable: false),
        translation: entry.value,
      ),
    );
  }
  return List<_TemplateTranslation>.unmodifiable(translations);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' ||
      locale.languageCode == 'en' ||
      locale.languageCode == 'ja';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
