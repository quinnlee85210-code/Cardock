part of 'subscription_record.dart';

enum TrialOutcome { active, pending, converted, cancelled, ended }

enum SubscriptionReminderEvent { renewal, decision, trialEnd }

enum PriceChangeKind { correction, change, backfill, baseline }

enum PaymentMethodType {
  wechat,
  alipay,
  bankCard,
  appStore,
  googlePlay,
  paypal,
  other,
}

/// Dates are local calendar dates; audit timestamps are UTC instants.
final class SubscriptionTrial {
  SubscriptionTrial({
    required DateTime startsOn,
    required DateTime endsOn,
    String amount = '0',
    String currency = 'CNY',
    this.expectedAutoConvert = false,
    DateTime? firstPaidOn,
    required String formalAmount,
    String formalCurrency = 'CNY',
    this.formalCycleCount = 1,
    this.formalCycleUnit = SubscriptionCycleUnit.month,
    this.outcome = TrialOutcome.active,
    DateTime? lastConfirmedAt,
    DateTime? convertedOn,
    this.paymentConfirmed = false,
  }) : startsOn = subscriptionDateOnly(startsOn),
       endsOn = subscriptionDateOnly(endsOn),
       amount = _managementAmount(amount),
       currency = _managementCurrency(currency),
       formalAmount = _managementAmount(formalAmount),
       formalCurrency = _managementCurrency(formalCurrency),
       firstPaidOn = firstPaidOn == null
           ? null
           : subscriptionDateOnly(firstPaidOn),
       convertedOn = convertedOn == null
           ? null
           : subscriptionDateOnly(convertedOn),
       lastConfirmedAt = lastConfirmedAt?.toUtc() {
    if (this.lastConfirmedAt != null) {
      _validateSubscriptionInstant(this.lastConfirmedAt!);
    }
    if (this.endsOn.isBefore(this.startsOn) ||
        (this.convertedOn?.isBefore(this.startsOn) ?? false) ||
        (this.firstPaidOn?.isBefore(this.endsOn) ?? false) ||
        formalCycleCount < 1 ||
        formalCycleCount > 120 ||
        (outcome == TrialOutcome.converted && this.convertedOn == null) ||
        (outcome != TrialOutcome.converted && convertedOn != null)) {
      throw ArgumentError('试用日期或正式方案无效');
    }
  }
  final DateTime startsOn, endsOn;
  final String amount, currency, formalAmount, formalCurrency;
  final bool expectedAutoConvert, paymentConfirmed;
  final DateTime? firstPaidOn, lastConfirmedAt, convertedOn;
  final int formalCycleCount;
  final SubscriptionCycleUnit formalCycleUnit;
  final TrialOutcome outcome;
  bool get unresolved =>
      outcome == TrialOutcome.active || outcome == TrialOutcome.pending;
  bool needsConfirmation(DateTime now) =>
      unresolved && !endsOn.isAfter(subscriptionDateOnly(now));
  SubscriptionTrial resolve(
    TrialOutcome result, {
    required DateTime now,
    DateTime? actualPaidOn,
    String? actualAmount,
    String? actualCurrency,
    bool paid = false,
  }) {
    if (!unresolved ||
        result == TrialOutcome.active ||
        result == TrialOutcome.pending) {
      throw StateError('试用结果已处理或无效');
    }
    if (result == TrialOutcome.converted &&
        (actualPaidOn == null ||
            actualAmount == null ||
            actualCurrency == null)) {
      throw ArgumentError('请确认实际转付费日期和方案');
    }
    return SubscriptionTrial(
      startsOn: startsOn,
      endsOn: endsOn,
      amount: amount,
      currency: currency,
      expectedAutoConvert: expectedAutoConvert,
      firstPaidOn: firstPaidOn,
      formalAmount: actualAmount ?? formalAmount,
      formalCurrency: actualCurrency ?? formalCurrency,
      formalCycleCount: formalCycleCount,
      formalCycleUnit: formalCycleUnit,
      outcome: result,
      convertedOn: actualPaidOn,
      lastConfirmedAt: now,
      paymentConfirmed: paid,
    );
  }

