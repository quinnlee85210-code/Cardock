import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_analysis.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_insights.dart';
import 'support/fake_vault_store.dart';
import 'stage3_account_analysis_test.dart' show account, vault;

const _master = 'SYNTHETIC-Clock-Only-Master';

Future<({AppState state, FakeVaultStore store})> _opened(
  VaultSnapshot snapshot,
  DateTime Function() now,
) async {
  final store = FakeVaultStore(
    configured: true,
    acceptedPassword: _master,
    snapshot: snapshot,
  );
  final state = AppState(vaultStore: store, now: now);
  addTearDown(state.dispose);
  await state.initialize();
  expect(await state.unlock(_master), VaultActionResult.success);
  return (state: state, store: store);
}

VaultSnapshot _calendarFixture(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  SubscriptionRecord subscription(String id, {bool trial = false}) =>
      SubscriptionRecord.fromDraft(
        id: id,
        draft: SubscriptionDraft(
          accountId: trial ? 'account-2' : 'account-1',
          details: SubscriptionDetailsDraft(
            serviceName: 'Synthetic calendar',
            amount: '1',
            firstSubscribedOn: day.subtract(const Duration(days: 3)),
            nextRenewalOn: day,
            management: trial
                ? SubscriptionManagement(
                    trial: SubscriptionTrial(
                      startsOn: day.subtract(const Duration(days: 3)),
                      endsOn: day,
                      formalAmount: '1',
                    ),
                  )
                : null,
          ),
        ),
      );
  return VaultSnapshot(
    nextAccountId: 3,
    accounts: [account(1), account(2)],
    nextSubscriptionId: 3,
    subscriptions: [
      subscription('subscription-1'),
      subscription('subscription-2', trial: true),
    ],
  );
}

