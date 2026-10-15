import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/platform/import_document_picker.dart';
import 'package:account_subscription_manager/core/platform/temporary_web_runtime_keeper.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_service.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_vault_store.dart';

const _master = 'Test-Only-Maple-84!Local';
const _backupPassword = 'Test-Only-Cobalt-73!Archive';
const _targetPassword = 'Test-Only-Fjord-62!Target';
const _documents = MethodChannel('cardock/document_storage_v1');
const _commercial = MethodChannel('cardock/commercial_license');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(_documents, null);
    messenger.setMockMethodCallHandler(_commercial, null);
  });
  test(
    'iOS defaults to App Store and rejects other channel definitions; Android keeps routing',
    () {
      for (final value in ['development', 'app_store']) {
        expect(
          CardockDistributionConfig.resolve(
            value,
            platform: TargetPlatform.iOS,
          ),
          CardockDistributionChannel.appStore,
        );
      }
      for (final value in ['website', 'google_play', 'unknown']) {
        expect(
          CardockDistributionConfig.resolve(
            value,
            platform: TargetPlatform.iOS,
          ),
          CardockDistributionChannel.unsupported,
        );
      }
      expect(
        CardockDistributionConfig.resolve(
          'website',
          platform: TargetPlatform.android,
        ),
        CardockDistributionChannel.website,
      );
      expect(
        CardockDistributionConfig.resolve(
          'google_play',
          platform: TargetPlatform.android,
        ),
        CardockDistributionChannel.googlePlay,
      );
    },
  );
  test('iOS requires the native runtime bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('cardock/temporary_web_runtime');
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final keeper = createDefaultTemporaryWebRuntimeKeeper();
    await keeper.start();
    await keeper.stop();
    expect(calls, ['start', 'stop']);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform explicitly selected backup/import uses bounded native contract',
      () async {
        final calls = <String>[];
        messenger.setMockMethodCallHandler(_documents, (call) async {
          calls.add(call.method);
          return {
            'name': 'test.asmbackup',
            'bytes': Uint8List.fromList([1, 2]),
          };
        });
        final service = FilePickerPortableBackupService(platform: platform);
        expect((await service.pickEncryptedBackup())?.bytes, [1, 2]);
        expect((await pickImportDocument(platform: platform))?.bytes, [1, 2]);
        expect(calls, ['pickBackup', 'pickImport']);
      },
    );
  }
  test(
    'iOS picker cancellation is distinct from failed reads and saves',
    () async {
      const service = FilePickerPortableBackupService(
        platform: TargetPlatform.iOS,
      );
      messenger.setMockMethodCallHandler(
        _documents,
        (call) async => call.method == 'saveBackup' ? false : null,
      );
      expect(await service.pickEncryptedBackup(), isNull);
      expect(await service.saveEncryptedBackup(Uint8List.fromList([1])), false);
      messenger.setMockMethodCallHandler(_documents, (_) async => true);
      expect(await service.saveEncryptedBackup(Uint8List.fromList([1])), true);
      messenger.setMockMethodCallHandler(_documents, (_) async => null);
      await expectLater(
        service.saveEncryptedBackup(Uint8List.fromList([1])),
        throwsFormatException,
      );
    },
  );
  for (final code in [
    'permission_revoked',
    'provider_unavailable',
    'read_failed',
    'interrupted',
    'too_large',
    'timeout',
    'operation_in_progress',
  ]) {
    test(
      'iOS $code remains a failure, not a cancellation or success',
      () async {
        messenger.setMockMethodCallHandler(
          _documents,
          (_) async => throw PlatformException(code: code),
        );
        const service = FilePickerPortableBackupService(
          platform: TargetPlatform.iOS,
        );
        await expectLater(
          service.pickEncryptedBackup(),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
        );
        await expectLater(
          service.saveEncryptedBackup(Uint8List.fromList([1])),
          throwsA(isA<PlatformException>()),
        );
      },
    );
  }
  test(
    'iOS rejects malformed/empty/oversize native data and oversized export before native call',
    () async {
      const service = FilePickerPortableBackupService(
        platform: TargetPlatform.iOS,
      );
      for (final value in [
        <String, Object?>{'bytes': Uint8List(0), 'name': 'empty'},
        <String, Object?>{
          'bytes': Uint8List(16 * 1024 * 1024 + 1),
          'name': 'large',
        },
        <String, Object?>{
          'bytes': [1],
          'name': 'wrong type',
        },
      ]) {
        messenger.setMockMethodCallHandler(_documents, (_) async => value);
        await expectLater(service.pickEncryptedBackup(), throwsFormatException);
      }
      var calls = 0;
      messenger.setMockMethodCallHandler(_documents, (_) async {
        calls++;
        return true;
      });
      await expectLater(
        service.saveEncryptedBackup(Uint8List(16 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'stream interruption and actual byte limit reject without a partial backup',
    () async {
      Stream<List<int>> interrupted() async* {
        yield [1];
        throw const FileSystemException('test-only interrupted');
      }

      await expectLater(
        readBoundedBackup(interrupted()),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        readBoundedBackup(
          Stream.fromIterable([
            Uint8List(16 * 1024 * 1024),
            [1],
          ]),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Apple preserves previously verified memory state on errors and clears on reliable absence',
    () async {
      Object? verification = true;
      messenger.setMockMethodCallHandler(_commercial, (call) async {
        if (call.method == 'inspect') {
          return {
            'trusted': true,
            'channel': 'app_store',
            'applicationId': 'com.localaccount.cardock',
            'installationKeySha256': 'a' * 64,
          };
        }
        if (call.method == 'verifyStore') {
          if (verification is Exception) throw verification;
          return verification;
        }
        return null;
      });
      final gateway = CommercialPurchaseGateway(
        config: const CommercialLicenseConfig(
          channel: CardockDistributionChannel.appStore,
          applicationId: 'com.localaccount.cardock',
        ),
      );
      addTearDown(gateway.dispose);
      expect(await gateway.query(), ProductEntitlement.purchased);
      verification = PlatformException(code: 'transaction_unverified');
      expect(await gateway.query(), ProductEntitlement.purchased);
      expect(
        (await gateway.restore()).entitlement,
        ProductEntitlement.purchased,
      );
      verification = null; // malformed responses cannot revoke trusted state
      expect(await gateway.query(), ProductEntitlement.purchased);
      verification = false;
      expect(await gateway.query(), ProductEntitlement.free);
      verification = PlatformException(code: 'network');
      expect(await gateway.query(), ProductEntitlement.free);
    },
  );
  test(
    'duplicate native purchase updates re-query authority and cannot grant by event payload',
    () async {
      var owned = false;
      messenger.setMockMethodCallHandler(
        _commercial,
        (call) async => switch (call.method) {
          'inspect' => {
            'trusted': true,
            'channel': 'app_store',
            'applicationId': 'com.localaccount.cardock',
            'installationKeySha256': 'b' * 64,
          },
          'verifyStore' => owned,
          _ => null,
        },
      );
      final gateway = CommercialPurchaseGateway(
        config: const CommercialLicenseConfig(
          channel: CardockDistributionChannel.appStore,
          applicationId: 'com.localaccount.cardock',
        ),
      );
      addTearDown(gateway.dispose);
      final events = <ProductEntitlement>[];
      final subscription = gateway.entitlementStream.listen(events.add);
      addTearDown(subscription.cancel);
      Future<void> emit() async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          _commercial.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('entitlementsChanged', {'purchased': true}),
          ),
          (_) => done.complete(),
        );
        await done.future;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await emit();
      expect(events.last, ProductEntitlement.free);
      owned = true;
      await emit();
      await emit();
      expect(events.skip(1), everyElement(ProductEntitlement.purchased));
      owned = false;
      await emit();
      expect(events.last, ProductEntitlement.free);
    },
  );
  test(
    'real encrypted core path: create, edit account/subscription, reopen, backup, isolated restore',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final directory = await Directory.systemTemp.createTemp(
        'ios-phase1-fictional-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = LayeredVaultStore.forDirectory(
        directory: Directory('${directory.path}/source'),
      );
      final created = await source.create(masterPassword: _master);
      final account = AccountRecord.fromDraft(
        id: 'account-1',
        draft: AccountDraft(
          platformName: 'TEST-ONLY Mail',
          password: 'TEST-ONLY-RECORD',
        ),
      );
      SubscriptionRecord subscription(String name) =>
          SubscriptionRecord.fromDraft(
            id: 'subscription-1',
            draft: SubscriptionDraft(
              accountId: 'account-1',
              details: SubscriptionDetailsDraft(
                serviceName: name,
                firstSubscribedOn: DateTime(2026, 9, 1),
                nextRenewalOn: DateTime(2026, 10, 1),
              ),
            ),
          );
      var snapshot = VaultSnapshot(
        nextAccountId: 2,
        accounts: [account],
        nextSubscriptionId: 2,
        subscriptions: [subscription('TEST-ONLY initial')],
      );
      await created.session.save(snapshot);
      snapshot = snapshot.copyWith(
        accounts: [
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(
              platformName: 'TEST-ONLY edited',
              password: 'TEST-ONLY-RECORD',
            ),
          ),
        ],
        subscriptions: [subscription('TEST-ONLY edited subscription')],
      );
      await created.session.save(snapshot);
      created.session.close();
      final restarted = LayeredVaultStore.forDirectory(
        directory: Directory('${directory.path}/source'),
      );
      final opened = await restarted.unlock(masterPassword: _master);
      expect(opened.snapshot.accounts.single.platformName, 'TEST-ONLY edited');
      expect(
        opened.snapshot.subscriptions.single.serviceName,
        'TEST-ONLY edited subscription',
      );
      final codec = PortableBackupCodec();
      final bytes = await codec.encryptV2(
        snapshot: opened.snapshot,
        backupMasterPassword: _backupPassword,
      );
      opened.session.close();
      expect(utf8.decode(bytes), isNot(contains('TEST-ONLY')));
      Uint8List? exported;
      messenger.setMockMethodCallHandler(_documents, (call) async {
        if (call.method == 'saveBackup') {
          exported = Uint8List.fromList(
            (call.arguments as Map)['bytes'] as Uint8List,
          );
          return true;
        }
        return {'name': 'test.asmbackup', 'bytes': exported};
      });
      const fileService = FilePickerPortableBackupService(
        platform: TargetPlatform.iOS,
      );
      expect(await fileService.saveEncryptedBackup(bytes), true);
      final selected = (await fileService.pickEncryptedBackup())!;
      final target = LayeredVaultStore.forDirectory(
        directory: Directory('${directory.path}/target'),
      );
      final targetCreated = await target.create(
        masterPassword: _targetPassword,
      );
      await expectLater(
        codec.read(bytes: selected.bytes, backupMasterPassword: _master),
        throwsA(isA<PortableBackupAuthenticationException>()),
      );
      final restored = await codec.read(
        bytes: selected.bytes,
        backupMasterPassword: _backupPassword,
      );
      await targetCreated.session.save(restored.snapshot);
      targetCreated.session.close();
      final targetOpened = await target.unlock(masterPassword: _targetPassword);
      expect(
        targetOpened.snapshot.accounts.single.platformName,
        'TEST-ONLY edited',
      );
      expect(targetOpened.snapshot.subscriptions, hasLength(1));
      targetOpened.session.close();
      await expectLater(
        target.unlock(masterPassword: _master),
        throwsA(isA<VaultUnlockException>()),
      );
      final sourceAgain = await restarted.unlock(masterPassword: _master);
      expect(sourceAgain.snapshot.accounts, hasLength(1));
      sourceAgain.session.close();
    },
  );
  test(
    'lock during backup KDF cancels stale export and leaves vault locked',
    () async {
      final state = AppState(
        vaultStore: FakeVaultStore(configured: true, acceptedPassword: _master),
      );
      addTearDown(state.dispose);
      await state.initialize();
      await state.unlock(_master);
      final pending = state.exportEncryptedBackup(
        backupMasterPassword: _backupPassword,
      );
      state.lock();
      expect(await pending, isNull);
      expect(state.isUnlocked, false);
    },
  );
  testWidgets(
    'iOS transient inactive shows cover without unlock loop; real background locks',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final store = FakeVaultStore(configured: true, acceptedPassword: _master);
      await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('unlock-master-password-field')),
        _master,
      );
      await tester.tap(find.byKey(const ValueKey('unlock-vault-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(const ValueKey('privacy-shield')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('unlock-master-password-field')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  test(
    'iOS phase copy exists in all three languages without internal security details',
    () {
      for (final locale in [
        const Locale('zh', 'CN'),
        const Locale('en'),
        const Locale('ja'),
      ]) {
        final translated = AppLocalizations(locale).translate(
          '离开应用或锁定保险库会保留会话，计时不会暂停。iOS 后台可能暂停连接，保持本页前台可持续录入；锁定后保存需先解锁手机。',
        );
        expect(translated, isNotEmpty);
        if (locale.languageCode != 'zh') {
          expect(translated, isNot(contains('保留会话')));
        }
      }
    },
  );
}
