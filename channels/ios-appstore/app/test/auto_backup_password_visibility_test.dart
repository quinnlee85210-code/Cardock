import 'package:account_subscription_manager/features/settings/presentation/data_safety_dialogs.dart';
import 'package:account_subscription_manager/features/settings/presentation/vault_health_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stage1_safety_ui_test.dart' show app, wrapper;

Widget inputHost({
  Locale locale = const Locale('zh', 'CN'),
  bool secret = true,
  bool allowVisibilityToggle = true,
  ValueChanged<String?>? onResult,
}) => wrapper(
  Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final result = await safetyInput(
            context,
            '自动备份独立密码',
            secret: secret,
            allowVisibilityToggle: allowVisibilityToggle,
          );
          onResult?.call(result);
        },
        child: const Text('OPEN'),
      ),
    ),
  ),
  locale,
);

Future<void> openInput(WidgetTester tester) async {
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

TextField input(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets(
      'visibility preserves input and localizes ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        String? result;
        await tester.pumpWidget(
          inputHost(locale: locale, onResult: (value) => result = value),
        );
        await openInput(tester);
        expect(input(tester).obscureText, true);
        expect(input(tester).enableIMEPersonalizedLearning, false);
        const text = ' TEST-ONLY-备份-1234 ';
        await tester.enterText(find.byType(TextField), text);
        final selection = input(tester).controller!.selection;
        final strings = AppLocalizations(locale);
        await tester.ensureVisible(find.byTooltip(strings.translate('显示密码')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(strings.translate('显示密码')));
        await tester.pumpAndSettle();
        expect(input(tester).obscureText, false);
        expect(input(tester).controller!.text, text);
        expect(input(tester).controller!.selection, selection);
        await tester.tap(find.byTooltip(strings.translate('隐藏密码')));
        await tester.pumpAndSettle();
        expect(input(tester).obscureText, true);
        await tester.tap(find.text(strings.translate('确认')));
        await tester.pumpAndSettle();
        expect(result, text);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('leaving foreground hides revealed password until explicit tap', (
    tester,
  ) async {
    await tester.pumpWidget(inputHost());
    await openInput(tester);
    await tester.enterText(find.byType(TextField), 'TEST-ONLY-background-1234');
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pumpAndSettle();
    expect(input(tester).obscureText, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(input(tester).obscureText, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(input(tester).obscureText, true);
    expect(input(tester).controller!.text, 'TEST-ONLY-background-1234');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and reopen clear input and reset visibility', (
    tester,
  ) async {
    String? result = 'uncompleted';
    await tester.pumpWidget(inputHost(onResult: (value) => result = value));
    await openInput(tester);
    await tester.enterText(find.byType(TextField), 'TEST-ONLY-cancel-1234');
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await openInput(tester);
    expect(input(tester).obscureText, true);
    expect(input(tester).controller!.text, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('other secret and plain confirmations retain existing behavior', (
    tester,
  ) async {
    await tester.pumpWidget(inputHost(allowVisibilityToggle: false));
    await openInput(tester);
    expect(input(tester).obscureText, true);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(inputHost(secret: false));
    await openInput(tester);
    expect(input(tester).obscureText, false);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backup setup reveals each entry but rejects mismatched passwords',
    (tester) async {
      const channel = MethodChannel('cardock/document_storage_v1');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'pickDirectory' ? 'TEST-ONLY-tree' : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final state = await app();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        wrapper(
          VaultHealthPage(
            appState: state,
            onManualBackup: () async {},
            onVerify: () async {},
            onRestore: () async {},
            onRecovery: () async {},
          ),
          const Locale('zh', 'CN'),
        ),
      );
      await tester.pumpAndSettle();
      final setup = find.text('选择或更换备份目录与密码');
      await tester.scrollUntilVisible(setup, 250);
      await tester.tap(setup);
      await tester.pumpAndSettle();
      expect(input(tester).obscureText, true);
      await tester.enterText(find.byType(TextField), 'TEST-ONLY-first-1234');
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(input(tester).obscureText, false);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(input(tester).obscureText, true);
      expect(input(tester).controller!.text, isEmpty);
      await tester.enterText(
        find.byType(TextField),
        'TEST-ONLY-different-1234',
      );
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(input(tester).obscureText, false);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(find.text('两次备份密码不一致。'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(state.autoBackup.status.enabled, false);
      expect(calls, ['pickDirectory']);
      expect(tester.takeException(), isNull);
    },
  );
}
