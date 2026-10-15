import 'dart:io';

import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'browser URL carries the phone-selected locale without changing data',
    () {
      final english = TemporaryWebSessionSnapshot(
        phase: TemporaryWebSessionPhase.waitingForPairing,
        policy: const TemporaryWebSessionPolicy(),
        pendingApprovals: const <TemporaryWebApproval>[],
        language: CardockLanguage.english,
        address: '192.168.1.2',
        port: 8080,
      );
      final japanese = TemporaryWebSessionSnapshot(
        phase: TemporaryWebSessionPhase.waitingForPairing,
        policy: const TemporaryWebSessionPolicy(),
        pendingApprovals: const <TemporaryWebApproval>[],
        language: CardockLanguage.japanese,
        address: '192.168.1.2',
        port: 8080,
      );

      expect(english.browserUri!.queryParameters['lang'], 'en');
      expect(japanese.browserUri!.queryParameters['lang'], 'ja');
      expect(english.browserUri!.host, '192.168.1.2');
    },
  );

  test('temporary web HTML has complete English and Japanese static copy', () {
    final html = File('assets/temporary_web/index.html').readAsStringSync();
    final controller = File(
      'lib/core/temporary_web/temporary_web_controller.dart',
    ).readAsStringSync();

    final textNodes = _tagsWithAttribute(html, 'data-i18n');
    final placeholders = _tagsWithAttribute(html, 'data-i18n-placeholder');
    final options = _tagsWithAttribute(html, 'data-i18n-option');

    expect(textNodes.length, greaterThanOrEqualTo(108));
    expect(placeholders.length, greaterThanOrEqualTo(3));
    expect(options, hasLength(9));
    for (final node in textNodes) {
      expect(node, matches(RegExp(r'\sdata-en="[^"]+"')));
      expect(node, matches(RegExp(r'\sdata-ja="[^"]+"')));
    }
    for (final node in placeholders) {
      expect(node, matches(RegExp(r'\sdata-placeholder-en="[^"]+"')));
      expect(node, matches(RegExp(r'\sdata-placeholder-ja="[^"]+"')));
    }
    for (final node in options) {
      expect(node, matches(RegExp(r'\sdata-label-en="[^"]+"')));
      expect(node, matches(RegExp(r'\sdata-label-ja="[^"]+"')));
      expect(node, matches(RegExp(r'\sdata-value-en="[^"]+"')));
      expect(node, matches(RegExp(r'\sdata-value-ja="[^"]+"')));
      expect(
        _attributeValue(node, 'data-value-en'),
        _attributeValue(node, 'data-label-en'),
      );
      expect(
        _attributeValue(node, 'data-value-ja'),
        _attributeValue(node, 'data-label-ja'),
      );
    }

    expect(html, contains('data-en="Temporary PC Entry"'));
    expect(html, contains('data-ja="パソコンから一時入力"'));
    expect(
      html,
      contains(
        'data-en="This page is served by your phone and does not connect '
        'to the public internet, cloud services, or a relay."',
      ),
    );
    expect(
      html,
      contains(
        'data-ja="このページはスマートフォンから配信され、パブリックインターネット、'
        'クラウドサービス、リレーには接続しません。"',
      ),
    );
    expect(html, contains('data-en="Linked account (optional)"'));
    expect(html, contains('data-ja="関連アカウント（任意）"'));
    expect(html, contains('data-en="Enable local reminders"'));
    expect(html, contains('data-ja="端末内の通知を有効化"'));
    expect(html, contains('data-en="Source row"'));
    expect(html, contains('data-ja="元の行"'));
    expect(html, contains('data-en="Platform / plan"'));
    expect(html, contains('data-ja="プラットフォーム / プラン"'));
    expect(html, contains('data-en="Password / billing cycle"'));
    expect(html, contains('data-ja="パスワード / 請求周期"'));
    expect(
      html,
      contains(
        'data-en="Field-by-field duplicate merging is handled only in the '
        'phone migration center.',
      ),
    );
    expect(
      html,
      contains('data-ja="重複項目のフィールド単位のマージは、スマートフォンの移行センターでのみ処理します。'),
    );
    expect(html, contains('maxlength="10485760"'));
    expect(html, contains('value="CNY"'));
    expect(html, contains('value="__custom__"'));
    expect(html, contains('value="AI工具"'));
    expect(controller, contains("'locale': _language.storageCode"));
  });

  test(
    'built-in categories are localized for display and submitted canonically',
    () {
      final html = File('assets/temporary_web/index.html').readAsStringSync();
      final client = File('tool/temporary_web_client.dart').readAsStringSync();
      const categories = <String, ({String english, String japanese})>{
        'AI工具': (english: 'AI tools', japanese: 'AIツール'),
        '影音娱乐': (english: 'Entertainment', japanese: '動画・音楽'),
        '购物': (english: 'Shopping', japanese: 'ショッピング'),
        '社交': (english: 'Social', japanese: 'ソーシャル'),
        '办公': (english: 'Productivity', japanese: '仕事効率化'),
        '云服务': (english: 'Cloud services', japanese: 'クラウドサービス'),
        '金融': (english: 'Finance', japanese: '金融'),
        '保险': (english: 'Insurance', japanese: '保険'),
        '其他': (english: 'Other', japanese: 'その他'),
      };

      for (final entry in categories.entries) {
        final canonical = RegExp.escape(entry.key);
        final english = RegExp.escape(entry.value.english);
        final japanese = RegExp.escape(entry.value.japanese);
        expect(
          client,
          matches(
            RegExp(
              "'$canonical':\\s*\\(\\s*english:\\s*'$english',\\s*"
              "japanese:\\s*'$japanese'\\s*\\)",
              multiLine: true,
            ),
          ),
          reason: '动态翻译表缺少内置分类 ${entry.key}',
        );
        expect(html, contains('value="${entry.key}"'));
        expect(html, contains('data-label-en="${entry.value.english}"'));
        expect(html, contains('data-label-ja="${entry.value.japanese}"'));
        expect(html, contains('data-value-en="${entry.value.english}"'));
        expect(html, contains('data-value-ja="${entry.value.japanese}"'));
      }

      final staticOptionContract = _sourceBlock(
        client,
        "for (final option in document.querySelectorAll('[data-i18n-option]'))",
        'void _applyResponseLocale(',
      );
      expect(staticOptionContract, contains("'data-value-zh'"));
      expect(
        staticOptionContract,
        contains("_PageLanguage.english => option.attributes['data-value-en']"),
      );
      expect(
        staticOptionContract,
        contains(
          "_PageLanguage.japanese => option.attributes['data-value-ja']",
        ),
      );
      expect(
        staticOptionContract,
        contains("option.attributes['value'] = value"),
      );

      final categoryContract = _sourceBlock(
        client,
        'String _displayAccountCategory(',
        'String? _cycleText(',
      );
      expect(
        categoryContract,
        contains('accountCategories.contains(value) ? _text(value) : value'),
      );
      expect(
        categoryContract,
        contains('folded == translation?.english.toLowerCase()'),
      );
      expect(categoryContract, contains('normalized == translation?.japanese'));
      expect(categoryContract, contains('return category;'));
      expect(
        categoryContract,
        contains('return normalized;'),
        reason: '自定义分类应仅 trim，不得被翻译或替换',
      );
      expect(
        client,
        contains(
          "'category': _canonicalAccountCategory("
          "_input('account-category').value),",
        ),
      );
      final dynamicOptionContract = _sourceBlock(
        client,
        'void _populateCategoryChoices()',
        'void _renderAccounts(',
      );
      expect(
        dynamicOptionContract,
        contains('final displayCategory = _displayAccountCategory(category)'),
      );
      expect(
        dynamicOptionContract,
        contains(
          'OptionElement(data: displayCategory, value: displayCategory)',
        ),
      );
      expect(dynamicOptionContract, isNot(contains('value: category')));
    },
  );

  test(
    'free quota and invalid-field messages do not leak Chinese in EN or JA',
    () {
      final client = File('tool/temporary_web_client.dart').readAsStringSync();
      final quotaBlock = _sourceBlock(
        client,
        'final limitMatch = RegExp(',
        r"if (RegExp(r'^.+ 格式无效。$')",
      );
      const englishTemplate =
          r'The Free Version $type limit has been reached ($current/$maximum). '
          r'Unlock Full Version in Cardock settings on your phone and try again.';
      const japaneseTemplate =
          r'無料版の$type数が上限に達しました（$current/$maximum）。'
          r'スマートフォンのCardock設定で完全版を有効にしてから、もう一度お試しください。';

      expect(quotaBlock, contains("'$englishTemplate'"));
      expect(quotaBlock, contains("'$japaneseTemplate'"));
      expect(quotaBlock, contains("_text('账号')"));
      expect(quotaBlock, contains("_text('订阅')"));

      final english = _fillQuotaTemplate(englishTemplate, 'account', 3, 3);
      final japanese = _fillQuotaTemplate(japaneseTemplate, 'アカウント', 3, 3);
      expect(english, contains('(3/3)'));
      expect(english, isNot(contains('account 3/3')));
      expect(english, isNot(matches(RegExp(r'[\u3400-\u9FFF]'))));
      expect(japanese, contains('（3/3）'));
      expect(japanese, isNot(contains('アカウント 3/3')));
      for (final chinesePhrase in const <String>[
        '账户',
        '订阅数量',
        '已达上限',
        '请在手机设置中',
        '解锁完整版后重试',
      ]) {
        expect(japanese, isNot(contains(chinesePhrase)));
      }

      final invalidFieldBlock = _sourceBlock(
        client,
        r"if (RegExp(r'^.+ 格式无效。$')",
        r"if (RegExp(r'[\u4e00-\u9fff]').hasMatch(message))",
      );
      expect(
        invalidFieldBlock,
        contains('One of the submitted fields has an invalid format.'),
      );
      expect(invalidFieldBlock, contains('入力内容の形式が正しくありません。'));
    },
  );

  test('browser cycle, date, and reminder formatting follows locale rules', () {
    final client = File('tool/temporary_web_client.dart').readAsStringSync();
    final cycleBlock = _sourceBlock(
      client,
      'String _localizedSubscriptionCycle(',
      'String? _localizedRecordDateValue(',
    );

    expect(cycleBlock, contains("SubscriptionCycleUnit.day => '毎日'"));
    expect(cycleBlock, contains("SubscriptionCycleUnit.week => '毎週'"));
    expect(cycleBlock, contains("SubscriptionCycleUnit.month => '毎月'"));
    expect(cycleBlock, contains("SubscriptionCycleUnit.year => '毎年'"));
    expect(cycleBlock, contains("SubscriptionCycleUnit.week => '週間'"));
    expect(cycleBlock, contains(r"return '$count$labelごと';"));
    expect(
      cycleBlock,
      contains("SubscriptionCycleUnit.day => count == 1 ? 'day' : 'days'"),
    );
    expect(
      cycleBlock,
      contains("SubscriptionCycleUnit.week => count == 1 ? 'week' : 'weeks'"),
    );
    expect(
      cycleBlock,
      contains(
        r"return count == 1 ? 'Every $unitLabel' : "
        r"'Every $count $unitLabel';",
      ),
      reason: '1 day/week 应显示 Every day/week，不应显示 1 days/weeks',
    );

    final dateBlock = _sourceBlock(
      client,
      'String? _localizedRecordDateValue(',
      'String? _localizedDaysBeforeValue(',
    );
    expect(
      dateBlock,
      contains('DateTime(parsed.year, parsed.month, parsed.day)'),
    );
    expect(dateBlock, contains("'Feb'"));
    expect(dateBlock, contains("'Dec'"));
    expect(
      dateBlock,
      contains(
        r"return '${months[date.month - 1]} ${date.day}, ${date.year}';",
      ),
    );
    expect(
      dateBlock,
      contains(r"return '${date.year}年${date.month}月${date.day}日';"),
    );

    final reminderBlock = _sourceBlock(
      client,
      'String? _localizedDaysBeforeValue(',
      'String? _yesNo(',
    );
    expect(reminderBlock, contains("value == 1"));
    expect(reminderBlock, contains("'1 day before'"));
    expect(reminderBlock, contains(r"'$value days before'"));
    expect(reminderBlock, contains(r"'$value日前'"));
  });

  test(
    'temporary web client applies phone locale without mutating data codes',
    () {
      final client = File('tool/temporary_web_client.dart').readAsStringSync();

      expect(client, contains("'en' => _PageLanguage.english"));
      expect(client, contains("'ja' => _PageLanguage.japanese"));
      expect(client, contains('_applyResponseLocale(response)'));
      expect(
        client,
        contains(
          'To prevent hidden-history probing through duplicate results, '
          'enable history summaries or details for this connection on your phone',
        ),
      );
      expect(
        client,
        contains('重複結果から非表示の履歴を推測されないよう、スマートフォンで今回の接続に履歴の概要または詳細を許可'),
      );
      expect(client, isNot(contains("value=\"CNY\"")));
      expect(
        client,
        contains("'cycleUnit': _select('subscription-cycle-unit').value"),
      );
    },
  );

  test('batch templates offer localized XLSX DOCX TXT and CSV schemas', () {
    final client = File('tool/temporary_web_client.dart').readAsStringSync();
    final port = File(
      'lib/features/data_import/infrastructure/'
      'app_state_temporary_web_batch_import_port.dart',
    ).readAsStringSync();
    expect(client, contains("'账号关联标识'"));
    expect(client, contains("'Login Username'"));
    expect(client, contains("'パスワード'"));
    expect(client, contains("case 'docx':"));
    expect(client, contains("case 'txt':"));
    expect(client, contains("case 'csv':"));
    expect(client, contains('_buildXlsxTemplate(headers)'));
    expect(
      File('assets/temporary_web/index.html').readAsStringSync(),
      contains('next_renewal_date 只表示下次续费日期，绝不会代填开始日期'),
    );
    expect(
      File('assets/temporary_web/index.html').readAsStringSync(),
      contains('.xlsx,.docx,.csv,.tsv,.txt'),
    );
    expect(client, contains('0xEF,'));
    expect(client, contains('0xBB,'));
    expect(client, contains('0xBF,'));
    expect(port, contains('maximumDataRows: 5000'));
    expect(client, contains('10 * 1024 * 1024'));
    expect(client, contains("_showBatchSummary('已接收文件，正在读取…');"));
    expect(client, contains('reader.onAbort.first'));
    expect(client, contains('FILE_READER_ERROR'));
    expect(client, contains('FILE_READER_RESULT_TYPE'));
    expect(client, contains('BATCH_UPLOAD_FAILED'));
    expect(client, contains('_batchRejectionMessage('));
    expect(client, contains("response['errorCode']"));
    expect(
      client,
      isNot(contains("throw StateError(response['message'] as String?")),
    );
  });
}

List<String> _tagsWithAttribute(String html, String attribute) => RegExp(
  '<[^>]*\\s${RegExp.escape(attribute)}(?=[\\s=>])[^>]*>',
  caseSensitive: false,
  multiLine: true,
).allMatches(html).map((match) => match.group(0)!).toList();

String? _attributeValue(String tag, String attribute) =>
    RegExp('${RegExp.escape(attribute)}="([^"]*)"').firstMatch(tag)?.group(1);

String _sourceBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, isNonNegative, reason: '找不到源码起点: $startMarker');
  expect(end, greaterThan(start), reason: '找不到源码终点: $endMarker');
  return source.substring(start, end);
}

String _fillQuotaTemplate(
  String template,
  String type,
  int current,
  int maximum,
) => template
    .replaceAll(r'$type', type)
    .replaceAll(r'$current', '$current')
    .replaceAll(r'$maximum', '$maximum');
