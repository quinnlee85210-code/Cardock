import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  test('快速解锁配置只被四类永久错误判定失效', () {
    const permanentReasons = <QuickUnlockFailureReason>{
      QuickUnlockFailureReason.keyInvalidated,
      QuickUnlockFailureReason.keyMissing,
      QuickUnlockFailureReason.corruptedSecret,
      QuickUnlockFailureReason.notConfigured,
    };

    for (final reason in QuickUnlockFailureReason.values) {
      expect(
        reason.invalidatesConfiguration,
        permanentReasons.contains(reason),
        reason: reason.name,
      );
    }
  });

  test('四类永久错误保留原因并自动清除快速解锁配置', () async {
    const permanentReasons = <QuickUnlockFailureReason>[
      QuickUnlockFailureReason.keyInvalidated,
      QuickUnlockFailureReason.keyMissing,
      QuickUnlockFailureReason.corruptedSecret,
      QuickUnlockFailureReason.notConfigured,
    ];

    for (final reason in permanentReasons) {
      final fixture = await _lockedQuickUnlockFixture();
      try {
        fixture.store.quickUnlockFailure = QuickUnlockException(reason);

        expect(
          await fixture.state.unlockWithQuickUnlock(),
          VaultActionResult.rejected,
          reason: reason.name,
        );
        expect(fixture.state.quickUnlockFailureReason, reason);
        expect(fixture.state.quickUnlockEnabled, isFalse);
        expect(fixture.store.quickUnlockEnabled, isFalse);
        expect(fixture.store.disableQuickUnlockCalls, 1);
      } finally {
        fixture.state.dispose();
      }
    }
  });

  test('临时硬件生命周期及启动错误均保留配置并可重试', () async {
    const transientReasons = <QuickUnlockFailureReason>[
      QuickUnlockFailureReason.userCanceled,
      QuickUnlockFailureReason.timeout,
      QuickUnlockFailureReason.temporaryLockout,
      QuickUnlockFailureReason.hardwareUnavailable,
      QuickUnlockFailureReason.lifecycleCanceled,
      QuickUnlockFailureReason.activityUnavailable,
      QuickUnlockFailureReason.promptStartFailed,
      QuickUnlockFailureReason.keySetupFailed,
      QuickUnlockFailureReason.securityUpdateRequired,
    ];

    for (final reason in transientReasons) {
      final fixture = await _lockedQuickUnlockFixture();
      try {
        fixture.store.quickUnlockFailure = QuickUnlockException(reason);

        expect(
          await fixture.state.unlockWithQuickUnlock(),
          VaultActionResult.rejected,
          reason: reason.name,
        );
        expect(fixture.state.quickUnlockFailureReason, reason);
        expect(fixture.state.quickUnlockEnabled, isTrue);
        expect(fixture.store.quickUnlockEnabled, isTrue);
        expect(fixture.store.disableQuickUnlockCalls, 0);

        fixture.store.quickUnlockFailure = null;
        expect(
          await fixture.state.unlockWithQuickUnlock(),
          VaultActionResult.success,
        );
        expect(fixture.state.quickUnlockFailureReason, isNull);
        expect(fixture.state.isUnlocked, isTrue);
      } finally {
        fixture.state.dispose();
      }
    }
  });

  test('启用阶段同样保留结构化原因并仅对永久错误执行清理', () async {
    for (final entry in <QuickUnlockFailureReason, int>{
      QuickUnlockFailureReason.keyMissing: 1,
      QuickUnlockFailureReason.userCanceled: 0,
    }.entries) {
      final store = FakeVaultStore(
        configured: true,
        acceptedPassword: _testMasterPassword,
      );
      final state = AppState(vaultStore: store);
      try {
        await state.initialize();
        expect(
          await state.unlock(_testMasterPassword),
          VaultActionResult.success,
        );
        store.quickUnlockEnableFailure = QuickUnlockException(entry.key);

        expect(await state.enableQuickUnlock(_testMasterPassword), isFalse);
        expect(state.quickUnlockFailureReason, entry.key);
        expect(state.quickUnlockEnabled, isFalse);
        expect(store.disableQuickUnlockCalls, entry.value);
      } finally {
        state.dispose();
      }
    }
  });
}

Future<_QuickUnlockFixture> _lockedQuickUnlockFixture() async {
  final store = FakeVaultStore(
    configured: true,
    acceptedPassword: _testMasterPassword,
  )..quickUnlockEnabled = true;
  final state = AppState(vaultStore: store);
  await state.initialize();
  expect(state.vaultPhase, VaultPhase.locked);
  expect(state.quickUnlockEnabled, isTrue);
  return _QuickUnlockFixture(store: store, state: state);
}

final class _QuickUnlockFixture {
  const _QuickUnlockFixture({required this.store, required this.state});

  final FakeVaultStore store;
  final AppState state;
}
