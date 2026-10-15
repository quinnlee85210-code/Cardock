import 'dart:convert';

import 'package:account_subscription_manager/core/temporary_web/temporary_web_crypto.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('可信局域网一次性连接码', () {
    test('Random.secure 生成 8 位全大写英文字母且不包含数字', () {
      final seen = <String>{};
      for (var i = 0; i < 64; i++) {
        final code = TrustedLanConnectionCode.generate();
        addTearDown(code.destroy);
        expect(code.formatted, matches(RegExp(r'^[A-Z]{8}$')));
        expect(code.compact, hasLength(trustedLanConnectionCodeSymbols));
        expect(
          code.extractBytes(),
          hasLength(trustedLanConnectionCodeEntropyBytes),
        );
        expect(seen.add(code.compact), isTrue);
        expect(code.compact, isNot(matches(RegExp(r'[0-9]'))));
        expect(code.toString(), isNot(contains(code.compact)));
      }
    });

    test('8 位字母连接码可无损解析且严格拒绝数字与符号', () {
      final generated = TrustedLanConnectionCode.generate();
      final parsed = TrustedLanConnectionCode.parse(
        generated.formatted.toLowerCase(),
      );
      addTearDown(generated.destroy);
      addTearDown(parsed.destroy);

      expect(parsed.extractBytes(), orderedEquals(generated.extractBytes()));
      for (final invalid in <String>[
        'ABCDEFG0',
        'ABCDEF1G',
        'ABCDEF_G',
        'ABCDEFG',
      ]) {
        expect(
          () => TrustedLanConnectionCode.parse(invalid),
          throwsFormatException,
        );
      }
    });

    test('销毁后不再暴露连接码字节或文本', () {
      final code = TrustedLanConnectionCode.generate();
      code.destroy();
      expect(() => code.extractBytes(), throwsStateError);
      expect(() => code.formatted, throwsStateError);
    });
  });

  group('可信局域网 X25519 + HKDF + 双向确认', () {
    test('正确连接码完成双向确认并建立可互通的独立方向通道', () async {
      final channels = await _pairChannels(roundTripJson: true);
      addTearDown(channels.destroy);

      final browserFrame = await channels.browser.encrypt(
        utf8.encode('browser to phone'),
      );
      final phoneClearText = await channels.phone.decrypt(
        TrustedLanEncryptedFrame.fromJson(browserFrame.toJson()),
      );
      expect(utf8.decode(phoneClearText), 'browser to phone');

      final phoneFrame = await channels.phone.encrypt(
        utf8.encode('phone to browser'),
      );
      final browserClearText = await channels.browser.decrypt(
        TrustedLanEncryptedFrame.fromJson(phoneFrame.toJson()),
      );
      expect(utf8.decode(browserClearText), 'phone to browser');
      expect(browserFrame.direction, isNot(phoneFrame.direction));
    });

    test('错误但格式有效的 8 位字母连接码无法通过浏览器确认', () async {
      final phone = await TrustedLanPhonePairing.start();
      final correctCode = phone.formattedConnectionCode;
      final browser = await TrustedLanBrowserPairing.start(
        phoneHello: phone.hello,
        connectionCode: _differentValidCode(correctCode),
      );
      addTearDown(browser.cancel);

      await expectLater(
        phone.finish(browser.hello),
        throwsA(
          _pairingFailure(TrustedLanPairingFailure.keyConfirmationFailed),
        ),
      );
      await expectLater(
        phone.finish(browser.hello),
        throwsA(_pairingFailure(TrustedLanPairingFailure.alreadyUsed)),
      );
    });

    test('篡改手机确认时浏览器拒绝建立通道', () async {
      final phone = await TrustedLanPhonePairing.start();
      final browser = await TrustedLanBrowserPairing.start(
        phoneHello: phone.hello,
        connectionCode: phone.formattedConnectionCode,
      );
      final phoneResult = await phone.finish(browser.hello);
      addTearDown(phoneResult.channel.destroy);
      final changed = phoneResult.confirmation.confirmation;
      changed[0] ^= 1;

      await expectLater(
        browser.finish(
          TrustedLanPhoneConfirmation(
            protocolVersion: phoneResult.confirmation.protocolVersion,
            sessionId: phoneResult.confirmation.sessionId,
            confirmation: changed,
          ),
        ),
        throwsA(
          _pairingFailure(TrustedLanPairingFailure.keyConfirmationFailed),
        ),
      );
    });

    test('X25519 低阶全零公钥产生全零共享秘密时安全拒绝', () async {
      final phone = await TrustedLanPhonePairing.start();
      final forged = TrustedLanBrowserHello(
        protocolVersion: trustedLanProtocolVersion,
        sessionId: phone.hello.sessionId,
        browserPublicKey: List<int>.filled(trustedLanPairingPublicKeyLength, 0),
        browserConfirmation: List<int>.filled(
          trustedLanKeyConfirmationLength,
          0,
        ),
      );

      await expectLater(
        phone.finish(forged),
        throwsA(_pairingFailure(TrustedLanPairingFailure.keyAgreementFailed)),
      );
    });

    test('握手消息 JSON 往返保持固定长度二进制字段', () async {
      final phone = await TrustedLanPhonePairing.start();
      addTearDown(phone.cancel);
      final phoneHello = TrustedLanPhoneHello.fromJson(phone.hello.toJson());
      expect(phoneHello.sessionId, hasLength(trustedLanSessionIdLength));
      expect(
        phoneHello.phonePublicKey,
        hasLength(trustedLanPairingPublicKeyLength),
      );
      expect(
        phoneHello.phoneToBrowserNoncePrefix,
        hasLength(trustedLanNoncePrefixLength),
      );
      expect(
        phoneHello.browserToPhoneNoncePrefix,
        hasLength(trustedLanNoncePrefixLength),
      );
    });
  });

  group('可信局域网 AES-256-GCM 记录层', () {
    test('密文篡改被拒绝且不推进接收计数器', () async {
      final channels = await _pairChannels();
      addTearDown(channels.destroy);
      final frame = await channels.browser.encrypt(utf8.encode('sensitive'));
      final changedCipherText = frame.cipherText;
      changedCipherText[0] ^= 1;

      await expectLater(
        channels.phone.decrypt(frame.copyWith(cipherText: changedCipherText)),
        throwsA(_recordFailure(TrustedLanRecordFailure.authenticationFailed)),
      );
      expect(
        await channels.phone.decrypt(frame),
        orderedEquals(utf8.encode('sensitive')),
      );
    });

    test('认证标签篡改被拒绝', () async {
      final channels = await _pairChannels();
      addTearDown(channels.destroy);
      final frame = await channels.browser.encrypt(utf8.encode('sensitive'));
      final changedTag = frame.authenticationTag;
      changedTag[changedTag.length - 1] ^= 1;

      await expectLater(
        channels.phone.decrypt(frame.copyWith(authenticationTag: changedTag)),
        throwsA(_recordFailure(TrustedLanRecordFailure.authenticationFailed)),
      );
    });

    test('同一帧重放被严格递增计数器拒绝', () async {
      final channels = await _pairChannels();
      addTearDown(channels.destroy);
      final frame = await channels.browser.encrypt(const <int>[1, 2, 3]);

      expect(
        await channels.phone.decrypt(frame),
        orderedEquals(<int>[1, 2, 3]),
      );
      await expectLater(
        channels.phone.decrypt(frame),
        throwsA(_recordFailure(TrustedLanRecordFailure.counterOutOfOrder)),
      );
    });

    test('乱序帧被拒绝且随后仍可按顺序接收', () async {
      final channels = await _pairChannels();
      addTearDown(channels.destroy);
      final first = await channels.browser.encrypt(const <int>[0]);
      final second = await channels.browser.encrypt(const <int>[1]);

      await expectLater(
        channels.phone.decrypt(second),
        throwsA(_recordFailure(TrustedLanRecordFailure.counterOutOfOrder)),
      );
      expect(await channels.phone.decrypt(first), orderedEquals(<int>[0]));
      expect(await channels.phone.decrypt(second), orderedEquals(<int>[1]));
    });

    test('跨方向使用密文被拒绝', () async {
      final channels = await _pairChannels();
      addTearDown(channels.destroy);
      final phoneOutgoing = await channels.phone.encrypt(const <int>[9]);

      await expectLater(
        channels.phone.decrypt(phoneOutgoing),
        throwsA(_recordFailure(TrustedLanRecordFailure.directionMismatch)),
      );
    });

    test('跨会话使用密文在认证前被会话绑定拒绝', () async {
      final firstSession = await _pairChannels();
      final secondSession = await _pairChannels();
      addTearDown(firstSession.destroy);
      addTearDown(secondSession.destroy);
      final firstFrame = await firstSession.browser.encrypt(const <int>[7]);

      await expectLater(
        secondSession.phone.decrypt(firstFrame),
        throwsA(_recordFailure(TrustedLanRecordFailure.sessionMismatch)),
      );
      expect(
        await firstSession.phone.decrypt(firstFrame),
        orderedEquals(<int>[7]),
      );
    });

    test('协议版本、nonce 与 AAD 绑定字段不能被替换', () async {
      final channels = await _pairChannels();
      addTearDown(channels.destroy);
      final frame = await channels.browser.encrypt(const <int>[4, 5]);
      final changedNonce = frame.nonce;
      changedNonce[0] ^= 1;

      await expectLater(
        channels.phone.decrypt(frame.copyWith(protocolVersion: 'future-v2')),
        throwsA(_recordFailure(TrustedLanRecordFailure.protocolMismatch)),
      );
      await expectLater(
        channels.phone.decrypt(frame.copyWith(nonce: changedNonce)),
        throwsA(_recordFailure(TrustedLanRecordFailure.invalidNonce)),
      );
      expect(await channels.phone.decrypt(frame), orderedEquals(<int>[4, 5]));
    });

    test('4 字节随机前缀加 64 位计数器使同方向 nonce 唯一', () async {
      final channels = await _pairChannels();
      addTearDown(channels.destroy);
      final nonces = <String>{};
      List<int>? prefix;
      for (var i = 0; i < 128; i++) {
        final frame = await channels.browser.encrypt(<int>[i]);
        final nonce = frame.nonce;
        expect(nonce, hasLength(trustedLanNonceLength));
        prefix ??= nonce.sublist(0, trustedLanNoncePrefixLength);
        expect(
          nonce.sublist(0, trustedLanNoncePrefixLength),
          orderedEquals(prefix),
        );
        expect(nonces.add(base64Url.encode(nonce)), isTrue);
        expect(frame.counter.high, 0);
        expect(frame.counter.low, i);
      }
    });

    test('64 位计数器跨低位边界且绝不回绕', () {
      final beforeLowRollover = TrustedLanCounter64(
        high: 0x12345678,
        low: 0xffffffff,
      );
      final afterLowRollover = beforeLowRollover.incremented();
      expect(afterLowRollover.high, 0x12345679);
      expect(afterLowRollover.low, 0);
      expect(
        TrustedLanCounter64.fromBytes(afterLowRollover.toBytes()),
        afterLowRollover,
      );
      expect(
        TrustedLanCounter64.maximum.incremented,
        throwsA(_recordFailure(TrustedLanRecordFailure.counterOverflow)),
      );
    });

    test('销毁后双向操作均 fail closed', () async {
      final channels = await _pairChannels();
      await channels.phone.destroy();

      await expectLater(
        channels.phone.encrypt(const <int>[1]),
        throwsA(_recordFailure(TrustedLanRecordFailure.closed)),
      );
      final browserFrame = await channels.browser.encrypt(const <int>[1]);
      await expectLater(
        channels.phone.decrypt(browserFrame),
        throwsA(_recordFailure(TrustedLanRecordFailure.closed)),
      );
      await channels.browser.destroy();
    });
  });
}