  Map<String, Object?> toJson() => {
    'startsOn': formatSubscriptionDate(startsOn),
    'endsOn': formatSubscriptionDate(endsOn),
    'amount': amount,
    'currency': currency,
    'expectedAutoConvert': expectedAutoConvert,
    'firstPaidOn': _managementDate(firstPaidOn),
    'formalAmount': formalAmount,
    'formalCurrency': formalCurrency,
    'formalCycleCount': formalCycleCount,
    'formalCycleUnit': formalCycleUnit.name,
    'outcome': outcome.name,
    'convertedOn': _managementDate(convertedOn),
    'lastConfirmedAt': lastConfirmedAt == null
        ? null
        : formatSubscriptionUtcInstant(lastConfirmedAt!),
    'paymentConfirmed': paymentConfirmed,
  };
  factory SubscriptionTrial.fromJson(Object? value) {
    final m = _managementMap(value);
    return SubscriptionTrial(
      startsOn: _managementRequiredDate(m, 'startsOn'),
      endsOn: _managementRequiredDate(m, 'endsOn'),
      amount: _managementString(m, 'amount'),
      currency: _managementString(m, 'currency'),
      expectedAutoConvert: _managementBool(m, 'expectedAutoConvert'),
      firstPaidOn: _managementOptionalDate(m, 'firstPaidOn'),
      formalAmount: _managementString(m, 'formalAmount'),
      formalCurrency: _managementString(m, 'formalCurrency'),
      formalCycleCount: _managementInt(m, 'formalCycleCount'),
      formalCycleUnit: _managementEnum(
        SubscriptionCycleUnit.values,
        m,
        'formalCycleUnit',
      ),
      outcome: _managementEnum(TrialOutcome.values, m, 'outcome'),
      convertedOn: _managementOptionalDate(m, 'convertedOn'),
      lastConfirmedAt: m['lastConfirmedAt'] == null
          ? null
          : parseSubscriptionUtcInstant(
              _managementString(m, 'lastConfirmedAt'),
            ),
      paymentConfirmed: _managementBool(m, 'paymentConfirmed'),
    );
  }
}

final class SubscriptionReminderRule {
  SubscriptionReminderRule({
    required this.event,
    required Iterable<int> daysBefore,
  }) : daysBefore = List.unmodifiable(
         daysBefore.toList()..sort((a, b) => b.compareTo(a)),
       ) {
    if (this.daysBefore.isEmpty ||
        this.daysBefore.length > 8 ||
        this.daysBefore.toSet().length != this.daysBefore.length ||
        this.daysBefore.any((d) => d < 0 || d > 365)) {
      throw ArgumentError('每种事件需设置1到8个不同的提醒点，范围为0到365天');
    }
  }
  final SubscriptionReminderEvent event;
  final List<int> daysBefore;
  Map<String, Object?> toJson() => {
    'event': event.name,
    'daysBefore': daysBefore,
  };
  factory SubscriptionReminderRule.fromJson(Object? value) {
    final m = _managementMap(value), days = m['daysBefore'];
    if (days is! List || days.any((d) => d is! int)) {
      throw const FormatException('提醒规则格式无效');
    }
    return SubscriptionReminderRule(
      event: _managementEnum(SubscriptionReminderEvent.values, m, 'event'),
      daysBefore: days.cast<int>(),
    );
  }
}

final class SubscriptionPricePoint {
  SubscriptionPricePoint({
    required String id,
    required DateTime effectiveOn,
    required String amount,
    required String currency,
    required this.cycleCount,
    required this.cycleUnit,
    required this.kind,
    required DateTime createdAt,
    String? note,
  }) : id = _requiredText(id, '方案编号', 128),
       effectiveOn = subscriptionDateOnly(effectiveOn),
       amount = _managementAmount(amount),
       currency = _managementCurrency(currency),
       createdAt = createdAt.toUtc(),
       note = _optionalText(note, '方案备注', 2000) {
    _validateSubscriptionInstant(this.createdAt);
    if (cycleCount < 1 || cycleCount > 120) {
      throw ArgumentError('计费周期数量必须为1到120');
    }
  }
  final String id, amount, currency;
  final int cycleCount;
  final SubscriptionCycleUnit cycleUnit;
  final DateTime effectiveOn, createdAt;
  final PriceChangeKind kind;
  final String? note;
  Map<String, Object?> toJson() => {
    'id': id,
    'effectiveOn': formatSubscriptionDate(effectiveOn),
    'amount': amount,
    'currency': currency,
    'cycleCount': cycleCount,
    'cycleUnit': cycleUnit.name,
    'kind': kind.name,
    'createdAt': formatSubscriptionUtcInstant(createdAt),
    'note': note,
  };
  factory SubscriptionPricePoint.fromJson(Object? value) {
    final m = _managementMap(value);
    return SubscriptionPricePoint(
      id: _managementString(m, 'id'),
      effectiveOn: _managementRequiredDate(m, 'effectiveOn'),
      amount: _managementString(m, 'amount'),
      currency: _managementString(m, 'currency'),
      cycleCount: _managementInt(m, 'cycleCount'),
      cycleUnit: _managementEnum(SubscriptionCycleUnit.values, m, 'cycleUnit'),
      kind: _managementEnum(PriceChangeKind.values, m, 'kind'),
      createdAt: parseSubscriptionUtcInstant(_managementString(m, 'createdAt')),
      note: _managementOptionalString(m, 'note'),
    );
  }
}

