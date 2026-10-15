import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';
import 'stage3_account_analysis_test.dart' show account, vault;

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

Future<FakeVaultStore> _pumpUnlockedApp(WidgetTester tester) async {
  final store = FakeVaultStore();
  await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('vault-setup-page')),
    findsOneWidget,
  );

  await tester.enterText(
    find.byKey(const ValueKey<String>('master-password-field')),
    _testMasterPassword,
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('master-password-confirmation-field')),
    _testMasterPassword,
  );
  final createButton = find.byKey(
    const ValueKey<String>('create-vault-button'),
  );
  await tester.ensureVisible(createButton);
  await tester.pumpAndSettle();
  await tester.tap(createButton);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);
  return store;
}

Future<void> _openAccountEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('nav-add')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey<String>('quick-add-sheet')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey<String>('quick-add-account')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('account-editor-page')),
    findsOneWidget,
  );
}

Future<void> _enterField(
  WidgetTester tester,
  String key,
  String value, {
  double scrollDelta = 300,
}) async {
  final field = find.byKey(ValueKey<String>(key));
  await _revealEditorWidget(tester, field, scrollDelta: scrollDelta);
  await tester.enterText(field, value);
}

Future<void> _revealEditorWidget(
  WidgetTester tester,
  Finder target, {
  double scrollDelta = 300,
}) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      scrollDelta,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('account-editor-page')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down &&
              widget.restorationId == null,
        ),
      ),
    );
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

Future<void> saveStage3Form(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('save-account-button'));
  await _revealEditorWidget(tester, save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'manual duplicate revise preserves draft, explicit approval writes exactly once',
    (tester) async {
      final store = await _pumpUnlockedApp(tester);
      await _openAccountEditor(tester);
      await _enterField(tester, 'platform-name-field', 'Fictional Stage3');
      await _enterField(tester, 'login-account-field', 'fictional-user');
      await saveStage3Form(tester);
      expect(store.snapshot.accounts, hasLength(1));
      await _openAccountEditor(tester);
      await _enterField(tester, 'platform-name-field', 'Fictional Stage3');
      await _enterField(tester, 'login-account-field', 'fictional-user');
      await _enterField(tester, 'password-field', 'SYNTHETIC-NEW-DRAFT#9');
      final saves = store.saveCalls;
      await saveStage3Form(tester);
      expect(
        find.byKey(const ValueKey('duplicate-return-edit')),
        findsOneWidget,
      );
      expect(store.saveCalls, saves);
      await tester.tap(find.byKey(const ValueKey('duplicate-return-edit')));
      await tester.pumpAndSettle();
      await _revealEditorWidget(
        tester,
        find.byKey(const ValueKey('password-field')),
        scrollDelta: -300,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('password-field')))
            .controller!
            .text,
        'SYNTHETIC-NEW-DRAFT#9',
      );
      await saveStage3Form(tester);
      await tester.tap(find.byKey(const ValueKey('duplicate-add-anyway')));
      await tester.pumpAndSettle();
      expect(store.snapshot.accounts, hasLength(2));
      expect(store.saveCalls, saves + 1);
      expect(store.snapshot.accounts.last.passwordChangeHistory, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed add keeps editor, values, generation and retry intact', (
    tester,
  ) async {
    final store = await _pumpUnlockedApp(tester);
    await _openAccountEditor(tester);
    await _enterField(tester, 'platform-name-field', 'Fictional Failed Save');
    await _enterField(tester, 'password-field', 'SYNTHETIC-DRAFT#2');
    store.failSaves = true;
    await saveStage3Form(tester);
    expect(find.byKey(const ValueKey('account-editor-page')), findsOneWidget);
    expect(store.snapshot.accounts, isEmpty);
    await _revealEditorWidget(
      tester,
      find.byKey(const ValueKey('password-field')),
      scrollDelta: -300,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('password-field')))
          .controller!
          .text,
      'SYNTHETIC-DRAFT#2',
    );
    store.failSaves = false;
    await saveStage3Form(tester);
    expect(store.snapshot.accounts, hasLength(1));
    expect(store.snapshot.accounts.single.passwordChangeHistory, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'account toolbar health and binding navigation is connected and query-only',
    (tester) async {
      final store = FakeVaultStore(
        configured: true,
        acceptedPassword: _testMasterPassword,
        snapshot: vault([
          account(1, password: 'SYNTHETIC-REUSE#3', phone: '+86 13800000000'),
          account(
            2,
            password: 'SYNTHETIC-REUSE#3',
            platform: 'Other Stage3',
            phone: '+86 13800000000',
          ),
        ]),
      );
      await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('unlock-master-password-field')),
        _testMasterPassword,
      );
      await tester.tap(find.byKey(const ValueKey('unlock-vault-button')));
      await tester.pumpAndSettle();
      final saves = store.saveCalls;
      await tester.tap(find.byKey(const ValueKey('nav-accounts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-tools-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('密码健康').last);
      await tester.pumpAndSettle();
      expect(find.text('密码健康'), findsWidgets);
      expect(store.saveCalls, saves);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-tools-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('绑定资料').last);
      await tester.pumpAndSettle();
      expect(find.text('绑定资料中心'), findsWidgets);
      expect(store.saveCalls, saves);
      expect(tester.takeException(), isNull);
    },
  );
}
