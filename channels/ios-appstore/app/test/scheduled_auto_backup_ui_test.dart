import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/storage/auto_backup_controller.dart';
import 'package:account_subscription_manager/features/settings/presentation/vault_health_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stage1_backup_export_test.dart'
    show ConfigSession, MemoryDocuments, exportFixture, testPassword;
import 'stage1_safety_ui_test.dart' show wrapper;
import 'support/fake_vault_store.dart';

Future<({AppState app, ConfigSession session})> configuredApp({
  DateTime Function()? now,
  int days = 15,
}) async {
  final controller = AutoBackupController(storage: MemoryDocuments(), now: now);
  final state = AppState(
    vaultStore: FakeVaultStore(
      configured: true,
      acceptedPassword: testPassword,
      snapshot: exportFixture(),
    ),
    autoBackupController: controller,
    now: now,
  );
  await state.initialize();
  await state.unlock(testPassword);
  final session = ConfigSession();
  await controller.attach(session, exportFixture());
  expect(
    await controller.configure(
      tree: 'tree',
      password: testPassword,
      intervalDays: days,
    ),
    true,
  );
  return (app: state, session: session);
}

Widget health(AppState app) => VaultHealthPage(
  appState: app,
  onManualBackup: () async {},
  onVerify: () async {},
  onRestore: () async {},
  onRecovery: () async {},
);

void main() {
  testWidgets(
    'backup password dialog rejects short input before requesting confirmation',
    (tester) async {
      final fixture = (await tester.runAsync(() => configuredApp()))!;
      addTearDown(fixture.app.dispose);
      await tester.pumpWidget(
        wrapper(health(fixture.app), const Locale('zh', 'CN')),
      );
      await tester.pumpAndSettle();
      final setup = find.text('选择或更换备份目录与密码');
      await tester.scrollUntilVisible(setup, 250);
      await tester.tap(setup);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Demo-8x!');
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(find.text('新密码至少需要16个字符；更推荐使用离线生成的随机密码。'), findsOneWidget);
      expect(find.text('再次输入备份密码'), findsNothing);
      await tester.enterText(find.byType(TextField), testPassword);
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(find.text('再次输入备份密码'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      fixture.app.autoBackup.detach();
    },
  );

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets(
      'scheduled settings ${locale.languageCode} 320px 2x font save the selected period',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        final fixture = (await tester.runAsync(() => configuredApp()))!;
        addTearDown(fixture.app.dispose);
        await tester.pumpWidget(wrapper(health(fixture.app), locale));
        await tester.pumpAndSettle();
        final picker = find.byType(DropdownButtonFormField<int>);
        await tester.scrollUntilVisible(picker, 250);
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        final label = AppLocalizations(locale).translate('30 天（一个月）');
        await tester.ensureVisible(find.text(label).last);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(fixture.app.autoBackup.status.intervalDays, 30);
        expect(fixture.session.value!['intervalDays'], 30);
        expect(fixture.app.autoBackup.status.retention, 3);
        expect(find.byType(TextField), findsNothing);
        fixture.app.autoBackup.detach();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed period save restores the displayed selection', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(() => configuredApp()))!;
    addTearDown(fixture.app.dispose);
    await tester.pumpWidget(
      wrapper(health(fixture.app), const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();
    final picker = find.byType(DropdownButtonFormField<int>);
    await tester.scrollUntilVisible(picker, 250);
    fixture.session.fail = true;
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 天（每周）').last);
    await tester.pumpAndSettle();
    expect(fixture.app.autoBackup.status.intervalDays, 15);
    expect(tester.state<FormFieldState<int>>(picker).value, 15);
    expect(find.text('备份周期保存失败，原设置保持不变。'), findsOneWidget);
    fixture.app.autoBackup.detach();
    expect(tester.takeException(), isNull);
  });

  test(
    'monthly schedule does not issue weekly or one-day dirty-data warnings',
    () async {
      var current = DateTime.utc(2026, 9, 4);
      final fixture = await configuredApp(now: () => current, days: 30);
      addTearDown(fixture.app.dispose);
      current = current.add(const Duration(days: 8));
      expect(fixture.app.backupWarning, isNull);
      await fixture.app.autoBackup.observe(exportFixture('changed'));
      current = current.add(const Duration(days: 3));
      expect(fixture.app.backupWarning, isNull);
      current = DateTime.utc(2026, 10, 5);
      expect(fixture.app.backupWarning, '自动备份已超过计划时间，请到数据安全与备份检查。');
    },
  );
}
