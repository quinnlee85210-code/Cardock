import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('没有账号时编辑器可保存独立订阅', (tester) async {
    SubscriptionDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              submitted = await Navigator.of(context).push<SubscriptionDraft>(
                MaterialPageRoute<SubscriptionDraft>(
                  builder: (context) =>
                      const SubscriptionEditorPage(accounts: <AccountRecord>[]),
                ),
              );
            },
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    expect(find.text('不关联账号 · 独立订阅'), findsOneWidget);
    expect(find.text('关联账号（可选）'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('subscription-service-name')),
      '无账号独立订阅',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('save-subscription-button')),
    );
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.accountId, isNull);
    expect(submitted!.details.serviceName, '无账号独立订阅');
  });

  group('周期推进', () {
    test('月末连续推进不漂移', () {
      final february = advanceSubscriptionDate(
        DateTime(2024, 1, 31),
        count: 1,
        unit: SubscriptionCycleUnit.month,
        preserveMonthEnd: true,
      );
      final march = advanceSubscriptionDate(
        february,
        count: 1,
        unit: SubscriptionCycleUnit.month,
        preserveMonthEnd: true,
      );

      expect(february, DateTime(2024, 2, 29));
      expect(march, DateTime(2024, 3, 31));
    });

    test('闰年年度周期保持二月月末语义', () {
      var date = DateTime(2024, 2, 29);
      for (var index = 0; index < 4; index += 1) {
        date = advanceSubscriptionDate(
          date,
          count: 1,
          unit: SubscriptionCycleUnit.year,
          preserveMonthEnd: true,
        );
      }
      expect(date, DateTime(2028, 2, 29));
    });

    test('天、周与手动续费日期都只推进一个周期', () {
      expect(
        advanceSubscriptionDate(
          DateTime(2026, 12, 30),
          count: 3,
          unit: SubscriptionCycleUnit.day,
        ),
        DateTime(2027, 1, 2),
      );
      expect(
        advanceSubscriptionDate(
          DateTime(2026, 12, 30),
          count: 2,
          unit: SubscriptionCycleUnit.week,
        ),
        DateTime(2027, 1, 13),
      );

      final renewed = _record(
        nextRenewalOn: DateTime(2026, 3, 10),
        cycleCount: 1,
        cycleUnit: SubscriptionCycleUnit.month,
      ).markRenewed(recordedOn: DateTime(2027, 8, 1));
      expect(renewed.nextRenewalOn, DateTime(2026, 4, 10));
      expect(renewed.renewalHistory, hasLength(1));
      expect(
        renewed.renewalHistory.single.previousRenewalOn,
        DateTime(2026, 3, 10),
      );
    });
  });

  group('兼容与审计字段', () {
    test('旧JSON缺少新增字段时按安全默认值读取', () {
      final legacyJson = _record().toEncryptedPayloadJson()
        ..remove('reminderEnabled')
        ..remove('snoozedUntil')
        ..remove('snoozedUntilUtc')
        ..remove('cancelledOn')
        ..remove('accessEndsOn')
        ..remove('renewalHistory');

      final restored = SubscriptionRecord.fromEncryptedPayloadJson(legacyJson);
      expect(restored.reminderEnabled, isTrue);
      expect(restored.snoozedUntil, isNull);
      expect(restored.snoozedUntilUtc, isNull);
      expect(restored.cancelledOn, isNull);
      expect(restored.accessEndsOn, isNull);
      expect(restored.renewalHistory, isEmpty);
    });

    test('1小时、5小时、10小时延后保留UTC精确时刻并严格往返', () {
      final now = DateTime.utc(2026, 8, 29, 23, 45, 30);
      for (final hours in <int>[1, 5, 10]) {
        final snoozed = _record().snoozeReminder(
          SubscriptionSnoozeTarget.after(Duration(hours: hours), now: now),
        );
        expect(snoozed.snoozedUntil, isNull);
        expect(snoozed.snoozedUntilUtc, now.add(Duration(hours: hours)));

        final restored = SubscriptionRecord.fromEncryptedPayloadJson(
          snoozed.toEncryptedPayloadJson(),
          allowInstantSnooze: true,
        );
        expect(restored.snoozedUntilUtc, snoozed.snoozedUntilUtc);
      }
    });

    test('日期延后与精确延后互斥且旧解析路径拒绝精确字段', () {
      final exact = _record().snoozeReminder(
        SubscriptionSnoozeTarget.exactInstant(DateTime.utc(2026, 8, 30, 4, 30)),
      );
      expect(
        () => SubscriptionRecord.fromEncryptedPayloadJson(
          exact.toEncryptedPayloadJson(),
        ),
        throwsFormatException,
      );

      final invalid = Map<String, Object?>.from(exact.toEncryptedPayloadJson())
        ..['snoozedUntil'] = '2026-08-31';
      expect(
        () => SubscriptionRecord.fromEncryptedPayloadJson(
          invalid,
          allowInstantSnooze: true,
        ),
        throwsFormatException,
      );
    });

    test('延期、取消、权益截止和续费历史均可严格往返', () {
      final renewed = _record().markRenewed(recordedOn: DateTime(2026, 2, 1));
      final cancelled = renewed.cancel(
        cancelledOn: DateTime(2026, 2, 2),
        accessEndsOn: DateTime(2026, 4, 30),
      );

      final restored = SubscriptionRecord.fromEncryptedPayloadJson(
        cancelled.toEncryptedPayloadJson(),
      );
      expect(restored.status, SubscriptionStatus.cancelled);
      expect(restored.reminderEnabled, isFalse);
      expect(restored.cancelledOn, DateTime(2026, 2, 2));
      expect(restored.accessEndsOn, DateTime(2026, 4, 30));
      expect(restored.renewalHistory, hasLength(1));
      expect(
        restored.renewalHistory.single.nextRenewalOn,
        DateTime(2026, 3, 31),
      );
    });

    test('编辑基础资料保留延期与续费历史，取消和恢复清理状态字段', () {
      final snoozed = _record()
          .markRenewed(recordedOn: DateTime(2026, 2, 1))
          .snoozeReminderUntil(DateTime(2026, 2, 20));
      final edited = snoozed.applyDraft(
        SubscriptionDraft(
          accountId: 'account-2',
          details: SubscriptionDetailsDraft(
            serviceName: '编辑后的服务',
            firstSubscribedOn: snoozed.firstSubscribedOn,
            nextRenewalOn: snoozed.nextRenewalOn,
            cycleCount: snoozed.cycleCount,
            cycleUnit: snoozed.cycleUnit,
          ),
        ),
      );
      expect(edited.accountId, 'account-2');
      expect(edited.snoozedUntil, DateTime(2026, 2, 20));
      expect(edited.renewalHistory, hasLength(1));

      final cancelled = edited.cancel(cancelledOn: DateTime(2026, 2, 2));
      expect(cancelled.snoozedUntil, isNull);
      expect(cancelled.reminderEnabled, isFalse);
      final restored = cancelled.restore();
      expect(restored.status, SubscriptionStatus.active);
      expect(restored.reminderEnabled, isTrue);
      expect(restored.cancelledOn, isNull);
      expect(restored.renewalHistory, hasLength(1));
    });

    test('权益截止日期不能早于本机取消日期', () {
      expect(
        () => _record().cancel(
          cancelledOn: DateTime(2026, 3, 1),
          accessEndsOn: DateTime(2026, 2, 28),
        ),
        throwsArgumentError,
      );
    });
  });
}

SubscriptionRecord _record({
  DateTime? nextRenewalOn,
  int cycleCount = 1,
  SubscriptionCycleUnit cycleUnit = SubscriptionCycleUnit.month,
}) => SubscriptionRecord.fromDraft(
  id: 'subscription-1',
  draft: SubscriptionDraft(
    accountId: 'account-1',
    details: SubscriptionDetailsDraft(
      serviceName: '本机测试订阅',
      firstSubscribedOn: DateTime(2026, 1, 31),
      nextRenewalOn: nextRenewalOn ?? DateTime(2026, 2, 28),
      cycleCount: cycleCount,
      cycleUnit: cycleUnit,
      reminderDaysBefore: 7,
    ),
  ),
);
