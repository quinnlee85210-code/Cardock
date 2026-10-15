import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/exchange_rates/semiannual_cny_exchange_rates.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('2026上半年离线汇率覆盖全部内置订阅币种', () {
    expect(SemiannualCnyExchangeRates.snapshotId, 'cny-2026-h1-v1');
    expect(SemiannualCnyExchangeRates.periodStart, '2026-01-01');
    expect(SemiannualCnyExchangeRates.periodEnd, '2026-06-30');
    expect(
      SemiannualCnyExchangeRates.rates.keys.toSet(),
      subscriptionCurrencies.toSet(),
    );
    expect(
      SemiannualCnyExchangeRates.rates.values
          .where((rate) => rate.currency != 'CNY' && rate.currency != 'TWD')
          .every(
            (rate) =>
                rate.observationCount ==
                SemiannualCnyExchangeRates.centralParityObservationCount,
          ),
      isTrue,
    );
    expect(
      SemiannualCnyExchangeRates.rates['TWD']?.observationCount,
      SemiannualCnyExchangeRates.twdCrossObservationCount,
    );
  });

  test('汇率常量保持官方数据归一化后的算术平均值', () {
    const expected = <String, double>{
      'CNY': 1,
      'USD': 6.8931836207,
      'EUR': 8.0195568966,
      'CAD': 4.9880620690,
      'JPY': 0.0434675603,
      'GBP': 9.2466258621,
      'HKD': 0.8810520690,
      'AUD': 4.8274034483,
      'CHF': 8.7377000000,
      'SGD': 5.3811051724,
      'KRW': 0.0046297447,
      'TWD': 0.2179450791,
    };

    for (final entry in expected.entries) {
      expect(
        SemiannualCnyExchangeRates.rates[entry.key]?.cnyPerUnit,
        closeTo(entry.value, 1e-12),
        reason: entry.key,
      );
    }
    expect(
      SemiannualCnyExchangeRates.rates['JPY']?.sourceQuote,
      '100JPY/CNY ÷ 100',
    );
    expect(
      SemiannualCnyExchangeRates.rates['KRW']?.method,
      SemiannualCnyRateMethod.normalizedCentralParity,
    );
    expect(
      SemiannualCnyExchangeRates.rates['TWD']?.method,
      SemiannualCnyRateMethod.officialCrossRate,
    );
  });

  test('官方来源证据清单与运行时离线汇率逐项一致', () {
    final manifest =
        jsonDecode(
              File(
                '../manifests/exchange-rates-2026-h1-source-validation.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final averages =
        manifest['cny_per_unit_arithmetic_averages']! as Map<String, Object?>;
    final sources = manifest['sources']! as List<Object?>;
    final chinaMoney = sources.first! as Map<String, Object?>;
    final twdCross = manifest['twd_cross_rate']! as Map<String, Object?>;

    expect(manifest['snapshot_id'], SemiannualCnyExchangeRates.snapshotId);
    expect(
      chinaMoney['official_publication_days'],
      SemiannualCnyExchangeRates.centralParityObservationCount,
    );
    expect(
      twdCross['overlap_observations'],
      SemiannualCnyExchangeRates.twdCrossObservationCount,
    );
    expect(twdCross['is_direct_central_parity'], isFalse);
    expect(
      averages.keys.toSet(),
      SemiannualCnyExchangeRates.rates.keys.toSet(),
    );
    for (final entry in SemiannualCnyExchangeRates.rates.entries) {
      expect(
        double.parse(averages[entry.key]! as String),
        closeTo(entry.value.cnyPerUnit, 1e-12),
        reason: entry.key,
      );
    }
  });

  test('人民币估算合计区分已换算、缺少金额和未支持币种', () {
    final estimate = CnyAmountEstimate.fromInputs(const [
      CurrencyAmountInput(currency: 'CNY', amount: '10'),
      CurrencyAmountInput(currency: ' usd ', amount: '2'),
      CurrencyAmountInput(currency: 'TWD', amount: '3'),
      CurrencyAmountInput(currency: 'EUR'),
      CurrencyAmountInput(currency: 'CUSTOM', amount: '4'),
    ]);

    expect(estimate.lineCount, 5);
    expect(estimate.convertedCount, 3);
    expect(estimate.missingAmountCount, 1);
    expect(estimate.unsupportedCurrencyCount, 1);
    expect(estimate.excludedCount, 2);
    expect(
      estimate.totalCny,
      closeTo(10 + (2 * 6.8931836207) + (3 * 0.2179450791), 1e-10),
    );
    expect(
      SemiannualCnyExchangeRates.convertToCny(currency: 'UNKNOWN', amount: 1),
      isNull,
    );
  });
}
