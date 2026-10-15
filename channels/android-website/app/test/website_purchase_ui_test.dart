import 'dart:convert';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/website_offline_browser.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_page.dart';
import 'package:account_subscription_manager/features/product/presentation/website_orders_page.dart';
import 'package:account_subscription_manager/features/product/presentation/website_purchase_access.dart';
import 'package:account_subscription_manager/features/product/presentation/website_purchase_coordinator.dart';
import 'package:account_subscription_manager/features/product/presentation/website_authorization_dialog.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;
import 'website_purchase_gateway_test.dart'
    show FakeOfflineBrowser, offlineTestConfig;

void main() {
  late FakeOfflineBrowser browser;
  late ProductEntitlementController controller;
  late WebsitePurchaseAccess access;
  setUp(() async {
    browser = FakeOfflineBrowser();
    access = WebsitePurchaseAccess()..update(true);
    final p = FakeLicensePlatform();
    browser.digest = p.digest;
    controller = ProductEntitlementController(
      gateway: CommercialPurchaseGateway(
        config: offlineTestConfig(),
        platform: p,
        offlineBrowser: browser.bridge,
        openCheckout: browser.open,
      ),
    );
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    access.dispose();
  });
  Widget host(Widget child, {String lang = 'zh'}) => MaterialApp(
    locale: Locale(lang),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: WebsitePurchaseScope(access: access, child: child),
  );
  test('access lease never revives after locking', () {
    final lease = access.lease();
    access.update(false);
    access.update(true);
    expect(lease(), isFalse);
  });
  testWidgets(
    'orders page has no automatic I/O and opens browser only on explicit tap',
    (tester) async {
      await tester.pumpWidget(
        host(WebsiteOrdersPage(controller: controller, access: access)),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 6));
      expect(browser.beginCalls, 0);
      await tester.runAsync(() async {
        await tester.tap(find.text('在浏览器中打开官网订单'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(
        browser.openCalls,
        1,
        reason:
            'begin=${browser.beginCalls} busy=${controller.isBusy} allowed=${access.allowed} texts=${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).join("|")}',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        browser.openCalls,
        1,
        reason:
            'begin=${browser.beginCalls} busy=${controller.isBusy} allowed=${access.allowed} texts=${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).join("|")}',
      );
    },
  );
  testWidgets('restricted view exposes no website order or recovery action', (
    tester,
  ) async {
    access.update(false);
    await tester.pumpWidget(host(FullVersionPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('website-orders-entry')), findsNothing);
    expect(find.byKey(const ValueKey('website-recovery-entry')), findsNothing);
    expect(browser.beginCalls, 0);
  });
  for (final managed in [true, false]) {
    testWidgets(
      'incoming request is one prompt and requires real managed unlock: $managed',
      (tester) async {
        const channel = MethodChannel('cardock/website_purchase_navigation');
        Map<String, Object?>? pending;
        final nativeCalls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'consumeOfflinePending') {
              final v = pending;
              pending = null;
              return v;
            }
            return false;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          WebsiteOfflineBrowser.channel,
          (call) async {
            nativeCalls.add(call.method);
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            WebsiteOfflineBrowser.channel,
            null,
          );
        });
        final vault = ValueNotifier(false);
        addTearDown(vault.dispose);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => WebsitePurchaseCoordinator(
              controller: controller,
              vaultChanges: vault,
              allowed: () => vault.value && managed,
              unlocked: () => vault.value,
              navigatorKey: navigator,
              child: child!,
            ),
            home: const Scaffold(body: Text('original unlock gate')),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> receive() async {
          pending = {
            'kind': 'request',
            'text': jsonEncode({'purpose': 'order_lookup', 'reference': ''}),
          };
          tester.binding.channelBuffers.push(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('pendingAvailable'),
            ),
            (_) {},
          );
          await tester.pumpAndSettle();
        }

        await receive();
        expect(find.byType(AlertDialog), findsNothing);
        expect(browser.beginCalls, 0);
        vault.value = true;
        await tester.pumpAndSettle();
        if (managed) {
          expect(find.byType(AlertDialog), findsOneWidget);
          await receive();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.runAsync(() async {
            await tester.tap(find.text('继续'));
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pumpAndSettle();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(
            browser.openCalls,
            1,
            reason:
                'begin=${browser.beginCalls} busy=${controller.isBusy} allowed=${access.allowed} texts=${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).join("|")}',
          );
        } else {
          expect(find.byType(AlertDialog), findsNothing);
          expect(browser.openCalls, 0);
          expect(nativeCalls, contains('clearOfflineRequest'));
        }
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(browser.openCalls, managed ? 1 : 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final lang in ['zh', 'en', 'ja']) {
    testWidgets('$lang narrow help fits', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          WebsiteOrdersPage(controller: controller, access: access),
          lang: lang,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(browser.beginCalls, 0);
    });
  }
  testWidgets(
    'clipboard is read only on tap and cannot overwrite typed input',
    (tester) async {
      int reads = 0;
      String copied = 'synthetic invalid authorization';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            reads++;
            return {'text': copied};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showWebsiteAuthorizationDialog(context, controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tester.enterText(find.byType(TextField), 'typed content');
      await tester.tap(find.text('粘贴'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.text('typed content'), findsOneWidget);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.text(copied), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
