import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/core/preferences/record_display_mode.dart';
import 'package:account_subscription_manager/features/settings/presentation/settings_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';
import 'support/recording_reminder_scheduler.dart';

const _masterPassword = 'TEST-ONLY-MASTER-1234';

const _summaryLayoutCases =
    <({CardockLanguage language, Size viewport, double textScale})>[
      (
        language: CardockLanguage.simplifiedChinese,
        viewport: Size(393, 873),
        textScale: 1,
      ),
      (
        language: CardockLanguage.english,
        viewport: Size(320, 640),
        textScale: 1,
      ),
      (
        language: CardockLanguage.english,
        viewport: Size(360, 800),
        textScale: 1,
      ),
      (
        language: CardockLanguage.english,
        viewport: Size(360, 800),
        textScale: 1.3,
      ),
      (
        language: CardockLanguage.english,
        viewport: Size(393, 873),
        textScale: 1.3,
      ),
      (
        language: CardockLanguage.english,
        viewport: Size(411, 915),
        textScale: 1.5,
      ),
      (
        language: CardockLanguage.japanese,
        viewport: Size(320, 640),
        textScale: 1.5,
      ),
      (
        language: CardockLanguage.japanese,
        viewport: Size(360, 800),
        textScale: 2,
      ),
      (
        language: CardockLanguage.japanese,
        viewport: Size(393, 873),
        textScale: 2,
      ),
      (
        language: CardockLanguage.japanese,
        viewport: Size(411, 915),
        textScale: 2,
      ),
      (
        language: CardockLanguage.english,
        viewport: Size(411, 915),
        textScale: 1,
      ),
    ];

