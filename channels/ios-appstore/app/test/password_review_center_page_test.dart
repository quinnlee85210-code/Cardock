import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/password_review_center_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('分类默认收起，显示数量且各分类可独立展开收起', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final records = ChangeNotifier();
    addTearDown(records.dispose);
    final accounts = [
      _account('cloud-a', category: '云服务', changes: 2),
      _account('cloud-b', category: '云服务'),
      _account('mail', category: '邮箱', changes: 1),
    ];
    await _pumpHistory(tester, records, () => accounts);
    expect(find.byType(PasswordChangeHistoryCard), findsNothing);
    expect(find.text('共2个账号 · 2次变更'), findsOneWidget);
    expect(find.text('共1个账号 · 1次变更'), findsOneWidget);
    await _toggleCategory(tester, '云服务');
    expect(find.text('platform-cloud-a'), findsOneWidget);
    expect(find.text('platform-cloud-b'), findsOneWidget);
    expect(find.text('platform-mail'), findsNothing);
    expect(find.text('首次录入不计次，尚未记录后续变更。'), findsOneWidget);
    await _toggleCategory(tester, '邮箱');
    expect(find.text('platform-cloud-a'), findsOneWidget);
    expect(find.text('platform-mail'), findsOneWidget);
    await _toggleCategory(tester, '云服务');
    expect(find.text('platform-cloud-a'), findsNothing);
    expect(find.text('platform-cloud-b'), findsNothing);
    expect(find.text('platform-mail'), findsOneWidget);
    await _toggleCategory(tester, '云服务');
    expect(find.text('platform-cloud-a'), findsOneWidget);
    expect(find.text('TEST-HIDDEN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类归一化与未分类保持一致，清空密码后仍可查看日期历史', (tester) async {
    final records = ChangeNotifier();
    addTearDown(records.dispose);
    final accounts = [
      _account('first', category: ' Work ', changes: 1),
      _account('second', category: 'work', changes: 2, saved: false),
      _account('uncategorized', changes: 1),
      _account('no-password', saved: false),
    ];
    await _pumpHistory(tester, records, () => accounts);
    expect(find.byType(ExpansionTile), findsNWidgets(2));
    expect(find.text('共2个账号 · 3次变更'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
    await _toggleCategory(tester, 'work');
    expect(find.text('platform-first'), findsOneWidget);
    expect(find.text('platform-second'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('view-password-history-second')),
      findsOneWidget,
    );
    expect(find.text('platform-no-password'), findsNothing);
    expect(accounts[0].passwordChangeHistory.length, 1);
    expect(accounts[1].password, isNull);
    expect(accounts[1].passwordChangeHistory.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据刷新与分类重排保留展开选择，日期和数量同步刷新', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final records = ChangeNotifier();
    addTearDown(records.dispose);
    var accounts = [
      _account('work', category: 'Work', changes: 1),
      _account('cloud', category: '云服务'),
    ];
    await _pumpHistory(tester, records, () => accounts);
    await _toggleCategory(tester, 'work');
    accounts = [
      accounts[1],
      _account('work', category: 'work', changes: 2),
      _account('new', category: 'WORK'),
    ];
    records.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('platform-work'), findsOneWidget);
    expect(find.text('platform-new'), findsOneWidget);
    expect(find.text('platform-cloud'), findsNothing);
    expect(find.text('共2个账号 · 2次变更'), findsOneWidget);
    expect(find.textContaining('2026年9月3日'), findsOneWidget);
    accounts = [];
    records.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('暂无密码变更记录'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(PasswordChangeHistoryCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets('自动密码记录显示分类账号与日期，无复核操作；小屏大字 $locale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records = ChangeNotifier();
      addTearDown(records.dispose);
      var accounts = [
        AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(
            platformName: '测试平台',
            category: 'Work',
            loginAccount: 'alpha@example.invalid',
            password: 'TEST-HIDDEN',
          ),
          passwordChangeHistory: [
            PasswordChangeRecord(
              changedAtUtc: DateTime.utc(2026, 9, 3, 12),
              previousStoredAtUtc: DateTime.utc(2026, 9, 1, 12),
            ),
          ],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: PasswordChangeHistoryPage(
            recordsListenable: records,
            accountsProvider: () => accounts,
            nowUtc: () => DateTime.utc(2026, 9, 4, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PasswordChangeHistoryCard), findsNothing);
      await _toggleCategory(tester, 'work');
      final history = find.byKey(
        const ValueKey('view-password-history-account-1'),
      );
      await tester.scrollUntilVisible(history, 220);
      await tester.pumpAndSettle();
      await tester.ensureVisible(history);
      await tester.pumpAndSettle();
      expect(find.text('alpha@example.invalid'), findsOneWidget);
      expect(find.text('TEST-HIDDEN'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(history);
      await tester.pumpAndSettle();
      expect(find.textContaining('2026'), findsWidgets);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byIcon(Icons.close))).pop();
      await tester.pumpAndSettle();
      accounts = [];
      records.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('alpha@example.invalid'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

AccountRecord _account(
  String id, {
  String? category,
  int changes = 0,
  bool saved = true,
}) => AccountRecord.fromDraft(
  id: id,
  draft: AccountDraft(
    platformName: 'platform-$id',
    category: category,
    loginAccount: '$id@example.invalid',
    password: saved ? 'TEST-HIDDEN' : null,
  ),
  passwordChangeHistory: [
    for (var i = 0; i < changes; i++)
      PasswordChangeRecord(
        changedAtUtc: DateTime.utc(2026, 9, 2 + i, 12),
        previousStoredAtUtc: DateTime.utc(2026, 9, 1 + i, 12),
      ),
  ],
);

Future<void> _pumpHistory(
  WidgetTester tester,
  Listenable records,
  List<AccountRecord> Function() accounts,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: PasswordChangeHistoryPage(
        recordsListenable: records,
        accountsProvider: accounts,
        nowUtc: () => DateTime.utc(2026, 9, 4, 12),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _toggleCategory(WidgetTester tester, String category) async {
  final tile = find.byKey(
    PageStorageKey('password-history-category-$category'),
  );
  await tester.scrollUntilVisible(tile, 180);
  await tester.pumpAndSettle();
  final header = find
      .descendant(of: tile, matching: find.byType(ListTile))
      .first;
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  await tester.tap(header);
  await tester.pumpAndSettle();
}
