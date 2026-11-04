import 'dart:async';
import 'dart:io';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/vault_rebuild_service.dart';
import 'package:account_subscription_manager/features/vault/presentation/vault_rebuild_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';
import 'stage1_safety_integration_test.dart' show QuickStore;

void main() {
  const channel = MethodChannel('cardock/vault_rebuild_v1');
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({AppState state, Directory directory})> open(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'CN'),
    bool directReset = false,
    bool realVault = false,
  }) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('cardock-rebuild-auth-test-'),
    );
    addTearDown(() => directory!.delete(recursive: true));
    final diskStore = await tester.runAsync(() async {
      if (!realVault) return null;
      final store = LayeredVaultStore.forDirectory(
        directory: directory!,
        creationKdf: const VaultKdfParameters(
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
        ),
        quickUnlockSecretStore: QuickStore(),
      );
      final opened = await store.create(
        masterPassword: 'TEST-ONLY-RESET-2026!',
      );
      opened.session.close();
      return store;
    });
    final state = (await tester.runAsync(() async {
      final state = AppState(
        vaultStore: diskStore ?? FakeVaultStore(configured: true),
        rebuildService: VaultRebuildService(
          directory: () async => directory!,
          platform: const MethodChannelRebuildPlatform(),
          reminders: const NoopReminderScheduler(),
          requiresTypedConfirmation: !directReset,
        ),
      );
      await state.initialize();
      return state;
    }))!;
    addTearDown(state.dispose);
    expect(state.vaultPhase, VaultPhase.locked);
    expect(state.anyRecoveryConfigured, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => state.vaultPhase == VaultPhase.needsSetup
                  ? const Text('TEST-SETUP')
                  : TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VaultRebuildPage(appState: state),
                        ),
                      ),
                      child: const Text('TEST-OPEN-RESET'),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST-OPEN-RESET'));
    await tester.pumpAndSettle();
    return (state: state, directory: directory!);
  }

  Future<void> start(
    WidgetTester tester, {
    bool settleAfterAuthentication = true,
  }) async {
    final button = find.text('了解后验证设备身份');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    if (settleAfterAuthentication) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final failure in ['missing channel', 'cancelled', 'platform error']) {
    testWidgets(
      '$failure displays feedback and keeps the no-recovery vault intact',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              if (failure == 'missing channel') {
                throw MissingPluginException();
              }
              if (failure == 'platform error') {
                throw PlatformException(code: 'unavailable');
              }
              return null;
            });
        await open(tester);
        await start(tester);
        expect(find.text('系统身份验证未完成。'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '了解后验证设备身份'),
        );
        expect(button.onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'iOS continue authenticates then deletes without typing or another confirmation',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'authorize':
                return {'token': 'test-only', 'unsecured': false};
              case 'consume':
                expect((call.arguments as Map)['phrase'], isEmpty);
                return true;
              case 'clearCommitted':
                return null;
              default:
                fail('Unexpected reset method: ${call.method}');
            }
          });
      final fixture = await open(tester, directReset: true, realVault: true);
      final backup = File('${fixture.directory.path}/outside.asmbackup');
      await tester.runAsync(() => backup.writeAsString('TEST-ONLY-BACKUP'));
      await start(tester, settleAfterAuthentication: false);
      for (
        var i = 0;
        i < 100 && fixture.state.vaultPhase != VaultPhase.needsSetup;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(fixture.state.vaultPhase, VaultPhase.needsSetup);
      await tester.pumpAndSettle();
      expect(find.text('TEST-SETUP'), findsOneWidget);
      expect(find.byType(VaultRebuildPage), findsNothing);
      expect(calls, ['authorize', 'consume', 'clearCommitted']);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('按住至少 3 秒'), findsNothing);
      expect(find.text('最终确认：删除本机数据？'), findsNothing);
      expect(await tester.runAsync(backup.readAsString), 'TEST-ONLY-BACKUP');
      expect(
        await tester.runAsync(
          () => Directory(
            '${fixture.directory.path}/encrypted_vault_v1',
          ).exists(),
        ),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final failure in ['cancelled', 'no passcode', 'unsecured', 'expired']) {
    testWidgets('iOS $failure preserves local files and never starts cleanup', (
      tester,
    ) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'authorize') {
              if (failure == 'cancelled') return null;
              if (failure == 'no passcode') {
                throw PlatformException(
                  code: 'device_authentication_unavailable',
                );
              }
              return {
                'token': 'test-only',
                'unsecured': failure == 'unsecured',
              };
            }
            if (call.method == 'consume') return false;
            fail('Cleanup must never start after $failure');
          });
      final fixture = await open(tester, directReset: true);
      final data = File('${fixture.directory.path}/vault_access_state_v1.json');
      await tester.runAsync(() => data.writeAsString('TEST-ONLY-PRESERVE'));
      await start(tester);
      expect(
        calls,
        failure == 'expired' ? ['authorize', 'consume'] : ['authorize'],
      );
      expect(fixture.state.vaultPhase, VaultPhase.locked);
      expect(find.byType(TextField), findsNothing);
      expect(await tester.runAsync(data.readAsString), 'TEST-ONLY-PRESERVE');
      expect(
        await tester.runAsync(
          () => File(
            '${fixture.directory.path}/${VaultRebuildService.journalName}',
          ).exists(),
        ),
        false,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'no security questions required: successful device auth reveals final confirmation only',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return {'token': 'test-only', 'unsecured': false};
          });
      await open(tester);
      await start(tester);
      expect(calls, ['authorize']);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '删除并重新开始'))
            .onPressed,
        isNull,
      );
      expect(find.text('系统身份验证未完成。'), findsNothing);
    },
  );

  testWidgets('pending authentication cannot be started twice', (tester) async {
    final pending = Completer<Object?>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) {
          calls++;
          return pending.future;
        });
    await open(tester);
    final button = find.widgetWithText(FilledButton, '了解后验证设备身份');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets(
    'expired unsecured hold returns to authentication without an uncaught error',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'authorize') {
              return {'token': 'test-only', 'unsecured': true};
            }
            throw PlatformException(code: 'authorization_expired');
          });
      await open(tester);
      await start(tester);
      final holdButton = find.text('按住至少 3 秒');
      await tester.ensureVisible(holdButton);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(holdButton));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('系统身份验证未完成。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