void main() {
  test(
    'subscription attention uses supplied local calendar at both UTC date edges',
    () {
      for (final hour in [0, 23]) {
        final now = DateTime(2026, 9, 4, hour, 30),
            source = _calendarFixture(DateTime(2026, 9, 4));
        final expected = subscriptionAttention(
          source.subscriptions,
          now,
        ).map((e) => e.subscription.accountId).toSet();
        final result = AccountAnalysisSnapshot.fromSnapshot(source, now: now);
        expect(result.attentionSubscriptionAccountIds, expected);
        expect(result.bindingGroups, isEmpty);
        final expectedNext = DateTime(now.year, now.month, now.day + 1).toUtc();
        expect(result.nextRefreshAtUtc, expectedNext);
      }
    },
  );

  test(
    'AppState refreshes on local midnight and keeps cache between boundaries',
    () async {
      var now = DateTime(2026, 9, 4, 23, 59, 58);
      final source = _calendarFixture(now);
      final opened = await _opened(source, () => now), state = opened.state;
      final first = state.accountAnalysis;
      now = now.add(const Duration(seconds: 1));
      expect(identical(first, state.accountAnalysis), isTrue);
      now = now.add(const Duration(seconds: 1));
      final after = state.accountAnalysis;
      expect(identical(first, after), isFalse);
      expect(after.computedAtUtc, now.toUtc());
      expect(opened.store.saveCalls, 0);
    },
  );

  test(
    '730-day sub-day expiry and clock rollback update cache without business writes',
    () async {
      final changed = DateTime.utc(2024, 9, 4, 12),
          exact = changed.add(const Duration(days: 730));
      var now = exact.subtract(const Duration(minutes: 5));
      final source = vault([
        account(
          1,
          password: 'SYNTHETIC-Long-Password#44',
          history: [PasswordChangeRecord(changedAtUtc: changed)],
        ),
      ]);
      final opened = await _opened(source, () => now), state = opened.state;
      final first = state.accountAnalysis;
      expect(
        first.nextRefreshAtUtc,
        exact.add(const Duration(microseconds: 1)),
      );
      now = exact;
      expect(identical(first, state.accountAnalysis), isTrue);
      expect(
        state.accountAnalysis.healthFindings.any(
          (f) => f.issueType == 'oldChangeDate',
        ),
        isFalse,
      );
      now = exact.add(const Duration(microseconds: 1));
      final expired = state.accountAnalysis;
      expect(identical(first, expired), isFalse);
      expect(
        expired.healthFindings.any((f) => f.issueType == 'oldChangeDate'),
        isTrue,
      );
      now = exact.subtract(const Duration(minutes: 1));
      expect(identical(expired, state.accountAnalysis), isFalse);
      expect(
        state.accountAnalysis.healthFindings.any(
          (f) => f.issueType == 'oldChangeDate',
        ),
        isFalse,
      );
      expect(opened.store.saveCalls, 0);
    },
  );

  test(
    'future password history becomes trusted at its instant in the same day',
    () async {
      final changed = DateTime.utc(2026, 9, 4, 12);
      var now = changed.subtract(const Duration(seconds: 1));
      final opened = await _opened(
        vault([
          account(
            1,
            password: 'SYNTHETIC-Long-Password#55',
            history: [PasswordChangeRecord(changedAtUtc: changed)],
          ),
        ]),
        () => now,
      );
      final first = opened.state.accountAnalysis;
      expect(first.nextRefreshAtUtc, changed);
      expect(
        first.healthFindings.any((f) => f.issueType == 'unknownChangeDate'),
        isTrue,
      );
      now = changed;
      expect(
        opened.state.accountAnalysis.healthFindings.any(
          (f) => f.issueType == 'unknownChangeDate',
        ),
        isFalse,
      );
      expect(opened.store.saveCalls, 0);
    },
  );

  test(
    'compact reuse basis depends only on member IDs and numeric revisions',
    () {
      final left = AccountAnalysisSnapshot.fromSnapshot(
        vault([
          account(1, password: 'SYNTHETIC-FIRST-GROUP'),
          account(2, password: 'SYNTHETIC-FIRST-GROUP'),
        ]),
      );
      final right = AccountAnalysisSnapshot.fromSnapshot(
        vault([
          account(2, password: 'SYNTHETIC-OTHER-GROUP'),
          account(1, password: 'SYNTHETIC-OTHER-GROUP'),
        ]),
      );
      final a = left.healthFindings
          .firstWhere((f) => f.issueType == 'reusedPassword')
          .toIgnoreRule();
      final b = right.healthFindings
          .firstWhere((f) => f.issueType == 'reusedPassword')
          .toIgnoreRule();
      expect(a.basis, b.basis);
      expect(a.basis, startsWith('reuse_members_v1:'));
      expect(a.memberRevisions, isEmpty);
      expect(
        a.basis,
        passwordReuseMembershipBasis({'account-1': 1, 'account-2': 1}),
      );
      expect(
        passwordReuseMembershipBasis({'account-1': 1, 'account-2': 2}),
        isNot(a.basis),
      );
      expect(passwordReuseMembershipBasis({'account-1': 1}), isNot(a.basis));
      expect(jsonEncode(a.toJson()), isNot(contains('SYNTHETIC-FIRST-GROUP')));
    },
  );

  test(
    'legacy member maps remain readable while new compact rules invalidate on membership changes',
    () {
      final source = vault([
        account(1, password: 'SYNTHETIC-GROUP'),
        account(2, password: 'SYNTHETIC-GROUP'),
      ]);
      final analysis = AccountAnalysisSnapshot.fromSnapshot(source);
      final issue = analysis.healthFindings.firstWhere(
        (f) => f.issueType == 'reusedPassword',
      );
      final legacy = PasswordHealthIgnoreRule(
        accountId: issue.accountId,
        issueType: issue.issueType,
        passwordValueRevision: issue.passwordValueRevision,
        memberRevisions: issue.memberRevisions,
      );
      for (final rule in [legacy, issue.toIgnoreRule()]) {
        final ignored = source.copyWith(passwordHealthIgnoreRules: [rule]);
        expect(
          AccountAnalysisSnapshot.fromSnapshot(
            ignored,
          ).healthFindings.firstWhere((f) => f.key == issue.key).ignored,
          isTrue,
        );
        final moved = VaultTrash.move(
          ignored,
          accountId: issue.accountId,
          now: DateTime.utc(2026, 9, 4),
          batchId: 'trash',
        );
        expect(
          normalizeAccountSecurityMetadata(
            moved,
            DateTime.utc(2026, 9, 4),
          ).passwordHealthIgnoreRules,
          isEmpty,
        );
        final expanded = ignored.copyWith(
          accounts: [
            ...ignored.accounts,
            account(3, password: 'SYNTHETIC-GROUP'),
          ],
        );
        expect(
          AccountAnalysisSnapshot.fromSnapshot(
            expanded,
          ).healthFindings.firstWhere((f) => f.key == issue.key).ignored,
          isFalse,
        );
      }
    },
  );

  test(
    '5000 same-group ignored accounts store compact rules and analyze in bounded work',
    () {
      final source = vault([
        for (var i = 1; i <= 5000; i++)
          account(
            i,
            login: 'synthetic-$i',
            password: 'SYNTHETIC-SHARED-GROUP#66',
          ),
      ]);
      final first = AccountAnalysisSnapshot.fromSnapshot(source);
      final rules = first.healthFindings
          .where((f) => f.issueType == 'reusedPassword')
          .map((f) => f.toIgnoreRule())
          .toList();
      expect(rules, hasLength(5000));
      expect(rules.every((rule) => rule.memberRevisions.isEmpty), isTrue);
      expect(rules.map((rule) => rule.basis).toSet(), hasLength(1));
      final serialized = jsonEncode(
        rules.map((rule) => rule.toJson()).toList(),
      );
      expect(utf8.encode(serialized).length, lessThan(1500000));
      final watch = Stopwatch()..start();
      final result = AccountAnalysisSnapshot.fromSnapshot(
        source.copyWith(passwordHealthIgnoreRules: rules),
      );
      watch.stop();
      expect(
        result.healthFindings.where(
          (f) => f.issueType == 'reusedPassword' && f.ignored,
        ),
        hasLength(5000),
      );
      expect(watch.elapsedMilliseconds, lessThan(10000));
      // Synthetic desktop workload only; no device latency claim.
      // ignore: avoid_print
      print(
        'stage3 compact ignores: accounts=5000; rulesBytes=${utf8.encode(serialized).length}; elapsedMs=${watch.elapsedMilliseconds}',
      );
    },
  );
}
