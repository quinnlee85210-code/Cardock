import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/core/storage/vault_recovery_journal.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:account_subscription_manager/features/settings/presentation/readable_export_page.dart';
import 'package:account_subscription_manager/features/settings/presentation/trash_page.dart';
import 'package:account_subscription_manager/features/settings/presentation/vault_health_page.dart';
import 'package:account_subscription_manager/features/vault/presentation/vault_rebuild_page.dart';
import 'package:account_subscription_manager/features/vault/presentation/vault_gate.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_stage1.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stage1_backup_export_test.dart' show exportFixture;
import 'support/fake_vault_store.dart';

const password = 'TEST-ONLY-MASTER-1234';
Future<AppState> app() async {
  final state = AppState(
    vaultStore: FakeVaultStore(
      configured: true,
      acceptedPassword: password,
      snapshot: VaultTrash.move(
        exportFixture(),
        accountId: 'account-1',
        now: DateTime.now(),
        batchId: 'UI-TEST',
      ),
    ),
  );
  await state.initialize();
  await state.unlock(password);
  return state;
}

Widget wrapper(Widget page, Locale locale) => MaterialApp(
  theme: AppTheme.light(),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: page,
);
void main() {
  test(
    'all stage1 translation keys and placeholders match in English/Japanese',
    () {
      expect(
        stage1EnglishTranslations.keys.toSet(),
        stage1JapaneseTranslations.keys.toSet(),
      );
      Set<String> placeholders(String text) => RegExp(
        r'\{[^{}]+\}',
      ).allMatches(text).map((m) => m.group(0)!).toSet();
      for (final key in stage1EnglishTranslations.keys) {
        expect(
          placeholders(stage1EnglishTranslations[key]!),
          placeholders(key),
          reason: key,
        );
        expect(
          placeholders(stage1JapaneseTranslations[key]!),
          placeholders(key),
          reason: key,
        );
        expect(
          AppLocalizations(const Locale('en')).translate(key),
          stage1EnglishTranslations[key],
          reason: key,
        );
        expect(
          AppLocalizations(const Locale('ja')).translate(key),
          stage1JapaneseTranslations[key],
          reason: key,
        );
      }
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets(
      'lock help stays outside unlock form at screen corner ${locale.languageCode} with keyboard and 200% text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        final state = await app();
        addTearDown(state.dispose);
        state.lock();
        await tester.pumpWidget(
          wrapper(VaultUnlockPage(appState: state), locale),
        );
        await tester.pumpAndSettle();
        final help = find.byKey(
          const ValueKey('vault-controlled-rebuild-entry'),
        );
        expect(
          find.ancestor(of: help, matching: find.byType(Form)),
          findsNothing,
        );
        final rect = tester.getRect(help);
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(380));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(help.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(find.byType(VaultRebuildPage), findsOneWidget);
        expect(state.isUnlocked, isFalse);
        expect(
          find.byKey(const ValueKey<String>('vault-recovery-option')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(
                  const ValueKey<String>('start-vault-recovery-option'),
                ),
              )
              .onPressed,
          isNull,
          reason: '当前入口未配置恢复时应保留删除路径但禁用恢复按钮',
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('vault-rebuild-option')),
          180,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('vault-rebuild-option')),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    for (final pageName in ['trash', 'export', 'health', 'rebuild']) {
      testWidgets(
        'stage1 $pageName ${locale.languageCode} 320x640 2x text scrolls without overflow',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 640);
          tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(
            tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
          );
          final state = await app();
          addTearDown(state.dispose);
          final Widget page = switch (pageName) {
            'trash' => TrashPage(appState: state),
            'export' => ReadableExportPage(appState: state),
            'health' => VaultHealthPage(
              appState: state,
              onManualBackup: () async {},
              onVerify: () async {},
              onRestore: () async {},
              onRecovery: () async {},
            ),
            _ => VaultRebuildPage(appState: state),
          };
          await tester.pumpWidget(wrapper(page, locale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 5; i++) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -420),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  testWidgets('锁屏帮助页的密保选项直接进入恢复页且不触发删除确认', (tester) async {
    final store = FakeVaultStore(configured: true, acceptedPassword: password);
    const questionIds = <String>[
      'childhood_city',
      'first_school',
      'first_teacher',
    ];
    const answers = <String>['杭州', '实验小学', '王老师'];
    await store.configureRecovery(
      currentMasterPassword: password,
      questionIds: questionIds,
      answers: answers,
      entryMode: VaultRecoveryEntryMode.visible,
    );
    final recoveryJournal = _CompletedRecoveryJournal();
    final state = AppState(vaultStore: store, recoveryJournal: recoveryJournal);
    addTearDown(state.dispose);
    await state.initialize();
    await tester.pumpWidget(
      wrapper(VaultUnlockPage(appState: state), const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();

    final help = find.byKey(
      const ValueKey<String>('vault-controlled-rebuild-entry'),
    );
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.byType(VaultRebuildPage), findsOneWidget);

    final recover = find.byKey(
      const ValueKey<String>('start-vault-recovery-option'),
    );
    await tester.ensureVisible(recover);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(recover).onPressed, isNotNull);
    await tester.tap(recover);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('vault-recovery-page')),
      findsOneWidget,
    );
    expect(find.text('删除本机Cardock数据并重新开始'), findsNothing);
    expect(state.isUnlocked, isFalse);
    for (final answer in answers) {
      expect(find.text(answer), findsNothing, reason: '恢复页只能显示问题，绝不能显示已配置答案');
    }

    for (var index = 0; index < questionIds.length; index += 1) {
      final field = find.byKey(
        ValueKey<String>('recovery-question-${index + 1}'),
      );
      await tester.ensureVisible(field);
      expect(
        find.descendant(
          of: field,
          matching: find.text(vaultRecoveryQuestionLabel(questionIds[index])),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(ValueKey<String>('recovery-answer-${index + 1}')),
        answers[index],
      );
    }
    const replacementPassword = 'Recovered-Master-74!Quartz';
    await tester.enterText(
      find.byKey(const ValueKey<String>('recovery-new-master-password')),
      replacementPassword,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('recovery-confirm-master-password')),
      replacementPassword,
    );
    final submit = find.byKey(const ValueKey<String>('submit-vault-recovery'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(state.isUnlocked, isTrue);
    expect(recoveryJournal.clearCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('vault-recovery-page')),
      findsNothing,
    );
    expect(find.byType(VaultRebuildPage), findsNothing);
    expect(find.byType(VaultUnlockPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final family in CardockThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets('stage1 pages use ${family.name} ${brightness.name} theme', (
        tester,
      ) async {
        final state = await app();
        addTearDown(state.dispose);
        final pages = <Widget>[
          TrashPage(appState: state),
          ReadableExportPage(appState: state),
          VaultHealthPage(
            appState: state,
            onManualBackup: () async {},
            onVerify: () async {},
            onRestore: () async {},
            onRecovery: () async {},
          ),
          VaultRebuildPage(appState: state),
        ];
        for (final page in pages) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(family, brightness),
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: page,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester
                .widget<MaterialApp>(find.byType(MaterialApp))
                .theme!
                .brightness,
            brightness,
          );
        }
      });
    }
  }
  testWidgets(
    'trash restore is available without password; permanent clear requires both confirmations',
    (tester) async {
      final state = await app();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        wrapper(TrashPage(appState: state), const Locale('zh', 'CN')),
      );
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复此项'));
      await tester.pumpAndSettle();
      expect(state.accounts, hasLength(1));
      expect(state.trashAccounts, isEmpty);
      await state.deleteAccount(state.accounts.single.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_forever_outlined));
      await tester.pumpAndSettle();
      expect(find.text('永久删除回收站记录？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(state.trashAccounts, hasLength(1));
      await tester.tap(find.byIcon(Icons.delete_forever_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'incorrect');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(state.trashAccounts, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'readable export starts with trash and passwords disabled; lock hides all data',
    (tester) async {
      final state = await app();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        wrapper(ReadableExportPage(appState: state), const Locale('zh', 'CN')),
      );
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((w) => !w.value),
        true,
      );
      state.lock();
      await tester.pumpAndSettle();
      expect(find.text('请完整解锁当前保险库。'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
    },
  );
  testWidgets(
    'sensitive readable export asks for the vault password only once',
    (tester) async {
      final state = await app();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        wrapper(ReadableExportPage(appState: state), const Locale('zh', 'CN')),
      );

      await tester.tap(find.widgetWithText(SwitchListTile, '包含敏感自定义字段值'));
      await tester.tap(find.text('验证密码并导出'));
      await tester.pumpAndSettle();
      expect(find.text('包含敏感自定义字段值？'), findsOneWidget);

      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('当前保险库密码'), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'incorrect');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(find.textContaining('再次验证当前保险库密码'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(state.errorMessage, '当前保险库密码不正确。');
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'backup reminder is based on facts, dismissible and scoped to current unlock',
    () async {
      final state = await app();
      addTearDown(state.dispose);
      expect(state.backupWarning, isNotNull);
      expect(state.backupWarning, isNot(contains('FORMULA')));
      state.dismissBackupWarning();
      expect(state.backupWarning, isNull);
      state.lock();
      expect(state.backupWarning, isNull);
      await state.unlock(password);
      expect(state.backupWarning, isNotNull);
      expect(state.hasSimilarTrashAccount('=formula()'), true);
      expect(state.hasSimilarTrashAccount('other'), false);
    },
  );
}

final class _CompletedRecoveryJournal implements VaultRecoveryJournal {
  var clearCalls = 0;
  var _cleared = false;

  @override
  Future<VaultRecoveryEntry?> read() async => _cleared
      ? null
      : VaultRecoveryEntry(
          transactionId: 'widget-completed-recovery',
          createdAtUtc: DateTime.utc(2026, 9, 6),
          sourceGeneration: 1,
          revision: 1,
          state: VaultRecoveryState.committed,
          encryptedVaultBytes: const <int>[1],
        );

  @override
  Future<void> clear() async {
    clearCalls += 1;
    _cleared = true;
  }

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) async => 'widget-completed-recovery';

  @override
  Future<void> markCommitted(String transactionId) async {}

  @override
  Future<void> markRolledBack(String transactionId) async {}
}
