import 'package:account_subscription_manager/features/subscriptions/domain/subscription_price_calendar.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/subscription_metadata_migration.dart';
import 'package:account_subscription_manager/core/storage/readable_export.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_automation.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_management_actions.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_insights.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_search.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_form_fields.dart';

final today = DateTime(2026, 9, 4);
SubscriptionRecord sub({
  String id = 'subscription-1',
  String amount = '120',
  String currency = 'CNY',
  int count = 1,
  SubscriptionCycleUnit unit = SubscriptionCycleUnit.month,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? next,
  DateTime? first,
  bool auto = true,
  String? payment = 'PayPal',
  String? account,
  SubscriptionManagement? management,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: account,
    details: SubscriptionDetailsDraft(
      serviceName: 'Cloud Service',
      planName: 'Premium',
      amount: amount,
      currency: currency,
      firstSubscribedOn: first ?? DateTime(2026, 1, 1),
      nextRenewalOn: next ?? DateTime(2026, 9, 10),
      cycleCount: count,
      cycleUnit: unit,
      status: status,
      autoRenew: auto,
      paymentMethod: payment,
      expenseCategory: '软件',
      notes: '供学习使用',
      management: management,
    ),
  ),
);
SubscriptionTrial trial({
  DateTime? end,
  DateTime? paid,
  bool auto = true,
  String fee = '0',
}) => SubscriptionTrial(
  startsOn: DateTime(2026, 9, 1),
  endsOn: end ?? DateTime(2026, 9, 10),
  amount: fee,
  formalAmount: '120',
  expectedAutoConvert: auto,
  firstPaidOn: paid ?? DateTime(2026, 9, 11),
);
VaultSnapshot vault(
  List<SubscriptionRecord> subs, {
  List<SubscriptionExpenseRecord> expenses = const [],
}) => VaultSnapshot(
  nextAccountId: 1,
  accounts: [],
  nextSubscriptionId: subs.length + 1,
  subscriptions: subs,
  nextExpenseId: expenses.length + 1,
  subscriptionExpenses: expenses,
);
SubscriptionPricePoint price(
  String id,
  DateTime date,
  String amount, {
  String currency = 'CNY',
  int count = 1,
  SubscriptionCycleUnit unit = SubscriptionCycleUnit.month,
}) => SubscriptionPricePoint(
  id: id,
  effectiveOn: date,
  amount: amount,
  currency: currency,
  cycleCount: count,
  cycleUnit: unit,
  kind: PriceChangeKind.change,
  createdAt: DateTime.utc(2026, 9, 4),
);
Future<List<int>> collect(Stream<List<int>> stream) =>
    stream.fold(<int>[], (a, b) => a..addAll(b));

