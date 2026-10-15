import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_editor_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

AccountRecord _account({
  required String id,
  required String platform,
  String? category,
  String? login,
  String? username,
}) => AccountRecord.fromDraft(
  id: id,
  draft: AccountDraft(
    platformName: platform,
    category: category,
    loginAccount: login,
    username: username,
  ),
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<AccountRecord> accounts,
  String? initialAccountId,
  Locale locale = const Locale('zh', 'CN'),
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    supportedLocales: const <Locale>[
      Locale('zh', 'CN'),
      Locale('en'),
      Locale('ja'),
    ],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: SubscriptionEditorPage(
      accounts: accounts,
      initialAccountId: initialAccountId,
    ),
  ),
);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('subscription-account-field')),
  );
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('subscription-account-picker-sheet')),
    findsOneWidget,
  );
}

void main() {
  testWidgets('关联账号按分类两阶段选择并保留独立订阅入口', (tester) async {
    final accounts = <AccountRecord>[
      _account(
        id: 'work-1',
        platform: '工作平台甲',
        category: 'Work',
        login: 'worker-a',
      ),
      _account(
        id: 'finance-1',
        platform: '财务平台',
        category: '金融',
        login: 'finance@example.test',
      ),
      _account(
        id: '__cardock_standalone__',
        platform: '工作平台乙',
        category: 'work',
        login: 'worker-b',
      ),
      _account(
        id: 'custom-unclassified',
        platform: '同名自定义分类平台',
        category: '未分类',
      ),
      _account(id: 'uncategorized-1', platform: '无分类平台'),
    ];
    await _pumpEditor(tester, accounts: accounts);

    expect(find.text('不关联账号 · 独立订阅'), findsOneWidget);
    await _openPicker(tester);

    expect(
      find.byKey(const ValueKey<String>('subscription-account-standalone')),
      findsOneWidget,
    );
    expect(find.text('金融'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('work'), findsNothing);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('“未分类”'), findsOneWidget);
    expect(find.text('财务平台'), findsNothing);
    expect(
      tester.getTopLeft(find.text('金融')).dy,
      lessThan(tester.getTopLeft(find.text('Work')).dy),
    );

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('工作平台甲'), findsOneWidget);
    expect(find.text('工作平台乙'), findsOneWidget);
    final firstTop = tester.getTopLeft(find.text('工作平台甲')).dy;
    final secondTop = tester.getTopLeft(find.text('工作平台乙')).dy;
    expect(firstTop, lessThan(secondTop));

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'subscription-account-option-__cardock_standalone__',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('工作平台乙 · worker-b'), findsOneWidget);

    await _openPicker(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-account-standalone')),
    );
    await tester.pumpAndSettle();
    expect(find.text('不关联账号 · 独立订阅'), findsOneWidget);
  });

  testWidgets('当前账号、用户名和未填写回退均不暴露内部 ID', (tester) async {
    final accounts = <AccountRecord>[
      _account(
        id: 'internal-username-id',
        platform: '用户名平台',
        category: '办公',
        username: 'visible-user',
      ),
      _account(id: 'internal-empty-id', platform: '空账号平台', category: '办公'),
    ];
    await _pumpEditor(
      tester,
      accounts: accounts,
      initialAccountId: 'internal-username-id',
    );

    expect(find.text('用户名平台 · visible-user'), findsOneWidget);
    expect(find.textContaining('internal-username-id'), findsNothing);
    await _openPicker(tester);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('subscription-account-category-category:办公'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('visible-user'), findsOneWidget);
    expect(find.text('未填写'), findsOneWidget);
    expect(find.textContaining('internal-empty-id'), findsNothing);
  });

  testWidgets('内置分类随语言本地化，自定义分类保持原文', (tester) async {
    await _pumpEditor(
      tester,
      locale: const Locale('en'),
      accounts: <AccountRecord>[
        _account(id: 'office', platform: 'Office App', category: '办公'),
        _account(id: 'custom', platform: 'Custom App', category: 'My Group'),
      ],
    );
    await _openPicker(tester);
    expect(find.text('Productivity'), findsOneWidget);
    expect(find.text('My Group'), findsOneWidget);
    expect(find.text('办公'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-account-picker-close')),
    );
    await tester.pumpAndSettle();

    await _pumpEditor(
      tester,
      locale: const Locale('ja'),
      accounts: <AccountRecord>[
        _account(id: 'office', platform: 'Office App', category: '办公'),
        _account(id: 'custom', platform: 'Custom App', category: 'My Group'),
      ],
    );
    await _openPicker(tester);
    expect(find.text('仕事効率化'), findsOneWidget);
    expect(find.text('My Group'), findsOneWidget);
    expect(find.text('办公'), findsNothing);
  });

  testWidgets('无账号时选择器仍保留独立订阅且没有空分类', (tester) async {
    await _pumpEditor(tester, accounts: const <AccountRecord>[]);
    await _openPicker(tester);
    expect(find.text('暂无账号记录'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('subscription-account-standalone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('subscription-account-list')),
      findsNothing,
    );
  });

  testWidgets('大字体小屏下分类和账号两层均可操作且无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await _pumpEditor(
      tester,
      accounts: List<AccountRecord>.generate(
        12,
        (index) => _account(
          id: 'scroll-$index',
          platform: '滚动平台$index',
          category: '自定义分类$index',
        ),
      ),
    );
    await _openPicker(tester);
    final lastCategory = find.text('自定义分类11');
    await tester.scrollUntilVisible(
      lastCategory,
      120,
      scrollable: find.descendant(
        of: find.byKey(
          const ValueKey<String>('subscription-account-category-list'),
        ),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('subscription-account-category-list')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(lastCategory);
    await tester.pumpAndSettle();
    expect(find.text('滚动平台11'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('subscription-account-category-back')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
