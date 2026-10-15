import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

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

Future<void> _enterSubscriptionField(
  WidgetTester tester,
  String key,
  String value, {
  double scrollDelta = 300,
}) async {
  final field = find.byKey(ValueKey<String>(key));
  await _revealSubscriptionWidget(tester, field, scrollDelta: scrollDelta);
  await tester.enterText(field, value);
}

Future<void> _revealSubscriptionWidget(
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
        of: find.byKey(const ValueKey<String>('subscription-editor-page')),
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

Future<void> _dismissTestKeyboard(WidgetTester tester) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'subscription toolbar opens both finance tabs and attention without top shortcuts',
    (tester) async {
      await _pumpUnlockedApp(tester);
      await tester.tap(find.byKey(const ValueKey('nav-subscriptions')));
      await tester.pumpAndSettle();
      expect(find.text('费用洞察'), findsNothing);
      expect(find.text('待处理中心'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('open-subscription-cost-stats')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subscription-finance-page')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('finance-insights-tab')));
      await tester.pumpAndSettle();
      expect(find.text('当前有效订阅月等效费用'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('open-subscription-attention')),
      );
      await tester.pumpAndSettle();
      expect(find.text('订阅待处理中心'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> unlockAgain(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey('unlock-vault-button')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'partial account including password survives a phone interruption without saving a record',
    (tester) async {
      final store = await _pumpUnlockedApp(tester);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await _openAccountEditor(tester);
      await _enterField(tester, 'platform-name-field', 'TEST-ONLY-UNFINISHED');
      await _enterField(tester, 'password-field', 'TEST-ONLY-PARTIAL');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(const ValueKey('privacy-shield')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await unlockAgain(tester);
      expect(find.byKey(const ValueKey('account-editor-page')), findsOneWidget);
      await _revealEditorWidget(
        tester,
        find.byKey(const ValueKey('platform-name-field')),
        scrollDelta: -300,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('platform-name-field')),
            )
            .controller!
            .text,
        'TEST-ONLY-UNFINISHED',
      );
      await _revealEditorWidget(
        tester,
        find.byKey(const ValueKey('password-field')),
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('password-field')))
            .controller!
            .text,
        'TEST-ONLY-PARTIAL',
      );
      expect(store.snapshot.accounts, isEmpty);
    },
  );

  testWidgets(
    'partial subscription survives app recreation and cancel prevents reopening',
    (tester) async {
      final store = await _pumpUnlockedApp(tester);
      await tester.tap(find.byKey(const ValueKey('nav-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-add-subscription')));
      await tester.pumpAndSettle();
      await _enterSubscriptionField(
        tester,
        'subscription-service-name',
        'TEST-ONLY-DMIT',
      );
      await _enterSubscriptionField(tester, 'subscription-amount', '10.');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
      await tester.pumpAndSettle();
      await unlockAgain(tester);
      expect(
        find.byKey(const ValueKey('subscription-editor-page')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('subscription-service-name')),
            )
            .controller!
            .text,
        'TEST-ONLY-DMIT',
      );
      await _revealSubscriptionWidget(
        tester,
        find.byKey(const ValueKey('subscription-amount')),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('subscription-amount')),
            )
            .controller!
            .text,
        '10.',
      );
      expect(store.snapshot.subscriptions, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(store.editorDraft, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
      await tester.pumpAndSettle();
      await unlockAgain(tester);
      expect(
        find.byKey(const ValueKey('subscription-editor-page')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    },
  );

  testWidgets('首次设置主密码并可手动锁定和重新解锁', (tester) async {
    final store = FakeVaultStore();
    await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
    await tester.pumpAndSettle();

    final passwordField = find.byKey(
      const ValueKey<String>('master-password-field'),
    );
    final confirmationField = find.byKey(
      const ValueKey<String>('master-password-confirmation-field'),
    );
    final createButton = find.byKey(
      const ValueKey<String>('create-vault-button'),
    );
    expect(find.textContaining('16–128个字符'), findsNWidgets(2));
    expect(find.textContaining('大小写字母、数字和符号'), findsNWidgets(2));
    final secureInput = tester.widget<EditableText>(
      find.descendant(of: passwordField, matching: find.byType(EditableText)),
    );
    expect(secureInput.autocorrect, isFalse);
    expect(secureInput.enableSuggestions, isFalse);
    expect(secureInput.enableIMEPersonalizedLearning, isFalse);

    await tester.enterText(passwordField, 'short');
    await tester.enterText(confirmationField, 'short');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pump();
    expect(find.text('请输入16到128个字符的密码'), findsNWidgets(2));

    await tester.enterText(passwordField, _testMasterPassword);
    await tester.enterText(confirmationField, 'TEST-ONLY-DIFFERENT-1234');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pump();
    expect(find.text('两次输入的主密码不一致，请重新输入。'), findsOneWidget);

    await tester.enterText(passwordField, _testMasterPassword);
    await tester.enterText(confirmationField, _testMasterPassword);
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
    await tester.pumpAndSettle();
    final lockAction = find.descendant(
      of: find.byKey(const ValueKey<String>('settings-page')),
      matching: find.widgetWithText(ListTile, '立即锁定'),
    );
    expect(lockAction, findsOneWidget);
    await tester.ensureVisible(lockAction);
    await tester.pumpAndSettle();
    await tester.tap(lockAction);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-unlock-page')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      'TEST-ONLY-WRONG-1234',
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('还可尝试9次'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);
  });

  testWidgets('从旧一代恢复后显示数据回退警告', (tester) async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      recoveredFromFallback: true,
    );
    await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('vault-recovery-warning')),
      findsOneWidget,
    );
    expect(find.text('已从上一份有效数据恢复，最近一次更改可能未保留。'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-recovery-warning')),
      findsNothing,
    );
  });

  testWidgets('底栏按首页账号加号订阅设置排列并可切换四个主页面', (tester) async {
    await _pumpUnlockedApp(tester);

    expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);
    for (final name in [
      'home',
      'accounts',
      'add',
      'subscriptions',
      'settings',
    ]) {
      expect(find.byKey(ValueKey<String>('nav-$name')), findsOneWidget);
    }
    final navigationCenters = [
      for (final name in [
        'home',
        'accounts',
        'add',
        'subscriptions',
        'settings',
      ])
        tester.getCenter(find.byKey(ValueKey<String>('nav-$name'))).dx,
    ];
    expect(navigationCenters, orderedEquals([...navigationCenters]..sort()));
    final dockBody = tester.getRect(
      find.byKey(const ValueKey<String>('cardock-bottom-dock-body')),
    );
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(dockBody.left, closeTo(16, 0.1));
    expect(dockBody.right, closeTo(logicalWidth - 16, 0.1));
    expect(dockBody.height, closeTo(62, 0.1));
    final dockPaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('cardock-bottom-dock-body')),
    );
    expect(dockPaint.painter, isNotNull);
    final quickAdd = tester.getRect(
      find.byKey(const ValueKey<String>('cardock-bottom-dock-add-button')),
    );
    expect(quickAdd.size, const Size.square(52));
    expect(quickAdd.top, closeTo(dockBody.top - 14, 0.1));
    for (final name in ['home', 'accounts', 'subscriptions', 'settings']) {
      final hotArea = tester.getSize(find.byKey(ValueKey<String>('nav-$name')));
      expect(hotArea.width, greaterThanOrEqualTo(48));
      expect(hotArea.height, greaterThanOrEqualTo(48));
    }

    await tester.tap(find.byKey(const ValueKey<String>('nav-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('quick-add-account')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('quick-add-subscription')),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('nav-accounts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('accounts-page')), findsOneWidget);

    final searchField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('account-search')),
    );
    expect(searchField.autocorrect, isFalse);
    expect(searchField.enableSuggestions, isTrue);
    expect(searchField.enableIMEPersonalizedLearning, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('account-search')),
      '保留搜索状态',
    );
    await tester.tap(find.byKey(const ValueKey<String>('nav-subscriptions')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('subscriptions-page')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('settings-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('nav-accounts')));
    await tester.pumpAndSettle();
    expect(find.text('保留搜索状态'), findsOneWidget);
  });

  testWidgets('新增表单校验必填项并写入加密仓库', (tester) async {
    await _pumpUnlockedApp(tester);
    await _openAccountEditor(tester);

    final passwordField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('password-field')),
    );
    final passwordInput = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('password-field')),
        matching: find.byType(EditableText),
      ),
    );
    final loginInput = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('login-account-field')),
        matching: find.byType(EditableText),
      ),
    );
    final usernameInput = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('username-field')),
        matching: find.byType(EditableText),
      ),
    );
    final websiteInput = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('website-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(passwordField.enabled, isTrue);
    expect(passwordInput.obscureText, isTrue);
    expect(loginInput.keyboardType, TextInputType.text);
    expect(loginInput.autocorrect, isFalse);
    expect(loginInput.enableSuggestions, isTrue);
    expect(loginInput.enableIMEPersonalizedLearning, isFalse);
    expect(usernameInput.keyboardType, TextInputType.text);
    expect(usernameInput.autocorrect, isFalse);
    expect(usernameInput.enableSuggestions, isTrue);
    expect(usernameInput.enableIMEPersonalizedLearning, isFalse);
    expect(websiteInput.keyboardType, TextInputType.text);
    expect(websiteInput.autocorrect, isFalse);
    expect(websiteInput.enableSuggestions, isTrue);
    expect(websiteInput.enableIMEPersonalizedLearning, isFalse);

    final notesField = find.byKey(const ValueKey<String>('notes-field'));
    await _revealEditorWidget(tester, notesField);
    final notesInput = tester.widget<EditableText>(
      find.descendant(of: notesField, matching: find.byType(EditableText)),
    );
    expect(notesInput.keyboardType, TextInputType.multiline);
    expect(notesInput.autocorrect, isTrue);
    expect(notesInput.enableSuggestions, isTrue);
    expect(notesInput.enableIMEPersonalizedLearning, isTrue);

    final saveButton = find.byKey(
      const ValueKey<String>('save-account-button'),
    );
    tester.binding.focusManager.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await _revealEditorWidget(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    expect(find.text('请输入平台或应用名称'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('account-editor-page')),
      findsOneWidget,
    );

    const platform = '测试平台';
    const usernameSentinel = '中文用户名_青山';
    const loginSentinel = '中文账号_甲-001';
    const phoneSentinel = 'TEST-ONLY-PHONE';
    const emailSentinel = 'test-only@example.invalid';
    const websiteSentinel = 'https://中文域名.测试/登录入口';
    const notesSentinel = '中文备注：空格/标点/emoji🙂/@#￥%\n第二行';

    await _enterField(
      tester,
      'platform-name-field',
      '  $platform  ',
      scrollDelta: -300,
    );
    await _enterField(tester, 'username-field', usernameSentinel);
    await _enterField(tester, 'login-account-field', loginSentinel);
    await _enterField(tester, 'bound-phone-field', phoneSentinel);
    await _enterField(tester, 'bound-email-field', emailSentinel);
    await _enterField(tester, 'website-field', websiteSentinel);
    await _enterField(tester, 'notes-field', notesSentinel);
    await _revealEditorWidget(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('accounts-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsOneWidget,
    );
    expect(find.text(platform), findsOneWidget);
    for (final hiddenValue in [
      usernameSentinel,
      loginSentinel,
      phoneSentinel,
      emailSentinel,
      websiteSentinel,
      notesSentinel,
    ]) {
      expect(find.text(hiddenValue), findsNothing);
    }
    expect(find.text('用户名：已填写'), findsOneWidget);
    expect(find.text('登录账号：已填写'), findsOneWidget);
    expect(find.text('绑定手机号：已填写'), findsOneWidget);
    expect(find.text('绑定邮箱：已填写'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('account-search')),
      '青山',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('account-search')),
      '中文域名.测试',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('account-search')),
      '中文备注',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('nav-home')));
    await tester.pumpAndSettle();
    expect(find.text('1个账号 · 0个订阅'), findsOneWidget);
  });

  testWidgets('新增账号时可一起新增首条订阅', (tester) async {
    await _pumpUnlockedApp(tester);
    await _openAccountEditor(tester);

    await _enterField(tester, 'platform-name-field', '首日注册平台');
    await _enterField(tester, 'login-account-field', '中文首日账号');
    await _dismissTestKeyboard(tester);
    await _revealEditorWidget(
      tester,
      find.byKey(const ValueKey<String>('account-has-subscription')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('account-has-subscription')),
    );
    await tester.pumpAndSettle();

    await _enterField(tester, 'initial-subscription-service-name', '首日高级会员');
    await _enterField(tester, 'initial-subscription-plan-name', '家庭季度版');
    await _enterField(tester, 'initial-subscription-amount', '88.8');
    await _dismissTestKeyboard(tester);

    final cycleField = find.byKey(
      const ValueKey<String>('initial-subscription-cycle-preset'),
    );
    await _revealEditorWidget(tester, cycleField);
    await tester.tap(cycleField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('每季度').last);
    await tester.pumpAndSettle();

    final autoRenew = find.byKey(
      const ValueKey<String>('initial-subscription-auto-renew'),
    );
    await _revealEditorWidget(tester, autoRenew);
    expect(tester.widget<SwitchListTile>(autoRenew).value, isTrue);
    await tester.tap(autoRenew);
    await tester.pumpAndSettle();

    final saveAccount = find.byKey(
      const ValueKey<String>('save-account-button'),
    );
    await _revealEditorWidget(tester, saveAccount);
    await tester.tap(saveAccount);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('accounts-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('nav-subscriptions')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('subscription-card-subscription-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-card-subscription-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('subscription-details-page')),
      findsOneWidget,
    );
    expect(find.text('首日高级会员'), findsOneWidget);
    expect(find.text('首日注册平台'), findsOneWidget);
    expect(find.text('家庭季度版'), findsOneWidget);
    expect(find.text('周期：'), findsOneWidget);
    expect(find.text('每3个月'), findsNWidgets(2));
    expect(find.text('自动续费：'), findsOneWidget);
    expect(find.text('否'), findsOneWidget);
    expect(find.text('金额：'), findsOneWidget);
    expect(find.text('CNY 88.8'), findsNWidgets(2));
    expect(find.text('首次订阅：'), findsOneWidget);
    expect(find.text('下次续费：'), findsOneWidget);
  });

  testWidgets('已有账号可从订阅页补录订阅并再次编辑', (tester) async {
    await _pumpUnlockedApp(tester);
    await _openAccountEditor(tester);
    await _enterField(tester, 'platform-name-field', '两周后订阅平台');
    await _enterField(tester, 'login-account-field', '中文后订阅账号');
    await _dismissTestKeyboard(tester);

    final saveAccount = find.byKey(
      const ValueKey<String>('save-account-button'),
    );
    await _revealEditorWidget(tester, saveAccount);
    await tester.tap(saveAccount);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('nav-subscriptions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('nav-add')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('quick-add-subscription')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('subscription-editor-page')),
      findsOneWidget,
    );
    expect(find.text('不关联账号 · 独立订阅'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-account-field')),
    );
    await tester.pumpAndSettle();
    expect(find.text('两周后订阅平台'), findsNothing);
    await tester.tap(find.text('未分类'));
    await tester.pumpAndSettle();
    expect(find.text('两周后订阅平台'), findsOneWidget);
    expect(find.text('中文后订阅账号'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('subscription-account-option-account-1'),
      ),
    );
    await tester.pumpAndSettle();

    await _enterSubscriptionField(tester, 'subscription-service-name', '后补云服务');
    await _enterSubscriptionField(tester, 'subscription-plan-name', '月度个人版');
    await _dismissTestKeyboard(tester);

    final saveSubscription = find.byKey(
      const ValueKey<String>('save-subscription-button'),
    );
    await _revealSubscriptionWidget(tester, saveSubscription);
    await tester.tap(saveSubscription);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subscription-card-subscription-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-card-subscription-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('后补云服务'), findsOneWidget);
    expect(find.text('月度个人版'), findsOneWidget);
    expect(find.text('周期：'), findsOneWidget);
    expect(find.text('每月'), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('edit-subscription-subscription-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑订阅'), findsOneWidget);

    await _enterSubscriptionField(
      tester,
      'subscription-service-name',
      '后补云服务专业版',
    );
    await _enterSubscriptionField(tester, 'subscription-plan-name', '家庭年度版');
    await _dismissTestKeyboard(tester);
    final autoRenew = find.byKey(
      const ValueKey<String>('subscription-auto-renew'),
    );
    await _revealSubscriptionWidget(tester, autoRenew);
    await tester.tap(autoRenew);
    await tester.pumpAndSettle();

    await _revealSubscriptionWidget(tester, saveSubscription);
    await tester.tap(saveSubscription);
    await tester.pumpAndSettle();

    expect(find.text('后补云服务'), findsNothing);
    expect(find.text('后补云服务专业版'), findsOneWidget);
    expect(find.text('家庭年度版'), findsOneWidget);
    expect(find.text('自动续费：'), findsOneWidget);
    expect(find.text('否'), findsOneWidget);
    expect(find.text('订阅修改已加密保存。'), findsOneWidget);
  });

  testWidgets('取消新增不会建立账号记录', (tester) async {
    await _pumpUnlockedApp(tester);
    await _openAccountEditor(tester);

    await _enterField(tester, 'platform-name-field', 'TEST-ONLY-CANCELLED');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('nav-accounts')));
    await tester.pumpAndSettle();

    expect(find.text('暂无账号记录'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsNothing,
    );
  });

  testWidgets('账号页空状态按钮可打开新增表单', (tester) async {
    await _pumpUnlockedApp(tester);
    await tester.tap(find.byKey(const ValueKey<String>('nav-accounts')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('empty-add-account')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('account-editor-page')),
      findsOneWidget,
    );
  });

  testWidgets('从非首页返回时先回到首页', (tester) async {
    await _pumpUnlockedApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('settings-page')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);
  });

  testWidgets('窄屏显示四页空壳时不发生布局异常', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpUnlockedApp(tester);
    for (final name in ['accounts', 'subscriptions', 'settings', 'home']) {
      await tester.tap(find.byKey(ValueKey<String>('nav-$name')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await _openAccountEditor(tester);
    final saveButton = find.byKey(
      const ValueKey<String>('save-account-button'),
    );
    await _revealEditorWidget(tester, saveButton);
    expect(tester.takeException(), isNull);
  });

  testWidgets('进入后台会遮盖并锁定，重新解锁后从加密仓库恢复记录', (tester) async {
    await _pumpUnlockedApp(tester);
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    await _openAccountEditor(tester);
    await _enterField(
      tester,
      'platform-name-field',
      'TEST-ONLY-LIFECYCLE-PLATFORM',
    );
    tester.binding.focusManager.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final saveButton = find.byKey(
      const ValueKey<String>('save-account-button'),
    );
    await _revealEditorWidget(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('TEST-ONLY-LIFECYCLE-PLATFORM'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('privacy-shield')),
      findsOneWidget,
    );
    expect(find.text('TEST-ONLY-LIFECYCLE-PLATFORM'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-unlock-page')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('privacy-shield')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('nav-accounts')));
    await tester.pumpAndSettle();
    expect(find.text('TEST-ONLY-LIFECYCLE-PLATFORM'), findsOneWidget);
  });
}
