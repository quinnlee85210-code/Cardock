import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/preferences/notification_privacy_preferences.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/recovery_device_secret.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'recording_reminder_scheduler.dart';
import '../stage2_subscription_management_test.dart' as f;

const stage4Master = 'TEST-ONLY-Stage4-Master-2468!';
const stage4Decoy = 'TEST-ONLY-Decoy-6428!';

class Stage4Harness {
  Stage4Harness._(this.directory, this.store, this.state, this.reminders);
  final Directory directory;
  final LayeredVaultStore store;
  final AppState state;
  final RecordingReminderScheduler reminders;
  static Future<Stage4Harness> create({
    NotificationPrivacyStore? privacy,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'cardock-stage4-synthetic-',
    );
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: const VaultKdfParameters(
        memoryKiB: 64,
        iterations: 1,
        parallelism: 1,
      ),
      quickUnlockSecretStore: Stage4QuickStore(),
      recoveryDeviceSecretStore: Stage4RecoveryStore(),
    );
    final reminders = RecordingReminderScheduler();
    final state = AppState(
      vaultStore: store,
      now: () => f.today,
      reminderScheduler: reminders,
      notificationPrivacyStore: privacy,
    );
    await state.initialize();
    expect(await state.createVault(stage4Master), VaultActionResult.success);
    return Stage4Harness._(directory, store, state, reminders);
  }

  Future<void> addSubscription() async {
    expect(
      await state.addSubscription(
        SubscriptionDraft(accountId: null, details: f.sub().details),
      ),
      true,
    );
  }

  Future<void> dispose() async {
    state.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class Stage4QuickStore implements QuickUnlockSecretStore {
  QuickUnlockSecret? value;
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;
  @override
  Future<bool> containsSecret() async => value != null;
  @override
  Future<void> deleteSecret() async {
    value?.destroy();
    value = null;
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async => value == null
      ? null
      : QuickUnlockSecret(vaultId: value!.vaultId, dataKey: value!.dataKey);
  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    value?.destroy();
    value = QuickUnlockSecret(vaultId: secret.vaultId, dataKey: secret.dataKey);
  }
}

class Stage4RecoveryStore implements RecoveryDeviceSecretStore {
  @override
  Future<bool> isConfigured() async => false;
  @override
  Future<RecoveryDeviceSecretMaterial?> read() async => null;
  @override
  Future<void> delete() async {}
  @override
  Future<void> write(RecoveryDeviceSecretMaterial material) async =>
      throw UnimplementedError('No recovery setup in this fixture');
}
