import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/security/unlock_throttle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MethodChannel 时钟按冻结协议解析并安全拒绝畸形返回', () async {
    const channel = MethodChannel(MethodChannelUnlockThrottleClock.channelName);
    final calls = <MethodCall>[];
    Object? response = <String, Object?>{
      'bootCount': 17,
      'elapsedRealtimeMilliseconds': 987654321,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return response;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const clock = MethodChannelUnlockThrottleClock(channel);

    final reading = await clock.read();
    expect(reading.bootCount, 17);
    expect(reading.elapsedRealtimeMilliseconds, 987654321);
    expect(calls.single.method, MethodChannelUnlockThrottleClock.readMethod);
    expect(calls.single.arguments, isNull);

    final malformedPayloads = <Object?>[
      null,
      <String, Object?>{},
      <String, Object?>{
        'bootCount': '17',
        'elapsedRealtimeMilliseconds': 987654321,
      },
      <String, Object?>{
        'bootCount': -1,
        'elapsedRealtimeMilliseconds': 987654321,
      },
      <String, Object?>{'bootCount': 17, 'elapsedRealtimeMilliseconds': -1},
      <String, Object?>{
        'bootCount': 17,
        'elapsedRealtimeMilliseconds': '987654321',
      },
    ];
    for (final malformed in malformedPayloads) {
      response = malformed;
      await expectLater(
        clock.read(),
        throwsA(isA<UnlockThrottleClockException>()),
        reason: 'must reject $malformed',
      );
    }
    expect(
      calls.map((call) => call.method),
      everyElement(MethodChannelUnlockThrottleClock.readMethod),
    );
  });

  test('冷却策略严格按5、7、9、10次递进且最高30分钟', () {
    expect(UnlockThrottlePolicy.cooldownFor(0), Duration.zero);
    expect(UnlockThrottlePolicy.cooldownFor(4), Duration.zero);
    expect(UnlockThrottlePolicy.cooldownFor(5), const Duration(seconds: 30));
    expect(UnlockThrottlePolicy.cooldownFor(6), const Duration(seconds: 30));
    expect(UnlockThrottlePolicy.cooldownFor(7), const Duration(minutes: 2));
    expect(UnlockThrottlePolicy.cooldownFor(8), const Duration(minutes: 2));
    expect(UnlockThrottlePolicy.cooldownFor(9), const Duration(minutes: 10));
    expect(UnlockThrottlePolicy.cooldownFor(10), const Duration(minutes: 30));
    expect(UnlockThrottlePolicy.cooldownFor(100), const Duration(minutes: 30));
  });

  test('中间冷却到期保留次数，10次层完整到期才清零', () async {
    final clock = MemoryUnlockThrottleClock();
    final store = MemoryUnlockThrottleStore();
    final controller = UnlockThrottleController(store, clock);
    expect(await controller.initialize(), const UnlockThrottleSnapshot.clear());

    for (var attempt = 1; attempt <= 4; attempt += 1) {
      final snapshot = await controller.recordCredentialFailure();
      expect(snapshot.failedAttempts, attempt);
      expect(snapshot.cooldownRemaining, Duration.zero);
    }

    await _expectFailureAndExpire(
      controller: controller,
      clock: clock,
      expectedAttempts: 5,
      expectedCooldown: const Duration(seconds: 30),
    );
    await _expectFailureAndExpire(
      controller: controller,
      clock: clock,
      expectedAttempts: 6,
      expectedCooldown: const Duration(seconds: 30),
    );
    await _expectFailureAndExpire(
      controller: controller,
      clock: clock,
      expectedAttempts: 7,
      expectedCooldown: const Duration(minutes: 2),
    );
    await _expectFailureAndExpire(
      controller: controller,
      clock: clock,
      expectedAttempts: 8,
      expectedCooldown: const Duration(minutes: 2),
    );
    await _expectFailureAndExpire(
      controller: controller,
      clock: clock,
      expectedAttempts: 9,
      expectedCooldown: const Duration(minutes: 10),
    );

    final maximum = await controller.recordCredentialFailure();
    expect(maximum.failedAttempts, 10);
    expect(maximum.cooldownRemaining, const Duration(minutes: 30));
    clock.advance(const Duration(minutes: 29, seconds: 59));
    expect((await controller.refresh()).failedAttempts, 10);
    clock.advance(const Duration(seconds: 1));
    expect(await controller.refresh(), const UnlockThrottleSnapshot.clear());
  });

  test('控制器重建保留冷却，同次开机按单调时钟，重启后重置当前阶段', () async {
    final clock = MemoryUnlockThrottleClock(
      bootCount: 12,
      elapsedRealtimeMilliseconds: 5000,
    );
    final store = MemoryUnlockThrottleStore();
    var controller = UnlockThrottleController(store, clock);
    await controller.initialize();
    for (var attempt = 0; attempt < 5; attempt += 1) {
      await controller.recordCredentialFailure();
    }
    clock.advance(const Duration(seconds: 10));

    controller = UnlockThrottleController(store, clock);
    var restored = await controller.initialize();
    expect(restored.failedAttempts, 5);
    expect(restored.cooldownRemaining, const Duration(seconds: 20));

    clock.elapsedRealtimeMilliseconds = 0;
    controller = UnlockThrottleController(store, clock);
    restored = await controller.initialize();
    expect(restored.failedAttempts, 5);
    expect(
      restored.cooldownRemaining,
      const Duration(seconds: 30),
      reason: '同一boot内单调时钟异常回拨时只能重置一个有界阶段',
    );

    clock.reboot(nextBootCount: 13);
    controller = UnlockThrottleController(store, clock);
    restored = await controller.initialize();
    expect(restored.failedAttempts, 5);
    expect(restored.cooldownRemaining, const Duration(seconds: 30));
  });

  test('真实主密码认证清零写入更高修订的tombstone', () async {
    final clock = MemoryUnlockThrottleClock();
    final store = MemoryUnlockThrottleStore();
    var controller = UnlockThrottleController(store, clock);
    await controller.initialize();
    await controller.recordCredentialFailure();
    await controller.recordCredentialFailure();
    final activeRevision = store.value!.revision;

    expect(
      await controller.clearAfterPrimaryAuthentication(),
      const UnlockThrottleSnapshot.clear(),
    );
    expect(store.value!.state, UnlockThrottleRecordState.cleared);
    expect(store.value!.revision, activeRevision + 1);

    controller = UnlockThrottleController(store, clock);
    expect(await controller.initialize(), const UnlockThrottleSnapshot.clear());
  });

  test('文件存储校验版本并从上一份有效代恢复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm_unlock_throttle_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    final store = FileUnlockThrottleStore(() async => file);
    const first = UnlockThrottleRecord(
      revision: 1,
      state: UnlockThrottleRecordState.active,
      failedAttempts: 4,
      bootCount: 3,
      cooldownDurationMilliseconds: 0,
      elapsedDeadlineMilliseconds: 0,
    );
    const second = UnlockThrottleRecord(
      revision: 2,
      state: UnlockThrottleRecordState.active,
      failedAttempts: 5,
      bootCount: 3,
      cooldownDurationMilliseconds: 30000,
      elapsedDeadlineMilliseconds: 45000,
    );
    await store.write(first);
    await store.write(second);
    expect((await store.read())!.revision, 2);

    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(decoded['magic'], 'ASM_UNLOCK_THROTTLE');
    expect(decoded['version'], 1);

    await file.writeAsString('{broken', flush: true);
    final recovered = await store.read();
    expect(recovered!.revision, 1);
    expect(recovered.failedAttempts, 4);
  });

  test('只有未知版本且无有效兄弟代时安全拒绝', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm_unlock_throttle_future_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    await file.writeAsString(
      jsonEncode(<String, Object>{
        'magic': 'ASM_UNLOCK_THROTTLE',
        'version': 2,
      }),
      flush: true,
    );
    final store = FileUnlockThrottleStore(() async => file);
    await expectLater(
      store.read(),
      throwsA(isA<UnlockThrottleStorageException>()),
    );
  });
}

Future<void> _expectFailureAndExpire({
  required UnlockThrottleController controller,
  required MemoryUnlockThrottleClock clock,
  required int expectedAttempts,
  required Duration expectedCooldown,
}) async {
  final blocked = await controller.recordCredentialFailure();
  expect(blocked.failedAttempts, expectedAttempts);
  expect(blocked.cooldownRemaining, expectedCooldown);
  clock.advance(expectedCooldown);
  final expired = await controller.refresh();
  expect(expired.failedAttempts, expectedAttempts);
  expect(expired.cooldownRemaining, Duration.zero);
}