final class _PairedChannels {
  const _PairedChannels({required this.phone, required this.browser});

  final TrustedLanSecureChannel phone;
  final TrustedLanSecureChannel browser;

  Future<void> destroy() async {
    await Future.wait(<Future<void>>[phone.destroy(), browser.destroy()]);
  }
}

Future<_PairedChannels> _pairChannels({bool roundTripJson = false}) async {
  final phonePairing = await TrustedLanPhonePairing.start();
  final code = phonePairing.formattedConnectionCode;
  final phoneHello = roundTripJson
      ? TrustedLanPhoneHello.fromJson(phonePairing.hello.toJson())
      : phonePairing.hello;
  final browserPairing = await TrustedLanBrowserPairing.start(
    phoneHello: phoneHello,
    connectionCode: code,
  );
  final browserHello = roundTripJson
      ? TrustedLanBrowserHello.fromJson(browserPairing.hello.toJson())
      : browserPairing.hello;
  final phoneResult = await phonePairing.finish(browserHello);
  final phoneConfirmation = roundTripJson
      ? TrustedLanPhoneConfirmation.fromJson(phoneResult.confirmation.toJson())
      : phoneResult.confirmation;
  final browserChannel = await browserPairing.finish(phoneConfirmation);
  return _PairedChannels(phone: phoneResult.channel, browser: browserChannel);
}

String _differentValidCode(String code) {
  final first = code[0];
  return (first == 'A' ? 'B' : 'A') + code.substring(1);
}

Matcher _pairingFailure(TrustedLanPairingFailure failure) {
  return isA<TrustedLanPairingException>().having(
    (error) => error.failure,
    'failure',
    failure,
  );
}

Matcher _recordFailure(TrustedLanRecordFailure failure) {
  return isA<TrustedLanRecordException>().having(
    (error) => error.failure,
    'failure',
    failure,
  );
}
