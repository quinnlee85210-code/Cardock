enum SemiannualCnyRateMethod {
  baseCurrency,
  directCentralParity,
  normalizedCentralParity,
  officialCrossRate,
}

final class SemiannualCnyRate {
  const SemiannualCnyRate({
    required this.currency,
    required this.cnyPerUnit,
    required this.observationCount,
    required this.method,
    required this.sourceQuote,
  });

  final String currency;
  final double cnyPerUnit;
  final int observationCount;
  final SemiannualCnyRateMethod method;
  final String sourceQuote;
}

abstract final class SemiannualCnyExchangeRates {
  static const String snapshotId = 'cny-2026-h1-v1';
  static const String periodLabel = '2026上半年';
  static const String periodStart = '2026-01-01';
  static const String periodEnd = '2026-06-30';
  static const int centralParityObservationCount = 116;
  static const int twdCrossObservationCount = 114;

  static const String chinaMoneySourceName = '中国外汇交易中心/中国货币网（中国人民银行授权）';
  static const String chinaMoneySourceUrl =
      'https://www.chinamoney.com.cn/chinese/bkccpr/';
  static const String taiwanCbcSourceName = '台湾中央银行新台币/美元银行间收盘汇率';
  static const String taiwanCbcSourceUrl =
      'https://www.cbc.gov.tw/tw/lp-645-1.html';

  static const Map<String, SemiannualCnyRate> rates =
      <String, SemiannualCnyRate>{
        'CNY': SemiannualCnyRate(
          currency: 'CNY',
          cnyPerUnit: 1,
          observationCount: 0,
          method: SemiannualCnyRateMethod.baseCurrency,
          sourceQuote: 'CNY',
        ),
        'USD': SemiannualCnyRate(
          currency: 'USD',
          cnyPerUnit: 6.8931836207,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'USD/CNY',
        ),
        'EUR': SemiannualCnyRate(
          currency: 'EUR',
          cnyPerUnit: 8.0195568966,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'EUR/CNY',
        ),
        'CAD': SemiannualCnyRate(
          currency: 'CAD',
          cnyPerUnit: 4.9880620690,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'CAD/CNY',
        ),
        'JPY': SemiannualCnyRate(
          currency: 'JPY',
          cnyPerUnit: 0.0434675603,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.normalizedCentralParity,
          sourceQuote: '100JPY/CNY ÷ 100',
        ),
        'GBP': SemiannualCnyRate(
          currency: 'GBP',
          cnyPerUnit: 9.2466258621,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'GBP/CNY',
        ),
        'HKD': SemiannualCnyRate(
          currency: 'HKD',
          cnyPerUnit: 0.8810520690,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'HKD/CNY',
        ),
        'AUD': SemiannualCnyRate(
          currency: 'AUD',
          cnyPerUnit: 4.8274034483,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'AUD/CNY',
        ),
        'CHF': SemiannualCnyRate(
          currency: 'CHF',
          cnyPerUnit: 8.7377000000,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'CHF/CNY',
        ),
        'SGD': SemiannualCnyRate(
          currency: 'SGD',
          cnyPerUnit: 5.3811051724,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.directCentralParity,
          sourceQuote: 'SGD/CNY',
        ),
        'KRW': SemiannualCnyRate(
          currency: 'KRW',
          cnyPerUnit: 0.0046297447,
          observationCount: centralParityObservationCount,
          method: SemiannualCnyRateMethod.normalizedCentralParity,
          sourceQuote: '逐日 1 ÷ CNY/KRW',
        ),
        'TWD': SemiannualCnyRate(
          currency: 'TWD',
          cnyPerUnit: 0.2179450791,
          observationCount: twdCrossObservationCount,
          method: SemiannualCnyRateMethod.officialCrossRate,
          sourceQuote: '逐日 USD/CNY ÷ NTD/USD',
        ),
      };

  static SemiannualCnyRate? rateFor(String currency) =>
      rates[currency.trim().toUpperCase()];

  static double? convertToCny({
    required String currency,
    required double amount,
  }) {
    if (!amount.isFinite || amount < 0) {
      return null;
    }
    final rate = rateFor(currency);
    return rate == null ? null : amount * rate.cnyPerUnit;
  }
}

final class CurrencyAmountInput {
  const CurrencyAmountInput({
    required this.currency,
    this.amount,
    this.refund = false,
  });

  final bool refund;

  final String currency;
  final String? amount;
}

final class CnyAmountEstimate {
  const CnyAmountEstimate._({
    required this.totalCny,
    required this.lineCount,
    required this.convertedCount,
    required this.missingAmountCount,
    required this.unsupportedCurrencyCount,
  });

  factory CnyAmountEstimate.fromInputs(Iterable<CurrencyAmountInput> inputs) {
    var totalCny = 0.0;
    var lineCount = 0;
    var convertedCount = 0;
    var missingAmountCount = 0;
    var unsupportedCurrencyCount = 0;

    for (final input in inputs) {
      lineCount += 1;
      final amount = double.tryParse(input.amount ?? '');
      if (amount == null || !amount.isFinite || amount < 0) {
        missingAmountCount += 1;
        continue;
      }
      final converted = SemiannualCnyExchangeRates.convertToCny(
        currency: input.currency,
        amount: amount,
      );
      if (converted == null) {
        unsupportedCurrencyCount += 1;
        continue;
      }
      totalCny += input.refund ? -converted : converted;
      convertedCount += 1;
    }

    return CnyAmountEstimate._(
      totalCny: totalCny,
      lineCount: lineCount,
      convertedCount: convertedCount,
      missingAmountCount: missingAmountCount,
      unsupportedCurrencyCount: unsupportedCurrencyCount,
    );
  }

  final double totalCny;
  final int lineCount;
  final int convertedCount;
  final int missingAmountCount;
  final int unsupportedCurrencyCount;

  int get excludedCount => missingAmountCount + unsupportedCurrencyCount;
  bool get hasConvertedAmount => convertedCount > 0;
}
