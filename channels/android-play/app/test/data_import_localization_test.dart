import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_app_state_backup.dart';
import 'package:account_subscription_manager/l10n/translations_app_state_general.dart';
import 'package:account_subscription_manager/l10n/translations_app_state_recovery.dart';
import 'package:account_subscription_manager/l10n/translations_core.dart';
import 'package:account_subscription_manager/l10n/translations_data_import.dart';
import 'package:account_subscription_manager/l10n/translations_domain.dart';
import 'package:account_subscription_manager/l10n/translations_platform.dart';
import 'package:account_subscription_manager/l10n/translations_records.dart';
import 'package:account_subscription_manager/l10n/translations_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const english = AppLocalizations(Locale('en'));
  const japanese = AppLocalizations(Locale('ja'));

  test('数据迁移独立目录的英日 key 与占位符完全一致', () {
    expect(
      dataImportEnglishTranslations.keys.toSet(),
      dataImportJapaneseTranslations.keys.toSet(),
    );
    expect(dataImportEnglishTranslations.length, greaterThanOrEqualTo(140));

    for (final source in dataImportEnglishTranslations.keys) {
      expect(
        _placeholders(dataImportEnglishTranslations[source]!),
        _placeholders(source),
        reason: '英语占位符不一致: $source',
      );
      expect(
        _placeholders(dataImportJapaneseTranslations[source]!),
        _placeholders(source),
        reason: '日语占位符不一致: $source',
      );
    }
  });

  test('与既有目录重复的通用 source 使用同一组英日译文', () {
    final canonicalEnglish = <String, String>{
      ...coreEnglishTranslations,
      ...appStateGeneralEnglishTranslations,
      ...appStateBackupEnglishTranslations,
      ...appStateRecoveryEnglishTranslations,
      ...domainEnglishTranslations,
      ...settingsEnglishTranslations,
      ...recordsEnglishTranslations,
      ...platformEnglishTranslations,
    };
    final canonicalJapanese = <String, String>{
      ...coreJapaneseTranslations,
      ...appStateGeneralJapaneseTranslations,
      ...appStateBackupJapaneseTranslations,
      ...appStateRecoveryJapaneseTranslations,
      ...domainJapaneseTranslations,
      ...settingsJapaneseTranslations,
      ...recordsJapaneseTranslations,
      ...platformJapaneseTranslations,
    };

    final conflicts = <String>[];
    for (final source in dataImportEnglishTranslations.keys) {
      if (canonicalEnglish[source] case final value?) {
        if (dataImportEnglishTranslations[source] != value) {
          conflicts.add(
            '英语重复 key 冲突: $source => '
            '${dataImportEnglishTranslations[source]} <> $value',
          );
        }
      }
      if (canonicalJapanese[source] case final value?) {
        if (dataImportJapaneseTranslations[source] != value) {
          conflicts.add(
            '日语重复 key 冲突: $source => '
            '${dataImportJapaneseTranslations[source]} <> $value',
          );
        }
      }
    }
    expect(conflicts, isEmpty, reason: conflicts.join('\n'));
  });

  test('每个数据迁移 source 均接入 AppLocalizations 且英日不回落源中文', () {
    final han = RegExp(r'[\u3400-\u9FFF]');
    final values = <String, Object?>{
      'account': 'Example account',
      'accounts': 11,
      'added': 2,
      'affected': 8,
      'bytes': 1024,
      'count': 3,
      'current': 4,
      'drafts': 1,
      'formal': 2,
      'format': 'UTF-8 · CSV',
      'merged': 1,
      'name': 'example.csv',
      'pending': 1,
      'row': 9,
      'selected': 7,
      'skipped': 2,
      'subscriptions': 4,
      'unsupported': 1,
      'updated': 1,
      'value': 'user@example.test',
    };

    for (final source in dataImportEnglishTranslations.keys) {
      expect(english.hasTranslation(source), isTrue, reason: '英语目录缺少: $source');
      expect(
        japanese.hasTranslation(source),
        isTrue,
        reason: '日语目录缺少: $source',
      );

      final englishText = english.translate(source, values);
      final japaneseText = japanese.translate(source, values);
      expect(
        han.hasMatch(englishText),
        isFalse,
        reason: '英语回落中文: $source -> $englishText',
      );
      if (!const <String>{'月', '年'}.contains(source)) {
        expect(japaneseText, isNot(source), reason: '日语回落源中文: $source');
      }
      expect(
        englishText,
        isNot(contains(RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}'))),
        reason: '英语仍有未替换占位符: $source',
      );
      expect(
        japaneseText,
        isNot(contains(RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}'))),
        reason: '日语仍有未替换占位符: $source',
      );
    }
  });

  test('迁移界面复用的通用按钮也在英日目录中', () {
    const commonSources = <String>['取消', '关闭', '处理中…'];
    for (final source in commonSources) {
      expect(english.hasTranslation(source), isTrue);
      expect(japanese.hasTranslation(source), isTrue);
      expect(english.translate(source), isNot(source));
      expect(japanese.translate(source), isNot(source));
    }
  });

  test('运行时插值模板可匹配审批摘要且不残留中文状态', () {
    const source =
        '当前真实保险库 · 已选 7 条\n'
        '新增账号 2 · 更新账号 1 · 跳过账号 3\n'
        '正式订阅 4 · 待完善草稿 1 · 不支持 0\n'
        '额度复核：通过 · 剩余账号 8 · 剩余订阅 2\n'
        '审批卡不显示密码原文；批准时会再次核对保险库代次和计划。';

    final englishText = english.translate(source);
    final japaneseText = japanese.translate(source);
    expect(englishText, allOf(contains('7'), contains('passed')));
    expect(englishText, isNot(contains('通过')));
    expect(japaneseText, allOf(contains('7'), contains('合格')));
    expect(japaneseText, isNot(contains('当前真实保险库')));
  });

  test('用户数据不作为 catalog source 翻译，作为模板值时也原样保留', () {
    const userValue = '用户自定义平台名称';
    expect(english.translate(userValue), userValue);
    expect(japanese.translate(userValue), userValue);

    final englishText = english.translate(
      '关联 {account} · 还需完善 {count} 项',
      const <String, Object?>{'account': userValue, 'count': 2},
    );
    final japaneseText = japanese.translate(
      '关联 {account} · 还需完善 {count} 项',
      const <String, Object?>{'account': userValue, 'count': 2},
    );
    expect(englishText, contains(userValue));
    expect(japaneseText, contains(userValue));
  });
}

List<String> _placeholders(String value) => <String>[
  for (final match in RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}').allMatches(value))
    match.group(1)!,
]..sort();
