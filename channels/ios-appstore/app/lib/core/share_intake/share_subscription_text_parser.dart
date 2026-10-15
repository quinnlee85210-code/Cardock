enum ShareCycleUnit { day, month, year }

final class ShareAmountCandidate {
  const ShareAmountCandidate({required this.amount, this.currency});

  final String amount;
  final String? currency;

  String get label => currency == null ? amount : '$currency $amount';
}

final class ShareBillingCycleCandidate {
  const ShareBillingCycleCandidate({required this.count, required this.unit});

  final int count;
  final ShareCycleUnit unit;

  String get key => '$count:${unit.name}';
}

final class ShareTextExtraction {
  const ShareTextExtraction({
    required this.platforms,
    required this.plans,
    required this.amounts,
    required this.currencies,
    required this.cycles,
    required this.renewalDates,
    required this.autoRenewValues,
    required this.urls,
  });

  final List<String> platforms;
  final List<String> plans;
  final List<ShareAmountCandidate> amounts;
  final List<String> currencies;
  final List<ShareBillingCycleCandidate> cycles;
  final List<DateTime> renewalDates;
  final List<bool> autoRenewValues;
  final List<String> urls;
}

final class ShareSubscriptionTextParser {
  const ShareSubscriptionTextParser();

  static final RegExp _negativeContext = RegExp(
    r'(订单|订单号|购买|买断|一次性|税费?|退款|物流|发货|快递|收货|验证码|激活码|'
    r'order|purchase|one[- ]?time|invoice|receipt|tax|refund|shipping|delivery|tracking|activation code|'
    r'注文|購入|買い切り|税|返金|配送|追跡|アクティベーションコード)',
    caseSensitive: false,
  );
  static final RegExp _platformLabel = RegExp(
    r'^\s*(?:平台|服务|应用|platform|service|app|プラットフォーム|サービス|アプリ)\s*[:：]\s*(.+?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _planLabel = RegExp(
    r'^\s*(?:套餐|方案|plan|tier|プラン|コース)\s*[:：]\s*(.+?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _currencyLabel = RegExp(
    r'^\s*(?:币种|货币|currency|通貨)\s*[:：]\s*([A-Za-z]{3})\s*$',
    caseSensitive: false,
  );
  static final RegExp _renewalContext = RegExp(
    r'(续费|续订|到期|下次扣费|renew|next billing|expires?|更新日|次回請求|有効期限)',
    caseSensitive: false,
  );
  static final RegExp _url = RegExp(
    r'https?://[^\s<>"'
    '\u0000-\u001f]+',
    caseSensitive: false,
  );
  static const List<String> _currencyCodes = <String>[
    'CNY',
    'RMB',
    'USD',
    'JPY',
    'EUR',
    'GBP',
    'HKD',
    'TWD',
    'AUD',
    'CAD',
    'SGD',
    'KRW',
  ];

  ShareTextExtraction parse({
    required String text,
    String? subject,
    String? title,
  }) {
    final platforms = <String>[];
    final plans = <String>[];
    final amounts = <ShareAmountCandidate>[];
    final currencies = <String>[];
    final cycles = <ShareBillingCycleCandidate>[];
    final renewalDates = <DateTime>[];
    final autoRenewValues = <bool>[];
    final urls = <String>[];
    final lines = <String>[
      ...<String?>[title, subject].whereType<String>(),
      ...text.split(RegExp(r'[\r\n]+')),
    ];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final negative = _negativeContext.hasMatch(line);
      if (!negative) {
        _addLabeledValue(platforms, _platformLabel, line);
        _addLabeledValue(plans, _planLabel, line);
        final currency = _currencyLabel
            .firstMatch(line)
            ?.group(1)
            ?.toUpperCase();
        if (currency != null && _currencyCodes.contains(currency)) {
          _addUniqueString(currencies, currency);
        }
        _extractAmounts(line, amounts, currencies);
        _extractCycles(line, cycles);
        _extractAutoRenew(line, autoRenewValues);
        if (_renewalContext.hasMatch(line)) {
          _extractDates(line, renewalDates);
        }
        _extractUrls(line, urls);
      }
    }

