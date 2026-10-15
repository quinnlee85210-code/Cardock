import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/temporary_web/temporary_web_server_io.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_batch_import_port.dart';
import 'package:flutter_test/flutter_test.dart';

const _runRealBrowser = bool.fromEnvironment('CARDOCK_REAL_BROWSER_TEST');

void main() {
  test(
    'compiled browser client pairs and reads File bytes with real Chrome',
    () async {
      final address = await _privateIpv4Address();
      final snapshotReceived = Completer<void>();
      final fatalError = Completer<Object>();
      var commits = 0;
      var approvalRead = false;
      late IoTemporaryWebTransport transport;
      transport = IoTemporaryWebTransport(
        assetLoader: (assetKey) async {
          final source = await File(assetKey).readAsString();
          if (!assetKey.endsWith('/app.js')) return source;
          return '$source\n${await File('test/support/temporary_web_browser_driver.js').readAsString()}';
        },
      );
      Process? browser;
      Future<String>? browserOutput;
      Future<String>? browserErrors;
      Directory? profile;
      try {
        final binding = await transport.start(
          address: address,
          onCommand: (command, _) async {
            switch (command['action']) {
              case 'snapshot':
                if (!snapshotReceived.isCompleted) snapshotReceived.complete();
                return <String, Object?>{
                  'status': 'ok',
                  'data': <String, Object?>{
                    'revision': 0,
                    'batchImportAvailable': true,
                    'historyMode': 'currentSessionOnly',
                    'allowHistoryEditing': false,
                    'allowHistoricalPasswordReveal': false,
                    'accountCategories': const <String>[],
                    'accounts': const <Object?>[],
                    'subscriptions': const <Object?>[],
                    'timeouts': <String, Object?>{
                      'connectionDurationMilliseconds': 300000,
                      'connectionRemainingMilliseconds': 300000,
                    },
                  },
                };
              case 'batchImportUploadStart':
                return {'status': 'ok', 'nextSequence': 0};
              case 'batchImportUploadChunk':
                return {'status': 'ok', 'nextSequence': 1};
              case 'batchImportUploadFinish':
                return {
                  'status': 'ok',
                  'data': const TemporaryWebBatchImportPreview(
                    previewToken: 'browser-preview',
                    revision: 0,
                    sourceLabel: 'Fictional CSV',
                    detectedFormat: 'UTF-8 CSV',
                    mappings: [
                      TemporaryWebBatchImportMapping(
                        columnIndex: 0,
                        sourceLabel: 'platformName',
                        targetField: 'platformName',
                        availableTargets: ['platformName'],
                      ),
                    ],
                    rows: [
                      TemporaryWebBatchImportRow(
                        id: 'account-row-2',
                        kind: 'account',
                        title: 'Browser fixture',
                        subtitle: '',
                        passwordStatus: 'absent',
                        defaultResolution: 'skip',
                        originalRowNumber: 2,
                        fields: {'platformName': 'Browser fixture'},
                      ),
                    ],
                  ).toJson(),
                };
              case 'batchImportCommit':
                commits++;
                expect((command['body'] as Map)['selectedRowIds'], [
                  'account-row-2',
                ]);
                return {
                  'status': 'pendingPhoneApproval',
                  'approvalId': 'browser-approval',
                };
              case 'approvalResult':
                approvalRead = true;
                return {
                  'status': 'rejected',
                  'message': 'Fictional phone declined',
                };
              case 'activity':
              case 'sessionStatus':
                if (approvalRead) {
                  // Same revocation boundary used by the phone's Stop action.
                  transport.revoke();
                  return {'status': 'ended'};
                }
                return <String, Object?>{
                  'status': 'ok',
                  'timeouts': <String, Object?>{
                    'connectionDurationMilliseconds': 300000,
                    'connectionRemainingMilliseconds': 300000,
                  },
                };
              default:
                return const <String, Object?>{'status': 'rejected'};
            }
          },
          onPaired: (_) {},
          onFatalError: (error) {
            if (!fatalError.isCompleted) fatalError.complete(error);
          },
        );
        profile = await Directory.systemTemp.createTemp(
          'cardock-browser-smoke-',
        );
        final chrome = Platform.environment['CHROME_EXECUTABLE'];
        if (chrome == null || chrome.isEmpty) {
          fail(
            'CHROME_EXECUTABLE is required for the real browser smoke test.',
          );
        }
        final uri = Uri(
          scheme: 'http',
          host: address,
          port: binding.port,
          path: '/',
          queryParameters: <String, String>{
            'code': binding.formattedConnectionCode,
          },
        );
        browser = await Process.start(chrome, <String>[
          '--headless=new',
          '--disable-gpu',
          '--dump-dom',
          '--virtual-time-budget=12000',
          '--no-first-run',
          '--no-default-browser-check',
          '--no-proxy-server',
          '--user-data-dir=${profile.path}',
          uri.toString(),
        ]);
        browserOutput = browser.stdout.transform(utf8.decoder).join();
        browserErrors = browser.stderr.transform(utf8.decoder).join();

        try {
          await Future.any<void>(<Future<void>>[
            snapshotReceived.future,
            fatalError.future.then<void>((error) => throw error),
            browser.exitCode.then<void>((exitCode) async {
              await Future<void>.delayed(Duration.zero);
              if (snapshotReceived.isCompleted) return;
              final output = await browserOutput!;
              final errors = await browserErrors!;
              throw StateError(
                'Chrome exited before pairing (code $exitCode): '
                '${_dumpedDomDiagnostics(output)}; '
                'stderr=${_sanitizedBrowserErrors(errors)}',
              );
            }),
          ]).timeout(const Duration(seconds: 15));
        } on TimeoutException {
          fail('Browser did not complete pairing before the smoke timeout.');
        }
        final exitCode = await browser.exitCode.timeout(
          const Duration(seconds: 15),
        );
        final output = await browserOutput;
        final errors = await browserErrors;
        if (exitCode != 0) {
          fail(
            'Chrome exited after pairing (code $exitCode): '
            '${_dumpedDomDiagnostics(output)}; '
            'stderr=${_sanitizedBrowserErrors(errors)}',
          );
        }
        final diagnostics = _dumpedDomDiagnostics(output);
        expect(commits, 1, reason: diagnostics.toString());
        expect(diagnostics['approval'], 'ok', reason: diagnostics.toString());
        expect(diagnostics['preflight'], 'ok', reason: diagnostics.toString());
        expect(diagnostics['disconnect'], 'ok', reason: diagnostics.toString());
        expect(_dumpedDomDiagnostics(output)['fileReader'], 'ok');
        expect(
          _dumpedDomDiagnostics(output)['accountEditor'],
          'ok',
          reason: _dumpedDomDiagnostics(output).toString(),
        );
      } finally {
        if (browser case final runningBrowser?) {
          runningBrowser.kill();
          try {
            await runningBrowser.exitCode.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            // The exact browser process was already asked to terminate. Child
            // processes can release the isolated profile shortly afterwards.
          }
        }
        await transport.stop();
        if (profile != null && await profile.exists()) {
          for (var attempt = 0; attempt < 20; attempt += 1) {
            try {
              await profile.delete(recursive: true);
              break;
            } on FileSystemException {
              if (attempt == 19) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
        }
      }
    },
    skip: !_runRealBrowser,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Map<String, Object?> _dumpedDomDiagnostics(String html) {
  String? textFor(String id) {
    final match = RegExp(
      '<[^>]+id="$id"[^>]*>(.*?)</[^>]+>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return match
        ?.group(1)
        ?.replaceAll(RegExp('<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  return <String, Object?>{
    'status': textFor('connection-status'),
    'batch': textFor('batch-summary'),
    'approval': textFor('cardock-approval-status'),
    'preflight': textFor('cardock-preflight-status'),
    'disconnect': textFor('cardock-disconnect-status'),
    'message': textFor('message'),
    'fileReader': textFor('cardock-file-reader-status'),
    'accountEditor': textFor('cardock-account-editor-status'),
  };
}

String _sanitizedBrowserErrors(String value) {
  final lines = value
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return lines.length <= 300 ? lines : '${lines.substring(0, 300)}…';
}

Future<String> _privateIpv4Address() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  for (final prefix in <List<int>>[
    <int>[192, 168],
    <int>[10],
    <int>[172],
  ]) {
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final bytes = address.rawAddress;
        if (bytes.length != 4 || bytes[0] != prefix[0]) continue;
        if (prefix.length == 2 && bytes[1] != prefix[1]) continue;
        if (prefix[0] == 172 && (bytes[1] < 16 || bytes[1] > 31)) continue;
        return address.address;
      }
    }
  }
  throw StateError('No private IPv4 address is available for browser smoke.');
}
