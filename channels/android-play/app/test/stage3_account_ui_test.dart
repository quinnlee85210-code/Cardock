import 'package:account_subscription_manager/core/platform/safe_url_launcher.dart';
import 'package:account_subscription_manager/core/platform/sensitive_clipboard.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_analysis.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_custom_fields_card.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_custom_fields_editor.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_duplicate_dialog.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_editor_page.dart';
import 'package:account_subscription_manager/features/accounts/presentation/accounts_page.dart';
import 'package:account_subscription_manager/features/accounts/presentation/binding_center_page.dart';
import 'package:account_subscription_manager/features/accounts/presentation/password_generator_sheet.dart';
import 'package:account_subscription_manager/features/accounts/presentation/password_health_center_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_stage3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class TestClipboard implements SensitiveClipboard {
  String? value;
  int copies = 0;
  Duration? expiry;
  @override
  Future<void> copySensitive({
    required String text,
    required String label,
    Duration clearAfter = const Duration(seconds: 60),
  }) async {
    value = text;
    copies++;
    expiry = clearAfter;
  }
}

final class TestUrlLauncher implements ExternalUrlLauncher {
  String? value;
  @override
  Future<bool> open(String input) async {
    value = input;
    return true;
  }
}

AccountRecord account(
  int id, {
  String? password = 'FICTIONAL-ONLY-Q7!tV9&kZ2',
  String? phone,
  String? email,
  List<AccountCustomField> fields = const [],
  String? category,
}) => AccountRecord.fromDraft(
  id: 'account-$id',
  draft: AccountDraft(
    platformName: 'Example $id',
    password: password,
    boundPhone: phone,
    boundEmail: email,
    customFields: fields,
    category: category,
  ),
);
AccountAnalysisSnapshot analysisFor(List<AccountRecord> accounts) =>
    AccountAnalysisSnapshot.fromSnapshot(
      VaultSnapshot(
        nextAccountId: accounts.length + 1,
        accounts: accounts,
        nextSubscriptionId: 1,
        subscriptions: const [],
      ),
    );
