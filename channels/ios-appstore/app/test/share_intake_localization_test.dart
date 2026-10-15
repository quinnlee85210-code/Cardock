import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_share_intake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('分享入口英日目录 key 完全一致、译文非空且英语无中文残留', () {
    expect(
      shareIntakeEnglishTranslations.keys.toSet(),
      shareIntakeJapaneseTranslations.keys.toSet(),
    );
    final han = RegExp(r'[\u3400-\u9FFF]');
    for (final entry in shareIntakeEnglishTranslations.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      expect(han.hasMatch(entry.value), isFalse, reason: entry.key);
      expect(
        _placeholders(entry.value),
        _placeholders(entry.key),
        reason: '英语占位符不一致: ${entry.key}',
      );
    }
    for (final entry in shareIntakeJapaneseTranslations.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      expect(
        _placeholders(entry.value),
        _placeholders(entry.key),
        reason: '日语占位符不一致: ${entry.key}',
      );
      expect(entry.value, isNot(contains('デコイ')), reason: entry.key);
    }
  });

  test('分享入口关键警告在中英日运行时目录均可解析', () {
    const keys = <String>[
      '从其他应用分享文字',
      'Android“分享至 Cardock”',
      '只在本机内存中解析，不上传、不联网打开网址。只有点按保存后，所选结构化字段才会进入当前解锁保险库的待完善草稿。',
      '草稿只写入这个账号所在的当前真实库或诱饵库，不会跨库。',
      '分享内容已过期并从内存中清除。',
      '这项分享不是受支持的纯文本或 http(s) 链接。',
    ];
    const english = AppLocalizations(Locale('en'));
    const japanese = AppLocalizations(Locale('ja'));
    for (final key in keys) {
      expect(english.hasTranslation(key), isTrue, reason: 'en: $key');
      expect(japanese.hasTranslation(key), isTrue, reason: 'ja: $key');
      expect(english.translate(key), isNot(key));
      expect(japanese.translate(key), isNot(key));
    }
  });

  test('确认页全部静态文案在英日运行时目录都有显式翻译', () {
    const keys = <String>[
      '从分享内容整理订阅',
      '取消并清除',
      '原始分享内容',
      '默认收起；离开、锁定、过期或保存后清除',
      '标题',
      '主题',
      '正文',
      '候选字段',
      '候选只作为本机建议；你可以编辑、清空或保持留空。',
      '检测到多个候选的字段没有自动选定；请点选、手工编辑、清空或保持留空。',
      '平台或服务名（仅用于核对）',
      '不会新建或修改账号；保存时以你选择的已有账号为准。',
      '套餐名称（可留空）',
      '金额（可留空）',
      '金额格式无效',
      '币种',
      '币种必须为 3 位字母代码',
      '计费周期数量',
      '计费周期单位',
      '清空计费周期',
      '下次续费日期（可留空）',
      '尚未选择',
      '清空日期',
      '选择日期',
      '自动续费（可留空）',
      '留空',
      '是',
      '否',
      '网页地址（仅用于核对）',
      '只接受 http(s)；Cardock 不会打开、抓取或保存为新账号网址。',
      '只接受有效的 http(s) 网页地址',
      '关联当前保险库中的已有账号',
      '关联已有账号（保存草稿必选）',
      '草稿只写入这个账号所在的当前真实库或诱饵库，不会跨库。',
      '尚未选择已有账号',
      '当前保险库没有已有账号；本次只能取消或清除，不会自动创建账号。',
      '清除本次内容',
      '保存待完善草稿',
      '正在保存…',
      '天',
      '周',
      '月',
      '个月',
      '年',
      '知道了',
    ];
    const english = AppLocalizations(Locale('en'));
    const japanese = AppLocalizations(Locale('ja'));
    for (final key in keys) {
      expect(english.hasTranslation(key), isTrue, reason: 'en: $key');
      expect(japanese.hasTranslation(key), isTrue, reason: 'ja: $key');
    }
  });
}

List<String> _placeholders(String value) => <String>[
  for (final match in RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}').allMatches(value))
    match.group(1)!,
]..sort();
