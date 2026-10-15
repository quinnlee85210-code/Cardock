import 'package:account_subscription_manager/core/share_intake/share_subscription_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ShareSubscriptionTextParser();

  test('中英日混合订阅文字只提取有上下文的结构化候选', () {
    final result = parser.parse(
      title: 'Example サブスクリプション',
      subject: 'service: Example',
      text: '''
平台：Example
プラン: Premium
金额: CNY 29.90
3か月ごと
续费日期：2026-10-15
自动续费：开启
https://billing.example.test/manage
''',
    );

    expect(result.platforms, <String>['Example']);
    expect(result.plans, <String>['Premium']);
    expect(result.amounts, hasLength(1));
    expect(result.amounts.single.amount, '29.90');
    expect(result.amounts.single.currency, 'CNY');
    expect(result.currencies, <String>['CNY']);
    expect(result.cycles, hasLength(1));
    expect(result.cycles.single.count, 3);
    expect(result.cycles.single.unit, ShareCycleUnit.month);
    expect(result.renewalDates.single, DateTime(2026, 10, 15));
    expect(result.autoRenewValues, <bool>[true]);
    expect(result.urls, <String>['https://billing.example.test/manage']);
  });

  test('多个候选和冲突值全部保留，不替用户猜测', () {
    final result = parser.parse(
      text: '''
plan: Basic
plan: Pro
USD 9.99 monthly
EUR 8.99 yearly
auto-renew: on
auto-renew: off
续费: 2026-11-01
renewal: 2026-12-01
''',
    );

    expect(result.plans, <String>['Basic', 'Pro']);
    expect(result.amounts, hasLength(2));
    expect(result.currencies.toSet(), <String>{'USD', 'EUR'});
    expect(result.cycles, hasLength(2));
    expect(result.autoRenewValues.toSet(), <bool>{true, false});
    expect(result.renewalDates, hasLength(2));
  });

  test('订单税费退款一次性购买等负向上下文不会生成订阅候选', () {
    final result = parser.parse(
      text: '''
订单号: USD 999.00 https://orders.example.test/1
一次性购买：EUR 88.00
Tax: GBP 5.00
返金 2026年12月1日
shipping every 3 months
续费金额: CNY 12.00
续费日期: 2026-09-30
''',
    );

    expect(result.amounts, hasLength(1));
    expect(result.amounts.single.label, 'CNY 12.00');
    expect(result.cycles, isEmpty);
    expect(result.urls, isEmpty);
    expect(result.renewalDates, <DateTime>[DateTime(2026, 9, 30)]);
  });

  test('不明确的货币符号、无续费上下文日期和危险网址不会被猜测', () {
    final result = parser.parse(
      text: '''
¥1200
\$9.99
金额: 1000
创建日期: 2026-08-01
https://user:secret@example.test/path
https://safe.example.test/path
content://provider/item
''',
    );

    expect(result.amounts, hasLength(1));
    expect(result.amounts.single.amount, '1000');
    expect(result.amounts.single.currency, isNull);
    expect(result.currencies, isEmpty);
    expect(result.renewalDates, isEmpty);
    expect(result.urls, <String>['https://safe.example.test/path']);
  });

  test('无效日期、过大周期和重复候选被安全忽略或去重', () {
    final result = parser.parse(
      text: '''
renewal: 2026-02-30
续费日期: 2026-02-28
续费日期: 2026-02-28
every 121 months
every 1 month
每1个月
''',
    );

    expect(result.renewalDates, <DateTime>[DateTime(2026, 2, 28)]);
    expect(result.cycles, hasLength(1));
    expect(result.cycles.single.key, '1:month');
  });
}
