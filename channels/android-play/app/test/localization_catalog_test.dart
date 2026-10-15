import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_app_state_backup.dart';
import 'package:account_subscription_manager/l10n/translations_app_state_general.dart';
import 'package:account_subscription_manager/l10n/translations_app_state_recovery.dart';
import 'package:account_subscription_manager/l10n/translations_core.dart';
import 'package:account_subscription_manager/l10n/translations_cost_password.dart';
import 'package:account_subscription_manager/l10n/translations_domain.dart';
import 'package:account_subscription_manager/l10n/translations_platform.dart';
import 'package:account_subscription_manager/l10n/translations_records.dart';
import 'package:account_subscription_manager/l10n/translations_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supportedLocales 精确为简体中文、英语、日语', () {
    expect(AppLocalizations.supportedLocales, const <Locale>[
      Locale('zh', 'CN'),
      Locale('en'),
      Locale('ja'),
    ]);
  });

  test('运行时枚举、临时网页确认与错误模板在英日目录均有显式 key', () {
    const requiredSources = <String>[
      '待处理续费优先',
      '最近添加',
      '最早添加',
      '名称顺序',
      '跟随→',
      '仅本次',
      '历史摘要',
      '历史详情',
      '确认删除历史账号',
      '将删除“{name}”。',
      '将删除“{name}”及 {count} 条关联订阅。',
      '确认删除历史订阅',
      '确认临时显示历史密码',
      '网页将显示“{name}”的密码 30 秒。',
      '当前保险库状态不允许开启电脑临时录入。',
      '网页空闲时限必须为 1、5、10 或 30 分钟。',
      '所选局域网地址已不可用，请重新选择。',
      '局域网临时服务启动失败：{error}',
      '连接码验证失败或配对请求已失效。请重新开启本次临时连接。',
      '网页连接异常：{error}',
      '{service}，{account}，{amount}，{date}，{status}',
      '{service}，{status}',
      '开发者的话',
      '第一款作品 · 关于初心与维护',
      '微信号已复制',
      '复制失败，请稍后重试',
      '反馈时请勿发送主密码、备份密码、密码恢复答案、完整账号密码，或包含敏感信息的截图。开发者不会通过微信向你索取这些信息。',
      '其他激活方式',
      '已获得推广激活码',
      '如果你已获得开发者签发的推广激活码，可在此使用本机申请码完成离线激活。',
      '真实保险库密码恢复',
      '诱饵保险库密码恢复',
      '未配置 · 独立三道密保 + 本机系统强认证',
      '两套保险库不能使用完全相同的三道密保问题；请至少更换一道。',
      '直接显示“忘记密码？恢复保险库访问”',
      '忘记密码？恢复保险库访问',
      '下方会直接显示你设置时选择的三道问题。请填写对应答案，再通过本机指纹或安全级人脸。成功后会生成全新数据密钥并重设密码。',
      '此入口有多组已配置的密保问题。请选择要回答的一组；页面不会标明它对应哪个保险库。',
      '已配置密保问题组',
      '问题组 {number}',
      '无法完成恢复；请核对当前显示的三道问题及对应答案，并通过本机系统强认证。',
      '新保险库密码',
      '验证并重设保险库密码',
      '请选择下一步。找回访问不会显示旧密码；删除本机数据无法撤销。',
      '通过密保重设保险库密码',
      '删除本机数据并重新开始',
      '保险库密码恢复准备',
      '真实库和诱饵库均已配置恢复',
      '仅真实库已配置恢复',
      '仅诱饵库已配置恢复',
      '此操作不会找回旧密码，也不会解密旧数据；没有可用备份的数据将永久丢失。外部 .asmbackup 文件和合法完整版授权会保留。恢复备份仍需对应备份密码。',
      '账号与订阅数据默认加密保存在本机，不上传云端，也不进行云同步。卡坞不会申请通讯录、位置、外部存储或媒体读取权限，也不会扫描设备上的其他文件；导入或导出加密备份时，只会通过系统文件选择器处理你当次明确指定的文件。应用所需的 INTERNET 权限仅用于你主动开启“电脑临时录入”后，在自己的手机热点或可信 Wi-Fi 上提供短时局域网连接，不会连接公网、云端或中继，结束会话即停止。卡坞是一款真正属于你个人的本地工具，数据与使用方式的控制权始终在你手中。',
    ];
    const values = <String, Object?>{
      'name': 'Example',
      'count': 2,
      'error': 'Socket error',
      'service': 'Example service',
      'account': 'Example account',
      'amount': 'USD 9.99',
      'date': 'Dec 31, 2026',
      'status': 'Active',
      'number': 1,
    };
    const english = AppLocalizations(Locale('en'));
    const japanese = AppLocalizations(Locale('ja'));
    final han = RegExp(r'[\u3400-\u9FFF]');

    for (final source in requiredSources) {
      expect(
        english.hasTranslation(source),
        isTrue,
        reason: '英语目录缺少运行时 key: $source',
      );
      expect(
        japanese.hasTranslation(source),
        isTrue,
        reason: '日语目录缺少运行时 key: $source',
      );
      final englishText = english.translate(source, values);
      final japaneseText = japanese.translate(source, values);
      expect(
        han.hasMatch(englishText),
        isFalse,
        reason: '英语运行时文案残留中文: $source -> $englishText',
      );
      expect(
        englishText,
        isNot(contains(RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}'))),
        reason: '英语运行时文案仍有占位符: $source -> $englishText',
      );
      expect(
        japaneseText,
        isNot(contains(RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}'))),
        reason: '日语运行时文案仍有占位符: $source -> $japaneseText',
      );
    }

    expect(
      english.translate('将删除“Example”及 2 条关联订阅。'),
      allOf(isNot(contains('将删除')), contains('Example'), contains('2')),
    );
    expect(
      japanese.translate('网页将显示“Example”的密码 30 秒。'),
      allOf(isNot(contains('网页')), contains('Example'), contains('30')),
    );
  });

  test('每个分区的英语与日语 key、占位符完全一致且译文非空', () {
    final sections = <(String, Map<String, String>, Map<String, String>)>[
      ('core', coreEnglishTranslations, coreJapaneseTranslations),
      (
        'costPassword',
        costPasswordEnglishTranslations,
        costPasswordJapaneseTranslations,
      ),
      ('domain', domainEnglishTranslations, domainJapaneseTranslations),
      (
        'appStateGeneral',
        appStateGeneralEnglishTranslations,
        appStateGeneralJapaneseTranslations,
      ),
      (
        'appStateRecovery',
        appStateRecoveryEnglishTranslations,
        appStateRecoveryJapaneseTranslations,
      ),
      (
        'appStateBackup',
        appStateBackupEnglishTranslations,
        appStateBackupJapaneseTranslations,
      ),
      ('settings', settingsEnglishTranslations, settingsJapaneseTranslations),
      ('records', recordsEnglishTranslations, recordsJapaneseTranslations),
      ('platform', platformEnglishTranslations, platformJapaneseTranslations),
    ];

    for (final (name, english, japanese) in sections) {
      expect(
        english.keys.toSet(),
        japanese.keys.toSet(),
        reason: '$name key 集不一致',
      );
      for (final key in english.keys) {
        expect(key.trim(), isNotEmpty, reason: '$name 存在空 key');
        expect(english[key]!.trim(), isNotEmpty, reason: '$name 英语译文为空: $key');
        expect(japanese[key]!.trim(), isNotEmpty, reason: '$name 日语译文为空: $key');
        expect(
          _placeholders(english[key]!),
          _placeholders(key),
          reason: '$name 英语占位符不一致: $key',
        );
        expect(
          _placeholders(japanese[key]!),
          _placeholders(key),
          reason: '$name 日语占位符不一致: $key',
        );
      }
    }
  });

  test('英语目录不残留中文字符', () {
    final englishCatalogs = <Map<String, String>>[
      coreEnglishTranslations,
      costPasswordEnglishTranslations,
      domainEnglishTranslations,
      appStateGeneralEnglishTranslations,
      appStateRecoveryEnglishTranslations,
      appStateBackupEnglishTranslations,
      settingsEnglishTranslations,
      recordsEnglishTranslations,
      platformEnglishTranslations,
    ];
    final han = RegExp(r'[\u3400-\u9FFF]');
    for (final catalog in englishCatalogs) {
      for (final entry in catalog.entries) {
        expect(
          han.hasMatch(entry.value),
          isFalse,
          reason: '英语译文残留中文: ${entry.key} -> ${entry.value}',
        );
      }
    }
  });

  test('日语诱饵库术语统一为おとり，不混用デコイ', () {
    final japaneseCatalogs = <Map<String, String>>[
      coreJapaneseTranslations,
      domainJapaneseTranslations,
      appStateGeneralJapaneseTranslations,
      appStateRecoveryJapaneseTranslations,
      appStateBackupJapaneseTranslations,
      settingsJapaneseTranslations,
      recordsJapaneseTranslations,
      platformJapaneseTranslations,
    ];
    for (final catalog in japaneseCatalogs) {
      for (final entry in catalog.entries) {
        expect(
          entry.value,
          isNot(contains('デコイ')),
          reason: '日语诱饵库术语混用: ${entry.key} -> ${entry.value}',
        );
      }
    }
  });

  test('跨模块重复源键的英日译文不得冲突', () {
    final sections = <(String, Map<String, String>, Map<String, String>)>[
      ('core', coreEnglishTranslations, coreJapaneseTranslations),
      ('domain', domainEnglishTranslations, domainJapaneseTranslations),
      (
        'appStateGeneral',
        appStateGeneralEnglishTranslations,
        appStateGeneralJapaneseTranslations,
      ),
      (
        'appStateRecovery',
        appStateRecoveryEnglishTranslations,
        appStateRecoveryJapaneseTranslations,
      ),
      (
        'appStateBackup',
        appStateBackupEnglishTranslations,
        appStateBackupJapaneseTranslations,
      ),
      ('settings', settingsEnglishTranslations, settingsJapaneseTranslations),
      ('records', recordsEnglishTranslations, recordsJapaneseTranslations),
      ('platform', platformEnglishTranslations, platformJapaneseTranslations),
    ];

    final conflicts = <String>[];
    for (final languageIndex in <int>[1, 2]) {
      final languageLabel = languageIndex == 1 ? '英语' : '日语';
      final seen = <String, (String, String)>{};
      for (final section in sections) {
        final catalog = languageIndex == 1 ? section.$2 : section.$3;
        for (final entry in catalog.entries) {
          final previous = seen[entry.key];
          if (previous != null) {
            if (entry.value != previous.$2) {
              conflicts.add(
                '$languageLabel重复键冲突: ${entry.key} '
                '(${previous.$1} / ${section.$1}) => '
                '${previous.$2} <> ${entry.value}',
              );
            }
          } else {
            seen[entry.key] = (section.$1, entry.value);
          }
        }
      }
    }
    expect(conflicts, isEmpty, reason: conflicts.join('\n'));
  });

  test('动态模板支持英语和日语语序，并本地化冷却时长单位', () {
    const source = '主密码已连续输错3次，请等待2分钟后继续尝试；本机数据不会清空、锁死或删除。';
    final english = const AppLocalizations(Locale('en')).translate(source);
    final japanese = const AppLocalizations(Locale('ja')).translate(source);

    expect(english, contains('3 times'));
    expect(english, contains('2 min'));
    expect(japanese, contains('3回'));
    expect(japanese, contains('2分'));
    expect(english, isNot(contains('分钟')));
    expect(japanese, isNot(contains('主密码')));
  });

  test('备份恢复与密码恢复术语分离，首次建库警告反映可配置恢复能力', () {
    const rollbackSource = '本机恢复前回滚副本已按你的确认永久废弃，但主密码未修改；当前保险库仍使用原主密码。';
    const setupSource = '忘记主密码将无法恢复本地记录。创建后可在设置中启用生物识别并导出加密备份。';
    final english = const AppLocalizations(Locale('en'));
    final japanese = const AppLocalizations(Locale('ja'));

    expect(english.translate(rollbackSource), contains('pre-restore'));
    expect(english.translate(rollbackSource), isNot(contains('pre-recovery')));
    expect(japanese.translate(rollbackSource), contains('復元前'));
    expect(japanese.translate(rollbackSource), isNot(contains('復旧前')));
    expect(
      english.translate(setupSource),
      contains('set up password recovery'),
    );
    expect(japanese.translate(setupSource), contains('パスワード復旧を設定する前'));
  });

  test('通知说明在英日目录中明确跟随所选隐私级别', () {
    const source = '通知内容取决于你选择的隐私级别；应用内记录才是权威来源';
    final english = const AppLocalizations(Locale('en')).translate(source);
    final japanese = const AppLocalizations(Locale('ja')).translate(source);

    expect(english, contains('selected privacy level'));
    expect(english, contains('authoritative source'));
    expect(japanese, contains('選択したプライバシーレベル'));
    expect(japanese, contains('Cardock内の記録'));
  });

  test('缺失 key 在中文和非中文均安全回显，不改写用户数据', () {
    const userValue = '用户自定义平台名称';
    expect(
      const AppLocalizations(Locale('zh', 'CN')).translate(userValue),
      userValue,
    );
    expect(
      const AppLocalizations(Locale('en')).translate(userValue),
      userValue,
    );
    expect(
      const AppLocalizations(Locale('ja')).translate(userValue),
      userValue,
    );
  });
}

List<String> _placeholders(String value) => <String>[
  for (final match in RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}').allMatches(value))
    match.group(1)!,
]..sort();
