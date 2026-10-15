import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_analysis.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/pending_subscription_draft.dart';
import 'stage3_account_analysis_test.dart' show account, vault;

void main() {
  test(
    'each filter uses current account, formal subscription and draft scope independently',
    () {
      final now = DateTime(2026, 9, 4, 12);
      final a1 = account(
        1,
        password: 'short',
        phone: '13800000000',
        email: 'fixture@example.invalid',
      );
      final a2 = account(2);
      final a3 = account(
        3,
        platform: 'Other Fixture',
        password: 'SYNTHETIC-COMPLEX#92',
      );
      final source = vault([a1, a2, a3]).copyWith(
        nextSubscriptionId: 3,
        subscriptions: [
          SubscriptionRecord.fromDraft(
            id: 'subscription-1',
            draft: SubscriptionDraft(
              accountId: a1.id,
              details: SubscriptionDetailsDraft(
                serviceName: 'Fixture related',
                firstSubscribedOn: DateTime(2026, 1, 1),
                nextRenewalOn: DateTime(2026, 9, 1),
              ),
            ),
          ),
          SubscriptionRecord.fromDraft(
            id: 'subscription-2',
            draft: SubscriptionDraft(
              accountId: null,
              details: SubscriptionDetailsDraft(
                serviceName: 'Fixture independent',
                firstSubscribedOn: DateTime(2026, 1, 1),
                nextRenewalOn: DateTime(2026, 9, 1),
              ),
            ),
          ),
        ],
        pendingSubscriptionDrafts: [
          PendingSubscriptionDraft(
            draftId: 'fixture-draft',
            accountId: a2.id,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        bindingRetirementPlans: [
          BindingRetirementPlan(
            id: 'fixture-plan',
            type: BindingType.phone,
            targetValue: '13800000000',
            normalizedValue: '13800000000',
            createdAtUtc: now.toUtc(),
            accountIds: {a1.id},
          ),
        ],
      );
      final analysis = AccountAnalysisSnapshot.fromSnapshot(source, now: now);
      final expected = <AccountFilter, Set<String>>{
        AccountFilter.hasPassword: {a1.id, a3.id},
        AccountFilter.noPassword: {a2.id},
        AccountFilter.hasPhone: {a1.id},
        AccountFilter.hasEmail: {a1.id},
        AccountFilter.hasSubscription: {a1.id},
        AccountFilter.noSubscription: {a2.id, a3.id},
        AccountFilter.hasPendingDraft: {a2.id},
        AccountFilter.hasAttentionSubscription: {a1.id},
        AccountFilter.hasDuplicate: {a1.id, a2.id},
        AccountFilter.hasPasswordHealth: {a1.id, a2.id, a3.id},
        AccountFilter.hasBindingPending: {a1.id},
        AccountFilter.crossPlatformLogin: {a1.id, a2.id, a3.id},
      };
      expect(expected.keys.toSet(), AccountFilter.values.toSet());
      for (final e in expected.entries) {
        expect(
          source.accounts
              .where((a) => analysis.matches(a, '', {e.key}))
              .map((a) => a.id)
              .toSet(),
          e.value,
          reason: e.key.name,
        );
      }
      expect(
        source.accounts
            .where(
              (a) => analysis.matches(a, 'Fictional', {
                AccountFilter.hasPhone,
                AccountFilter.hasDuplicate,
                AccountFilter.hasSubscription,
              }),
            )
            .map((a) => a.id),
        [a1.id],
      );
      expect(
        source.accounts.where(
          (a) => analysis.matches(a, '', {
            AccountFilter.hasPassword,
            AccountFilter.noPassword,
          }),
        ),
        isEmpty,
      );
      expect(
        source.accounts.where((a) => analysis.matches(a, '', {})),
        hasLength(3),
      );
      expect(
        source.accounts.where(
          (a) => analysis.matches(a, 'Fixture independent', {}),
        ),
        isEmpty,
      );
    },
  );
  test(
    'custom field names and every non-sensitive stable value are searchable, sensitive values never are',
    () {
      final a = AccountRecord.fromDraft(
        id: 'account-1',
        draft: AccountDraft(
          platformName: 'Fixture search',
          password: 'DO-NOT-SEARCH-PASSWORD',
          customFields: [
            AccountCustomField(
              id: 'field-text',
              name: 'Text name',
              type: AccountCustomFieldType.text,
              value: 'Ordinary needle',
              order: 0,
            ),
            AccountCustomField(
              id: 'field-secret',
              name: 'Secret label',
              type: AccountCustomFieldType.sensitiveText,
              value: 'DO-NOT-SEARCH-SECRET',
              order: 1,
            ),
            AccountCustomField(
              id: 'field-url',
              name: 'URL label',
              type: AccountCustomFieldType.url,
              value: 'https://fixture.example.invalid/path',
              order: 2,
            ),
            AccountCustomField(
              id: 'field-date',
              name: 'Date label',
              type: AccountCustomFieldType.date,
              value: '2026-08-03',
              order: 3,
            ),
            AccountCustomField(
              id: 'field-number',
              name: 'Number label',
              type: AccountCustomFieldType.number,
              value: '12345678901234567890.00001',
              order: 4,
            ),
          ],
        ),
      );
      final analysis = AccountAnalysisSnapshot.fromSnapshot(vault([a]));
      for (final query in [
        'Text name',
        'Secret label',
        'ordinary needle',
        'example.invalid/path',
        '2026-08-03',
        '12345678901234567890.00001',
      ]) {
        expect(analysis.matches(a, query, {}), isTrue, reason: query);
      }
      for (final query in ['DO-NOT-SEARCH-PASSWORD', 'DO-NOT-SEARCH-SECRET']) {
        expect(analysis.matches(a, query, {}), isFalse);
      }
    },
  );
}
