import 'package:account_subscription_manager/core/branding/brand_catalog.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/brand_catalog_fixture.dart';

Future<void> _revealAndTap(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    500,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey<String>('account-editor-page')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down &&
                widget.restorationId == null,
          ),
        )
        .first,
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  test('分类候选合并内置与现有自定义名称并去重', () {
    final options = accountCategoryOptions(<AccountRecord>[
      AccountRecord.fromDraft(
        id: 'account-1',
        draft: AccountDraft(platformName: '平台一', category: '币圈'),
      ),
      AccountRecord.fromDraft(
        id: 'account-2',
        draft: AccountDraft(platformName: '平台二', category: '币圈'),
      ),
      AccountRecord.fromDraft(
        id: 'account-3',
        draft: AccountDraft(platformName: '平台三', category: '保险'),
      ),
    ]);

    expect(options, <String>[...accountCategories, '币圈']);
    expect(options.where((category) => category == '保险'), hasLength(1));
  });

  testWidgets('新增账号可从下拉框直接选择默认保险分类', (tester) async {
    AccountEditorResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                captured = await Navigator.of(context)
                    .push<AccountEditorResult>(
                      MaterialPageRoute<AccountEditorResult>(
                        builder: (context) => const AccountEditorPage(),
                      ),
                    );
              },
              child: const Text('打开复用分类'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开复用分类'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('platform-name-field')),
      '新保险平台',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('account-category-field')),
    );
    await tester.pumpAndSettle();
    expect(find.text('保险'), findsOneWidget);
    await tester.tap(find.text('保险'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('custom-category-field')),
      findsNothing,
    );
    await _revealAndTap(
      tester,
      find.byKey(const ValueKey<String>('save-account-button')),
    );
    expect(captured?.account.category, '保险');
  });

  testWidgets('新增账号支持任意密码、中文字段和自定义分类', (tester) async {
    AccountEditorResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const ValueKey<String>('open-editor'),
              onPressed: () async {
                captured = await Navigator.of(context)
                    .push<AccountEditorResult>(
                      MaterialPageRoute<AccountEditorResult>(
                        builder: (context) => const AccountEditorPage(),
                      ),
                    );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open-editor')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('platform-name-field')),
      '中文平台',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('account-category-field')),
    );
    await tester.pumpAndSettle();
    final customCategoryOption = find.text('自定义分类…').last;
    await tester.ensureVisible(customCategoryOption);
    await tester.pumpAndSettle();
    await tester.tap(customCategoryOption);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('custom-category-field')),
      '学习课程',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('username-field')),
      '中文用户名',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-account-field')),
      '中文登录账号',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('password-field')),
      ' 密码🙂 中文 !@# ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('website-field')),
      'https://中文域名.cn/登录',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('notes-field')),
      '中文备注\n第二行🙂',
    );
    await _revealAndTap(
      tester,
      find.byKey(const ValueKey<String>('save-account-button')),
    );

    expect(captured, isNotNull);
    expect(captured!.account.category, '学习课程');
    expect(captured!.account.username, '中文用户名');
    expect(captured!.account.loginAccount, '中文登录账号');
    expect(captured!.account.password, ' 密码🙂 中文 !@# ');
    expect(captured!.account.website, 'https://中文域名.cn/登录');
    expect(captured!.account.notes, '中文备注\n第二行🙂');
    expect(captured!.passwordUpdateMode, AccountPasswordUpdateMode.replace);
  });

  testWidgets('编辑账号默认保留密码并支持明确替换和清除', (tester) async {
    final existing = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '原平台',
        category: '自定义旧分类',
        password: '原密码',
      ),
    );
    AccountEditorResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const ValueKey<String>('open-editor'),
              onPressed: () async {
                captured = await Navigator.of(context)
                    .push<AccountEditorResult>(
                      MaterialPageRoute<AccountEditorResult>(
                        builder: (context) =>
                            AccountEditorPage(existing: existing),
                      ),
                    );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('open-editor')));
    await tester.pumpAndSettle();
    expect(find.text('编辑账号'), findsOneWidget);
    expect(find.text('自定义旧分类'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('password-field')), findsNothing);
    await _revealAndTap(
      tester,
      find.byKey(const ValueKey<String>('save-account-button')),
    );
    expect(captured?.account.password, '原密码');
    expect(captured?.passwordUpdateMode, AccountPasswordUpdateMode.preserve);

    captured = null;
    await tester.tap(find.byKey(const ValueKey<String>('open-editor')));
    await tester.pumpAndSettle();
    await _revealAndTap(
      tester,
      find.byKey(const ValueKey<String>('password-update-mode-field')),
    );
    await tester.tap(find.text('替换密码').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('password-field')),
      '新密码中文🙂',
    );
    await _revealAndTap(
      tester,
      find.byKey(const ValueKey<String>('save-account-button')),
    );
    expect(captured?.account.password, '新密码中文🙂');
    expect(captured?.passwordUpdateMode, AccountPasswordUpdateMode.replace);

    captured = null;
    await tester.tap(find.byKey(const ValueKey<String>('open-editor')));
    await tester.pumpAndSettle();
    await _revealAndTap(
      tester,
      find.byKey(const ValueKey<String>('password-update-mode-field')),
    );
    await tester.tap(find.text('清除已保存密码').last);
    await tester.pumpAndSettle();
    await _revealAndTap(
      tester,
      find.byKey(const ValueKey<String>('save-account-button')),
    );
    expect(captured?.account.password, isNull);
    expect(captured?.passwordUpdateMode, AccountPasswordUpdateMode.clear);
  });

  testWidgets('160ms前不运行fuzzy，候选不自动替换且只有明确点选才保存canonical', (tester) async {
    final catalog = _brandCatalog();
    AccountEditorResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const ValueKey<String>('open-brand-editor'),
              onPressed: () async {
                captured = await Navigator.of(context)
                    .push<AccountEditorResult>(
                      MaterialPageRoute<AccountEditorResult>(
                        builder: (context) => AccountEditorPage(
                          brandCatalogFuture: Future.value(catalog),
                        ),
                      ),
                    );
              },
              child: const Text('打开品牌编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open-brand-editor')));
    await tester.pumpAndSettle();

    final platformField = find.byKey(
      const ValueKey<String>('platform-name-field'),
    );
    await tester.enterText(platformField, 'Aple');
    await tester.pump(const Duration(milliseconds: 159));
    expect(
      find.byKey(const ValueKey<String>('account-brand-suggestions')),
      findsNothing,
    );
    expect(
      tester.widget<TextFormField>(platformField).controller!.text,
      'Aple',
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    final suggestion = find.byKey(
      const ValueKey<String>('account-brand-suggestion-apple'),
    );
    expect(suggestion, findsOneWidget);
    expect(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('account-brand-suggestions')),
            matching: find.byType(ListTile),
          )
          .evaluate()
          .length,
      lessThanOrEqualTo(5),
    );
    expect(
      tester.widget<TextFormField>(platformField).controller!.text,
      'Aple',
    );

    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(platformField).controller!.text,
      'Apple',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('account-brand-preview-icon')),
        matching: find.byKey(const ValueKey<String>('brand-asset-apple')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('save-account-button')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.account.platformName, 'Apple');
  });

  testWidgets('320宽与200%字体下品牌预览和候选保持48dp且无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1200);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AccountEditorPage(
          brandCatalogFuture: Future.value(_brandCatalog()),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('platform-name-field')),
      'Aple',
    );
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('account-brand-preview-icon')),
      ),
      const Size(48, 48),
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('account-brand-suggestion-apple'),
            ),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
  });
}

CardockBrandCatalog _brandCatalog() => CardockBrandCatalog.fromJson(
  catalogFixture(<Map<String, Object?>>[
    brandFixture(
      brandId: 'apple',
      canonicalName: 'Apple',
      aliases: const <String>['Apple', '苹果'],
    ),
  ]),
);
