import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_codec.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_service.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_store.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final firstInstallation = Uint8List.fromList(
    List<int>.generate(16, (index) => index),
  );
  final secondInstallation = Uint8List.fromList(
    List<int>.generate(16, (index) => index + 16),
  );

  late SimpleKeyPair keyPair;
  late PromoActivationVerifier verifier;

  setUp(() async {
    keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    verifier = PromoActivationVerifier(publicKeyBytes: publicKey.bytes);
  });

  tearDown(() => keyPair.destroy());

  test('申请码由16字节安装ID确定性派生为8位Crockford Base32', () async {
    final first = await derivePromoRequestCode(firstInstallation);
    final repeated = await derivePromoRequestCode(firstInstallation);
    final second = await derivePromoRequestCode(secondInstallation);

    expect(first, hasLength(8));
    expect(first, repeated);
    expect(first, isNot(second));
    expect(first, isNot(matches(RegExp('[OIL]'))));
  });

  test('首次启动生成安装ID并在后续启动复用同一申请码', () async {
    final store = MemoryPromoActivationStore();
    final firstController = PromoActivationController(
      store: store,
      verifier: verifier,
      installationIdGenerator: () => firstInstallation,
    );
    await firstController.initialize();
    final firstRequest = firstController.requestCode;
    expect(store.value?.installationId, orderedEquals(firstInstallation));
    firstController.dispose();

    final restarted = PromoActivationController(
      store: store,
      verifier: verifier,
      installationIdGenerator: () => secondInstallation,
    );
    await restarted.initialize();
    expect(restarted.requestCode, firstRequest);
    expect(store.value?.installationId, orderedEquals(firstInstallation));
    restarted.dispose();
  });

  test('持久化目录不可用时保持免费且不暴露临时申请码', () async {
    final controller = PromoActivationController(
      store: const UnavailablePromoActivationStore(),
      verifier: verifier,
      installationIdGenerator: () => firstInstallation,
    );

    await controller.initialize();

    expect(controller.isInitialized, isTrue);
    expect(controller.value, ProductEntitlement.free);
    expect(controller.requestCode, isNull);
    controller.dispose();
  });

  test('Ed25519签码可验证并容忍连字符、空白和小写', () async {
    final request = await derivePromoRequestCode(firstInstallation);
    final code = await const PromoActivationIssuer().issue(
      requestCode: request,
      keyPair: keyPair,
      issuedAtUtc: DateTime.utc(2026, 8, 14, 7, 30),
    );
    final pasted = '  ${code.toLowerCase().replaceAll('-', '-\n')}  ';
    final result = await verifier.verify(
      activationCode: pasted,
      expectedRequestCode: request,
    );

    expect(result.status, PromoActivationVerificationStatus.valid);
    expect(result.requestCode, request);
    expect(result.issuedAtUtc, DateTime.utc(2026, 8, 14, 7, 30));
    expect(result.canonicalCode, code);
  });

  test('有效签名属于另一安装ID时明确返回设备不符', () async {
    final firstRequest = await derivePromoRequestCode(firstInstallation);
    final secondRequest = await derivePromoRequestCode(secondInstallation);
    final code = await const PromoActivationIssuer().issue(
      requestCode: firstRequest,
      keyPair: keyPair,
    );

    final result = await verifier.verify(
      activationCode: code,
      expectedRequestCode: secondRequest,
    );
    expect(result.status, PromoActivationVerificationStatus.deviceMismatch);
  });

  test('签名篡改和格式损坏均不会授予权益', () async {
    final request = await derivePromoRequestCode(firstInstallation);
    final code = await const PromoActivationIssuer().issue(
      requestCode: request,
      keyPair: keyPair,
    );
    final normalized = normalizePromoActivationCode(code);
    final index = 20;
    final replacement = normalized[index] == 'A' ? 'B' : 'A';
    final tampered = normalized.replaceRange(index, index + 1, replacement);

    expect(
      (await verifier.verify(
        activationCode: tampered,
        expectedRequestCode: request,
      )).status,
      PromoActivationVerificationStatus.invalidSignature,
    );
    expect(
      (await verifier.verify(
        activationCode: 'NOT-A-VALID-CODE',
        expectedRequestCode: request,
      )).status,
      PromoActivationVerificationStatus.malformed,
    );
  });

  test('激活成功持久化原签名码且每次启动重新验签', () async {
    final store = MemoryPromoActivationStore(
      PromoActivationRecord(installationId: firstInstallation),
    );
    final request = await derivePromoRequestCode(firstInstallation);
    final code = await const PromoActivationIssuer().issue(
      requestCode: request,
      keyPair: keyPair,
    );
    final firstController = PromoActivationController(
      store: store,
      verifier: verifier,
    );
    await firstController.initialize();
    expect(firstController.value, ProductEntitlement.free);
    expect((await firstController.activate(code)).succeeded, isTrue);
    expect(firstController.value, ProductEntitlement.purchased);
    firstController.dispose();

    final restarted = PromoActivationController(
      store: store,
      verifier: verifier,
    );
    await restarted.initialize();
    expect(restarted.value, ProductEntitlement.purchased);
    restarted.dispose();

    store.value = PromoActivationRecord(
      installationId: firstInstallation,
      activationCode: _tamper(code),
    );
    final corrupted = PromoActivationController(
      store: store,
      verifier: verifier,
    );
    await corrupted.initialize();
    expect(corrupted.value, ProductEntitlement.free);
    corrupted.dispose();
  });

  test('文件存储跨控制器启动保留签名码而非布尔权益', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cardock-promo-store-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FilePromoActivationStore(
      File('${directory.path}${Platform.pathSeparator}promo.json'),
    );
    final firstController = PromoActivationController(
      store: store,
      verifier: verifier,
      installationIdGenerator: () => firstInstallation,
    );
    await firstController.initialize();
    final code = await const PromoActivationIssuer().issue(
      requestCode: firstController.requestCode!,
      keyPair: keyPair,
    );
    expect((await firstController.activate(code)).succeeded, isTrue);
    firstController.dispose();

    final raw = await store.file.readAsString();
    expect(raw, contains('activationCode'));
    expect(raw, isNot(contains('purchased')));
    final restarted = PromoActivationController(
      store: store,
      verifier: verifier,
    );
    await restarted.initialize();
    expect(restarted.isActivated, isTrue);
    restarted.dispose();
  });

  test('激活记录不进入便携备份且新安装恢复后保持免费', () async {
    final sourceRequest = await derivePromoRequestCode(firstInstallation);
    final code = await const PromoActivationIssuer().issue(
      requestCode: sourceRequest,
      keyPair: keyPair,
    );
    final sourcePromo = PromoActivationController(
      store: MemoryPromoActivationStore(
        PromoActivationRecord(
          installationId: firstInstallation,
          activationCode: code,
        ),
      ),
      verifier: verifier,
    );
    await sourcePromo.initialize();
    expect(sourcePromo.isActivated, isTrue);

    final codec = PortableBackupCodec();
    final backup = await codec.encryptV2(
      snapshot: VaultSnapshot.empty(),
      backupMasterPassword: 'Cobalt-River-Quartz-74!Archive',
    );
    final restored = await codec.read(
      bytes: backup,
      backupMasterPassword: 'Cobalt-River-Quartz-74!Archive',
    );
    final restoredPayload = jsonEncode(
      restored.snapshot.toEncryptedPayloadJson(),
    );
    expect(restoredPayload, isNot(contains('installationId')));
    expect(restoredPayload, isNot(contains('activationCode')));
    expect(restoredPayload, isNot(contains(sourceRequest)));

    final targetPromo = PromoActivationController(
      store: MemoryPromoActivationStore(
        PromoActivationRecord(installationId: secondInstallation),
      ),
      verifier: verifier,
    );
    await targetPromo.initialize();
    expect(targetPromo.value, ProductEntitlement.free);
    expect(targetPromo.requestCode, isNot(sourceRequest));
    expect(
      (await targetPromo.activate(code)).status,
      PromoActivationActionStatus.deviceMismatch,
    );
    expect(targetPromo.value, ProductEntitlement.free);
    sourcePromo.dispose();
    targetPromo.dispose();
  });
}

String _tamper(String code) {
  final normalized = normalizePromoActivationCode(code);
  final index = 24;
  final replacement = normalized[index] == 'A' ? 'B' : 'A';
  return normalized.replaceRange(index, index + 1, replacement);
}
