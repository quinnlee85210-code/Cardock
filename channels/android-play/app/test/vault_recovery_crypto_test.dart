import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

const _testKdf = VaultRecoveryKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _questionIds = <String>[
  'childhood_city',
  'first_school',
  'favorite_book',
];
const _answers = <String>['杭州', '实验小学', 'The Little Prince'];

void main() {
  test('内置题库 ID 唯一且 label 可由公共 API 查询', () {
    expect(vaultRecoveryQuestionCatalog, hasLength(8));
    expect(
      vaultRecoveryQuestionCatalog.map((question) => question.id).toSet(),
      hasLength(vaultRecoveryQuestionCatalog.length),
    );
    for (final question in vaultRecoveryQuestionCatalog) {
      expect(vaultRecoveryQuestionLabel(question.id), question.label);
      expect(question.label, isNotEmpty);
    }
    expect(
      () => vaultRecoveryQuestionLabel('not_in_catalog'),
      throwsArgumentError,
    );
  });

  test('答案执行 NFKC、首尾去空白、连续空白折叠及大小写归一', () {
    expect(
      normalizeVaultRecoveryAnswer('  Ｔｈｅ\u3000  Little\tPRINCE  '),
      'the little prince',
    );
  });

  test('三答案与 32 字节设备因子共同包装和解包 DEK', () async {
    final crypto = VaultRecoveryCrypto();
    final dataKey = SecretKeyData(
      Uint8List.fromList(List<int>.generate(32, (index) => index)),
      overwriteWhenDestroyed: true,
    );
    final deviceSecret = Uint8List.fromList(
      List<int>.generate(32, (index) => 0xa0 + index),
    );
    addTearDown(() {
      dataKey.destroy();
      deviceSecret.fillRange(0, deviceSecret.length, 0);
    });
    final binding = _binding();
    final slot = await crypto.createSlot(
      binding: binding,
      dataKey: dataKey,
      questionIds: _questionIds,
      answers: _answers,
      deviceSecret: deviceSecret,
      entryMode: VaultRecoveryEntryMode.logoFiveTap,
      kdf: _testKdf,
    );

    final reopened = await crypto.unwrapDataKey(
      slot: slot,
      answers: const <String>[' 杭州 ', '实验小学', 'ｔｈｅ  LITTLE prince'],
      deviceSecret: deviceSecret,
    );
    addTearDown(reopened.destroy);
    expect(reopened.bytes, orderedEquals(dataKey.bytes));
    expect(slot.challenge.binding.hasSameValuesAs(binding), isTrue);
    expect(slot.challenge.questionIds, orderedEquals(_questionIds));
    expect(slot.challenge.entryMode, VaultRecoveryEntryMode.logoFiveTap);

    final serialized = jsonEncode(slot.toJson());
    expect(serialized, isNot(contains(_answers.first)));
    expect(serialized, isNot(contains(base64Encode(deviceSecret))));
    final reparsed = VaultRecoverySlot.fromJson(
      jsonDecode(serialized),
      supportedKdfProfiles: const <VaultRecoveryKdfParameters>[_testKdf],
    );
    final reopenedAfterParse = await crypto.unwrapDataKey(
      slot: reparsed,
      answers: _answers,
      deviceSecret: deviceSecret,
    );
    addTearDown(reopenedAfterParse.destroy);
    expect(reopenedAfterParse.bytes, orderedEquals(dataKey.bytes));
  });

  test('错误答案、错误设备因子及错误长度统一拒绝恢复', () async {
    final crypto = VaultRecoveryCrypto();
    final dataKey = SecretKeyData.random(length: 32);
    final deviceSecret = Uint8List(32)..fillRange(0, 32, 7);
    addTearDown(() {
      dataKey.destroy();
      deviceSecret.fillRange(0, deviceSecret.length, 0);
    });
    final slot = await crypto.createSlot(
      binding: _binding(),
      dataKey: dataKey,
      questionIds: _questionIds,
      answers: _answers,
      deviceSecret: deviceSecret,
      entryMode: VaultRecoveryEntryMode.visible,
      kdf: _testKdf,
    );

    await expectLater(
      crypto.unwrapDataKey(
        slot: slot,
        answers: const <String>['错误城市', '实验小学', 'The Little Prince'],
        deviceSecret: deviceSecret,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );
    final wrongDeviceSecret = Uint8List.fromList(deviceSecret)..[0] ^= 0xff;
    await expectLater(
      crypto.unwrapDataKey(
        slot: slot,
        answers: _answers,
        deviceSecret: wrongDeviceSecret,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );
    await expectLater(
      crypto.unwrapDataKey(
        slot: slot,
        answers: _answers,
        deviceSecret: Uint8List(31),
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );
    wrongDeviceSecret.fillRange(0, wrongDeviceSecret.length, 0);
  });

  test('伪恢复验证执行完整 KDF 与 AEAD 路径且不改写设备因子', () async {
    final crypto = VaultRecoveryCrypto();
    final deviceSecret = Uint8List(32)..fillRange(0, 32, 19);
    final original = Uint8List.fromList(deviceSecret);
    addTearDown(() {
      deviceSecret.fillRange(0, deviceSecret.length, 0);
      original.fillRange(0, original.length, 0);
    });

    await crypto.performDummyVerification(
      questionIds: _questionIds,
      answers: _answers,
      deviceSecret: deviceSecret,
      kdf: _testKdf,
    );

    expect(deviceSecret, orderedEquals(original));
  });

  test('长度前缀阻止答案边界拼接歧义', () async {
    final crypto = VaultRecoveryCrypto();
    final dataKey = SecretKeyData.random(length: 32);
    final deviceSecret = Uint8List(32)..fillRange(0, 32, 11);
    addTearDown(() {
      dataKey.destroy();
      deviceSecret.fillRange(0, deviceSecret.length, 0);
    });
    final slot = await crypto.createSlot(
      binding: _binding(),
      dataKey: dataKey,
      questionIds: _questionIds,
      answers: const <String>['ab', 'c', 'de'],
      deviceSecret: deviceSecret,
      entryMode: VaultRecoveryEntryMode.visible,
      kdf: _testKdf,
    );

    await expectLater(
      crypto.unwrapDataKey(
        slot: slot,
        answers: const <String>['a', 'bc', 'de'],
        deviceSecret: deviceSecret,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );
  });

  test('未知题库 ID 在配置时拒绝，在持久化解析时视为格式损坏', () async {
    final crypto = VaultRecoveryCrypto();
    final dataKey = SecretKeyData.random(length: 32);
    final deviceSecret = Uint8List(32);
    addTearDown(() {
      dataKey.destroy();
      deviceSecret.fillRange(0, deviceSecret.length, 0);
    });

    await expectLater(
      crypto.createSlot(
        binding: _binding(),
        dataKey: dataKey,
        questionIds: const <String>[
          'childhood_city',
          'first_school',
          'unknown_question',
        ],
        answers: _answers,
        deviceSecret: deviceSecret,
        entryMode: VaultRecoveryEntryMode.visible,
        kdf: _testKdf,
      ),
      throwsArgumentError,
    );

    final valid = await crypto.createSlot(
      binding: _binding(),
      dataKey: dataKey,
      questionIds: _questionIds,
      answers: _answers,
      deviceSecret: deviceSecret,
      entryMode: VaultRecoveryEntryMode.visible,
      kdf: _testKdf,
    );
    final tampered = Map<String, Object?>.from(valid.toJson());
    tampered['questionIds'] = const <String>[
      'childhood_city',
      'first_school',
      'unknown_question',
    ];
    expect(
      () => VaultRecoverySlot.fromJson(
        tampered,
        supportedKdfProfiles: const <VaultRecoveryKdfParameters>[_testKdf],
      ),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('重包新 DEK 前必须先用原答案和设备因子认证旧槽', () async {
    final crypto = VaultRecoveryCrypto();
    final oldDataKey = SecretKeyData.random(length: 32);
    final newDataKey = SecretKeyData.random(length: 32);
    final deviceSecret = Uint8List(32)..fillRange(0, 32, 19);
    addTearDown(() {
      oldDataKey.destroy();
      newDataKey.destroy();
      deviceSecret.fillRange(0, deviceSecret.length, 0);
    });
    final slot = await crypto.createSlot(
      binding: _binding(),
      dataKey: oldDataKey,
      questionIds: _questionIds,
      answers: _answers,
      deviceSecret: deviceSecret,
      entryMode: VaultRecoveryEntryMode.visible,
      kdf: _testKdf,
    );
    await expectLater(
      crypto.rewrapDataKey(
        previous: slot,
        newDataKey: newDataKey,
        answers: const <String>['错误城市', '实验小学', 'The Little Prince'],
        deviceSecret: deviceSecret,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );

    final rewrapped = await crypto.rewrapDataKey(
      previous: slot,
      newDataKey: newDataKey,
      answers: _answers,
      deviceSecret: deviceSecret,
    );
    expect(rewrapped.binding.hasSameValuesAs(slot.binding), isTrue);
    expect(rewrapped.salt, isNot(orderedEquals(slot.salt)));
    final reopened = await crypto.unwrapDataKey(
      slot: rewrapped,
      answers: _answers,
      deviceSecret: deviceSecret,
    );
    addTearDown(reopened.destroy);
    expect(reopened.bytes, orderedEquals(newDataKey.bytes));
  });
}

VaultRecoveryBinding _binding() => VaultRecoveryBinding(
  vaultInstanceId: List<int>.generate(16, (index) => index + 1),
  slotId: List<int>.generate(16, (index) => index + 33),
  deviceBindingId: List<int>.generate(16, (index) => index + 65),
);