    return ShareTextExtraction(
      platforms: List<String>.unmodifiable(platforms),
      plans: List<String>.unmodifiable(plans),
      amounts: List<ShareAmountCandidate>.unmodifiable(amounts),
      currencies: List<String>.unmodifiable(currencies),
      cycles: List<ShareBillingCycleCandidate>.unmodifiable(cycles),
      renewalDates: List<DateTime>.unmodifiable(renewalDates),
      autoRenewValues: List<bool>.unmodifiable(autoRenewValues),
      urls: List<String>.unmodifiable(urls),
    );
  }

  void _addLabeledValue(List<String> output, RegExp pattern, String line) {
    final value = pattern.firstMatch(line)?.group(1)?.trim();
    if (value == null || value.isEmpty || value.runes.length > 120) return;
    final withoutUrl = value.replaceAll(_url, '').trim();
    if (withoutUrl.isNotEmpty) _addUniqueString(output, withoutUrl);
  }

  void _extractAmounts(
    String line,
    List<ShareAmountCandidate> amounts,
    List<String> currencies,
  ) {
    final countBeforeLine = amounts.length;
    const number = r'((?:\d{1,3}(?:,\d{3})+|\d{1,12})(?:\.\d{1,4})?)';
    final codeAlternation = _currencyCodes.join('|');
    final before = RegExp(
      '\\b($codeAlternation)\\s*$number',
      caseSensitive: false,
    );
    final after = RegExp(
      '$number\\s*\\b($codeAlternation)\\b',
      caseSensitive: false,
    );
    for (final match in before.allMatches(line)) {
      _addAmount(amounts, match.group(2)!, match.group(1)!, currencies);
    }
    for (final match in after.allMatches(line)) {
      _addAmount(amounts, match.group(1)!, match.group(2)!, currencies);
    }
    final symbols = RegExp('(CN¥|JP¥|€|£)\\s*$number', caseSensitive: false);
    for (final match in symbols.allMatches(line)) {
      final currency = switch (match.group(1)!.toUpperCase()) {
        'CN¥' => 'CNY',
        'JP¥' => 'JPY',
        '€' => 'EUR',
        '£' => 'GBP',
        _ => null,
      };
      _addAmount(amounts, match.group(2)!, currency, currencies);
    }
    if (amounts.length == countBeforeLine &&
        RegExp(
          r'^\s*(?:金额|价格|amount|price|金額|料金)\s*[:：]',
          caseSensitive: false,
        ).hasMatch(line)) {
      final bare = RegExp(number).firstMatch(line)?.group(1);
      if (bare != null) _addAmount(amounts, bare, null, currencies);
    }
  }

  void _addAmount(
    List<ShareAmountCandidate> output,
    String rawAmount,
    String? rawCurrency,
    List<String> currencies,
  ) {
    final amount = rawAmount.replaceAll(',', '');
    if (!RegExp(r'^(?:0|[1-9]\d{0,11})(?:\.\d{1,4})?$').hasMatch(amount)) {
      return;
    }
    var currency = rawCurrency?.toUpperCase();
    if (currency == 'RMB') currency = 'CNY';
    if (currency != null && !_currencyCodes.contains(currency)) return;
    if (output.any(
      (item) => item.amount == amount && item.currency == currency,
    )) {
      return;
    }
    output.add(ShareAmountCandidate(amount: amount, currency: currency));
    if (currency != null) _addUniqueString(currencies, currency);
  }

  void _extractCycles(String line, List<ShareBillingCycleCandidate> output) {
    void add(int count, ShareCycleUnit unit) {
      if (count < 1 || count > 120) return;
      final value = ShareBillingCycleCandidate(count: count, unit: unit);
      if (output.every((item) => item.key != value.key)) output.add(value);
    }

    if (RegExp(
      r'(每月|月付|monthly|per month|月額)',
      caseSensitive: false,
    ).hasMatch(line)) {
      add(1, ShareCycleUnit.month);
    }
    if (RegExp(
      r'(每年|年付|annual|yearly|per year|年額)',
      caseSensitive: false,
    ).hasMatch(line)) {
      add(1, ShareCycleUnit.year);
    }
    final zh = RegExp(r'每\s*(\d{1,3})\s*(天|日|个月|個月|月|年)');
    for (final match in zh.allMatches(line)) {
      add(int.parse(match.group(1)!), switch (match.group(2)!) {
        '天' || '日' => ShareCycleUnit.day,
        '年' => ShareCycleUnit.year,
        _ => ShareCycleUnit.month,
      });
    }
    final en = RegExp(
      r'every\s+(\d{1,3})\s+(day|days|month|months|year|years)\b',
      caseSensitive: false,
    );
    for (final match in en.allMatches(line)) {
      add(int.parse(match.group(1)!), switch (match.group(2)!.toLowerCase()) {
        'day' || 'days' => ShareCycleUnit.day,
        'year' || 'years' => ShareCycleUnit.year,
        _ => ShareCycleUnit.month,
      });
    }
    final ja = RegExp(r'(\d{1,3})\s*(日|か月|ヶ月|年)\s*(?:ごと|毎)');
    for (final match in ja.allMatches(line)) {
      add(int.parse(match.group(1)!), switch (match.group(2)!) {
        '日' => ShareCycleUnit.day,
        '年' => ShareCycleUnit.year,
        _ => ShareCycleUnit.month,
      });
    }
  }

  void _extractAutoRenew(String line, List<bool> output) {
    final normalized = line.toLowerCase();
    bool? value;
    if (RegExp(
          r'(自动续费|自动续订)\s*[:：]?\s*(是|开启|开|已开启|否|关闭|关|已关闭)',
        ).firstMatch(line)
        case final match?) {
      value = !<String>{'否', '关闭', '关', '已关闭'}.contains(match.group(2));
    } else if (RegExp(
          r'auto[- ]?renew(?:al)?\s*[:：]?\s*(on|yes|enabled|off|no|disabled)',
          caseSensitive: false,
        ).firstMatch(line)
        case final match?) {
      value = <String>{
        'on',
        'yes',
        'enabled',
      }.contains(match.group(1)!.toLowerCase());
    } else if (RegExp(r'自動更新\s*[:：]?\s*(有効|無効|する|しない)').firstMatch(line)
        case final match?) {
      value = <String>{'有効', 'する'}.contains(match.group(1));
    } else if (normalized.contains('renews automatically')) {
      value = true;
    }
    if (value != null && !output.contains(value)) output.add(value);
  }

  void _extractDates(String line, List<DateTime> output) {
    final iso = RegExp(r'\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b');
    for (final match in iso.allMatches(line)) {
      _addDate(output, match.group(1)!, match.group(2)!, match.group(3)!);
    }
    final cjk = RegExp(r'\b(20\d{2})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日');
    for (final match in cjk.allMatches(line)) {
      _addDate(output, match.group(1)!, match.group(2)!, match.group(3)!);
    }
    final english = RegExp(
      r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s*(20\d{2})\b',
      caseSensitive: false,
    );
    const months = <String>[
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    for (final match in english.allMatches(line)) {
      _addDate(
        output,
        match.group(3)!,
        '${months.indexOf(match.group(1)!.toLowerCase()) + 1}',
        match.group(2)!,
      );
    }
  }

  void _addDate(List<DateTime> output, String year, String month, String day) {
    final y = int.parse(year);
    final m = int.parse(month);
    final d = int.parse(day);
    final value = DateTime(y, m, d);
    if (value.year != y || value.month != m || value.day != d) return;
    if (output.every(
      (item) => item.year != y || item.month != m || item.day != d,
    )) {
      output.add(value);
    }
  }

  void _extractUrls(String line, List<String> output) {
    for (final match in _url.allMatches(line)) {
      var value = match.group(0)!;
      value = value.replaceFirst(RegExp(r'[\)\]\}\.,;:!?，。；：！？》」』]+$'), '');
      final uri = Uri.tryParse(value);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          value.length > 2048) {
        continue;
      }
      _addUniqueString(output, value);
    }
  }

  void _addUniqueString(List<String> output, String value) {
    if (output.every((item) => item.toLowerCase() != value.toLowerCase())) {
      output.add(value);
    }
  }
}
