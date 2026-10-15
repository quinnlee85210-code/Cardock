import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_form_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('月末与季度周期按自然月正确计算', () {
    final controller = SubscriptionFormController(today: DateTime(2024, 1, 31));
    addTearDown(controller.dispose);

    expect(controller.nextRenewalOn, DateTime(2024, 2, 29));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.automatic);

    controller.setCyclePreset(SubscriptionCyclePreset.quarterly);
    expect(controller.nextRenewalOn, DateTime(2024, 4, 30));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.automatic);
  });

  test('年度周期正确处理闰年日期', () {
    final controller = SubscriptionFormController(today: DateTime(2024, 2, 29));
    addTearDown(controller.dispose);

    controller.setCyclePreset(SubscriptionCyclePreset.yearly);

    expect(controller.nextRenewalOn, DateTime(2025, 2, 28));
  });

  test('自定义天与周周期均会自动生成续费日期', () {
    final controller = SubscriptionFormController(today: DateTime(2026, 8, 1));
    addTearDown(controller.dispose);

    controller.setCyclePreset(SubscriptionCyclePreset.custom);
    controller.setCustomCycleUnit(SubscriptionCycleUnit.day);
    controller.setCustomCycleCount('10');
    expect(controller.nextRenewalOn, DateTime(2026, 8, 11));

    controller.setCustomCycleUnit(SubscriptionCycleUnit.week);
    controller.setCustomCycleCount('2');
    expect(controller.nextRenewalOn, DateTime(2026, 8, 15));
  });

  test('编辑已有赠送日期先保留，手动覆盖后改变周期会恢复自动计算', () {
    final controller = SubscriptionFormController(
      initial: SubscriptionDetailsDraft(
        serviceName: '含赠送天数的会员',
        firstSubscribedOn: DateTime(2026, 1, 31),
        nextRenewalOn: DateTime(2026, 3, 10),
        cycleCount: 1,
        cycleUnit: SubscriptionCycleUnit.month,
      ),
    );
    addTearDown(controller.dispose);

    expect(controller.nextRenewalOn, DateTime(2026, 3, 10));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.manual);

    controller.setManualNextRenewalOn(DateTime(2026, 3, 15));
    expect(controller.nextRenewalOn, DateTime(2026, 3, 15));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.manual);

    controller.setCyclePreset(SubscriptionCyclePreset.quarterly);
    expect(controller.nextRenewalOn, DateTime(2026, 4, 30));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.automatic);

    controller.setManualNextRenewalOn(DateTime(2026, 5, 8));
    controller.setFirstSubscribedOn(DateTime(2026, 2, 28));
    expect(controller.nextRenewalOn, DateTime(2026, 5, 28));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.automatic);
  });

  test('手动日期可恢复自动计算', () {
    final controller = SubscriptionFormController(today: DateTime(2026, 6, 30));
    addTearDown(controller.dispose);

    controller.setManualNextRenewalOn(DateTime(2026, 8, 5));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.manual);

    controller.useAutomaticNextRenewalOn();
    expect(controller.nextRenewalOn, DateTime(2026, 7, 30));
    expect(controller.renewalDateMode, SubscriptionRenewalDateMode.automatic);
  });

  test('自动结果超过2300年时安全限制到支持上限', () {
    final controller = SubscriptionFormController(
      today: DateTime(2300, 12, 31),
    );
    addTearDown(controller.dispose);

    expect(controller.nextRenewalOn, DateTime(2300, 12, 31));
    expect(controller.renewalDateReachedSupportedLimit, isTrue);
    expect(
      () => formatSubscriptionDate(controller.nextRenewalOn),
      returnsNormally,
    );
  });

  test('新增订阅会采用可注入的默认币种与默认提醒参数', () {
    final controller = SubscriptionFormController(
      today: DateTime(2026, 8, 1),
      defaultCurrency: 'usd',
      defaultReminderDays: 12,
    );
    addTearDown(controller.dispose);
    controller.serviceNameController.text = '默认值测试';

    final draft = controller.toDraft();
    expect(draft.currency, 'USD');
    expect(draft.reminderDaysBefore, 12);
    expect(draft.reminderEnabled, isTrue);

    controller.reminderEnabled = false;
    expect(controller.toDraft().reminderEnabled, isFalse);
  });
}
