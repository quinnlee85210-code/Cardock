import 'package:account_subscription_manager/core/platform/safe_url_launcher.dart';
import 'package:account_subscription_manager/core/platform/sensitive_clipboard.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_details_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeClipboard implements SensitiveClipboard {
  final copied = <({String text, String label, Duration clearAfter})>[];

  @override
  Future<void> copySensitive({
    required String text,
    required String label,
    Duration clearAfter = const Duration(seconds: 60),
  }) async {
    copied.add((text: text, label: label, clearAfter: clearAfter));
  }
}

final class _FakeUrlLauncher implements ExternalUrlLauncher {
  String? opened;

  @override
  Future<bool> open(String input) async {
    opened = input;
    return true;
  }
}

AccountRecord _record({String platformName = '测试平台'}) {
  return AccountRecord.fromDraft(
    id: 'account-1',
    draft: AccountDraft(
      platformName: platformName,
      category: '自定义分类',
      username: '中文用户名',
      loginAccount: '中文登录账号',
      boundPhone: '13800000000',
      boundEmail: 'test@example.invalid',
      password: '敏感密码🙂',
      website: '中文域名.cn/登录',
      notes: '中文备注',
    ),
  );
}

SubscriptionRecord _subscription(String id, String serviceName) {
  return SubscriptionRecord.fromDraft(
    id: id,
    draft: SubscriptionDraft(
      accountId: 'account-1',
      details: SubscriptionDetailsDraft(
        serviceName: serviceName,
        firstSubscribedOn: DateTime(2026, 7, 1),
        nextRenewalOn: DateTime(2026, 8, 1),
      ),
    ),
  );
}

Future<void> _revealDetailsWidget(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    400,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey<String>('account-details-page')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('详情页默认隐藏密码，显示会超时隐藏，复制不在提示中回显', (tester) async {
    final clipboard = _FakeClipboard();
    final launcher = _FakeUrlLauncher();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailsPage(
          account: _record(),
          subscriptions: const [],
          sensitiveClipboard: clipboard,
          urlLauncher: launcher,
          passwordRevealDuration: const Duration(seconds: 1),
        ),
      ),
    );

    for (final section in <String>['基本资料', '联系绑定', '安全信息', '补充信息']) {
      expect(find.text(section), findsOneWidget);
    }
    expect(find.text('敏感密码🙂'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('toggle-detail-password')),
    );
    await tester.pump();
    expect(find.text('敏感密码🙂'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('敏感密码🙂'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('copy-account-用户名')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('copy-account-password')),
    );
    await tester.pump();
    expect(clipboard.copied.map((item) => item.label), ['用户名', '登录密码']);
    expect(clipboard.copied.last.clearAfter, const Duration(seconds: 60));
    expect(find.textContaining('敏感密码🙂'), findsNothing);

    final websiteAction = find.byKey(
      const ValueKey<String>('open-account-website'),
    );
    await tester.ensureVisible(websiteAction);
    await tester.pumpAndSettle();
    await tester.tap(websiteAction);
    await tester.pump();
    expect(launcher.opened, '中文域名.cn/登录');
  });

  testWidgets('编辑结果会刷新详情，删除只有二次确认后才回调', (tester) async {
    var deleteCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailsPage(
          account: _record(),
          subscriptions: const [],
          sensitiveClipboard: _FakeClipboard(),
          urlLauncher: _FakeUrlLauncher(),
          onEdit: (account) async => AccountRecord.fromDraft(
            id: account.id,
            draft: AccountDraft(
              platformName: '修改后的平台',
              password: account.password,
            ),
          ),
          onDelete: (account) async {
            deleteCalls += 1;
            return false;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('edit-account-action')));
    await tester.pumpAndSettle();
    expect(find.text('修改后的平台'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('delete-account-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('移入回收站？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('cancel-delete-account')),
    );
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('delete-account-action')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-delete-account')),
    );
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
    expect(find.text('删除失败，原记录仍保留。'), findsOneWidget);
  });

  testWidgets('新增订阅后通过 provider 实时刷新且删除确认使用最新数量', (tester) async {
    var subscriptions = <SubscriptionRecord>[];
    var deleteCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailsPage(
          account: _record(),
          subscriptions: const [],
          subscriptionsProvider: (account) => List.unmodifiable(subscriptions),
          sensitiveClipboard: _FakeClipboard(),
          urlLauncher: _FakeUrlLauncher(),
          onAddSubscription: (account) async {
            subscriptions = <SubscriptionRecord>[
              _subscription('subscription-1', '新增云服务'),
              _subscription('subscription-2', '新增影音会员'),
            ];
          },
          onDelete: (account) async {
            deleteCalls += 1;
            return false;
          },
        ),
      ),
    );

    expect(find.text('订阅记录（0）'), findsOneWidget);
    expect(find.text('这个账号暂无订阅记录。'), findsOneWidget);

    final addSubscription = find.byKey(
      const ValueKey<String>('add-subscription-for-account'),
    );
    await _revealDetailsWidget(tester, addSubscription);
    await tester.tap(addSubscription);
    await tester.pumpAndSettle();

    expect(find.text('订阅记录（2）'), findsOneWidget);
    expect(find.text('这个账号暂无订阅记录。'), findsNothing);
    expect(find.text('新增云服务'), findsOneWidget);
    expect(find.text('新增影音会员'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('delete-account-action')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('这个账号关联了2项订阅，将一起移入回收站保留 30 天。历史费用保留；这不会在对应平台取消订阅或停止扣费。'),
      findsOneWidget,
    );
    expect(deleteCalls, 0);
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-delete-account')),
    );
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
  });
}