Widget host(
  Widget page, {
  Locale locale = const Locale('zh', 'CN'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);
Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double step = 400,
}) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    step,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'custom field controller preserves five types, exact values and draft ordering',
    () {
      final fields = [
        for (final type in AccountCustomFieldType.values)
          AccountCustomField(
            id: type.name,
            name: type.name,
            type: type,
            value: switch (type) {
              AccountCustomFieldType.date => '2026-09-04',
              AccountCustomFieldType.number => '12345678901234567890.4500',
              AccountCustomFieldType.url => 'https://example.invalid/path',
              _ => '  fictional value\nsecond line  ',
            },
            order: type.index,
          ),
      ];
      final controller = AccountCustomFieldsController(fields);
      final restored = AccountCustomFieldsController();
      addTearDown(controller.dispose);
      addTearDown(restored.dispose);
      controller.move(4, 0);
      restored.restoreEditorFields(controller.exportEditorFields());
      expect(
        restored.toFields().map((f) => f.toJson()),
        controller.toFields().map((f) => f.toJson()),
      );
      expect(restored.toFields().first.value, '12345678901234567890.4500');
      expect(restored.toFields().last.type, AccountCustomFieldType.date);
    },
  );
  test(
    'custom field controller rejects field eleven, duplicate normalized names and future draft types',
    () {
      final controller = AccountCustomFieldsController();
      addTearDown(controller.dispose);
      for (var i = 0; i < 10; i++) {
        controller.add();
        controller.rows.last.name.text = 'Field $i';
      }
      expect(controller.toFields(), hasLength(10));
      expect(controller.add, throwsArgumentError);
      controller.rows.last.name.text = 'Ｆｉｅｌｄ ０';
      expect(controller.toFields, throwsArgumentError);
      expect(
        () => controller.restoreEditorFields([
          {'id': 'x', 'name': 'x', 'value': '', 'type': 'future_secret'},
        ]),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'custom sensitive detail defaults hidden, expires, clears on background and copies explicitly',
    (tester) async {
      final clipboard = TestClipboard();
      final launcher = TestUrlLauncher();
      final fields = [
        AccountCustomField(
          id: 'secret',
          name: 'Fictional custom',
          type: AccountCustomFieldType.sensitiveText,
          value: 'FICTIONAL-CUSTOM-ONLY',
          order: 0,
        ),
        AccountCustomField(
          id: 'url',
          name: 'Public site',
          type: AccountCustomFieldType.url,
          value: 'https://example.invalid',
          order: 1,
        ),
      ];
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              child: AccountCustomFieldsCard(
                fields: fields,
                sensitiveClipboard: clipboard,
                urlLauncher: launcher,
                revealDuration: const Duration(seconds: 1),
              ),
            ),
          ),
        ),
      );
      expect(find.text('FICTIONAL-CUSTOM-ONLY'), findsNothing);
      expect(clipboard.copies, 0);
      await tester.tap(
        find.byKey(const ValueKey('reveal-custom-field-detail-secret')),
      );
      await tester.pump();
      expect(find.text('FICTIONAL-CUSTOM-ONLY'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FICTIONAL-CUSTOM-ONLY'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('reveal-custom-field-detail-secret')),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('FICTIONAL-CUSTOM-ONLY'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.byKey(const ValueKey('copy-custom-field-secret')));
      await tester.pump();
      expect(clipboard.value, 'FICTIONAL-CUSTOM-ONLY');
      expect(clipboard.expiry, const Duration(seconds: 60));
      await reveal(
        tester,
        find.byKey(const ValueKey('open-custom-field-url-url')),
      );
      await tester.tap(find.byKey(const ValueKey('open-custom-field-url-url')));
      await tester.pump();
      expect(launcher.value, 'https://example.invalid');
    },
  );
  testWidgets(
    'generator fills encrypted-draft callback without saving and existing password requires confirmation',
    (tester) async {
      final clipboard = TestClipboard();
      Map<String, Object?>? draft;
      AccountEditorResult? result;
      await tester.pumpWidget(
        host(
          AccountEditorPage(
            existing: account(1),
            sensitiveClipboard: clipboard,
            onDraftChanged: (v) => draft = v,
            onBeforeSubmit: (v) async {
              result = v;
              return null;
            },
          ),
        ),
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('open-account-password-generator')),
      );
      await tester.tap(
        find.byKey(const ValueKey('open-account-password-generator')),
      );
      await tester.pumpAndSettle();
      expect(clipboard.copies, 0);
      expect(result, isNull);
      await reveal(
        tester,
        find.byKey(const ValueKey('use-generated-password')),
      );
      await tester.tap(find.byKey(const ValueKey('use-generated-password')));
      await tester.pumpAndSettle();
      expect(draft?['generatedPassword'], true);
      expect(draft?['passwordUpdateMode'], 'replace');
      expect(result, isNull);
      await tester.tap(find.byKey(const ValueKey('save-account-button')));
      await tester.pumpAndSettle();
      expect(find.text(generatedPasswordSaveNotice), findsOneWidget);
      expect(result, isNull);
      await tester.tap(
        find.byKey(const ValueKey('confirm-generated-password-save')),
      );
      await tester.pumpAndSettle();
      expect(result?.account.password?.length, 20);
      expect(result?.passwordUpdateMode, AccountPasswordUpdateMode.replace);
      expect(find.byType(AccountEditorPage), findsOneWidget);
    },
  );
  testWidgets(
    'generator cancel and background do not copy or return a generated result',
    (tester) async {
      final clipboard = TestClipboard();
      await tester.pumpWidget(
        host(
          Scaffold(
            body: PasswordGeneratorSheet(
              sensitiveClipboard: clipboard,
              revealDuration: const Duration(seconds: 1),
            ),
          ),
        ),
      );
      expect(clipboard.copies, 0);
      await tester.tap(find.byKey(const ValueKey('reveal-generated-password')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('请重新生成密码'), findsOneWidget);
      expect(clipboard.copies, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  testWidgets(
    'duplicate dialog distinguishes activity and recycle bin and returns edit/add decisions',
    (tester) async {
      AccountDuplicateChoice? choice;
      final candidates = [
        AccountDuplicateCandidate(
          account: account(1),
          inTrash: false,
          matchingFields: {'平台与登录账号'},
        ),
        AccountDuplicateCandidate(
          account: account(2),
          inTrash: true,
          matchingFields: {'平台与绑定邮箱'},
        ),
      ];
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  choice = await showAccountDuplicateDialog(
                    context: context,
                    candidates: candidates,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('活动账号中的相似记录'), findsOneWidget);
      expect(find.text('回收站中的相似记录'), findsOneWidget);
      expect(find.text('FICTIONAL-ONLY-Q7!tV9&kZ2'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('duplicate-return-edit')));
      await tester.pumpAndSettle();
      expect(choice, AccountDuplicateChoice.revise);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('duplicate-add-anyway')));
      await tester.pumpAndSettle();
      expect(choice, AccountDuplicateChoice.addAnyway);
    },
  );
  testWidgets(
    '5000 reused passwords render one lazy group rather than repeated member lists',
    (tester) async {
      final records = [for (var i = 1; i <= 5000; i++) account(i)];
      final analysis = analysisFor(records);
      final changes = ChangeNotifier();
      addTearDown(changes.dispose);
      await tester.pumpWidget(
        host(
          PasswordHealthCenterPage(
            analysisProvider: () => analysis,
            accountsProvider: () => records,
            changes: changes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('open-password-reuse-group-account-1')),
      );
      expect(find.text('以下 5000 个账号当前使用相同密码'), findsOneWidget);
      expect(find.text('FICTIONAL-ONLY-Q7!tV9&kZ2'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('open-password-reuse-group-account-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Example 1'), findsOneWidget);
      expect(find.text('Example 4999'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account visible selection clears on query changes and batch impact confirms once',
    (tester) async {
      final records = [
        account(1, category: 'AI工具'),
        account(2, password: null, category: 'AI工具'),
      ];
      final analysis = analysisFor(records);
      Set<String>? selected;
      int calls = 0;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: AccountsPage(
              accounts: records,
              subscriptions: const [],
              analysis: analysis,
              onAddAccount: () {},
              onBatchRecycle: (ids, {int? expectedRevision}) async {
                selected = ids;
                calls++;
                return true;
              },
              countPendingDrafts: (_) => 3,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('account-selection-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-visible-accounts')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个账号'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('account-search')),
        'Example 1',
      );
      await tester.pumpAndSettle();
      expect(find.text('已选 0 个账号'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('select-visible-accounts')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 个账号'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('batch-account-recycle')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('影响 1 个账号、0 条关联订阅、3 条待完善订阅草稿。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-batch-recycle')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(selected, {'account-1'});
    },
  );
  testWidgets(
    'combined account filters clear and one-shot cross-page filters update without hiding all data',
    (tester) async {
      final records = [account(1), account(2, password: null)];
      final analysis = analysisFor(records);
      Widget page(int token, Set<AccountFilter> filters) => host(
        Scaffold(
          body: AccountsPage(
            accounts: records,
            subscriptions: const [],
            analysis: analysis,
            onAddAccount: () {},
            filterToken: token,
            initialFilters: filters,
          ),
        ),
      );
      await tester.pumpWidget(page(0, {AccountFilter.noPassword}));
      await tester.pumpAndSettle();
      expect(find.text('Example 1'), findsNothing);
      expect(find.text('Example 2'), findsWidgets);
      await tester.pumpWidget(page(1, {AccountFilter.hasPassword}));
      await tester.pumpAndSettle();
      expect(find.text('Example 1'), findsWidgets);
      expect(find.text('Example 2'), findsNothing);
      await tester.tap(find.text('清除全部'));
      await tester.pumpAndSettle();
      expect(find.text('Example 1'), findsWidgets);
      await reveal(tester, find.text('Example 2').first);
      expect(find.text('Example 2'), findsWidgets);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets(
      'stage3 UI ${locale.languageCode} at 320x640 and 200% remains operable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final records = [
          account(1, phone: '000-000-0000', email: 'fictional@example.invalid'),
        ];
        final analysis = analysisFor(records);
        final changes = ChangeNotifier();
        addTearDown(changes.dispose);
        await tester.pumpWidget(
          host(
            Scaffold(
              body: AccountsPage(
                accounts: records,
                subscriptions: const [],
                analysis: analysis,
                onAddAccount: () {},
                onOpenPasswordHealth: () {},
                onOpenBindings: () {},
                onBatchCategory: (_, _, {int? expectedRevision}) async => true,
                onBatchRecycle: (_, {int? expectedRevision}) async => true,
                onSortModeChanged: (_) {},
              ),
            ),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(const ValueKey('account-combined-filters')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('apply-account-filters')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          host(
            BindingCenterPage(
              analysisProvider: () => analysis,
              accountsProvider: () => records,
              changes: changes,
            ),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('000-000-0000'), findsNothing);
        await tester.pumpWidget(
          host(
            PasswordHealthCenterPage(
              analysisProvider: () => analysis,
              accountsProvider: () => records,
              changes: changes,
            ),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          host(
            Scaffold(body: PasswordGeneratorSheet()),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'stage3 translation keys and placeholders match in English and Japanese',
    () {
      expect(
        stage3EnglishTranslations.keys.toSet(),
        stage3JapaneseTranslations.keys.toSet(),
      );
      final pattern = RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}');
      for (final entry in stage3EnglishTranslations.entries) {
        expect(entry.value.trim(), isNotEmpty);
        expect(
          RegExp(r'[\u3400-\u9fff]').hasMatch(entry.value),
          false,
          reason: entry.key,
        );
        final keys = pattern
            .allMatches(entry.key)
            .map((m) => m.group(0))
            .toSet();
        expect(
          pattern.allMatches(entry.value).map((m) => m.group(0)).toSet(),
          keys,
        );
        expect(
          pattern
              .allMatches(stage3JapaneseTranslations[entry.key]!)
              .map((m) => m.group(0))
              .toSet(),
          keys,
        );
      }
    },
  );
}
