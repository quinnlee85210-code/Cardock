import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/security/account_comparison.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_analysis.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';

AccountRecord account(
  int id, {
  String platform = 'Fictional Cloud',
  String? login = 'fixture-user',
  String? password,
  String? phone,
  String? email,
  String? username,
  String? url,
  List<PasswordChangeRecord> history = const [],
  int? revision,
}) => AccountRecord.fromDraft(
  id: 'account-$id',
  draft: AccountDraft(
    platformName: platform,
    loginAccount: login,
    password: password,
    boundPhone: phone,
    boundEmail: email,
    username: username,
    website: url,
  ),
  passwordValueRevision: revision,
  passwordChangeHistory: history,
);
VaultSnapshot vault(List<AccountRecord> accounts) => VaultSnapshot(
  nextAccountId: 10001,
  accounts: accounts,
  nextSubscriptionId: 1,
  subscriptions: const [],
);
AccountAnalysisSnapshot analyze(VaultSnapshot s, {DateTime? now}) =>
    AccountAnalysisSnapshot.fromSnapshot(
      s,
      now: now ?? DateTime.utc(2026, 9, 4),
    );

void main() {
  test(
    'comparison uses copies, NFKC and conservative phone/email identity',
    () {
      expect(
        AccountComparison.email(' Ｆｏｏ+tag@EXAMPLE.invalid '),
        'foo+tag@example.invalid',
      );
      expect(
        AccountComparison.email('a.b@gmail.com'),
        isNot(AccountComparison.email('ab@gmail.com')),
      );
      expect(
        AccountComparison.email('a+tag@gmail.com'),
        isNot(AccountComparison.email('a@gmail.com')),
      );
      expect(AccountComparison.phone('＋８６ （１３８）００００－００００'), '+8613800000000');
      expect(
        AccountComparison.phone('+86 13800000000'),
        isNot(AccountComparison.phone('13800000000')),
      );
      expect(
        AccountComparison.login('CaseUser'),
        isNot(AccountComparison.login('caseuser')),
      );
    },
  );
  test(
    'safe HTTP domains include subdomains and preserve private-host tenants',
    () {
      expect(
        AccountComparison.domain('https://login.example.com/a'),
        'example.com',
      );
      expect(
        AccountComparison.domain('https://mail.example.co.uk/a'),
        'example.co.uk',
      );
      expect(
        AccountComparison.domain('https://one.github.io/a'),
        'one.github.io',
      );
      expect(
        AccountComparison.domain('https://two.github.io/a'),
        'two.github.io',
      );
      for (final value in [
        'javascript:alert(1)',
        'file:///tmp/a',
        'ftp://example.com',
        'https://u:p@example.com',
      ]) {
        expect(AccountComparison.domain(value), '');
      }
    },
  );
  test(
    'duplicate keys never collide through separators inside user fields',
    () {
      final a = analyze(vault([account(1, platform: 'x', login: 'a|p:y')]));
      expect(
        a.duplicatesFor(
          AccountDraft(platformName: 'x|l:a', loginAccount: 'p:y'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'platform plus login/email/phone or domain plus login yield candidates',
    () {
      for (final draft in [
        AccountDraft(
          platformName: 'fictional cloud',
          loginAccount: 'fixture-user',
        ),
        AccountDraft(
          platformName: 'Fictional Cloud',
          boundEmail: 'OWNER@EXAMPLE.invalid',
        ),
        AccountDraft(
          platformName: 'Fictional Cloud',
          boundPhone: '138 0000-0000',
        ),
        AccountDraft(
          platformName: 'Other Brand',
          loginAccount: 'fixture-user',
          website: 'https://other.example.com',
        ),
        AccountDraft(
          platformName: 'Fictional Cloud',
          username: 'name',
          website: 'https://other.example.com',
        ),
      ]) {
        final a = analyze(
          vault([
            account(
              1,
              password: 'fixture-secret',
              email: 'owner@example.invalid',
              phone: '13800000000',
              username: 'name',
              url: 'https://login.example.com',
            ),
          ]),
        );
        expect(a.duplicatesFor(draft).single.account.id, 'account-1');
      }
    },
  );
  test(
    'single-field matches and shared passwords are not account duplicates',
    () {
      final a = analyze(
        vault([
          account(
            1,
            password: 'fixture-secret',
            email: 'owner@example.invalid',
            phone: '13800000000',
            username: 'name',
            url: 'https://example.com',
          ),
        ]),
      );
      for (final draft in [
        AccountDraft(platformName: 'Fictional Cloud'),
        AccountDraft(platformName: 'Other', username: 'name'),
        AccountDraft(
          platformName: 'Other',
          boundEmail: 'owner@example.invalid',
        ),
        AccountDraft(platformName: 'Other', boundPhone: '13800000000'),
        AccountDraft(platformName: 'Other', website: 'https://example.com'),
        AccountDraft(platformName: 'Other', password: 'fixture-secret'),
      ]) {
        expect(a.duplicatesFor(draft), isEmpty);
      }
      expect(
        a.duplicatesFor(
          AccountDraft(
            platformName: 'Fictional Cloud',
            loginAccount: 'fixture-user',
          ),
          excludeAccountId: 'account-1',
        ),
        isEmpty,
      );
    },
  );
  test('all manual duplicate candidates retain active versus trash origin', () {
    final source = VaultTrash.move(
      vault([account(1), account(2), account(3)]),
      accountId: 'account-2',
      now: DateTime.utc(2026, 9, 4),
      batchId: 'test-batch',
    );
    final a = analyze(source),
        matches = a.duplicatesFor(
          AccountDraft(
            platformName: 'Fictional Cloud',
            loginAccount: 'fixture-user',
          ),
        );
    expect(matches, hasLength(3));
    expect(matches.where((m) => m.inTrash).single.account.id, 'account-2');
    expect(a.duplicateAccountIds, {'account-1', 'account-3'});
  });
  test(
    'reuse compares exact nonempty current strings, without trim or Unicode changes',
    () {
      final a = analyze(
        vault([
          account(1, password: 'Value '),
          account(2, password: 'Value '),
          account(3, password: 'Value'),
          account(4, password: 'value '),
          account(5, password: 'é'),
          account(6, password: 'e\u0301'),
          account(7),
          account(8, password: ''),
          account(9, password: 'Value\n'),
        ]),
      );
      final reuse = a.healthFindings.where(
        (f) => f.issueType == 'reusedPassword',
      );
      expect(reuse.map((f) => f.accountId).toSet(), {'account-1', 'account-2'});
      expect(reuse.first.relatedAccountIds, {'account-1', 'account-2'});
    },
  );
  test(
    'trash passwords excluded and cross-platform login is only organization information',
    () {
      var s = vault([
        account(1, password: 'LongFixturePassword#70', platform: 'A'),
        account(2, password: 'LongFixturePassword#70', platform: 'B'),
        account(3, password: 'OtherFixtureValue#91', platform: 'C'),
      ]);
      s = VaultTrash.move(
        s,
        accountId: 'account-2',
        now: DateTime.utc(2026, 9, 4),
        batchId: 'fixture',
      );
      final a = analyze(s);
      expect(
        a.healthFindings.where((f) => f.issueType == 'reusedPassword'),
        isEmpty,
      );
      expect(a.crossPlatformLoginAccountIds, {'account-1', 'account-3'});
      expect(a.duplicateAccountIds, isEmpty);
    },
  );
  test('weak local variants, sequences and explicit length thresholds', () {
    for (final p in ['password', 'Password123!', 'P@ssw0rd!']) {
      expect(passwordPatternIssues(p), contains('commonPassword'));
    }
    expect(passwordPatternIssues('aZ#7rX!'), contains('shortPassword'));
    expect(passwordPatternIssues('aZ#7rX!9'), isNot(contains('shortPassword')));
    expect(passwordPatternIssues('aZ#7rX!9abc'), contains('moderateLength'));
    expect(
      passwordPatternIssues('aZ#7rX!9abcdQ'),
      isNot(contains('moderateLength')),
    );
    expect(passwordPatternIssues('508397260491'), contains('numericPassword'));
    expect(
      passwordPatternIssues('5083972604918'),
      isNot(contains('numericPassword')),
    );
    expect(
      passwordPatternIssues('zzzzzzzzzzzzzzzz'),
      contains('repeatedCharacters'),
    );
    expect(passwordPatternIssues('abcd'), contains('shortSequence'));
    expect(passwordPatternIssues('asdfgh'), contains('keyboardSequence'));
    expect(passwordPatternIssues('xyxyxyxy'), contains('simplePattern'));
  });
  test('missing history differs from reliable 730-day timing boundary', () {
    final now = DateTime.utc(2026, 9, 4, 12);
    final a = analyze(
      vault([
        account(1),
        account(2, password: 'LongFixturePassword#70'),
        account(
          3,
          password: 'LongFixturePassword#71',
          history: [
            PasswordChangeRecord(
              changedAtUtc: now.subtract(const Duration(days: 730)),
            ),
          ],
        ),
        account(
          4,
          password: 'LongFixturePassword#72',
          history: [
            PasswordChangeRecord(
              changedAtUtc: now.subtract(const Duration(days: 730, seconds: 1)),
            ),
          ],
        ),
      ]),
      now: now,
    );
    expect(
      a.healthFindings
          .where((f) => f.issueType == 'missingPassword')
          .single
          .accountId,
      'account-1',
    );
    expect(
      a.healthFindings
          .where((f) => f.issueType == 'unknownChangeDate')
          .single
          .accountId,
      'account-2',
    );
    expect(
      a.healthFindings
          .where((f) => f.issueType == 'oldChangeDate')
          .single
          .accountId,
      'account-4',
    );
  });
  test(
    'ignore is issue-specific and value revision or reuse membership invalidates it',
    () {
      final source = vault([
        account(1, password: 'same-value'),
        account(2, password: 'same-value'),
      ]);
      final issue = analyze(source).healthFindings.firstWhere(
        (f) => f.accountId == 'account-1' && f.issueType == 'reusedPassword',
      );
      final ignored = source.copyWith(
        passwordHealthIgnoreRules: [issue.toIgnoreRule()],
      );
      expect(
        analyze(
          ignored,
        ).healthFindings.firstWhere((f) => f.key == issue.key).ignored,
        isTrue,
      );
      expect(
        analyze(ignored).healthFindings
            .where(
              (f) =>
                  f.accountId == 'account-1' && f.issueType == 'moderateLength',
            )
            .single
            .ignored,
        isFalse,
      );
      final revised = ignored.copyWith(
        accounts: [
          account(1, password: 'same-value', revision: 2),
          source.accounts.last,
        ],
      );
      expect(
        analyze(
          revised,
        ).healthFindings.firstWhere((f) => f.key == issue.key).ignored,
        isFalse,
      );
      final newMember = ignored.copyWith(
        accounts: [
          ...ignored.accounts,
          account(3, password: 'same-value'),
        ],
      );
      expect(
        analyze(
          newMember,
        ).healthFindings.firstWhere((f) => f.key == issue.key).ignored,
        isFalse,
      );
      expect(
        issue.toIgnoreRule().toJson().values,
        isNot(contains('same-value')),
      );
    },
  );
  test(
    'binding progress changes only with actual account fields, including trash and restore',
    () {
      final source = vault([
        account(1, phone: '13800000000'),
        account(2, phone: '138 0000-0000'),
      ]);
      final plan = BindingRetirementPlan(
        id: 'plan',
        type: BindingType.phone,
        targetValue: '13800000000',
        normalizedValue: '13800000000',
        createdAtUtc: DateTime.utc(2026, 9, 4),
        accountIds: {'account-1', 'account-2'},
      );
      var changed = source.copyWith(
        bindingRetirementPlans: [plan],
        accounts: [
          account(1, phone: '13900000000'),
          source.accounts[1],
        ],
      );
      var p = analyze(changed).bindingPlans.single;
      expect(p.completedAccountIds, {'account-1'});
      expect(p.pendingAccountIds, {'account-2'});
      changed = VaultTrash.move(
        changed,
        accountId: 'account-2',
        now: DateTime.utc(2026, 9, 4),
        batchId: 'fixture',
      );
      p = analyze(changed).bindingPlans.single;
      expect(p.pendingAccountIds, isEmpty);
      expect(p.trashAccountIds, {'account-2'});
      changed = VaultTrash.restore(changed, accountId: 'account-2');
      expect(analyze(changed).bindingPlans.single.pendingAccountIds, {
        'account-2',
      });
      changed = changed.copyWith(
        accounts: [
          account(1, phone: '13800000000'),
          changed.accounts[1],
          account(3, phone: '13800000000'),
        ],
      );
      changed = normalizeAccountSecurityMetadata(
        changed,
        DateTime.utc(2026, 9, 4),
      );
      expect(changed.bindingRetirementPlans.single.accountIds, {
        'account-1',
        'account-2',
        'account-3',
      });
      expect(analyze(changed).bindingPlans.single.pendingAccountIds, {
        'account-1',
        'account-2',
        'account-3',
      });
    },
  );
  test(
    'search excludes password and sensitive custom values, combines filters',
    () {
      final a = AccountRecord.fromDraft(
        id: 'account-1',
        draft: AccountDraft(
          platformName: 'Fictional Cloud',
          password: 'NEVER-SEARCH-THIS',
          boundEmail: 'fixture@example.invalid',
          customFields: [
            AccountCustomField(
              id: 'one',
              name: 'Visible label',
              type: AccountCustomFieldType.text,
              value: 'Visible text',
              order: 0,
            ),
            AccountCustomField(
              id: 'two',
              name: 'Hidden label',
              type: AccountCustomFieldType.sensitiveText,
              value: 'HIDDEN-FIXTURE-SECRET',
              order: 1,
            ),
            AccountCustomField(
              id: 'three',
              name: 'Date label',
              type: AccountCustomFieldType.date,
              value: '2026-09-04',
              order: 2,
            ),
          ],
        ),
      );
      final analysis = analyze(vault([a]));
      expect(
        analysis.matches(a, 'Visible text', {
          AccountFilter.hasPassword,
          AccountFilter.hasEmail,
        }),
        isTrue,
      );
      expect(analysis.matches(a, 'Hidden label', {}), isTrue);
      expect(analysis.matches(a, '2026-09', {}), isTrue);
      expect(analysis.matches(a, 'NEVER-SEARCH-THIS', {}), isFalse);
      expect(analysis.matches(a, 'HIDDEN-FIXTURE-SECRET', {}), isFalse);
      expect(analysis.matches(a, '', {AccountFilter.noPassword}), isFalse);
      expect(analysis.matches(a, '', {}), isTrue);
    },
  );
  test(
    'disposing the session analysis drops all public results and account references',
    () {
      final analysis = analyze(
        vault([account(1, password: 'same'), account(2, password: 'same')]),
      );
      analysis.dispose();
      expect(analysis.healthFindings, isEmpty);
      expect(analysis.bindingGroups, isEmpty);
      expect(
        analysis.duplicatesFor(
          AccountDraft(
            platformName: 'Fictional Cloud',
            loginAccount: 'fixture-user',
          ),
        ),
        isEmpty,
      );
    },
  );
  test(
    '5000 fictional records, one password group, binding groups and filters use bounded indexed work',
    () {
      final accounts = List.generate(
        5000,
        (i) => AccountRecord.fromDraft(
          id: 'account-${i + 1}',
          draft: AccountDraft(
            platformName: 'Fictional Platform ${i % 20}',
            loginAccount: 'fixture-$i',
            password: 'SharedFixture#1234',
            boundPhone: '13800000000',
            boundEmail: 'group${i % 5}@example.invalid',
            customFields: List.generate(
              10,
              (f) => AccountCustomField(
                id: 'f$f',
                name: 'Field $f',
                type: f == 9
                    ? AccountCustomFieldType.sensitiveText
                    : AccountCustomFieldType.text,
                value: 'synthetic-$i-$f',
                order: f,
              ),
            ),
          ),
        ),
      );
      final source = vault(accounts), watch = Stopwatch()..start();
      final analysis = analyze(source);
      final results = accounts
          .where(
            (a) => analysis.matches(a, 'synthetic', {
              AccountFilter.hasPassword,
              AccountFilter.hasEmail,
              AccountFilter.hasPasswordHealth,
            }),
          )
          .length;
      watch.stop();
      expect(results, 5000);
      expect(
        analysis.healthFindings.where((f) => f.issueType == 'reusedPassword'),
        hasLength(5000),
      );
      expect(watch.elapsedMilliseconds, lessThan(10000));
      // Controlled development-host regression, not a claim about phone speed.
      // ignore: avoid_print
      print(
        'stage3 performance: OS=${Platform.operatingSystem}; Dart=${Platform.version.split(" ").first}; accounts=5000; customFields=50000; elapsedMs=${watch.elapsedMilliseconds}',
      );
    },
  );
}
