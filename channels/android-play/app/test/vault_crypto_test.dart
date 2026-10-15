import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  test('Argon2id 符合 RFC 9106 第5.3节测试向量', () async {
    final password = SecretKeyData(
      Uint8List(32)..fillRange(0, 32, 0x01),
      overwriteWhenDestroyed: true,
    );
    final algorithm = Argon2id(
      memory: 32,
      iterations: 3,
      parallelism: 4,
      hashLength: 32,
    );
    final derived = await algorithm.deriveKey(
      secretKey: password,
      nonce: Uint8List(16)..fillRange(0, 16, 0x02),
      optionalSecret: Uint8List(8)..fillRange(0, 8, 0x03),
      associatedData: Uint8List(12)..fillRange(0, 12, 0x04),
    );
    addTearDown(() {
      password.destroy();
      derived.destroy();
    });

    expect(
      await derived.extractBytes(),
      _hex(
        '0d640df58d78766c08c037a34a8b53c9'
        'd01ef0452d75b65eb52520e96b01e659',
      ),
    );
  });

  test('AES-256-GCM 符合空明文标准测试向量', () async {
    final cipher = AesGcm.with256bits();
    final key = SecretKeyData(Uint8List(32), overwriteWhenDestroyed: true);
    addTearDown(key.destroy);

    final box = await cipher.encrypt(
      const <int>[],
      secretKey: key,
      nonce: Uint8List(12),
    );

    expect(box.cipherText, isEmpty);
    expect(box.mac.bytes, _hex('530f8afbc74536b9a963b4f1c4cb738b'));
    expect(await cipher.decrypt(box, secretKey: key), isEmpty);
  });

  test('生产 KDF 参数固定为当前 OWASP Argon2id 基线', () {
    expect(VaultKdfParameters.production.memoryKiB, 19 * 1024);
    expect(VaultKdfParameters.production.iterations, 2);
    expect(VaultKdfParameters.production.parallelism, 1);
    expect(VaultKdfParameters.production.hashLength, 32);
  });

  test('envelope 默认只接受生产 KDF，测试 profile 必须显式允许', () {
    final productionBytes = _syntheticEnvelope(
      VaultKdfParameters.production,
    ).toBytes();
    final production = VaultEnvelope.fromBytes(productionBytes);
    expect(
      production.kdf.hasSameProfileAs(VaultKdfParameters.production),
      isTrue,
    );

    final testProfileBytes = _syntheticEnvelope(_testKdf).toBytes();
    expect(
      () => VaultEnvelope.fromBytes(testProfileBytes),
      throwsA(isA<VaultUnsupportedKdfProfileException>()),
    );
    final explicitlySupported = VaultEnvelope.fromBytes(
      testProfileBytes,
      supportedKdfProfiles: const <VaultKdfParameters>[_testKdf],
    );
    expect(explicitlySupported.kdf.hasSameProfileAs(_testKdf), isTrue);
  });

  test('加密文件不含明文，nonce 更新，错密码失败且重启可恢复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-roundtrip-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final opened = await store.create(masterPassword: _testMasterPassword);

    const platform = 'TEST-ONLY-PLATFORM-SENTINEL';
    const login = 'TEST-ONLY-LOGIN-SENTINEL';
    const username = '加密中文用户名-SENTINEL';
    const password = 'TEST-ONLY-PASSWORD-SENTINEL';
    const subscriptionService = '测试专属云存储服务-SENTINEL';
    const subscriptionPlan = '测试年度套餐-SENTINEL';
    const subscriptionAmount = '8844.7712';
    const subscriptionPaymentMethod = '测试支付方式-SENTINEL';
    const firstSubscribedOnText = '2026-07-13';
    const nextRenewalOnText = '2027-07-13';
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: platform,
        loginAccount: login,
        username: username,
        password: password,
        notes: 'TEST-ONLY-NOTES-SENTINEL',
      ),
    );
    final subscription = SubscriptionRecord.fromDraft(
      id: 'subscription-1',
      draft: SubscriptionDraft(
        accountId: account.id,
        details: SubscriptionDetailsDraft(
          serviceName: subscriptionService,
          planName: subscriptionPlan,
          amount: subscriptionAmount,
          currency: 'CNY',
          firstSubscribedOn: DateTime(2026, 7, 13),
          nextRenewalOn: DateTime(2027, 7, 13),
          cycleCount: 1,
          cycleUnit: SubscriptionCycleUnit.year,
          autoRenew: false,
          paymentMethod: subscriptionPaymentMethod,
          reminderDaysBefore: 15,
          status: SubscriptionStatus.paused,
        ),
      ),
    );
    final snapshot = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      nextSubscriptionId: 2,
      subscriptions: <SubscriptionRecord>[subscription],
    );
    await opened.session.save(snapshot);
    opened.session.close();

    final envelopes = <VaultEnvelope>[];
    for (final file in _slotFiles(directory)) {
      expect(await file.exists(), isTrue);
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes);
      for (final sentinel in [
        platform,
        login,
        username,
        password,
        'TEST-ONLY-NOTES',
        subscriptionService,
        subscriptionPlan,
        subscriptionAmount,
        subscriptionPaymentMethod,
        firstSubscribedOnText,
        nextRenewalOnText,
      ]) {
        expect(text.contains(sentinel), isFalse);
      }
      expect(text.contains('masterPassword'), isFalse);
      expect(text.contains('verifier'), isFalse);
      envelopes.add(
        VaultEnvelope.fromBytes(
          bytes,
          supportedKdfProfiles: const <VaultKdfParameters>[_testKdf],
        ),
      );
    }
    expect(
      envelopes.map((envelope) => base64Encode(envelope.payload.nonce)).toSet(),
      hasLength(2),
    );

    await expectLater(
      store.unlock(masterPassword: 'TEST-ONLY-WRONG-1234'),
      throwsA(isA<VaultUnlockException>()),
    );

    final reopened = await _testStore(
      directory,
    ).unlock(masterPassword: _testMasterPassword);
    expect(reopened.recoveredFromFallback, isFalse);
    expect(reopened.snapshot.accounts, hasLength(1));
    expect(reopened.snapshot.accounts.single.platformName, platform);
    expect(reopened.snapshot.accounts.single.username, username);
    expect(reopened.snapshot.accounts.single.password, password);
    expect(reopened.snapshot.nextSubscriptionId, 2);
    expect(reopened.snapshot.subscriptions, hasLength(1));
    final restoredSubscription = reopened.snapshot.subscriptions.single;
    expect(restoredSubscription.id, 'subscription-1');
    expect(restoredSubscription.accountId, account.id);
    expect(restoredSubscription.serviceName, subscriptionService);
    expect(restoredSubscription.planName, subscriptionPlan);
    expect(restoredSubscription.amount, subscriptionAmount);
    expect(restoredSubscription.currency, 'CNY');
    expect(restoredSubscription.firstSubscribedOn, DateTime(2026, 7, 13));
    expect(restoredSubscription.nextRenewalOn, DateTime(2027, 7, 13));
    expect(restoredSubscription.cycleCount, 1);
    expect(restoredSubscription.cycleUnit, SubscriptionCycleUnit.year);
    expect(restoredSubscription.autoRenew, isFalse);
    expect(restoredSubscription.paymentMethod, subscriptionPaymentMethod);
    expect(restoredSubscription.reminderDaysBefore, 15);
    expect(restoredSubscription.status, SubscriptionStatus.paused);
    reopened.session.close();
  });

  test('schema v1 加密负载兼容读取且后续序列化升级为 v5', () async {
    const legacyPlatform = '旧版中文平台-SENTINEL';
    const legacyLogin = '旧版中文账号-SENTINEL';
    final legacyPayload = <String, Object?>{
      'schemaVersion': 1,
      'nextAccountId': 2,
      'accounts': <Object?>[
        <String, Object?>{
          'id': 'account-1',
          'platformName': legacyPlatform,
          'category': '云服务',
          'loginAccount': legacyLogin,
          'boundPhone': null,
          'boundEmail': null,
          'password': null,
          'website': null,
          'notes': '旧版备注-SENTINEL',
        },
      ],
    };
    final cipher = AesGcm.with256bits();
    final dataKey = SecretKeyData(
      Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
      overwriteWhenDestroyed: true,
    );
    addTearDown(dataKey.destroy);
    const generation = 7;
    final encryptedLegacyPayload = await cipher.encrypt(
      utf8.encode(jsonEncode(legacyPayload)),
      secretKey: dataKey,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 11)),
      aad: VaultEnvelope.payloadAadFor(generation),
    );
    final envelope = VaultEnvelope(
      generation: generation,
      kdf: _testKdf,
      salt: Uint8List(16),
      wrappedDataKey: SecretBox(
        Uint8List(32),
        nonce: Uint8List(12),
        mac: Mac(Uint8List(16)),
      ),
      payload: encryptedLegacyPayload,
    );

    final restored = await VaultCrypto(
      cipher: cipher,
    ).decryptSnapshot(envelope: envelope, dataKey: dataKey);

    expect(restored.nextAccountId, 2);
    expect(restored.accounts, hasLength(1));
    expect(restored.accounts.single.platformName, legacyPlatform);
    expect(restored.accounts.single.loginAccount, legacyLogin);
    expect(restored.accounts.single.username, isNull);
    expect(restored.nextSubscriptionId, 1);
    expect(restored.subscriptions, isEmpty);
    final upgradedPayload = restored.toEncryptedPayloadJson();
    expect(
      upgradedPayload['schemaVersion'],
      VaultSnapshot.currentSchemaVersion,
    );
    expect(upgradedPayload['nextSubscriptionId'], 1);
    expect(upgradedPayload['subscriptions'], isEmpty);
  });

  test('主密码保留首尾空格，不进行隐式 trim', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-password-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    const exactPassword = '  TEST-ONLY-MASTER-1234  ';
    final store = _testStore(directory);
    final created = await store.create(masterPassword: exactPassword);
    created.session.close();

    await expectLater(
      store.unlock(masterPassword: exactPassword.trim()),
      throwsA(isA<VaultUnlockException>()),
    );
    final reopened = await store.unlock(masterPassword: exactPassword);
    reopened.session.close();
  });

  test('活动密文可导出并用备份主密码独立验证读取', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-backup-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final opened = await store.create(masterPassword: _testMasterPassword);
    await opened.session.save(
      VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(platformName: '加密备份账号-SENTINEL'),
          ),
        ],
      ),
    );
    final backup = await opened.session.exportEncryptedBackup();
    opened.session.close();

    expect(utf8.decode(backup), isNot(contains('加密备份账号-SENTINEL')));
    final restored = await store.readEncryptedBackup(
      bytes: backup,
      masterPassword: _testMasterPassword,
    );
    expect(restored.accounts.single.platformName, '加密备份账号-SENTINEL');
    await expectLater(
      store.readEncryptedBackup(
        bytes: backup,
        masterPassword: 'TEST-ONLY-WRONG-1234',
      ),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('快速解锁密钥由受保护存储边界持有且绑定当前加密库', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-biometric-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final quickStore = _MemoryQuickUnlockSecretStore();
    addTearDown(quickStore.dispose);
    final store = EncryptedVaultStore(
      directoryProvider: () async => directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickStore,
    );
    final opened = await store.create(masterPassword: _testMasterPassword);
    await opened.session.save(
      VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(platformName: '生物识别绑定账号'),
          ),
        ],
      ),
    );
    await opened.session.enableQuickUnlock();
    expect(await store.isQuickUnlockEnabled(), isTrue);
    opened.session.close();

    final quickOpened = await store.unlockWithQuickUnlock();
    expect(quickOpened.snapshot.accounts.single.platformName, '生物识别绑定账号');
    quickOpened.session.close();
    await store.disableQuickUnlock();
    expect(await store.isQuickUnlockEnabled(), isFalse);
  });

  test('同一存储实例会串行执行并发创建请求', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-serialized-create-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final providerEntered = Completer<void>();
    final releaseProvider = Completer<void>();
    var providerCalls = 0;
    final store = EncryptedVaultStore(
      directoryProvider: () async {
        providerCalls += 1;
        if (providerCalls == 1) {
          providerEntered.complete();
          await releaseProvider.future;
        }
        return directory;
      },
      creationKdf: _testKdf,
    );

    final firstCreate = store.create(masterPassword: _testMasterPassword);
    final secondCreate = store.create(
      masterPassword: 'TEST-ONLY-SECOND-MASTER',
    );
    await providerEntered.future;
    expect(providerCalls, 1);

    releaseProvider.complete();
    final firstOpened = await firstCreate;
    firstOpened.session.close();
    await expectLater(
      secondCreate,
      throwsA(isA<VaultAlreadyExistsException>()),
    );
  });

  test('最新槽为未来 envelope 版本时硬拒绝且不回退或写盘', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-future-envelope-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final opened = await store.create(masterPassword: _testMasterPassword);
    await opened.session.save(
      VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(platformName: '未来 envelope 前的最新数据'),
          ),
        ],
      ),
    );
    opened.session.close();

    final slots = _slotFiles(directory);
    final decoded =
        jsonDecode(await slots.last.readAsString()) as Map<String, dynamic>;
    expect(decoded['generation'], 2);
    decoded['formatVersion'] = 3;
    await slots.last.writeAsString(jsonEncode(decoded), flush: true);
    final beforeA = await slots.first.readAsBytes();
    final beforeB = await slots.last.readAsBytes();

    await expectLater(
      store.unlock(masterPassword: _testMasterPassword),
      throwsA(
        isA<VaultUnsupportedEnvelopeVersionException>().having(
          (error) => error.version,
          'version',
          3,
        ),
      ),
    );
    expect(await slots.first.readAsBytes(), orderedEquals(beforeA));
    expect(await slots.last.readAsBytes(), orderedEquals(beforeB));
  });

  test('最新槽为受认证的未来 schema 时硬拒绝且不回退或写盘', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-future-schema-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final crypto = VaultCrypto();
    final material = await crypto.create(
      masterPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty(),
      kdf: _testKdf,
    );
    addTearDown(() {
      if (!material.dataKey.hasBeenDestroyed) {
        material.dataKey.destroy();
      }
    });

    const futureGeneration = 2;
    final futureSchema = VaultSnapshot.currentSchemaVersion + 1;
    final cipher = AesGcm.with256bits();
    final futurePayload = await cipher.encrypt(
      utf8.encode(jsonEncode(<String, Object?>{'schemaVersion': futureSchema})),
      secretKey: material.dataKey,
      nonce: cipher.newNonce(),
      aad: VaultEnvelope.payloadAadFor(futureGeneration),
    );
    final futureEnvelope = VaultEnvelope(
      generation: futureGeneration,
      kdf: material.envelope.kdf,
      salt: material.envelope.salt,
      wrappedDataKey: material.envelope.wrappedDataKey,
      payload: futurePayload,
    );
    final slots = _slotFiles(directory);
    await slots.first.writeAsBytes(material.envelope.toBytes(), flush: true);
    await slots.last.writeAsBytes(futureEnvelope.toBytes(), flush: true);
    final beforeA = await slots.first.readAsBytes();
    final beforeB = await slots.last.readAsBytes();

    await expectLater(
      _testStore(directory).unlock(masterPassword: _testMasterPassword),
      throwsA(
        isA<VaultUnsupportedSchemaVersionException>().having(
          (error) => error.version,
          'version',
          futureSchema,
        ),
      ),
    );
    expect(await slots.first.readAsBytes(), orderedEquals(beforeA));
    expect(await slots.last.readAsBytes(), orderedEquals(beforeB));
  });

  test('最新槽使用未允许的 KDF profile 时硬拒绝且不回退', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-unsupported-kdf-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final opened = await store.create(masterPassword: _testMasterPassword);
    await opened.session.save(
      VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(platformName: '不应从未允许 KDF 槽读取'),
          ),
        ],
      ),
    );
    opened.session.close();

    final slots = _slotFiles(directory);
    final decoded =
        jsonDecode(await slots.last.readAsString()) as Map<String, dynamic>;
    final kdf = decoded['kdf'] as Map<String, dynamic>;
    kdf['memoryKiB'] = _testKdf.memoryKiB + 1;
    await slots.last.writeAsString(jsonEncode(decoded), flush: true);
    final beforeA = await slots.first.readAsBytes();
    final beforeB = await slots.last.readAsBytes();

    await expectLater(
      store.unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultUnsupportedKdfProfileException>()),
    );
    expect(await slots.first.readAsBytes(), orderedEquals(beforeA));
    expect(await slots.last.readAsBytes(), orderedEquals(beforeB));
  });

  test('受未来 KDF profile 保护的最新代不会被旧槽降级覆盖', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-future-kdf-no-downgrade-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    const futureKdf = VaultKdfParameters(
      memoryKiB: 65,
      iterations: 1,
      parallelism: 1,
    );
    final crypto = VaultCrypto();
    final legacy = await crypto.create(
      masterPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty(),
      kdf: _testKdf,
    );
    final future = await crypto.create(
      masterPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty(),
      kdf: futureKdf,
    );
    addTearDown(() {
      if (!legacy.dataKey.hasBeenDestroyed) legacy.dataKey.destroy();
      if (!future.dataKey.hasBeenDestroyed) future.dataKey.destroy();
    });
    final futureEnvelope = await crypto.encryptNext(
      previous: future.envelope,
      dataKey: future.dataKey,
      snapshot: VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(platformName: '未来 KDF 最新数据'),
          ),
        ],
      ),
    );
    final slots = _slotFiles(directory);
    await slots.first.writeAsBytes(legacy.envelope.toBytes(), flush: true);
    await slots.last.writeAsBytes(futureEnvelope.toBytes(), flush: true);
    final beforeA = await slots.first.readAsBytes();
    final beforeB = await slots.last.readAsBytes();

    final oldStore = _testStore(directory);
    await expectLater(
      oldStore.unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultUnsupportedKdfProfileException>()),
    );
    await expectLater(
      oldStore.unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultUnsupportedKdfProfileException>()),
    );
    expect(await slots.first.readAsBytes(), orderedEquals(beforeA));
    expect(await slots.last.readAsBytes(), orderedEquals(beforeB));
    final persistedLatest = jsonDecode(await slots.last.readAsString());
    expect((persistedLatest as Map<String, dynamic>)['generation'], 2);
  });

  test('活动数据密钥可显式销毁且销毁后拒绝继续加密', () async {
    final crypto = VaultCrypto();
    final material = await crypto.create(
      masterPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty(),
      kdf: _testKdf,
    );

    material.dataKey.destroy();

    expect(material.dataKey.hasBeenDestroyed, isTrue);
    await expectLater(
      crypto.encryptNext(
        previous: material.envelope,
        dataKey: material.dataKey,
        snapshot: VaultSnapshot.empty(),
      ),
      throwsA(isA<VaultClosedException>()),
    );
  });

  test('最新槽被篡改时回退到上一代有效槽', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-fallback-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final opened = await store.create(masterPassword: _testMasterPassword);
    await opened.session.save(
      VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(platformName: 'TEST-ONLY-LATEST-GENERATION'),
          ),
        ],
      ),
    );
    opened.session.close();

    final latestFile = _slotFiles(directory).last;
    await _tamperPayload(latestFile);

    final recovered = await store.unlock(masterPassword: _testMasterPassword);
    expect(recovered.recoveredFromFallback, isTrue);
    expect(recovered.session.generation, 1);
    expect(recovered.snapshot.accounts, isEmpty);
    recovered.session.close();
  });

  test('唯一有效槽被篡改时不会重建或覆盖为空库', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-tamper-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final created = await store.create(masterPassword: _testMasterPassword);
    created.session.close();

    final slot = _slotFiles(directory).first;
    final before = await slot.readAsBytes();
    await _tamperPayload(slot);
    await expectLater(
      store.unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultUnlockException>()),
    );
    expect(await slot.readAsBytes(), isNot(equals(before)));
    expect(await _slotFiles(directory).last.exists(), isFalse);
  });

  test('密码轮换使用全新随机 DEK，旧密码和旧 DEK 都不能读取新代', () async {
    const newPassword = 'TEST-ONLY-NEW-MASTER-5678!';
    final crypto = VaultCrypto();
    final material = await crypto.create(
      masterPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty(),
      kdf: _testKdf,
    );
    final originalDataKey = Uint8List.fromList(material.dataKey.bytes);
    final rotated = await crypto.rotateDataKeyNext(
      previous: material.envelope,
      snapshot: material.snapshot,
      newPassword: newPassword,
      kdf: _testKdf,
    );
    expect(rotated.dataKey.bytes, isNot(equals(originalDataKey)));
    expect(
      rotated.envelope.wrappedDataKey.nonce,
      isNot(equals(material.envelope.wrappedDataKey.nonce)),
    );
    expect(
      rotated.envelope.wrappedDataKey.cipherText,
      isNot(equals(material.envelope.wrappedDataKey.cipherText)),
    );
    expect(
      rotated.envelope.payload.nonce,
      isNot(equals(material.envelope.payload.nonce)),
    );
    final reopenedMaterial = await crypto.open(
      masterPassword: newPassword,
      envelope: rotated.envelope,
    );
    expect(reopenedMaterial.dataKey.bytes, rotated.dataKey.bytes);
    await expectLater(
      crypto.open(
        masterPassword: _testMasterPassword,
        envelope: rotated.envelope,
      ),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    await expectLater(
      crypto.decryptSnapshot(
        envelope: rotated.envelope,
        dataKey: material.dataKey,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    reopenedMaterial.dataKey.destroy();
    rotated.dataKey.destroy();
    material.dataKey.destroy();
    originalDataKey.fillRange(0, originalDataKey.length, 0);

    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-password-change-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final quickStore = _MemoryQuickUnlockSecretStore();
    addTearDown(quickStore.dispose);
    final store = _testStore(directory, quickUnlockSecretStore: quickStore);
    final created = await store.create(masterPassword: _testMasterPassword);
    final snapshot = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[
        AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(platformName: '轮换保留数据'),
        ),
      ],
    );
    await created.session.save(snapshot);
    await created.session.enableQuickUnlock();
    final oldQuickSecret = await quickStore.readSecret();
    expect(oldQuickSecret, isNotNull);
    created.session.close();

    final changed = await store.changeMasterPassword(
      currentMasterPassword: _testMasterPassword,
      newMasterPassword: newPassword,
    );
    expect(changed.snapshot.accounts.single.platformName, '轮换保留数据');
    await changed.session.save(snapshot);
    changed.session.close();

    final activeEnvelopes = <VaultEnvelope>[];
    for (final slot in _slotFiles(directory)) {
      if (!await slot.exists()) continue;
      activeEnvelopes.add(
        VaultEnvelope.fromBytes(
          await slot.readAsBytes(),
          supportedKdfProfiles: const <VaultKdfParameters>[_testKdf],
        ),
      );
    }
    activeEnvelopes.sort(
      (left, right) => right.generation.compareTo(left.generation),
    );
    final oldDataKey = SecretKeyData(
      Uint8List.fromList(oldQuickSecret!.dataKey),
      overwriteWhenDestroyed: true,
    );
    await expectLater(
      crypto.decryptSnapshot(
        envelope: activeEnvelopes.first,
        dataKey: oldDataKey,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    oldDataKey.destroy();
    oldQuickSecret.destroy();

    await expectLater(
      _testStore(directory).unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final reopened = await _testStore(
      directory,
    ).unlock(masterPassword: newPassword);
    expect(reopened.snapshot.accounts.single.platformName, '轮换保留数据');
    reopened.session.close();

    // 主状态损坏时，上一代仍是 committed floor，不会退回旧密码。
    final passwordState = File(
      '${directory.path}${Platform.pathSeparator}password_change_state_v1.json',
    );
    await passwordState.writeAsString('{broken', flush: true);
    await expectLater(
      _testStore(directory).unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final recoveredFromCommittedBackup = await _testStore(
      directory,
    ).unlock(masterPassword: newPassword);
    recoveredFromCommittedBackup.session.close();
  });

  test('committed floor 后拒绝换密前旧会话覆写槽位', () async {
    const newPassword = 'TEST-ONLY-NEW-MASTER-SESSION-GUARD!';
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-stale-session-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final stale = await store.create(masterPassword: _testMasterPassword);
    final beforeRotation = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[
        AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(platformName: '换密前数据'),
        ),
      ],
    );
    await stale.session.save(beforeRotation);

    final changed = await store.changeMasterPassword(
      currentMasterPassword: _testMasterPassword,
      newMasterPassword: newPassword,
    );
    final staleOverwrite = VaultSnapshot(
      nextAccountId: 3,
      accounts: <AccountRecord>[
        ...beforeRotation.accounts,
        AccountRecord.fromDraft(
          id: 'account-2',
          draft: AccountDraft(platformName: '旧会话不得写入'),
        ),
      ],
    );
    await expectLater(
      stale.session.save(staleOverwrite),
      throwsA(isA<VaultClosedException>()),
    );

    final afterRotation = VaultSnapshot(
      nextAccountId: 3,
      accounts: <AccountRecord>[
        ...beforeRotation.accounts,
        AccountRecord.fromDraft(
          id: 'account-2',
          draft: AccountDraft(platformName: '新会话正常写入'),
        ),
      ],
    );
    await changed.session.save(afterRotation);
    changed.session.close();
    stale.session.close();

    await expectLater(
      _testStore(directory).unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final reopened = await _testStore(
      directory,
    ).unlock(masterPassword: newPassword);
    expect(
      reopened.snapshot.accounts.map((account) => account.platformName),
      containsAll(<String>['换密前数据', '新会话正常写入']),
    );
    expect(
      reopened.snapshot.accounts.map((account) => account.platformName),
      isNot(contains('旧会话不得写入')),
    );
    reopened.session.close();
  });

  test('committed 目标代只接受提交时验证的精确封套', () async {
    const newPassword = 'TEST-ONLY-NEW-MASTER-DIGEST-GUARD!';
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-committed-digest-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final created = await store.create(masterPassword: _testMasterPassword);
    created.session.close();

    final sourceBytes = await _slotFiles(directory).first.readAsBytes();
    final sourceEnvelope = VaultEnvelope.fromBytes(
      sourceBytes,
      supportedKdfProfiles: const <VaultKdfParameters>[_testKdf],
    );
    final crypto = VaultCrypto();
    final sourceMaterial = await crypto.open(
      masterPassword: _testMasterPassword,
      envelope: sourceEnvelope,
    );
    final targetMaterial = await crypto.rotateDataKeyNext(
      previous: sourceEnvelope,
      snapshot: sourceMaterial.snapshot,
      newPassword: newPassword,
      kdf: _testKdf,
    );
    final sameGenerationOldWrapper = await crypto.encryptNext(
      previous: sourceEnvelope,
      dataKey: sourceMaterial.dataKey,
      snapshot: sourceMaterial.snapshot,
    );
    final targetBytes = targetMaterial.envelope.toBytes();
    await _slotFiles(
      directory,
    ).first.writeAsBytes(sameGenerationOldWrapper.toBytes(), flush: true);
    await _slotFiles(directory).last.writeAsBytes(targetBytes, flush: true);
    final targetDigest = await Sha256().hash(targetBytes);
    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}password_change_state_v1.json',
    );
    await stateFile.writeAsString(
      jsonEncode(<String, Object?>{
        'magic': 'ASM_VAULT_PASSWORD_CHANGE',
        'version': 1,
        'revision': 1,
        'phase': 'committed',
        'minimumAcceptedGeneration': targetMaterial.envelope.generation,
        'sourceGeneration': sourceEnvelope.generation,
        'targetGeneration': targetMaterial.envelope.generation,
        'targetSlotIndex': 1,
        'targetEnvelopeDigest': base64UrlEncode(targetDigest.bytes),
      }),
      flush: true,
    );
    sourceMaterial.dataKey.destroy();
    targetMaterial.dataKey.destroy();

    await expectLater(
      _testStore(directory).unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final reopened = await _testStore(
      directory,
    ).unlock(masterPassword: newPassword);
    reopened.session.close();
  });

  test('committed 临时状态已可读时 final rename 异常仍按成功接管', () async {
    const newPassword = 'TEST-ONLY-NEW-MASTER-RENAME-RECOVERY!';
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-commit-rename-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    var simulatedCommittedRenameFailures = 0;
    final store = _testStore(
      directory,
      beforePasswordStateFinalRenameForTesting: (isCommitted) async {
        if (!isCommitted) return;
        simulatedCommittedRenameFailures += 1;
        throw const FileSystemException('simulated final rename failure');
      },
    );
    final stale = await store.create(masterPassword: _testMasterPassword);

    final changed = await store.changeMasterPassword(
      currentMasterPassword: _testMasterPassword,
      newMasterPassword: newPassword,
    );
    expect(simulatedCommittedRenameFailures, greaterThanOrEqualTo(1));
    await expectLater(
      stale.session.save(VaultSnapshot.empty()),
      throwsA(isA<VaultClosedException>()),
    );
    stale.session.close();
    changed.session.close();

    await expectLater(
      _testStore(directory).unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final reopened = await _testStore(
      directory,
    ).unlock(masterPassword: newPassword);
    reopened.session.close();
  });

  test('prepared 阶段中断只允许旧密码，重试后才原子切换', () async {
    const newPassword = 'TEST-ONLY-PREPARED-NEW-5678!';
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-password-prepared-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final store = _testStore(directory);
    final created = await store.create(masterPassword: _testMasterPassword);
    created.session.close();

    final sourceBytes = await _slotFiles(directory).first.readAsBytes();
    final sourceEnvelope = VaultEnvelope.fromBytes(
      sourceBytes,
      supportedKdfProfiles: const <VaultKdfParameters>[_testKdf],
    );
    final opened = await VaultCrypto().open(
      masterPassword: _testMasterPassword,
      envelope: sourceEnvelope,
    );
    final targetMaterial = await VaultCrypto().rotateDataKeyNext(
      previous: sourceEnvelope,
      snapshot: opened.snapshot,
      newPassword: newPassword,
      kdf: _testKdf,
    );
    opened.dataKey.destroy();
    final targetEnvelope = targetMaterial.envelope;
    final targetBytes = targetEnvelope.toBytes();
    targetMaterial.dataKey.destroy();
    await _slotFiles(directory).last.writeAsBytes(targetBytes, flush: true);
    final digest = await Sha256().hash(targetBytes);
    final state = <String, Object?>{
      'magic': 'ASM_VAULT_PASSWORD_CHANGE',
      'version': 1,
      'revision': 2,
      'phase': 'prepared',
      'minimumAcceptedGeneration': 1,
      'sourceGeneration': 1,
      'targetGeneration': 2,
      'targetSlotIndex': 1,
      'targetEnvelopeDigest': base64UrlEncode(digest.bytes),
    };
    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}password_change_state_v1.json',
    );
    await stateFile.writeAsString(jsonEncode(state), flush: true);
    await File('${stateFile.path}.bak').writeAsString(
      jsonEncode(<String, Object?>{...state, 'revision': 1}),
      flush: true,
    );

    final oldStillActive = await _testStore(
      directory,
    ).unlock(masterPassword: _testMasterPassword);
    oldStillActive.session.close();
    await expectLater(
      _testStore(directory).unlock(masterPassword: newPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );

    // 新槽若在 prepared 阶段变成截断文件，重试会删除该目标，而不会损伤旧活动槽。
    await _slotFiles(directory).last.writeAsBytes(<int>[1, 2, 3], flush: true);
    final retried = await _testStore(directory).changeMasterPassword(
      currentMasterPassword: _testMasterPassword,
      newMasterPassword: newPassword,
    );
    retried.session.close();
    await expectLater(
      _testStore(directory).unlock(masterPassword: _testMasterPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final newActive = await _testStore(
      directory,
    ).unlock(masterPassword: newPassword);
    newActive.session.close();
  });

  test('诱饵上下文可使用 6 到 32 位新密码，不放宽默认主库', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-vault-short-decoy-',
    );
    addTearDown(() => _deleteTestDirectory(directory));
    final decoyStore = EncryptedVaultStore(
      directoryProvider: () async => directory,
      creationKdf: _testKdf,
      creationPasswordMinimumLength: 6,
      creationPasswordMaximumLength: 32,
      unlockPasswordMinimumLength: 6,
      unlockPasswordMaximumLength: 128,
    );
    final created = await decoyStore.create(masterPassword: '135790');
    created.session.close();
    final changed = await decoyStore.changeMasterPassword(
      currentMasterPassword: '135790',
      newMasterPassword: '246802',
    );
    changed.session.close();
    await expectLater(
      decoyStore.unlock(masterPassword: '135790'),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final reopened = await decoyStore.unlock(masterPassword: '246802');
    reopened.session.close();

    final primaryDirectory = await Directory.systemTemp.createTemp(
      'asm-vault-primary-short-reject-',
    );
    addTearDown(() => _deleteTestDirectory(primaryDirectory));
    await expectLater(
      _testStore(primaryDirectory).create(masterPassword: '135790'),
      throwsArgumentError,
    );
  });

  test('envelope v2 双因子恢复、普通保存与全新 DEK 轮换保持绑定', () async {
    const recoveryKdf = VaultRecoveryKdfParameters(
      memoryKiB: 64,
      iterations: 1,
      parallelism: 1,
    );
    final crypto = VaultCrypto();
    final snapshot = VaultSnapshot.empty();
    final created = await crypto.create(
      masterPassword: _testMasterPassword,
      snapshot: snapshot,
      kdf: _testKdf,
    );
    final deviceSecret = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    const answers = <String>['杭州', '实验小学', '王老师'];
    final binding = crypto.createRecoveryProvisioning(
      previous: created.envelope,
    );
    final enabled = await crypto.enableRecoveryNext(
      previous: created.envelope,
      dataKey: created.dataKey,
      snapshot: snapshot,
      currentMasterPassword: _testMasterPassword,
      binding: binding,
      questionIds: vaultRecoveryQuestionCatalog
          .take(3)
          .map((question) => question.id)
          .toList(growable: false),
      answers: answers,
      deviceSecret: deviceSecret,
      entryMode: VaultRecoveryEntryMode.logoFiveTap,
      recoveryKdf: recoveryKdf,
    );
    expect(enabled.formatVersion, 2);
    expect(
      crypto.getRecoveryChallenge(enabled)?.entryMode,
      VaultRecoveryEntryMode.logoFiveTap,
    );

    final parsed = VaultEnvelope.fromBytes(
      enabled.toBytes(),
      supportedKdfProfiles: const <VaultKdfParameters>[_testKdf],
      supportedRecoveryKdfProfiles: const <VaultRecoveryKdfParameters>[
        recoveryKdf,
      ],
    );
    final recovered = await crypto.openWithRecovery(
      envelope: parsed,
      answers: answers,
      deviceSecret: deviceSecret,
    );
    expect(recovered.snapshot.accounts, isEmpty);
    recovered.dataKey.destroy();
    await expectLater(
      crypto.openWithRecovery(
        envelope: parsed,
        answers: const <String>['错误', '实验小学', '王老师'],
        deviceSecret: deviceSecret,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );

    final tamperedPayloadMac = Uint8List.fromList(parsed.payload.mac.bytes);
    tamperedPayloadMac[0] ^= 0x01;
    final payloadTampered = VaultEnvelope(
      formatVersion: parsed.formatVersion,
      vaultInstanceId: parsed.vaultInstanceId,
      generation: parsed.generation,
      kdf: parsed.kdf,
      salt: parsed.salt,
      wrappedDataKey: parsed.wrappedDataKey,
      payload: SecretBox(
        parsed.payload.cipherText,
        nonce: parsed.payload.nonce,
        mac: Mac(tamperedPayloadMac),
      ),
      recoverySlot: parsed.recoverySlot,
    );
    await expectLater(
      crypto.openWithRecovery(
        envelope: payloadTampered,
        answers: answers,
        deviceSecret: deviceSecret,
      ),
      throwsA(isA<VaultIntegrityException>()),
    );

    final saved = await crypto.encryptNext(
      previous: parsed,
      dataKey: created.dataKey,
      snapshot: snapshot,
    );
    expect(saved.recoverySlot, isNotNull);
    await expectLater(
      crypto.rotateDataKeyNext(
        previous: saved,
        snapshot: snapshot,
        newPassword: 'NEW-TEST-MASTER-5678!',
        kdf: _testKdf,
      ),
      throwsA(isA<VaultRecoveryRefreshRequiredException>()),
    );

    final credentials = VaultRecoveryCredentials(
      answers: answers,
      deviceSecret: deviceSecret,
    );
    final rotated = await crypto.rotateDataKeyNext(
      previous: saved,
      snapshot: snapshot,
      newPassword: 'NEW-TEST-MASTER-5678!',
      kdf: _testKdf,
      recoveryCredentials: credentials,
    );
    credentials.destroy();
    final newPasswordOpened = await crypto.open(
      masterPassword: 'NEW-TEST-MASTER-5678!',
      envelope: rotated.envelope,
    );
    newPasswordOpened.dataKey.destroy();
    final recoveredAfterRotation = await crypto.openWithRecovery(
      envelope: rotated.envelope,
      answers: answers,
      deviceSecret: deviceSecret,
    );
    recoveredAfterRotation.dataKey.destroy();
    expect(rotated.dataKey.bytes, isNot(orderedEquals(created.dataKey.bytes)));
    created.dataKey.destroy();
    rotated.dataKey.destroy();
    deviceSecret.fillRange(0, deviceSecret.length, 0);
  });
}

VaultEnvelope _syntheticEnvelope(VaultKdfParameters kdf) => VaultEnvelope(
  generation: 1,
  kdf: kdf,
  salt: Uint8List(16),
  wrappedDataKey: SecretBox(
    Uint8List(32),
    nonce: Uint8List(12),
    mac: Mac(Uint8List(16)),
  ),
  payload: SecretBox(
    Uint8List(1),
    nonce: Uint8List(12),
    mac: Mac(Uint8List(16)),
  ),
);

EncryptedVaultStore _testStore(
  Directory directory, {
  QuickUnlockSecretStore? quickUnlockSecretStore,
  Future<void> Function(bool isCommitted)?
  beforePasswordStateFinalRenameForTesting,
}) => EncryptedVaultStore(
  directoryProvider: () async => directory,
  creationKdf: _testKdf,
  quickUnlockSecretStore: quickUnlockSecretStore,
  beforePasswordStateFinalRenameForTesting:
      beforePasswordStateFinalRenameForTesting,
);

List<File> _slotFiles(Directory directory) => <File>[
  File('${directory.path}${Platform.pathSeparator}vault_a.json'),
  File('${directory.path}${Platform.pathSeparator}vault_b.json'),
];

Future<void> _tamperPayload(File file) async {
  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final payload = decoded['payload'] as Map<String, dynamic>;
  final concatenated = base64Decode(payload['box'] as String);
  concatenated[concatenated.length - 1] ^= 0x01;
  payload['box'] = base64Encode(concatenated);
  await file.writeAsString(jsonEncode(decoded), flush: true);
}

Future<void> _deleteTestDirectory(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

Uint8List _hex(String value) {
  final result = Uint8List(value.length ~/ 2);
  for (var index = 0; index < result.length; index++) {
    result[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}

final class _MemoryQuickUnlockSecretStore implements QuickUnlockSecretStore {
  QuickUnlockSecret? _secret;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;

  @override
  Future<bool> containsSecret() async => _secret != null;

  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    _secret?.destroy();
    _secret = QuickUnlockSecret(
      vaultId: secret.vaultId,
      dataKey: secret.dataKey,
    );
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async {
    final secret = _secret;
    return secret == null
        ? null
        : QuickUnlockSecret(vaultId: secret.vaultId, dataKey: secret.dataKey);
  }

  @override
  Future<void> deleteSecret() async {
    _secret?.destroy();
    _secret = null;
  }

  void dispose() {
    _secret?.destroy();
    _secret = null;
  }
}