void main() {
  for (final language in CardockLanguage.values) {
    testWidgets(
      'both reminder time pickers persist independently in ${language.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controller = CardockLanguageController(
          store: MemoryLanguagePreferencesStore(
            LanguagePreferences(language: language),
          ),
        );
        addTearDown(controller.dispose);
        await controller.load();
        final harness = await _LanguageSettingsHarness.create(
          controller,
          notificationsEnabled: true,
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness);
        await tester.pumpAndSettle();
        final copy = AppLocalizations(controller.locale);
        expect(find.text(copy.translate('第一次提醒发送时间')), findsOneWidget);
        expect(find.text(copy.translate('第二次提醒发送时间')), findsOneWidget);
        expect(find.text('12:30'), findsOneWidget);
        expect(find.text('17:00'), findsOneWidget);
        for (final secondSlot in [false, true]) {
          final tile = find.byKey(
            ValueKey<String>(
              secondSlot ? 'second-reminder-time' : 'first-reminder-time',
            ),
          );
          await tester.ensureVisible(tile);
          await tester.tap(tile);
          await tester.pumpAndSettle();
          expect(
            find.text(copy.translate(secondSlot ? '选择第二次提醒时间' : '选择第一次提醒时间')),
            findsOneWidget,
          );
          final picker = tester.widget<TimePickerDialog>(
            find.byType(TimePickerDialog),
          );
          expect(
            picker.initialTime,
            secondSlot
                ? const TimeOfDay(hour: 17, minute: 0)
                : const TimeOfDay(hour: 12, minute: 30),
          );
          // Exercise the picker result in either 12-hour or 24-hour locales.
          final context = tester.element(find.byType(TimePickerDialog));
          Navigator.of(
            context,
          ).pop(TimeOfDay(hour: secondSlot ? 18 : 11, minute: 45));
          await tester.pumpAndSettle();
        }
        expect(
          harness.appState.preferences.defaultReminderTimeMinutes,
          11 * 60 + 45,
        );
        expect(
          harness.appState.preferences.secondReminderTimeMinutes,
          18 * 60 + 45,
        );
        expect(
          harness.scheduler.rescheduleCalls.last.reminderTimeMinutes,
          11 * 60 + 45,
        );
        expect(
          harness.scheduler.rescheduleCalls.last.secondReminderTimeMinutes,
          18 * 60 + 45,
        );
        expect(find.text('11:45'), findsOneWidget);
        expect(find.text('18:45'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('设置英日目录始终使用完全相同的源键', () {
    expect(
      settingsEnglishTranslations.keys.toSet(),
      settingsJapaneseTranslations.keys.toSet(),
    );
  });

  test('关键设置文案使用自然英日语且人民币价格标识明确', () {
    const english = AppLocalizations(Locale('en'));
    const japanese = AppLocalizations(Locale('ja'));

    expect(english.translate('显示偏好'), 'Display preferences');
    expect(english.translate('密码恢复'), 'Password recovery');
    expect(english.translate('导出加密备份'), 'Export encrypted backup');
    expect(english.translate('数据导入与备份'), 'Data import and backups');
    expect(english.translate('导入外部数据'), 'Import external data');
    expect(
      english.translate('恢复 Cardock 加密备份'),
      'Restore Cardock encrypted backup',
    );
    expect(
      english.translate('XLSX/CSV 等外部文件；.asmbackup 请用“恢复”'),
      'External XLSX/CSV etc.; Restore .asmbackup',
    );
    expect(
      english.translate('手动/自动备份 .asmbackup；先验证再恢复'),
      'Manual/auto .asmbackup; verify first',
    );
    expect(english.translate('通知可靠性'), 'Notification reliability');
    expect(japanese.translate('显示偏好'), '表示設定');
    expect(japanese.translate('密码恢复'), 'パスワード復旧');
    expect(japanese.translate('导出加密备份'), '暗号化バックアップを書き出す');
    expect(japanese.translate('数据导入与备份'), 'データのインポートとバックアップ');
    expect(japanese.translate('导入外部数据'), '外部データをインポート');
    expect(japanese.translate('恢复 Cardock 加密备份'), 'Cardock 暗号化バックアップを復元');
    expect(
      japanese.translate('XLSX/CSV 等外部文件；.asmbackup 请用“恢复”'),
      'XLSX/CSV 等の外部ファイル。.asmbackup は「復元」へ',
    );
    expect(
      japanese.translate('手动/自动备份 .asmbackup；先验证再恢复'),
      '手動/自動 .asmbackup。検証後に復元',
    );
    expect(japanese.translate('通知可靠性'), '通知の信頼性');
    expect(english.translate('可折叠卡片'), 'Collapsible cards');
    expect(english.translate('紧凑列表'), 'Compact list');
    expect(japanese.translate('可折叠卡片'), '折りたたみカード');
    expect(japanese.translate('紧凑列表'), 'コンパクトリスト');
    expect(english.translate('输入“恢复”确认'), 'Type “Restore” to confirm');
    expect(japanese.translate('输入“恢复”确认'), '確認のため「復元」と入力');
    expect(english.translate('恢复'), 'Restore');
    expect(japanese.translate('恢复'), '復元');
    expect(
      english.translate('{price} 一次买断', <String, Object?>{'price': '¥9.9'}),
      'CN¥9.9 one-time purchase',
    );
    expect(
      japanese.translate('{price} 一次买断', <String, Object?>{'price': '¥9.9'}),
      'CN¥9.9の買い切り',
    );
  });

  for (final testCase in _summaryLayoutCases) {
    testWidgets('保险库摘要 ${testCase.language.storageCode} '
        '${testCase.viewport.width.toInt()}px 文字${testCase.textScale} '
        '保持紧凑2乘2且无溢出', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = testCase.viewport;
      tester.binding.platformDispatcher.textScaleFactorTestValue =
          testCase.textScale;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final languageController = CardockLanguageController(
        store: MemoryLanguagePreferencesStore(
          LanguagePreferences(language: testCase.language),
        ),
      );
      addTearDown(languageController.dispose);
      await languageController.load();
      final harness = await _LanguageSettingsHarness.create(
        languageController,
        quickUnlockEnabled: true,
        autoLockSeconds: 30,
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            '${testCase.language.storageCode} ${testCase.viewport.width} '
            '文字${testCase.textScale}',
      );
      final masterPassword = tester.getTopLeft(
        find.byKey(const ValueKey<String>('vault-status-主密码')),
      );
      final biometrics = tester.getTopLeft(
        find.byKey(const ValueKey<String>('vault-status-生物识别')),
      );
      final autoLock = tester.getTopLeft(
        find.byKey(const ValueKey<String>('vault-status-自动锁定')),
      );
      final decoyVault = tester.getTopLeft(
        find.byKey(const ValueKey<String>('vault-status-诱饵保险库')),
      );
      expect(biometrics.dy, closeTo(masterPassword.dy, 0.1));
      expect(biometrics.dx, greaterThan(masterPassword.dx));
      expect(autoLock.dx, closeTo(masterPassword.dx, 0.1));
      expect(autoLock.dy, greaterThan(masterPassword.dy));
      expect(decoyVault.dy, closeTo(autoLock.dy, 0.1));
      expect(decoyVault.dx, greaterThan(autoLock.dx));

      for (final key in <String>[
        'vault-status-主密码',
        'vault-status-生物识别',
        'vault-status-自动锁定',
        'vault-status-诱饵保险库',
      ]) {
        final paragraphs = find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(RichText),
        );
        for (final element in paragraphs.evaluate()) {
          final renderObject = element.renderObject;
          if (renderObject is RenderParagraph) {
            expect(renderObject.didExceedMaxLines, isFalse, reason: key);
          }
        }
      }
      if (testCase.language == CardockLanguage.simplifiedChinese &&
          testCase.viewport == const Size(393, 873) &&
          testCase.textScale == 1) {
        _expectStatusValueOnSecondLine(
          tester,
          tileKey: 'vault-status-主密码',
          label: '主密码',
          value: '已设置',
        );
        _expectStatusValueOnSecondLine(
          tester,
          tileKey: 'vault-status-生物识别',
          label: '生物识别',
          value: '已开启',
        );
        _expectStatusValueOnSecondLine(
          tester,
          tileKey: 'vault-status-自动锁定',
          label: '自动锁定',
          value: '30秒后锁定',
        );
        _expectStatusValueOnSecondLine(
          tester,
          tileKey: 'vault-status-诱饵保险库',
          label: '诱饵保险库',
          value: '未配置',
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('vault-summary')))
              .height,
          lessThanOrEqualTo(112),
        );
      }
    });
  }

  for (final testCase
      in <
        ({
          CardockLanguage language,
          String importStatus,
          String exportStatus,
          String restoreStatus,
        })
      >[
        (
          language: CardockLanguage.simplifiedChinese,
          importStatus: 'XLSX/CSV 等外部文件；.asmbackup 请用“恢复”',
          exportStatus: '.asmbackup · 账号与订阅 · 独立备份密码',
          restoreStatus: '手动/自动备份 .asmbackup；先验证再恢复',
        ),
        (
          language: CardockLanguage.english,
          importStatus: 'External XLSX/CSV etc.; Restore .asmbackup',
          exportStatus: '.asmbackup · Vault · Separate password',
          restoreStatus: 'Manual/auto .asmbackup; verify first',
        ),
        (
          language: CardockLanguage.japanese,
          importStatus: 'XLSX/CSV 等の外部ファイル。.asmbackup は「復元」へ',
          exportStatus: '.asmbackup · アカウントとサブスクリプション · 専用パスワード',
          restoreStatus: '手動/自動 .asmbackup。検証後に復元',
        ),
      ]) {
    testWidgets('导入导出恢复说明 ${testCase.language.storageCode} 320宽200%字体完整且可点击', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final languageController = CardockLanguageController(
        store: MemoryLanguagePreferencesStore(
          LanguagePreferences(language: testCase.language),
        ),
      );
      addTearDown(languageController.dispose);
      await languageController.load();
      final harness = await _LanguageSettingsHarness.create(languageController);
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      for (final entry in <({String key, String status})>[
        (key: 'data-migration-center-entry', status: testCase.importStatus),
        (key: 'encrypted-backup-export-entry', status: testCase.exportStatus),
        (key: 'encrypted-backup-restore-entry', status: testCase.restoreStatus),
      ]) {
        final tile = find.byKey(ValueKey<String>(entry.key));
        await tester.scrollUntilVisible(
          tile,
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tile.hitTestable(), findsOneWidget);
        final status = find.descendant(
          of: tile,
          matching: find.text(entry.status),
        );
        expect(status, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(status).didExceedMaxLines,
          isFalse,
          reason:
              '${testCase.language.storageCode} ${entry.key} status clipped',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('语言项使用本族名称并可从中文即时切换英语和日语', (tester) async {
    final store = MemoryLanguagePreferencesStore();
    final languageController = CardockLanguageController(store: store);
    addTearDown(languageController.dispose);
    await languageController.load();
    final harness = await _LanguageSettingsHarness.create(
      languageController,
      notificationsEnabled: true,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness);
    await tester.pumpAndSettle();
    await _openLanguageDialog(tester);

    _expectNativeLanguageChoices();
    await tester.tap(find.byKey(const ValueKey<String>('language-en')));
    await tester.pumpAndSettle();

    expect(languageController.language, CardockLanguage.english);
    expect(store.value?.language, CardockLanguage.english);
    expect(harness.scheduler.rescheduleCalls, hasLength(1));
    expect(find.text('Display preferences'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await _openLanguageDialog(tester);
    _expectNativeLanguageChoices();
    await tester.tap(find.byKey(const ValueKey<String>('language-ja')));
    await tester.pumpAndSettle();

    expect(languageController.language, CardockLanguage.japanese);
    expect(store.value?.language, CardockLanguage.japanese);
    expect(harness.scheduler.rescheduleCalls, hasLength(2));
    expect(find.text('表示設定'), findsOneWidget);
    expect(find.text('言語'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
  });

  for (final testCase
      in <
        ({
          CardockLanguage language,
          String collapsibleCards,
          String compactList,
        })
      >[
        (
          language: CardockLanguage.english,
          collapsibleCards: 'Collapsible cards',
          compactList: 'Compact list',
        ),
        (
          language: CardockLanguage.japanese,
          collapsibleCards: '折りたたみカード',
          compactList: 'コンパクトリスト',
        ),
      ]) {
    testWidgets('账号与订阅显示方式在 ${testCase.language.storageCode} 下翻译摘要和弹窗选项', (
      tester,
    ) async {
      final languageController = CardockLanguageController(
        store: MemoryLanguagePreferencesStore(
          LanguagePreferences(language: testCase.language),
        ),
      );
      addTearDown(languageController.dispose);
      await languageController.load();
      final harness = await _LanguageSettingsHarness.create(languageController);
      addTearDown(harness.dispose);
      expect(
        await harness.appState.updatePreferences(
          harness.appState.preferences.copyWith(
            accountDisplayMode: RecordDisplayMode.collapsibleCards,
            subscriptionDisplayMode: RecordDisplayMode.compactList,
          ),
        ),
        isTrue,
      );

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      final accountTile = find.byKey(
        const ValueKey<String>('account-display-mode-setting'),
      );
      await tester.scrollUntilVisible(
        accountTile,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: accountTile,
          matching: find.text(testCase.collapsibleCards),
        ),
        findsOneWidget,
      );
      await tester.tap(accountTile);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('account-display-collapsibleCards'),
          ),
          matching: find.text(testCase.collapsibleCards),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('account-display-compactList')),
          matching: find.text(testCase.compactList),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('account-display-collapsibleCards')),
      );
      await tester.pumpAndSettle();

      final subscriptionTile = find.byKey(
        const ValueKey<String>('subscription-display-mode-setting'),
      );
      await tester.scrollUntilVisible(
        subscriptionTile,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: subscriptionTile,
          matching: find.text(testCase.compactList),
        ),
        findsOneWidget,
      );
      await tester.tap(subscriptionTile);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('subscription-display-collapsibleCards'),
          ),
          matching: find.text(testCase.collapsibleCards),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('subscription-display-compactList'),
          ),
          matching: find.text(testCase.compactList),
        ),
        findsOneWidget,
      );
      expect(find.text('可折叠卡片'), findsNothing);
      expect(find.text('紧凑列表'), findsNothing);
    });
  }

  testWidgets('语言持久化失败时保留原语言并显示本地化错误', (tester) async {
    final store = _FailingLanguageStore(
      const LanguagePreferences(language: CardockLanguage.english),
    );
    final languageController = CardockLanguageController(store: store);
    addTearDown(languageController.dispose);
    await languageController.load();
    final harness = await _LanguageSettingsHarness.create(languageController);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness);
    await tester.pumpAndSettle();
    await _openLanguageDialog(tester);
    await tester.tap(find.byKey(const ValueKey<String>('language-ja')));
    await tester.pumpAndSettle();

    expect(languageController.language, CardockLanguage.english);
    expect(store.value.language, CardockLanguage.english);
    expect(
      find.text('Could not change the language. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });
}

Future<void> _openLanguageDialog(WidgetTester tester) async {
  final languageTile = find.byKey(const ValueKey<String>('language-setting'));
  await tester.scrollUntilVisible(
    languageTile,
    280,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(languageTile);
  await tester.pumpAndSettle();
}

void _expectNativeLanguageChoices() {
  expect(
    find.descendant(
      of: find.byKey(const ValueKey<String>('language-zh_CN')),
      matching: find.text('简体中文'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey<String>('language-en')),
      matching: find.text('English'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey<String>('language-ja')),
      matching: find.text('日本語'),
    ),
    findsOneWidget,
  );
}

void _expectStatusValueOnSecondLine(
  WidgetTester tester, {
  required String tileKey,
  required String label,
  required String value,
}) {
  final tile = find.byKey(ValueKey<String>(tileKey));
  final labelFinder = find.descendant(of: tile, matching: find.text(label));
  final valueFinder = find.descendant(of: tile, matching: find.text(value));
  expect(labelFinder, findsOneWidget);
  expect(valueFinder, findsOneWidget);
  expect(
    tester.getTopLeft(valueFinder).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(labelFinder).dy),
  );
  final valueText = tester.widget<Text>(valueFinder);
  expect(valueText.maxLines, 1);
  expect(valueText.softWrap, isFalse);
  expect(
    tester.renderObject<RenderParagraph>(valueFinder).didExceedMaxLines,
    isFalse,
  );
}

class _LanguageSettingsHarness extends StatelessWidget {
  const _LanguageSettingsHarness._({
    required this.appState,
    required this.languageController,
    required this.entitlementController,
    required this.scheduler,
  });

  final AppState appState;
  final CardockLanguageController languageController;
  final ProductEntitlementController entitlementController;
  final RecordingReminderScheduler scheduler;

  static Future<_LanguageSettingsHarness> create(
    CardockLanguageController languageController, {
    bool notificationsEnabled = false,
    bool quickUnlockEnabled = false,
    int? autoLockSeconds,
  }) async {
    final scheduler = RecordingReminderScheduler();
    final vaultStore = FakeVaultStore(
      configured: true,
      acceptedPassword: _masterPassword,
    )..quickUnlockEnabled = quickUnlockEnabled;
    final appState = AppState(
      vaultStore: vaultStore,
      reminderScheduler: scheduler,
    );
    await appState.initialize();
    expect(await appState.unlock(_masterPassword), VaultActionResult.success);
    if (autoLockSeconds != null) {
      expect(
        await appState.updatePreferences(
          appState.preferences.copyWith(autoLockSeconds: autoLockSeconds),
        ),
        isTrue,
      );
    }
    if (notificationsEnabled) {
      await appState.setNotificationsEnabled(true);
      expect(appState.preferences.notificationsEnabled, isTrue);
      scheduler.reset();
    }
    final entitlementController = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: true),
    );
    await entitlementController.initialize();
    return _LanguageSettingsHarness._(
      appState: appState,
      languageController: languageController,
      entitlementController: entitlementController,
      scheduler: scheduler,
    );
  }

  void dispose() {
    entitlementController.dispose();
    appState.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CardockLanguageScope(
      controller: languageController,
      child: ProductEntitlementScope(
        controller: entitlementController,
        child: ListenableBuilder(
          listenable: languageController,
          builder: (context, child) => MaterialApp(
            locale: languageController.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: ListenableBuilder(
              listenable: appState,
              builder: (context, child) => Scaffold(
                body: SettingsPage(appState: appState, onLock: () {}),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FailingLanguageStore implements LanguagePreferencesStore {
  _FailingLanguageStore(this.value);

  LanguagePreferences value;

  @override
  Future<LanguagePreferences?> read() async => value;

  @override
  Future<void> write(LanguagePreferences preferences) async {
    throw StateError('test write failure');
  }
}
