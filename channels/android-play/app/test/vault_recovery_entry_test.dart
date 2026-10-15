import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  testWidgets('visible模式显示忘记密码入口并可打开恢复页', (tester) async {
    await _pumpLockedRecoveryApp(
      tester,
      entryMode: VaultRecoveryEntryMode.visible,
    );

    final visibleEntry = find.byKey(
      const ValueKey<String>('visible-vault-recovery-entry'),
    );
    expect(visibleEntry, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('vault-recovery-page')),
      findsNothing,
    );

    await tester.ensureVisible(visibleEntry);
    await tester.pumpAndSettle();
    await tester.tap(visibleEntry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('vault-recovery-page')),
      findsOneWidget,
    );
    for (var index = 1; index <= 3; index += 1) {
      final selector = find.byKey(ValueKey<String>('recovery-question-$index'));
      expect(selector, findsOneWidget);
      expect(
        find.descendant(
          of: selector,
          matching: find.text(
            vaultRecoveryQuestionLabel(
              const <String>[
                'childhood_city',
                'first_school',
                'first_teacher',
              ][index - 1],
            ),
          ),
        ),
        findsOneWidget,
        reason: '恢复页应直接显示设置时保存的具体题目',
      );
    }
    expect(find.textContaining('真实保险库'), findsNothing);
    expect(find.textContaining('诱饵保险库'), findsNothing);

    final submit = find.byKey(const ValueKey<String>('submit-vault-recovery'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('请输入该问题的完整答案'), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('同一入口存在两组密保时仅以中性问题组切换并展示具体题目', (tester) async {
    await _pumpLockedRecoveryApp(
      tester,
      entryMode: VaultRecoveryEntryMode.visible,
      both: true,
    );

    final visibleEntry = find.byKey(
      const ValueKey<String>('visible-vault-recovery-entry'),
    );
    await tester.ensureVisible(visibleEntry);
    await tester.tap(visibleEntry);
    await tester.pumpAndSettle();

    final selector = find.byKey(
      const ValueKey<String>('recovery-question-set-selector'),
    );
    expect(selector, findsOneWidget);
    expect(find.textContaining('真实保险库'), findsNothing);
    expect(find.textContaining('诱饵保险库'), findsNothing);
    expect(
      find.text(vaultRecoveryQuestionLabel('childhood_city')),
      findsOneWidget,
    );

    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('问题组 2').last);
    await tester.pumpAndSettle();

    expect(
      find.text(vaultRecoveryQuestionLabel('favorite_food')),
      findsOneWidget,
    );
    expect(
      find.text(vaultRecoveryQuestionLabel('childhood_city')),
      findsNothing,
    );
    expect(find.textContaining('真实保险库'), findsNothing);
    expect(find.textContaining('诱饵保险库'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('logoFiveTap模式隐藏入口且3秒内第五击才打开恢复页', (tester) async {
    await _pumpLockedRecoveryApp(
      tester,
      entryMode: VaultRecoveryEntryMode.logoFiveTap,
      decoy: true,
    );

    expect(
      find.byKey(const ValueKey<String>('visible-vault-recovery-entry')),
      findsNothing,
    );
    final logo = find.byKey(const ValueKey<String>('vault-brand-mark-action'));
    expect(logo, findsOneWidget);

    for (var tap = 0; tap < 4; tap += 1) {
      await tester.tap(logo);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byKey(const ValueKey<String>('vault-recovery-page')),
      findsNothing,
      reason: '四击不能暴露恢复页',
    );

    await tester.tap(logo);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-recovery-page')),
      findsOneWidget,
      reason: '累计五击耗时不足3秒时应进入恢复页',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('恢复页在320x640与200%字号下可滚动且不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await _pumpLockedRecoveryApp(
      tester,
      entryMode: VaultRecoveryEntryMode.visible,
    );
    final entry = find.byKey(
      const ValueKey<String>('visible-vault-recovery-entry'),
    );
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final submit = find.byKey(const ValueKey<String>('submit-vault-recovery'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpLockedRecoveryApp(
  WidgetTester tester, {
  required VaultRecoveryEntryMode entryMode,
  bool decoy = false,
  bool both = false,
}) async {
  final store = FakeVaultStore(
    configured: true,
    acceptedPassword: _testMasterPassword,
  );
  final challenge = VaultRecoveryChallenge(
    binding: VaultRecoveryBinding(
      vaultInstanceId: List<int>.filled(16, 1),
      slotId: List<int>.filled(16, 2),
      deviceBindingId: List<int>.filled(16, 3),
    ),
    questionIds: decoy
        ? const <String>['favorite_food', 'first_pet', 'favorite_book']
        : const <String>['childhood_city', 'first_school', 'first_teacher'],
    entryMode: entryMode,
  );
  if (both) {
    store
      ..decoyConfigured = true
      ..configuredRecoveryChallenge = challenge
      ..configuredDecoyRecoveryChallenge = VaultRecoveryChallenge(
        binding: VaultRecoveryBinding(
          vaultInstanceId: List<int>.filled(16, 4),
          slotId: List<int>.filled(16, 5),
          deviceBindingId: List<int>.filled(16, 6),
        ),
        questionIds: const <String>[
          'favorite_food',
          'first_pet',
          'favorite_book',
        ],
        entryMode: entryMode,
      );
  } else if (decoy) {
    store
      ..decoyConfigured = true
      ..configuredDecoyRecoveryChallenge = challenge;
  } else {
    store.configuredRecoveryChallenge = challenge;
  }

  await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('vault-unlock-page')),
    findsOneWidget,
  );
}
