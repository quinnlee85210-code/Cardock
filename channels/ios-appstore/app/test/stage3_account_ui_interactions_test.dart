import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_analysis.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_custom_fields_editor.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_duplicate_dialog.dart';
import 'package:account_subscription_manager/features/accounts/presentation/accounts_page.dart';
import 'package:account_subscription_manager/features/accounts/presentation/binding_center_page.dart';
import 'package:account_subscription_manager/features/accounts/presentation/password_health_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stage3_account_ui_test.dart' show host, account, analysisFor, reveal;

void main() {
  testWidgets(
    'health ignores one concrete issue and restores its prompt without displaying passwords',
    (tester) async {
      final records = [account(1, password: 'abc')];
      final changes = ChangeNotifier();
      addTearDown(changes.dispose);
      var analysis = analysisFor(records);
      PasswordHealthFinding? ignored;
      void rebuild() {
        analysis = AccountAnalysisSnapshot.fromSnapshot(
          VaultSnapshot(
            nextAccountId: 2,
            accounts: records,
            nextSubscriptionId: 1,
            subscriptions: const [],
            passwordHealthIgnoreRules: ignored == null
                ? []
                : [ignored!.toIgnoreRule()],
          ),
        );
        changes.notifyListeners();
      }

      await tester.pumpWidget(
        host(
          PasswordHealthCenterPage(
            analysisProvider: () => analysis,
            accountsProvider: () => records,
            changes: changes,
            onIgnore: (f) async {
              ignored = f;
              rebuild();
              return true;
            },
            onRestore: (f) async {
              ignored = null;
              rebuild();
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final issue = find.byKey(
        const ValueKey('health-account-1-shortPassword'),
      );
      await reveal(tester, issue);
      await tester.tap(issue);
      await tester.pumpAndSettle();
      expect(ignored?.issueType, 'shortPassword');
      expect(find.text('abc'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('show-ignored-health')),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('show-ignored-health')));
      await tester.pumpAndSettle();
      await reveal(tester, issue);
      await tester.tap(issue);
      await tester.pumpAndSettle();
      expect(ignored, isNull);
    },
  );
  testWidgets(
    'binding plan uses current account edits for pending/completed progress',
    (tester) async {
      var records = [
        account(1, phone: '000-000-0000'),
        account(2, phone: '0000000000'),
      ];
      final changes = ChangeNotifier();
      addTearDown(changes.dispose);
      BindingRetirementPlan? plan;
      var analysis = analysisFor(records);
      void rebuild() {
        analysis = AccountAnalysisSnapshot.fromSnapshot(
          VaultSnapshot(
            nextAccountId: 3,
            accounts: records,
            nextSubscriptionId: 1,
            subscriptions: const [],
            bindingRetirementPlans: plan == null ? [] : [plan!],
          ),
        );
        changes.notifyListeners();
      }

      await tester.pumpWidget(
        host(
          BindingCenterPage(
            analysisProvider: () => analysis,
            accountsProvider: () => records,
            changes: changes,
            onCreatePlan: (group) async {
              plan = BindingRetirementPlan(
                id: 'test-plan',
                type: group.type,
                targetValue: group.targetValue,
                normalizedValue: group.normalizedValue,
                createdAtUtc: DateTime.utc(2026, 9, 4),
                accountIds: group.activeAccountIds,
              );
              rebuild();
              return true;
            },
            onEditAccount: (record) async {
              records = [
                for (final a in records)
                  if (a.id == record.id) account(1, phone: '1111111111') else a,
              ];
              rebuild();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('标记准备停用'));
      await tester.tap(find.text('标记准备停用'));
      await tester.pumpAndSettle();
      expect(plan, isNotNull);
      await tester.scrollUntilVisible(
        find.text('准备停用计划'),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('准备停用计划'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('查看待处理账号'));
      await tester.tap(find.text('查看待处理账号'));
      await tester.pumpAndSettle();
      expect(find.text('Example 1'), findsOneWidget);
      await tester.tap(find.byTooltip('编辑账号').first);
      await tester.pumpAndSettle();
      expect(find.text('Example 1'), findsNothing);
      expect(find.text('Example 2'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('待处理 1 · 已处理 1 · 回收站 0'));
      expect(find.text('待处理 1 · 已处理 1 · 回收站 0'), findsOneWidget);
    },
  );
  testWidgets(
    'batch recycle passes the displayed revision even when state changes while confirmation is open',
    (tester) async {
      var revision = 10;
      final changes = ValueNotifier<int>(0);
      addTearDown(changes.dispose);
      int? submittedRevision;
      Set<String>? ids;
      final records = [account(1)];
      final analysis = analysisFor(records);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: changes,
              builder: (context, _, _) => AccountsPage(
                accounts: records,
                subscriptions: const [],
                analysis: analysis,
                dataRevision: revision,
                onAddAccount: () {},
                onBatchRecycle: (selected, {int? expectedRevision}) async {
                  ids = selected;
                  submittedRevision = expectedRevision;
                  return false;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('account-selection-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-visible-accounts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-account-recycle')));
      await tester.pumpAndSettle();
      revision = 11;
      changes.value++;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-batch-recycle')));
      await tester.pumpAndSettle();
      expect(submittedRevision, 10);
      expect(ids, {'account-1'});
      expect(find.text('批量操作失败，原记录仍保留。'), findsOneWidget);
    },
  );
  testWidgets('batch category freezes IDs and revision before dialog', (
    tester,
  ) async {
    var records = [account(1), account(2)];
    var revision = 20;
    final changes = ValueNotifier<int>(0);
    addTearDown(changes.dispose);
    Set<String>? submitted;
    int? submittedRevision;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: changes,
            builder: (context, _, _) => AccountsPage(
              accounts: records,
              subscriptions: const [],
              analysis: analysisFor(records),
              dataRevision: revision,
              onAddAccount: () {},
              onBatchCategory: (ids, category, {int? expectedRevision}) async {
                submitted = ids;
                submittedRevision = expectedRevision;
                return false;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('account-selection-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-visible-accounts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-account-category')));
    await tester.pumpAndSettle();
    records = [records.first];
    revision++;
    changes.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-batch-category')));
    await tester.pumpAndSettle();
    expect(submitted, {'account-1', 'account-2'});
    expect(submittedRevision, 20);
  });
  testWidgets(
    'field reorder and explicit remove are accessible without dragging',
    (tester) async {
      final controller = AccountCustomFieldsController([
        AccountCustomField(
          id: 'a',
          name: 'Alpha',
          type: AccountCustomFieldType.text,
          value: 'first',
          order: 0,
        ),
        AccountCustomField(
          id: 'b',
          name: 'Beta',
          type: AccountCustomFieldType.sensitiveText,
          value: 'FICTIONAL-BETA',
          order: 1,
        ),
      ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              child: AccountCustomFieldsEditor(controller: controller),
            ),
          ),
        ),
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('move-custom-field-down-0')),
      );
      await tester.tap(find.byKey(const ValueKey('move-custom-field-down-0')));
      await tester.pumpAndSettle();
      expect(controller.toFields().first.id, 'b');
      await reveal(tester, find.byKey(const ValueKey('remove-custom-field-0')));
      await tester.tap(find.byKey(const ValueKey('remove-custom-field-0')));
      await tester.pumpAndSettle();
      expect(controller.toFields().single.id, 'a');
    },
  );
  testWidgets(
    '5000 duplicate candidates stay lazy and all results remain scrollable',
    (tester) async {
      final candidates = [
        for (var i = 1; i <= 5000; i++)
          AccountDuplicateCandidate(
            account: account(i),
            inTrash: i > 2500,
            matchingFields: {'platformName+loginAccount'},
          ),
      ];
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAccountDuplicateDialog(
                  context: context,
                  candidates: candidates,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Example 1'), findsOneWidget);
      expect(find.text('Example 4999'), findsNothing);
      expect(find.text('platformName+loginAccount'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('duplicate-candidate-list')),
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );
    },
  );
}
