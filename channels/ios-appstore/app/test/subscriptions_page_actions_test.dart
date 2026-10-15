import 'package:account_subscription_manager/core/preferences/record_display_mode.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('没有账号时订阅空态仍可直接新增独立订阅', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubscriptionsPage(
            accounts: const <AccountRecord>[],
            subscriptions: const <SubscriptionRecord>[],
            onAddSubscription: () => calls += 1,
          ),
        ),
      ),
    );

    expect(find.textContaining('直接新增独立订阅'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('empty-add-subscription')),
    );
    expect(calls, 1);
  });

  testWidgets('已续费操作先确认且只通过回调提交', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final subscription = _record();
    SubscriptionRecord? submitted;

    await tester.pumpWidget(
      _testApp(
        account: account,
        subscription: subscription,
        onMarkRenewed: (record) async {
          submitted = record.markRenewed(recordedOn: DateTime(2026, 3, 1));
          return true;
        },
      ),
    );
    await tester.ensureVisible(find.text('已续费'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已续费'));
    await tester.pumpAndSettle();

    expect(find.text('确认已续费？'), findsOneWidget);
    expect(find.textContaining('不会向平台付款'), findsOneWidget);
    expect(submitted, isNull);

    await tester.tap(find.text('确认已续费'));
    await tester.pumpAndSettle();
    expect(submitted?.nextRenewalOn, DateTime(2027, 4, 30));
    expect(find.text('已推进一期续费日期。'), findsOneWidget);
  });

  testWidgets('记录取消明确提示不会在平台取消并支持权益截止日参数', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final subscription = _record();
    var called = false;

    await tester.pumpWidget(
      _testApp(
        account: account,
        subscription: subscription,
        onCancelSubscription: (record, {accessEndsOn}) async {
          called = true;
          return true;
        },
      ),
    );
    await tester.ensureVisible(find.text('记录取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录取消'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不会在对应平台取消订阅、停止扣费或申请退款'), findsOneWidget);
    expect(called, isFalse);

    await tester.tap(find.text('仅记录取消'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(find.textContaining('请继续到平台核实'), findsOneWidget);
  });

  testWidgets('延后提醒提供1、5、10小时及原有日期选项', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final subscription = _record();
    SubscriptionSnoozeTarget? submittedTarget;

    await tester.pumpWidget(
      _testApp(
        account: account,
        subscription: subscription,
        onSnoozeReminder: (record, target) async {
          submittedTarget = target;
          return true;
        },
      ),
    );
    await tester.ensureVisible(find.text('延后提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后提醒'));
    await tester.pumpAndSettle();

    expect(find.text('1小时后提醒'), findsOneWidget);
    expect(find.text('5小时后提醒'), findsOneWidget);
    expect(find.text('10小时后提醒'), findsOneWidget);
    expect(find.text('明天提醒'), findsOneWidget);
    expect(find.text('3天后提醒'), findsOneWidget);
    expect(find.text('7天后提醒'), findsOneWidget);
    expect(find.text('选择日期…'), findsOneWidget);

    final today = DateUtils.dateOnly(DateTime.now());
    await tester.tap(find.text('3天后提醒'));
    await tester.pumpAndSettle();
    expect(submittedTarget?.calendarDate, today.add(const Duration(days: 3)));
    expect(submittedTarget?.instantUtc, isNull);
  });

  testWidgets('5小时延后提交精确UTC瞬时而不是当天日期', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final subscription = _record();
    SubscriptionSnoozeTarget? submittedTarget;

    await tester.pumpWidget(
      _testApp(
        account: account,
        subscription: subscription,
        onSnoozeReminder: (record, target) async {
          submittedTarget = target;
          return true;
        },
      ),
    );
    await tester.ensureVisible(find.text('延后提醒'));
    await tester.pumpAndSettle();
    final before = DateTime.now().toUtc();
    await tester.tap(find.text('延后提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5小时后提醒'));
    await tester.pumpAndSettle();
    final after = DateTime.now().toUtc();

    expect(submittedTarget?.calendarDate, isNull);
    expect(
      submittedTarget!.instantUtc!.isBefore(
        before.add(const Duration(hours: 5)),
      ),
      isFalse,
    );
    expect(
      submittedTarget!.instantUtc!.isAfter(after.add(const Duration(hours: 5))),
      isFalse,
    );
  });

  testWidgets('已取消订阅的恢复记录需确认，返回时不回调', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final subscription = _record().cancel(cancelledOn: DateTime(2026, 3, 1));
    var calls = 0;

    await tester.pumpWidget(
      _testApp(
        account: account,
        subscription: subscription,
        onRestoreSubscription: (record) async {
          calls += 1;
          return true;
        },
      ),
    );
    await tester.tap(find.text('已取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('恢复记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复记录'));
    await tester.pumpAndSettle();

    expect(find.text('恢复本机订阅记录？'), findsOneWidget);
    expect(find.textContaining('不会在平台重新订阅'), findsOneWidget);
    expect(calls, 0);

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(calls, 0);

    await tester.ensureVisible(find.text('恢复记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复记录').last);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('已恢复本机订阅记录。'), findsOneWidget);
  });

  testWidgets('移入回收站先确认，取消不回调而确认只回调一次', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final subscription = _record();
    var calls = 0;

    await tester.pumpWidget(
      _testApp(
        account: account,
        subscription: subscription,
        onDeleteSubscription: (record) async {
          calls += 1;
          return true;
        },
      ),
    );
    final deleteAction = find.byKey(
      const ValueKey<String>('delete-subscription-subscription-1'),
    );
    await tester.ensureVisible(deleteAction);
    await tester.pumpAndSettle();
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();

    expect(find.text('移入回收站？'), findsOneWidget);
    expect(find.textContaining('记录将在回收站保留 30 天'), findsOneWidget);
    expect(calls, 0);

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(calls, 0);

    await tester.ensureVisible(deleteAction);
    await tester.pumpAndSettle();
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('confirm-delete-subscription-subscription-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('订阅记录已移入回收站。'), findsOneWidget);
  });
}

Widget _testApp({
  required AccountRecord account,
  required SubscriptionRecord subscription,
  SubscriptionRecordAction? onMarkRenewed,
  SubscriptionSnoozeAction? onSnoozeReminder,
  SubscriptionCancelAction? onCancelSubscription,
  SubscriptionRecordAction? onRestoreSubscription,
  SubscriptionRecordAction? onDeleteSubscription,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SubscriptionRecordCard(
        subscription: subscription,
        account: account,
        displayMode: RecordDisplayMode.expandedCards,
        showFullDetails: true,
        onMarkRenewed: onMarkRenewed,
        onSnoozeReminder: onSnoozeReminder,
        onCancelSubscription: onCancelSubscription,
        onRestoreSubscription: onRestoreSubscription,
        onDeleteSubscription: onDeleteSubscription,
      ),
    ),
  ),
);

SubscriptionRecord _record() => SubscriptionRecord.fromDraft(
  id: 'subscription-1',
  draft: SubscriptionDraft(
    accountId: 'account-1',
    details: SubscriptionDetailsDraft(
      serviceName: '测试订阅',
      firstSubscribedOn: DateTime(2026, 1, 31),
      nextRenewalOn: DateTime(2027, 3, 31),
      cycleUnit: SubscriptionCycleUnit.month,
    ),
  ),
);