final class SubscriptionCancellationInfo {
  SubscriptionCancellationInfo({
    String? location,
    String? url,
    String? steps,
    String? channelNotes,
    DateTime? manuallyConfirmedOn,
  }) : location = _optionalText(location, '取消位置', 500),
       url = _optionalText(url, '取消链接', 2048),
       steps = _optionalText(steps, '取消步骤', 10000),
       channelNotes = _optionalText(channelNotes, '渠道备注', 2000),
       manuallyConfirmedOn = manuallyConfirmedOn == null
           ? null
           : subscriptionDateOnly(manuallyConfirmedOn) {
    if (this.url != null) {
      final uri = Uri.tryParse(this.url!);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw ArgumentError('取消链接仅支持有效的 HTTP(S) 地址');
      }
    }
  }
  final String? location, url, steps, channelNotes;
  final DateTime? manuallyConfirmedOn;
  Map<String, Object?> toJson() => {
    'location': location,
    'url': url,
    'steps': steps,
    'channelNotes': channelNotes,
    'manuallyConfirmedOn': _managementDate(manuallyConfirmedOn),
  };
  factory SubscriptionCancellationInfo.fromJson(Object? value) {
    final m = _managementMap(value);
    return SubscriptionCancellationInfo(
      location: _managementOptionalString(m, 'location'),
      url: _managementOptionalString(m, 'url'),
      steps: _managementOptionalString(m, 'steps'),
      channelNotes: _managementOptionalString(m, 'channelNotes'),
      manuallyConfirmedOn: _managementOptionalDate(m, 'manuallyConfirmedOn'),
    );
  }
}

/// Embedded in the encrypted record so trash, drafts and portable backups retain it.
final class SubscriptionManagement {
  SubscriptionManagement({
    this.trial,
    Iterable<SubscriptionReminderRule> reminderRules = const [],
    Iterable<SubscriptionPricePoint> priceHistory = const [],
    this.cancellation,
    String? paymentMethodId,
    this.historyIncomplete = true,
    this.compatibilityBaseline,
  }) : reminderRules = List.unmodifiable(reminderRules),
       priceHistory = List.unmodifiable(
         priceHistory.toList()
           ..sort((a, b) => a.effectiveOn.compareTo(b.effectiveOn)),
       ),
       paymentMethodId = _optionalText(paymentMethodId, '支付方式编号', 128) {
    if (this.reminderRules.length > 3 ||
        this.reminderRules.map((r) => r.event).toSet().length !=
            this.reminderRules.length ||
        this.priceHistory.length > 500 ||
        this.priceHistory.map((p) => p.id).toSet().length !=
            this.priceHistory.length ||
        this.priceHistory
                .map((p) => formatSubscriptionDate(p.effectiveOn))
                .toSet()
                .length !=
            this.priceHistory.length) {
      throw ArgumentError('提醒或价格历史重复或超出上限');
    }
  }
  final SubscriptionTrial? trial;
  final List<SubscriptionReminderRule> reminderRules;
  final List<SubscriptionPricePoint> priceHistory;
  final SubscriptionCancellationInfo? cancellation;
  final String? paymentMethodId;
  final bool historyIncomplete;

  /// Not a historical claim. Preserves the old calculation if no dated evidence exists.
  final SubscriptionPricePoint? compatibilityBaseline;
  SubscriptionManagement copyWith({
    SubscriptionTrial? trial,
    List<SubscriptionReminderRule>? reminderRules,
    List<SubscriptionPricePoint>? priceHistory,
    SubscriptionCancellationInfo? cancellation,
    String? paymentMethodId,
    bool? historyIncomplete,
    SubscriptionPricePoint? compatibilityBaseline,
    bool clearPaymentMethod = false,
  }) => SubscriptionManagement(
    trial: trial ?? this.trial,
    reminderRules: reminderRules ?? this.reminderRules,
    priceHistory: priceHistory ?? this.priceHistory,
    cancellation: cancellation ?? this.cancellation,
    paymentMethodId: clearPaymentMethod
        ? null
        : paymentMethodId ?? this.paymentMethodId,
    historyIncomplete: historyIncomplete ?? this.historyIncomplete,
    compatibilityBaseline: compatibilityBaseline ?? this.compatibilityBaseline,
  );
  SubscriptionPricePoint? priceAt(DateTime date) {
    for (final p in priceHistory.reversed) {
      if (!p.effectiveOn.isAfter(subscriptionDateOnly(date))) return p;
    }
    return compatibilityBaseline;
  }