void main() {
  group('stage2 final lifecycle and dated-cycle regression', () {
    test('ordinary cancel also resolves trial and cannot renew', () {
      final cancelled = sub(
        management: SubscriptionManagement(trial: trial()),
      ).cancel(cancelledOn: today);
      expect(cancelled.management!.trial!.outcome, TrialOutcome.cancelled);
      expect(() => cancelled.restore().markRenewed(), throwsStateError);
      expect(
        SubscriptionForecast.build([cancelled.restore()], today).lines,
        isEmpty,
      );
    });
    test('converted actual price supersedes compatibility baseline', () {
      final source = normalizeSubscriptionMetadata(
        vault([sub(management: SubscriptionManagement(trial: trial()))]),
      );
      final result = resolveSubscriptionTrial(
        source,
        subscriptionId: 'subscription-1',
        outcome: TrialOutcome.converted,
        now: DateTime(2026, 9, 12),
        actualPaidOn: DateTime(2026, 9, 11),
        actualAmount: '180',
        actualCurrency: 'USD',
      );
      final line = monthlyEquivalentLines(
        result.subscriptions,
        DateTime(2026, 9, 12),
      ).single;
      expect(line.originalAmount, '180');
      expect(line.currency, 'USD');
      expect(result.subscriptionExpenses, isEmpty);
    });
    test('conversion date before trial start rejected', () {
      expect(
        () => trial().resolve(
          TrialOutcome.converted,
          now: today,
          actualPaidOn: DateTime(2026, 8, 31),
          actualAmount: '1',
          actualCurrency: 'CNY',
        ),
        throwsArgumentError,
      );
    });
    test('invalid system audit timestamp rejected', () {
      expect(() => price('p', today, '1').toJson(), returnsNormally);
      expect(
        () => SubscriptionPricePoint(
          id: 'p',
          effectiveOn: today,
          amount: '1',
          currency: 'CNY',
          cycleCount: 1,
          cycleUnit: SubscriptionCycleUnit.month,
          kind: PriceChangeKind.change,
          createdAt: DateTime.utc(2500),
        ),
        throwsArgumentError,
      );
    });
    test('amount change preserves Jan 30 calendar anchor', () {
      final record = sub(
        first: DateTime(2026, 1, 30),
        management: SubscriptionManagement(
          priceHistory: [price('p', DateTime(2026, 2, 1), '150')],
        ),
      );
      expect(
        subscriptionPriceBillingDates(
          record,
          anchor: DateTime(2026, 1, 30),
          start: DateTime(2026, 1),
          endExclusive: DateTime(2026, 5),
        ).toList(),
        [
          DateTime(2026, 1, 30),
          DateTime(2026, 2, 28),
          DateTime(2026, 3, 30),
          DateTime(2026, 4, 30),
        ],
      );
    });
    test(
      'cycle change takes effect at billing date and anchors subsequent dates',
      () {
        final record = sub(
          management: SubscriptionManagement(
            priceHistory: [price('p', DateTime(2026, 2, 1), '300', count: 3)],
          ),
        );
        expect(
          subscriptionPriceBillingDates(
            record,
            anchor: DateTime(2026, 1, 1),
            start: DateTime(2026, 1),
            endExclusive: DateTime(2026, 9),
          ).toList(),
          [
            DateTime(2026, 1, 1),
            DateTime(2026, 2, 1),
            DateTime(2026, 5, 1),
            DateTime(2026, 8, 1),
          ],
        );
      },
    );
    test('multi reminder display uses rule instead of legacy days', () {
      final record = sub(
        management: SubscriptionManagement(
          reminderRules: [
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.renewal,
              daysBefore: [3, 0],
            ),
          ],
        ),
      );
      expect(subscriptionReminderOn(record), DateTime(2026, 9, 7));
      expect(
        subscriptionReminderAt(record, reminderTimeMinutes: 540),
        DateTime(2026, 9, 7, 9),
      );
    });
    test('empty explicit rules do not fabricate reminder display', () {
      expect(
        subscriptionReminderAt(
          sub(management: SubscriptionManagement()),
          reminderTimeMinutes: 540,
        ),
        isNull,
      );
    });
  });
  group('search privacy and conjunction', () {
    for (final query in [
      'cloud',
      'premium',
      '软件',
      '学习',
      'paypal',
      'cny',
      ' App platform ',
      '取消按钮',
      'cancel.example',
    ]) {
      test('authorized field $query', () {
        final record = sub(
          account: 'account-1',
          management: SubscriptionManagement(
            cancellation: SubscriptionCancellationInfo(
              location: '取消按钮',
              url: 'https://cancel.example',
            ),
          ),
        );
        final account = AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(
            platformName: 'App platform',
            loginAccount: 'hidden-login',
            password: 'synthetic-password',
          ),
        );
        expect(
          SubscriptionSearch(
            query: query,
          ).apply([record], today: today, accounts: [account]),
          hasLength(1),
        );
      });
    }
    test('password and login never searched', () {
      final account = AccountRecord.fromDraft(
        id: 'account-1',
        draft: AccountDraft(
          platformName: 'App platform',
          loginAccount: 'hidden-login',
          password: 'synthetic-password',
        ),
      );
      for (final q in ['hidden-login', 'synthetic-password']) {
        expect(
          SubscriptionSearch(query: q).apply(
            [sub(account: 'account-1')],
            today: today,
            accounts: [account],
          ),
          isEmpty,
        );
      }
    });
    test('read-only projection fields cannot be searched', () {
      final s = sub(
        account: 'account-1',
        management: SubscriptionManagement(
          cancellation: SubscriptionCancellationInfo(steps: 'PRIVATE_CANCEL'),
        ),
      );
      expect(
        const SubscriptionSearch(
          query: 'PRIVATE_CANCEL',
        ).apply([s], today: today, includeCancellation: false),
        isEmpty,
      );
    });
    test('AND across categories OR within category and clear', () {
      final records = [
        sub(),
        sub(id: 'subscription-2', currency: 'USD', auto: false),
        sub(id: 'subscription-3', currency: 'JPY'),
      ];
      const filter = SubscriptionSearch(
        currencies: {'CNY', 'USD'},
        autoRenew: {false},
      );
      expect(filter.apply(records, today: today).single.id, 'subscription-2');
      expect(
        const SubscriptionSearch().apply(records, today: today),
        hasLength(3),
      );
    });
    test('trial status independent of active', () {
      final records = [
        sub(),
        sub(
          id: 'subscription-2',
          management: SubscriptionManagement(trial: trial()),
        ),
      ];
      expect(
        const SubscriptionSearch(
          statuses: {SubscriptionSearchStatus.trial},
        ).apply(records, today: today).single.id,
        'subscription-2',
      );
    });
    for (final days in [30, 60, 90]) {
      test('inclusive date boundary $days', () {
        final filter = SubscriptionSearch(
          dates: {
            SubscriptionDateFilter.values[[30, 60, 90].indexOf(days)],
          },
        );
        expect(
          filter.apply([
            sub(next: DateTime(2026, 9, 4 + days)),
            sub(id: 'subscription-2', next: DateTime(2026, 9, 5 + days)),
          ], today: today),
          hasLength(1),
        );
      });
    }
  });
  group('trial lifecycle and explicit ledger', () {
    test('reaching end is pending without mutation', () {
      final t = trial(end: today), before = jsonEncode(t.toJson());
      expect(t.needsConfirmation(today), isTrue);
      expect(t.outcome, TrialOutcome.active);
      expect(jsonEncode(t.toJson()), before);
    });
    test('trial creation never infers an entry fee', () {
      final record = sub(
        management: SubscriptionManagement(trial: trial(fee: '9.99')),
      );
      expect(
        recordSubscriptionActions(
          previousSubscriptions: [],
          subscriptions: [record],
          accounts: [],
          expenses: [],
          nextExpenseId: 1,
        ).expenses,
        isEmpty,
      );
    });
    for (final paid in [false, true]) {
      test('conversion explicit payment $paid', () {
        final source = vault([
          sub(
            management: SubscriptionManagement(trial: trial(end: today)),
          ),
        ]);
        final result = resolveSubscriptionTrial(
          source,
          subscriptionId: 'subscription-1',
          outcome: TrialOutcome.converted,
          now: today,
          actualPaidOn: today,
          actualAmount: '99.1234',
          actualCurrency: 'USD',
          paymentConfirmed: paid,
        );
        expect(result.subscriptionExpenses.length, paid ? 1 : 0);
        expect(
          result.subscriptions.single.nextRenewalOn,
          DateTime(2026, 10, 4),
        );
        expect(
          result.subscriptions.single.management!.trial!.outcome,
          TrialOutcome.converted,
        );
        expect(
          () => resolveSubscriptionTrial(
            result,
            subscriptionId: 'subscription-1',
            outcome: TrialOutcome.converted,
            now: today,
            actualPaidOn: today,
            actualAmount: '99.1234',
            actualCurrency: 'USD',
            paymentConfirmed: paid,
          ),
          throwsStateError,
        );
      });
    }
    for (final outcome in [TrialOutcome.cancelled, TrialOutcome.ended]) {
      test('terminal trial $outcome excludes forecast', () {
        final result = resolveSubscriptionTrial(
          vault([sub(management: SubscriptionManagement(trial: trial()))]),
          subscriptionId: 'subscription-1',
          outcome: outcome,
          now: today,
        );
        expect(
          SubscriptionForecast.build(result.subscriptions, today).lines,
          isEmpty,
        );
        expect(result.subscriptionExpenses, isEmpty);
        expect(
          subscriptionReminderOccurrences(
            result.subscriptions.single,
            reminderTimeMinutes: 540,
            now: today,
          ),
          isEmpty,
        );
      });
    }
    test('trial fee idempotent and exact', () {
      final source = vault([
        sub(
          management: SubscriptionManagement(trial: trial(fee: '0.1234')),
        ),
      ]);
      final result = confirmTrialCharge(
        source,
        subscriptionId: 'subscription-1',
        paidOn: today,
        now: today,
      );
      expect(result.subscriptionExpenses.single.amount, '0.1234');
      expect(
        () => confirmTrialCharge(
          result,
          subscriptionId: 'subscription-1',
          paidOn: today,
          now: today,
        ),
        throwsStateError,
      );
    });
    test('first paid date cannot precede trial end', () {
      expect(() => trial(paid: DateTime(2026, 9, 2)), throwsArgumentError);
    });
    test('trial never enters historical cost without explicit expense', () {
      final s = sub(management: SubscriptionManagement(trial: trial()));
      final analysis = SubscriptionCostAnalysis.build(
        subscriptions: [s],
        expenses: [],
        today: today,
        range: SubscriptionCostRange(
          startMonth: DateTime(2026, 1),
          endMonth: DateTime(2026, 12),
        ),
      );
      expect(analysis.lines, isEmpty);
    });
  });
  group('multi-point reminder calendar', () {
    for (final invalid in [
      <int>[],
      [1, 1],
      [-1],
      [366],
      List.generate(9, (i) => i),
    ]) {
      test('invalid points $invalid', () {
        expect(
          () => SubscriptionReminderRule(
            event: SubscriptionReminderEvent.renewal,
            daysBefore: invalid,
          ),
          throwsArgumentError,
        );
      });
    }
    test('multiple events remain distinct stable IDs', () {
      final s = sub(
        management: SubscriptionManagement(
          reminderRules: [
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.renewal,
              daysBefore: [3, 0],
            ),
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.decision,
              daysBefore: [3, 0],
            ),
          ],
        ),
      );
      final plan = subscriptionReminderOccurrences(
        s,
        reminderTimeMinutes: 540,
        now: today,
      );
      expect(plan, hasLength(4));
      expect(plan.map((p) => p.id).toSet(), hasLength(4));
      expect(
        subscriptionReminderOccurrences(
          s,
          reminderTimeMinutes: 540,
          now: today,
        ).map((p) => p.id),
        plan.map((p) => p.id),
      );
    });
    test('no catch-up on repeat unlock or restart', () {
      final s = sub(
        next: today,
        management: SubscriptionManagement(
          reminderRules: [
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.renewal,
              daysBefore: [3, 1, 0],
            ),
          ],
        ),
      );
      expect(
        subscriptionReminderOccurrences(
          s,
          reminderTimeMinutes: 540,
          now: DateTime(2026, 9, 4, 10),
        ),
        isEmpty,
      );
    });
    test('trial schedules only trial event', () {
      final s = sub(
        management: SubscriptionManagement(
          trial: trial(),
          reminderRules: [
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.renewal,
              daysBefore: [3, 0],
            ),
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.trialEnd,
              daysBefore: [3, 1, 0],
            ),
          ],
        ),
      );
      expect(
        subscriptionReminderOccurrences(
          s,
          reminderTimeMinutes: 780,
          now: today,
        ),
        hasLength(3),
      );
      expect(
        subscriptionReminderOccurrences(
          s,
          reminderTimeMinutes: 780,
          now: today,
        ).first.at,
        DateTime(2026, 9, 7, 13),
      );
    });
    for (final status in [
      SubscriptionStatus.paused,
      SubscriptionStatus.cancelled,
      SubscriptionStatus.expired,
    ]) {
      test('inactive no alarms $status', () {
        expect(
          subscriptionReminderOccurrences(
            sub(status: status),
            reminderTimeMinutes: 540,
            now: today,
          ),
          isEmpty,
        );
      });
    }
  });
  group('prices and cancellation validation', () {
    test(
      'out of order insertion sorted and duplicate day requires consent',
      () {
        var m = SubscriptionManagement()
            .putPrice(price('later', DateTime(2026, 10, 1), '130'))
            .putPrice(price('earlier', DateTime(2026, 8, 1), '90'));
        expect(m.priceAt(today)!.amount, '90');
        expect(m.priceHistory.first.id, 'earlier');
        expect(
          () => m.putPrice(price('collision', DateTime(2026, 8, 1), '100')),
          throwsStateError,
        );
        m = m.putPrice(
          price('replacement', DateTime(2026, 8, 1), '100'),
          replaceSameDay: true,
        );
        expect(m.priceHistory, hasLength(2));
      },
    );
    test('currency and cycle only changes preserved', () {
      final p = price(
        'p',
        today,
        '120',
        currency: 'USD',
        count: 1,
        unit: SubscriptionCycleUnit.year,
      );
      final restored = SubscriptionPricePoint.fromJson(
        jsonDecode(jsonEncode(p.toJson())),
      );
      expect(restored.currency, 'USD');
      expect(restored.cycleUnit, SubscriptionCycleUnit.year);
    });
    for (final url in [
      'javascript:alert(1)',
      'file:///private',
      'https://',
      'https://user:pass@example.com',
    ]) {
      test('unsafe cancellation URL $url', () {
        expect(
          () => SubscriptionCancellationInfo(url: url),
          throwsArgumentError,
        );
      });
    }
    test('cancel retains guide and prices', () {
      final s = sub(
        management: SubscriptionManagement(
          cancellation: SubscriptionCancellationInfo(
            url: 'https://example.com/cancel',
            steps: '1\n2',
          ),
          priceHistory: [price('p', today, '100')],
        ),
      );
      expect(
        s.cancel(cancelledOn: today).restore().management!.cancellation!.steps,
        '1\n2',
      );
      expect(
        s.cancel(cancelledOn: today).management!.priceHistory,
        hasLength(1),
      );
    });
  });
  group('monthly equivalents and forecasts', () {
    for (final pair in [
      (1, SubscriptionCycleUnit.month, '120'),
      (3, SubscriptionCycleUnit.month, '40'),
      (6, SubscriptionCycleUnit.month, '20'),
      (1, SubscriptionCycleUnit.year, '10'),
      (2, SubscriptionCycleUnit.year, '5'),
    ]) {
      test('monthly conversion ${pair.$1} ${pair.$2}', () {
        expect(monthlyEquivalent('120', pair.$1, pair.$2).display, pair.$3);
      });
    }
    test('day/week exact average month and aggregate before rounding', () {
      expect(
        monthlyEquivalent('1', 1, SubscriptionCycleUnit.day).display,
        '30.4369',
      );
      expect(
        monthlyEquivalent('7', 1, SubscriptionCycleUnit.week).display,
        '30.4369',
      );
      final third = monthlyEquivalent('0.0001', 3, SubscriptionCycleUnit.month);
      expect((third + third + third).display, '0.0001');
    });
    test('manual renew included and currencies separated', () {
      final lines = monthlyEquivalentLines([
        sub(auto: false),
        sub(id: 'subscription-2', currency: 'USD'),
        sub(id: 'subscription-3', status: SubscriptionStatus.paused),
      ], today);
      expect(lines, hasLength(2));
      expect(monthlyEquivalentTotals(lines).keys, containsAll(['CNY', 'USD']));
    });
    test('trial potential independent and pending removed', () {
      final lines = monthlyEquivalentLines([
        sub(),
        sub(
          id: 'subscription-2',
          management: SubscriptionManagement(trial: trial()),
        ),
      ], today);
      expect(monthlyEquivalentTotals(lines)['CNY']!.display, '120');
      expect(
        monthlyEquivalentTotals(lines, potential: true)['CNY']!.display,
        '120',
      );
      expect(
        monthlyEquivalentLines([
          sub(
            management: SubscriptionManagement(trial: trial(end: today)),
          ),
        ], today),
        isEmpty,
      );
    });
    test(
      'forecast excludes previous dates, covers exactly twelve natural months',
      () {
        final f = SubscriptionForecast.build([
          sub(next: DateTime(2026, 9, 3)),
          sub(id: 'subscription-2', next: today),
        ], today);
        expect(f.months.first, DateTime(2026, 9));
        expect(f.months.last, DateTime(2027, 8));
        expect(f.lines, hasLength(12));
        expect(f.excluded[ForecastExclusion.overdue], 1);
      },
    );
    for (final day in [28, 29, 30, 31]) {
      test('January $day anchor survives February', () {
        final s = sub(
          first: DateTime(2026, 1, 1),
          next: DateTime(2027, 1, day),
        );
        final f = SubscriptionForecast.build([s], DateTime(2027, 1, 1));
        expect(f.lines[2].date, DateTime(2027, 3, day));
      });
    }
    test('leap day yearly anchor', () {
      final f = SubscriptionForecast.build([
        sub(
          first: DateTime(2024, 2, 29),
          next: DateTime(2028, 2, 29),
          unit: SubscriptionCycleUnit.year,
        ),
      ], DateTime(2028, 1, 1));
      expect(f.lines.single.date, DateTime(2028, 2, 29));
    });
    test('forecast observes future price without changing old expense', () {
      final s = sub(
        management: SubscriptionManagement(
          priceHistory: [
            price('p', DateTime(2026, 10, 1), '150', currency: 'USD'),
          ],
        ),
      );
      final f = SubscriptionForecast.build([s], today);
      expect(f.lines.first.amount, '120');
      expect(f.lines[1].amount, '150');
      expect(f.lines[1].currency, 'USD');
    });
    test('pending center detects formal and both trial conditions', () {
      final records = [
        sub(next: DateTime(2026, 9, 3)),
        sub(
          id: 'subscription-2',
          management: SubscriptionManagement(
            trial: trial(end: today, paid: DateTime(2026, 9, 5)),
          ),
        ),
        sub(
          id: 'subscription-3',
          management: SubscriptionManagement(
            trial: trial(end: today, paid: today),
          ),
        ),
      ];
      expect(
        subscriptionAttention(records, today).map((i) => i.kind).toSet(),
        SubscriptionAttentionKind.values.toSet(),
      );
    });
  });
  group('schema, payment migration and readable export', () {
    test('schema 11 migration deterministic and preserves exact amounts', () {
      final old = vault([
        sub(amount: '120.0001'),
        sub(id: 'subscription-2', payment: ' paypal '),
        sub(id: 'subscription-3', payment: '微信'),
        sub(id: 'subscription-4', payment: '微信支付'),
      ]).toEncryptedPayloadJson()..['schemaVersion'] = 11;
      final a = VaultSnapshot.fromEncryptedPayloadJson(old),
          b = VaultSnapshot.fromEncryptedPayloadJson(old);
      expect(a.paymentMethods, hasLength(3));
      expect(a.subscriptions.first.amount, '120.0001');
      expect(a.subscriptions.first.management!.historyIncomplete, isTrue);
      expect(a.subscriptions.first.management!.priceHistory, isEmpty);
      expect(
        jsonEncode(a.toEncryptedPayloadJson()),
        jsonEncode(b.toEncryptedPayloadJson()),
      );
    });
    test('future schema rejected without guessing', () {
      final raw = vault([]).toEncryptedPayloadJson()
        ..['schemaVersion'] = VaultSnapshot.currentSchemaVersion + 1;
      expect(
        () => VaultSnapshot.fromEncryptedPayloadJson(raw),
        throwsA(isA<VaultUnsupportedSchemaVersionException>()),
      );
    });
    test('new fields survive roundtrip and form draft', () {
      final s = sub(
        management: SubscriptionManagement(
          trial: trial(),
          cancellation: SubscriptionCancellationInfo(steps: 'cancel steps'),
          priceHistory: [price('p', today, '99')],
          reminderRules: [
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.trialEnd,
              daysBefore: [3, 1, 0],
            ),
          ],
        ),
      );
      final source = normalizeSubscriptionMetadata(vault([s]));
      final restored = VaultSnapshot.fromEncryptedPayloadJson(
        jsonDecode(jsonEncode(source.toEncryptedPayloadJson())),
      );
      expect(
        jsonEncode(restored.toEncryptedPayloadJson()),
        jsonEncode(source.toEncryptedPayloadJson()),
      );
      final form = SubscriptionFormController(initial: s.details),
          copy = SubscriptionFormController();
      form.advancedFields['cancelSteps'] = 'incomplete edited steps';
      copy.restoreEditorFields(form.exportEditorFields());
      expect(
        copy.toDraft().management!.cancellation!.steps,
        'incomplete edited steps',
      );
      form.dispose();
      copy.dispose();
    });
    test('rename merge archive do not rewrite historical name or amount', () {
      var v = normalizeSubscriptionMetadata(
        vault([sub(), sub(id: 'subscription-2', payment: '银行卡')]),
      );
      final a = v.paymentMethods.first, b = v.paymentMethods.last;
      final e = SubscriptionExpenseRecord.fromDraft(
        id: 'expense-1',
        draft: SubscriptionExpenseDraft(
          subscriptionId: 'subscription-1',
          serviceName: 'Cloud',
          occurredOn: today,
          amount: '1.0001',
          currency: 'USD',
          kind: SubscriptionExpenseKind.payment,
          paymentMethodId: a.id,
          paymentMethodName: a.name,
        ),
      );
      v = v.copyWith(subscriptionExpenses: [e], nextExpenseId: 2);
      v = savePaymentMethod(v, a.copyWith(name: 'Renamed'));
      expect(v.subscriptionExpenses.single.paymentMethodName, 'PayPal');
      v = mergePaymentMethods(v, fromId: a.id, intoId: b.id);
      expect(v.subscriptionExpenses.single.paymentMethodId, b.id);
      expect(v.subscriptionExpenses.single.amount, '1.0001');
      expect(() => deletePaymentMethod(v, b.id), throwsStateError);
      expect(
        savePaymentMethod(
          v,
          b.copyWith(archived: true),
        ).paymentMethods.single.archived,
        isTrue,
      );
    });
    test('CSV ZIP has normalized stage2 tables and guards formulas', () async {
      final v = normalizeSubscriptionMetadata(
        vault([
          sub(
            management: SubscriptionManagement(
              trial: trial(),
              cancellation: SubscriptionCancellationInfo(steps: '=SUM(1,2)'),
            ),
          ),
        ]),
      );
      final bytes = await collect(
        ReadableExport(v, const ReadableExportOptions()).bytes(),
      );
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(
        zip.files.map((f) => f.name),
        containsAll([
          'subscriptions.csv',
          'subscription_trials.csv',
          'subscription_reminders.csv',
          'subscription_price_history.csv',
          'payment_methods.csv',
          'expense_records.csv',
          'metadata.json',
          'README.txt',
        ]),
      );
      expect(ReadableExport.csvCell(' =SUM(1,2)'), contains("' =SUM"));
      final json =
          jsonDecode(
                utf8.decode(
                  await collect(
                    ReadableExport(
                      v,
                      const ReadableExportOptions(
                        format: ReadableExportFormat.json,
                      ),
                    ).bytes(),
                  ),
                ),
              )
              as Map;
      expect(json['schema_version'], 2);
      expect(json['restore_format'], false);
      expect((json['subscriptions'] as List).single['trial_info'], isNotNull);
      expect(json['payment_methods'], isNotEmpty);
    });
  });
}
