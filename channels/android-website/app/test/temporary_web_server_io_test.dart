import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/temporary_web/temporary_web_controller.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_crypto.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_pairing.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_server_io.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IoTemporaryWebTransport loopback integration', () {
    late IoTemporaryWebTransport transport;
    late TemporaryWebTransportBinding binding;
    late HttpClient client;
    late List<Object> fatalErrors;
    late List<String> pairedAddresses;
    late List<Map<String, Object?>> receivedCommands;
    late List<String> commandRemoteAddresses;
    TrustedLanSecureChannel? browserChannel;

    Future<void> startTransport({
      Duration requestReadTimeout = const Duration(seconds: 10),
      int maximumConcurrentHandlers = 8,
      int maximumBufferedRequestBytes = 1024 * 1024,
    }) async {
      transport = IoTemporaryWebTransport(
        assetLoader: _minimalAssetLoader,
        requestReadTimeout: requestReadTimeout,
        maximumConcurrentHandlers: maximumConcurrentHandlers,
        maximumBufferedRequestBytes: maximumBufferedRequestBytes,
      );
      binding = await transport.start(
        address: InternetAddress.loopbackIPv4.address,
        onCommand: (command, remoteAddress) async {
          receivedCommands.add(Map<String, Object?>.from(command));
          commandRemoteAddresses.add(remoteAddress);
          return <String, Object?>{
            'status': 'ok',
            'echo': Map<String, Object?>.from(command),
          };
        },
        onPaired: pairedAddresses.add,
        onFatalError: fatalErrors.add,
      );
    }

    setUp(() async {
      fatalErrors = <Object>[];
      pairedAddresses = <String>[];
      receivedCommands = <Map<String, Object?>>[];
      commandRemoteAddresses = <String>[];
      client = HttpClient()..findProxy = (_) => 'DIRECT';
      await startTransport();
    });

    tearDown(() async {
      await browserChannel?.destroy();
      await transport.stop();
      client.close(force: true);
    });

    Uri endpoint(String path) => Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: binding.port,
      path: path,
    );

    String expectedOrigin() => endpoint('/').origin;

    Future<void> restartTransport({
      Duration requestReadTimeout = const Duration(seconds: 10),
      int maximumConcurrentHandlers = 8,
      int maximumBufferedRequestBytes = 1024 * 1024,
    }) async {
      await transport.stop();
      await startTransport(
        requestReadTimeout: requestReadTimeout,
        maximumConcurrentHandlers: maximumConcurrentHandlers,
        maximumBufferedRequestBytes: maximumBufferedRequestBytes,
      );
    }

    Future<_HttpResult> request(
      String method,
      String path, {
      Object? jsonBody,
      List<int>? rawBody,
      ContentType? contentType,
      String? origin,
    }) async {
      assert(jsonBody == null || rawBody == null);
      final outgoing = await client.openUrl(method, endpoint(path));
      final body =
          rawBody ??
          (jsonBody == null
              ? const <int>[]
              : utf8.encode(jsonEncode(jsonBody)));
      if (jsonBody != null || contentType != null) {
        outgoing.headers.contentType = contentType ?? ContentType.json;
      }
      if (origin != null) outgoing.headers.set('Origin', origin);
      if (body.isNotEmpty) {
        outgoing.contentLength = body.length;
        outgoing.add(body);
      }
      final response = await outgoing.close();
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(', ');
      });
      final responseBody = await utf8.decoder.bind(response).join();
      return _HttpResult(
        statusCode: response.statusCode,
        headers: headers,
        body: responseBody,
      );
    }

    Future<Socket> openRawRequest(
      String method,
      String path, {
      required int contentLength,
      List<int> initialBody = const <int>[],
    }) async {
      final socket = await Socket.connect('127.0.0.1', binding.port);
      socket.add(
        utf8.encode(
          '$method $path HTTP/1.1\r\n'
          'Host: 127.0.0.1:${binding.port}\r\n'
          'Origin: ${expectedOrigin()}\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: $contentLength\r\n'
          'Connection: close\r\n'
          '\r\n',
        ),
      );
      if (initialBody.isNotEmpty) socket.add(initialBody);
      await socket.flush();
      return socket;
    }

    Future<TrustedLanSecureChannel> pairBrowser() async {
      final helloResponse = await request('GET', '/api/pairing/hello');
      expect(helloResponse.statusCode, HttpStatus.ok);
      final phoneHello = TrustedLanPhoneHello.fromJson(
        _requiredObject(_decodeObject(helloResponse.body), 'hello'),
      );
      final browserPairing = await TrustedLanBrowserPairing.start(
        phoneHello: phoneHello,
        connectionCode: binding.formattedConnectionCode,
      );
      final finishResponse = await request(
        'POST',
        '/api/pairing/finish',
        jsonBody: <String, Object?>{'hello': browserPairing.hello.toJson()},
        origin: expectedOrigin(),
      );
      expect(finishResponse.statusCode, HttpStatus.ok);
      final confirmation = TrustedLanPhoneConfirmation.fromJson(
        _requiredObject(_decodeObject(finishResponse.body), 'confirmation'),
      );
      return browserPairing.finish(confirmation);
    }

    Future<_HttpResult> sendEncrypted(
      TrustedLanSecureChannel channel,
      Map<String, Object?> command,
    ) async {
      final frame = await channel.encrypt(utf8.encode(jsonEncode(command)));
      return request(
        'POST',
        '/api/message',
        jsonBody: <String, Object?>{'frame': frame.toJson()},
        origin: expectedOrigin(),
      );
    }

    test(
      'binds loopback, mutually pairs, and round-trips encrypted JSON',
      () async {
        expect(binding.port, greaterThan(0));
        expect(binding.formattedConnectionCode, matches(RegExp(r'^[A-Z]{8}$')));

        browserChannel = await pairBrowser();
        final command = <String, Object?>{
          'action': 'snapshot',
          'requestId': 'ABCDEFGHIJKLMNOP',
        };
        final response = await sendEncrypted(browserChannel!, command);
        expect(response.statusCode, HttpStatus.ok);
        final responseFrame = TrustedLanEncryptedFrame.fromJson(
          _requiredObject(_decodeObject(response.body), 'frame'),
        );
        final plaintext = await browserChannel!.decrypt(responseFrame);
        final decoded = _decodeObject(utf8.decode(plaintext));

        expect(decoded['status'], 'ok');
        expect(_requiredObject(decoded, 'echo'), command);
        expect(receivedCommands, <Map<String, Object?>>[command]);
        expect(commandRemoteAddresses, <String>['127.0.0.1']);
        expect(pairedAddresses, <String>['127.0.0.1']);
        expect(fatalErrors, isEmpty);
      },
    );

    test(
      'serves every response with cache and browser hardening headers',
      () async {
        final response = await request('GET', '/');

        expect(response.statusCode, HttpStatus.ok);
        expect(response.body, '<!doctype html><title>temporary</title>');
        expect(response.headers['cache-control'], contains('no-store'));
        expect(response.headers['cache-control'], contains('private'));
        expect(response.headers['pragma'], 'no-cache');
        expect(response.headers['expires'], '0');
        expect(response.headers['x-content-type-options'], 'nosniff');
        expect(response.headers['referrer-policy'], 'no-referrer');
        expect(response.headers['x-frame-options'], 'DENY');
        expect(response.headers['cross-origin-resource-policy'], 'same-origin');
        expect(response.headers['cross-origin-opener-policy'], 'same-origin');
        final permissions = response.headers['permissions-policy']!;
        expect(permissions, contains('camera=()'));
        expect(permissions, contains('microphone=()'));
        expect(permissions, contains('clipboard-read=()'));
        expect(permissions, contains('clipboard-write=()'));
        final csp = response.headers['content-security-policy']!;
        expect(csp, contains("default-src 'none'"));
        expect(csp, contains("script-src 'self'"));
        expect(csp, contains("connect-src 'self'"));
        expect(csp, contains("frame-ancestors 'none'"));
        expect(csp, contains("object-src 'none'"));
      },
    );

    test(
      'rejects a Host header that does not match the bound endpoint',
      () async {
        final socket = await Socket.connect('127.0.0.1', binding.port);
        socket.write(
          'GET / HTTP/1.1\r\n'
          'Host: attacker.invalid\r\n'
          'Connection: close\r\n'
          '\r\n',
        );
        await socket.flush();
        final rawResponse = await utf8.decoder.bind(socket).join();

        expect(rawResponse, startsWith('HTTP/1.1 400'));
        expect(rawResponse, contains('invalidHost'));
        expect(receivedCommands, isEmpty);
        expect(fatalErrors, isEmpty);
      },
    );

    test('rejects a GET body without draining a slow sender', () async {
      final socket = await openRawRequest(
        'GET',
        '/',
        contentLength: 64,
        initialBody: const <int>[0x7b],
      );
      final response = await _readRawResponse(
        socket,
      ).timeout(const Duration(seconds: 2));
      final retry = await request('GET', '/');

      expect(response.statusCode, HttpStatus.badRequest);
      expect(_decodeObject(response.body)['status'], 'invalidRequest');
      expect(retry.statusCode, HttpStatus.ok);
      expect(fatalErrors, isEmpty);
    });

    test(
      'rejects missing or foreign POST Origin and non-JSON content',
      () async {
        final missingOrigin = await request(
          'POST',
          '/api/pairing/finish',
          jsonBody: const <String, Object?>{},
        );
        final foreignOrigin = await request(
          'POST',
          '/api/pairing/finish',
          jsonBody: const <String, Object?>{},
          origin: 'http://attacker.invalid',
        );
        final wrongContentType = await request(
          'POST',
          '/api/pairing/finish',
          rawBody: utf8.encode('{}'),
          contentType: ContentType.text,
          origin: expectedOrigin(),
        );

        for (final response in <_HttpResult>[
          missingOrigin,
          foreignOrigin,
          wrongContentType,
        ]) {
          expect(response.statusCode, HttpStatus.forbidden);
          expect(_decodeObject(response.body)['status'], 'rejected');
        }
        expect(receivedCommands, isEmpty);
        expect(fatalErrors, isEmpty);
      },
    );

    test(
      'invalid one-time code fails closed and reports pairing rejection',
      () async {
        final helloResponse = await request('GET', '/api/pairing/hello');
        final phoneHello = TrustedLanPhoneHello.fromJson(
          _requiredObject(_decodeObject(helloResponse.body), 'hello'),
        );
        final code = binding.formattedConnectionCode;
        final wrongCode = (code[0] == 'A' ? 'B' : 'A') + code.substring(1);
        final browserPairing = await TrustedLanBrowserPairing.start(
          phoneHello: phoneHello,
          connectionCode: wrongCode,
        );
        addTearDown(browserPairing.cancel);

        final response = await request(
          'POST',
          '/api/pairing/finish',
          jsonBody: <String, Object?>{'hello': browserPairing.hello.toJson()},
          origin: expectedOrigin(),
        );

        expect(response.statusCode, HttpStatus.unauthorized);
        expect(_decodeObject(response.body)['status'], 'pairingFailed');
        await Future<void>.delayed(Duration.zero);
        expect(fatalErrors, hasLength(1));
        expect(fatalErrors.single, isA<TemporaryWebPairingRejectedException>());
      },
    );

    test(
      'fixed total deadline cancels a slow drip and permits retry',
      () async {
        await restartTransport(
          requestReadTimeout: const Duration(milliseconds: 250),
        );
        final socket = await openRawRequest(
          'POST',
          '/api/pairing/finish',
          contentLength: 64,
          initialBody: const <int>[0x7b],
        );
        final stopwatch = Stopwatch()..start();
        var keepDripping = true;
        final drip = () async {
          while (keepDripping) {
            await Future<void>.delayed(const Duration(milliseconds: 75));
            try {
              socket.add(const <int>[0x20]);
              await socket.flush();
            } on Object {
              return;
            }
          }
        }();

        final response = await _readRawResponse(
          socket,
        ).timeout(const Duration(milliseconds: 600));
        keepDripping = false;
        await drip;
        stopwatch.stop();

        expect(response.statusCode, HttpStatus.requestTimeout);
        expect(_decodeObject(response.body)['status'], 'requestTimeout');
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 600)));
        expect(fatalErrors, isEmpty);

        browserChannel = await pairBrowser();
        expect(browserChannel, isNotNull);
      },
    );

    test(
      'concurrent pairing finish is gated and timeout releases the gate',
      () async {
        await restartTransport(
          requestReadTimeout: const Duration(milliseconds: 250),
        );
        final firstSocket = await openRawRequest(
          'POST',
          '/api/pairing/finish',
          contentLength: 64,
          initialBody: const <int>[0x7b],
        );
        final firstResponseFuture = _readRawResponse(firstSocket);
        await Future<void>.delayed(const Duration(milliseconds: 25));

        final secondSocket = await openRawRequest(
          'POST',
          '/api/pairing/finish',
          contentLength: 64,
          initialBody: const <int>[0x7b],
        );
        final secondResponse = await _readRawResponse(
          secondSocket,
        ).timeout(const Duration(seconds: 2));
        final firstResponse = await firstResponseFuture.timeout(
          const Duration(seconds: 2),
        );

        expect(secondResponse.statusCode, HttpStatus.tooManyRequests);
        expect(
          _decodeObject(secondResponse.body)['status'],
          'requestInProgress',
        );
        expect(firstResponse.statusCode, HttpStatus.requestTimeout);
        expect(_decodeObject(firstResponse.body)['status'], 'requestTimeout');
        expect(fatalErrors, isEmpty);

        browserChannel = await pairBrowser();
        expect(browserChannel, isNotNull);
      },
    );

    test(
      'handler limit reports busy and reuses the slot after timeout',
      () async {
        await restartTransport(
          requestReadTimeout: const Duration(milliseconds: 250),
          maximumConcurrentHandlers: 1,
        );
        final firstSocket = await openRawRequest(
          'POST',
          '/api/pairing/finish',
          contentLength: 64,
          initialBody: const <int>[0x7b],
        );
        final firstResponseFuture = _readRawResponse(firstSocket);
        await Future<void>.delayed(const Duration(milliseconds: 25));

        final busySocket = await openRawRequest(
          'POST',
          '/api/pairing/finish',
          contentLength: 64,
          initialBody: const <int>[0x7b],
        );
        final busyResponse = await _readRawResponse(
          busySocket,
        ).timeout(const Duration(seconds: 2));
        final firstResponse = await firstResponseFuture.timeout(
          const Duration(seconds: 2),
        );
        final afterTimeout = await request('GET', '/api/pairing/hello');

        expect(busyResponse.statusCode, HttpStatus.serviceUnavailable);
        expect(_decodeObject(busyResponse.body)['status'], 'serverBusy');
        expect(firstResponse.statusCode, HttpStatus.requestTimeout);
        expect(afterTimeout.statusCode, HttpStatus.ok);
        expect(fatalErrors, isEmpty);
      },
    );

    test(
      'buffer budget reports busy and is reusable by the next request',
      () async {
        await restartTransport(maximumBufferedRequestBytes: 4 * 1024);
        final socket = await openRawRequest(
          'POST',
          '/api/pairing/finish',
          contentLength: 4 * 1024 + 1,
        );
        final response = await _readRawResponse(
          socket,
        ).timeout(const Duration(seconds: 2));

        expect(response.statusCode, HttpStatus.serviceUnavailable);
        expect(_decodeObject(response.body)['status'], 'serverBusy');
        expect(fatalErrors, isEmpty);

        browserChannel = await pairBrowser();
        expect(browserChannel, isNotNull);
      },
    );

    test('rejects more than 512 KiB without invalidating pairing', () async {
      final socket = await openRawRequest(
        'POST',
        '/api/pairing/finish',
        contentLength: 512 * 1024 + 1,
      );
      final response = await _readRawResponse(
        socket,
      ).timeout(const Duration(seconds: 2));

      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      expect(_decodeObject(response.body)['status'], 'requestTooLarge');
      expect(receivedCommands, isEmpty);
      expect(fatalErrors, isEmpty);

      browserChannel = await pairBrowser();
      expect(browserChannel, isNotNull);
    });

    test(
      'revoke responds gone and stop closes the loopback listener',
      () async {
        browserChannel = await pairBrowser();
        final first = await sendEncrypted(browserChannel!, <String, Object?>{
          'action': 'snapshot',
          'requestId': 'ABCDEFGHIJKLMNOP',
        });
        expect(first.statusCode, HttpStatus.ok);
        expect(receivedCommands, hasLength(1));

        transport.revoke();
        final afterRevoke = await sendEncrypted(
          browserChannel!,
          <String, Object?>{
            'action': 'snapshot',
            'requestId': 'QRSTUVWXYZabcdef',
          },
        );
        expect(afterRevoke.statusCode, HttpStatus.gone);
        expect(_decodeObject(afterRevoke.body)['status'], 'sessionEnded');
        expect(receivedCommands, hasLength(1));

        await transport.stop();
        await expectLater(() async {
          final outgoing = await client.getUrl(endpoint('/'));
          final response = await outgoing.close();
          await response.drain<void>();
        }(), throwsA(isA<Object>()));
      },
    );
  });

  group('temporary web static assets', () {
    test('uses only bundled relative CSS and JavaScript references', () async {
      final html = await _projectFile(
        'assets/temporary_web/index.html',
      ).readAsString();
      final css = await _projectFile(
        'assets/temporary_web/app.css',
      ).readAsString();
      final javascript = await _projectFile(
        'assets/temporary_web/app.js',
      ).readAsString();

      final references = RegExp(
        r'''(?:src|href)\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).allMatches(html).map((match) => match.group(1)!).toList();
      expect(references, containsAll(<String>['/app.css', '/app.js']));
      expect(references, everyElement(startsWith('/')));
      expect(html, isNot(matches(RegExp(r'https?://', caseSensitive: false))));
      expect(css, isNot(matches(RegExp(r'https?://', caseSensitive: false))));
      expect(css, isNot(matches(RegExp(r'@import\b', caseSensitive: false))));
      expect(
        javascript,
        isNot(matches(RegExp(r'https?://', caseSensitive: false))),
      );

      final scriptTags = RegExp(
        r'<script\b[^>]*>',
        caseSensitive: false,
      ).allMatches(html).map((match) => match.group(0)!).toList();
      expect(scriptTags, hasLength(1));
      expect(scriptTags.single, contains('src="/app.js"'));
      for (final formId in <String>['account-form', 'subscription-form']) {
        final formTag = RegExp(
          '<form id="$formId"[^>]*>',
          dotAll: true,
        ).firstMatch(html)!.group(0)!;
        expect(formTag, contains('autocomplete="off"'));
        expect(formTag, contains('autocorrect="off"'));
        expect(formTag, contains('autocapitalize="off"'));
        expect(formTag, contains('spellcheck="false"'));
      }
      final pairingInput = RegExp(
        r'<input id="connection-code"[^>]*>',
        dotAll: true,
      ).firstMatch(html)!.group(0)!;
      expect(pairingInput, contains('autocomplete="off"'));
      expect(pairingInput, contains('autocorrect="off"'));
      expect(pairingInput, contains('autocapitalize="characters"'));
      expect(pairingInput, contains('spellcheck="false"'));
      expect(pairingInput, contains('maxlength="8"'));
      expect(pairingInput, contains('pattern="[A-Za-z]{8}"'));
      expect(pairingInput, contains('placeholder="ABCDEFGH"'));
      final accountCategoryInput = RegExp(
        r'<input id="account-category"[^>]*>',
        dotAll: true,
      ).firstMatch(html)!.group(0)!;
      expect(accountCategoryInput, contains('list="account-category-options"'));
      final subscriptionCurrencySelect = RegExp(
        r'<select id="subscription-currency"[^>]*>(.*?)</select>',
        dotAll: true,
      ).firstMatch(html)!;
      expect(subscriptionCurrencySelect.group(0), contains('required'));
      final subscriptionCurrencyValues = RegExp(r'<option value="([^"]+)"')
          .allMatches(subscriptionCurrencySelect.group(1)!)
          .map((match) => match.group(1)!)
          .toList();
      expect(
        subscriptionCurrencyValues.take(subscriptionCurrencies.length),
        orderedEquals(subscriptionCurrencies),
      );
      expect(subscriptionCurrencyValues.last, '__custom__');
      final customCurrencyInput = RegExp(
        r'<input id="subscription-custom-currency"[^>]*>',
        dotAll: true,
      ).firstMatch(html)!.group(0)!;
      expect(customCurrencyInput, contains('maxlength="12"'));
      expect(customCurrencyInput, contains('disabled'));
      expect(html, contains('id="subscription-custom-currency-label" hidden'));

      List<String> dataListValues(String id) {
        final content = RegExp(
          '<datalist id="$id"[^>]*>(.*?)</datalist>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(html)!.group(1)!;
        return RegExp(
          r'<option\b[^>]*>\s*</option>',
          caseSensitive: false,
        ).allMatches(content).map((match) {
          final value = RegExp(
            r'\svalue="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(match.group(0)!);
          return value!.group(1)!;
        }).toList();
      }

      expect(
        dataListValues('account-category-options'),
        orderedEquals(accountCategories),
      );
      expect(html, contains('建议使用浏览器的无痕/隐私窗口'));
      expect(html, contains('无痕模式不能保证电脑不留痕迹'));
      const disconnectWarning = '连接会持续到所选时间结束，或你在手机点击“主动断开”';
      expect(html, contains(disconnectWarning));
      final warningIndex = html.indexOf(disconnectWarning);
      final pairingPanelIndex = html.indexOf('id="pairing-panel"');
      final messageIndex = html.indexOf('id="message"');
      final hiddenWorkspaceIndex = html.indexOf('id="workspace" hidden');
      expect(warningIndex, greaterThan(0));
      expect(pairingPanelIndex, greaterThan(warningIndex));
      expect(messageIndex, greaterThan(0));
      expect(hiddenWorkspaceIndex, greaterThan(messageIndex));
      expect(hiddenWorkspaceIndex, greaterThan(warningIndex));
    });

    test('client source and generated bundle do not persist browser data', () async {
      final html = await _projectFile(
        'assets/temporary_web/index.html',
      ).readAsString();
      final clientSource = await _projectFile(
        'tool/temporary_web_client.dart',
      ).readAsString();
      expect(clientSource, contains("_snapshot['accountCategories']"));
      expect(clientSource, contains('_populateCategoryChoices'));
      final javascript = await _projectFile(
        'assets/temporary_web/app.js',
      ).readAsString();
      const persistentOrBackgroundApis = <String>[
        'localStorage',
        'sessionStorage',
        'indexedDB',
        'serviceWorker',
        'document.cookie',
        'sendBeacon',
        'WebSocket',
        'EventSource',
      ];
      for (final api in persistentOrBackgroundApis) {
        expect(
          clientSource.toLowerCase(),
          isNot(contains(api.toLowerCase())),
          reason: 'Browser client source must not use $api.',
        );
      }
      expect(clientSource, contains("'visibleForMilliseconds'"));
      expect(clientSource, contains('onPageHide'));
      expect(clientSource, contains('onVisibilityChange'));
      expect(clientSource, contains('_clearTemporarySecret'));
      expect(clientSource, contains('_connectionExpiryTimer'));
      expect(clientSource, contains('connectionDurationMilliseconds'));
      expect(clientSource, isNot(contains('_heartbeatTimer')));
      expect(clientSource, isNot(contains('Timer.periodic')));
      expect(clientSource, contains("'phone-approval-dialog'"));
      expect(clientSource, contains("'batch-commit-guidance'"));
      expect(html, contains('id="phone-approval-dialog"'));
      expect(html, contains('请在手机批准'));
      for (final stage in <String>[
        'HELLO',
        'LOCAL_CODE',
        'FINISH',
        'CONFIRM',
        'INITIAL_SYNC',
      ]) {
        expect(clientSource, contains(stage));
      }
      expect(clientSource, contains('serverStatus'));
      expect(
        clientSource,
        contains('if (_ended) {\n      return;\n    }'),
        reason: 'Repeated termination must preserve the first visible error.',
      );

      // dart2js emits browser type tables for ServiceWorker/WebSocket even when
      // they are never called, so the generated bundle is checked for the APIs
      // whose occurrence itself proves storage or external transmission access.
      for (final api in <String>[
        'localStorage',
        'sessionStorage',
        'indexedDB',
        'document.cookie',
        'sendBeacon',
      ]) {
        expect(
          javascript.toLowerCase(),
          isNot(contains(api.toLowerCase())),
          reason: 'Generated browser bundle must not access $api.',
        );
      }
      for (final webCryptoProbe in <String>[
        'crypto.subtle',
        'isSecureContext',
      ]) {
        expect(
          javascript,
          isNot(contains(webCryptoProbe)),
          reason:
              'LAN HTTP bundle must not initialize the secure-context-only '
              '$webCryptoProbe path.',
        );
      }
    });
  });
}

Future<_HttpResult> _readRawResponse(Socket socket) async {
  try {
    final raw = await utf8.decoder.bind(socket).join();
    final separator = raw.indexOf('\r\n\r\n');
    if (separator < 0) {
      throw const FormatException('HTTP response headers are incomplete.');
    }
    final headerLines = raw.substring(0, separator).split('\r\n');
    final statusParts = headerLines.first.split(' ');
    if (statusParts.length < 2) {
      throw const FormatException('HTTP response status is invalid.');
    }
    final headers = <String, String>{};
    for (final line in headerLines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim().toLowerCase()] = line
          .substring(colon + 1)
          .trim();
    }
    return _HttpResult(
      statusCode: int.parse(statusParts[1]),
      headers: headers,
      body: raw.substring(separator + 4),
    );
  } finally {
    socket.destroy();
  }
}

Future<String> _minimalAssetLoader(String assetKey) async {
  return switch (assetKey) {
    'assets/temporary_web/index.html' =>
      '<!doctype html><title>temporary</title>',
    'assets/temporary_web/app.css' => 'body{display:block}',
    'assets/temporary_web/app.js' => 'void 0;',
    _ => throw ArgumentError.value(assetKey, 'assetKey'),
  };
}

Map<String, Object?> _decodeObject(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, Object?>.from(decoded);
}

Map<String, Object?> _requiredObject(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Expected object at $key.');
  }
  return Map<String, Object?>.from(value);
}

File _projectFile(String relativePath) {
  final direct = File(relativePath);
  if (direct.existsSync()) return direct;
  final fromRepositoryRoot = File('app/$relativePath');
  if (fromRepositoryRoot.existsSync()) return fromRepositoryRoot;
  throw StateError('Missing project file: $relativePath');
}

final class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}