  SubscriptionManagement putPrice(
    SubscriptionPricePoint point, {
    bool replaceSameDay = false,
  }) {
    final sameDay = priceHistory.where(
      (p) => p.effectiveOn == point.effectiveOn,
    );
    if (sameDay.isNotEmpty && !replaceSameDay) {
      throw StateError('同一天已有方案，请确认覆盖或取消');
    }
    return copyWith(
      priceHistory: [
        ...priceHistory.where((p) => p.effectiveOn != point.effectiveOn),
        point,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'trial': trial?.toJson(),
    'reminderRules': reminderRules.map((r) => r.toJson()).toList(),
    'priceHistory': priceHistory.map((p) => p.toJson()).toList(),
    'cancellation': cancellation?.toJson(),
    'paymentMethodId': paymentMethodId,
    'historyIncomplete': historyIncomplete,
    'compatibilityBaseline': compatibilityBaseline?.toJson(),
  };
  factory SubscriptionManagement.fromJson(Object? value) {
    final m = _managementMap(value);
    return SubscriptionManagement(
      trial: m['trial'] == null ? null : SubscriptionTrial.fromJson(m['trial']),
      reminderRules: _managementList(
        m,
        'reminderRules',
        3,
      ).map(SubscriptionReminderRule.fromJson),
      priceHistory: _managementList(
        m,
        'priceHistory',
        500,
      ).map(SubscriptionPricePoint.fromJson),
      cancellation: m['cancellation'] == null
          ? null
          : SubscriptionCancellationInfo.fromJson(m['cancellation']),
      paymentMethodId: _managementOptionalString(m, 'paymentMethodId'),
      historyIncomplete: _managementBool(m, 'historyIncomplete'),
      compatibilityBaseline: m['compatibilityBaseline'] == null
          ? null
          : SubscriptionPricePoint.fromJson(m['compatibilityBaseline']),
    );
  }
}

final class PaymentMethodRecord {
  PaymentMethodRecord({
    required String id,
    required String name,
    this.type = PaymentMethodType.other,
    String? shortLabel,
    String? note,
    this.archived = false,
  }) : id = _requiredText(id, '支付方式编号', 128),
       name = _requiredText(name, '支付方式', 100),
       shortLabel = _optionalText(shortLabel, '支付方式简标', 20),
       note = _optionalText(note, '支付方式备注', 2000);
  final String id, name;
  final String? shortLabel, note;
  final PaymentMethodType type;
  final bool archived;
  PaymentMethodRecord copyWith({
    String? name,
    PaymentMethodType? type,
    String? shortLabel,
    String? note,
    bool? archived,
  }) => PaymentMethodRecord(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    shortLabel: shortLabel ?? this.shortLabel,
    note: note ?? this.note,
    archived: archived ?? this.archived,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'shortLabel': shortLabel,
    'note': note,
    'archived': archived,
  };
  factory PaymentMethodRecord.fromJson(Object? value) {
    final m = _managementMap(value);
    return PaymentMethodRecord(
      id: _managementString(m, 'id'),
      name: _managementString(m, 'name'),
      type: _managementEnum(PaymentMethodType.values, m, 'type'),
      shortLabel: _managementOptionalString(m, 'shortLabel'),
      note: _managementOptionalString(m, 'note'),
      archived: _managementBool(m, 'archived'),
    );
  }
}

String normalizedPaymentMethodName(String value) =>
    value.trim().replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase());
String _managementCurrency(String value) {
  final text = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{3,12}$').hasMatch(text)) throw ArgumentError('币种格式无效');
  return text;
}

String? _managementDate(DateTime? date) =>
    date == null ? null : formatSubscriptionDate(date);
Map<Object?, Object?> _managementMap(Object? v) {
  if (v is! Map<Object?, Object?>) throw const FormatException('订阅扩展数据无效');
  return v;
}

String _managementString(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v is! String) throw const FormatException('订阅扩展文本无效');
  return v;
}

String? _managementOptionalString(Map<Object?, Object?> m, String k) =>
    m[k] == null ? null : _managementString(m, k);
int _managementInt(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v is! int) throw const FormatException('订阅扩展数值无效');
  return v;
}

bool _managementBool(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v is! bool) throw const FormatException('订阅扩展开关无效');
  return v;
}

DateTime _managementRequiredDate(Map<Object?, Object?> m, String k) =>
    parseSubscriptionDate(_managementString(m, k));
DateTime? _managementOptionalDate(Map<Object?, Object?> m, String k) =>
    m[k] == null ? null : _managementRequiredDate(m, k);
T _managementEnum<T extends Enum>(
  List<T> values,
  Map<Object?, Object?> m,
  String k,
) {
  final name = _managementString(m, k);
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw const FormatException('订阅扩展枚举无效');
}

List<Object?> _managementList(Map<Object?, Object?> m, String k, int maximum) {
  final v = m[k];
  if (v is! List<Object?> || v.length > maximum) {
    throw const FormatException('订阅扩展列表无效');
  }
  return v;
}

String _managementAmount(String value) =>
    _normalizeAmount(value) ?? (throw ArgumentError('请填写有效金额'));
