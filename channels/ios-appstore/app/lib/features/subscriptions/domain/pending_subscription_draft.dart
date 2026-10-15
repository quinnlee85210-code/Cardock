import 'subscription_record.dart';

enum PendingSubscriptionDraftSource { batchImport }

final class PendingSubscriptionBillingCycle {
  const PendingSubscriptionBillingCycle({
    required this.count,
    required this.unit,
  });

  factory PendingSubscriptionBillingCycle.fromEncryptedPayloadJson(
    Object? value,
  ) {
    if (value is! Map<Object?, Object?> ||
        value['count'] is! int ||
        value['unit'] is! String) {
      throw const FormatException('待完善订阅计费周期格式无效');
    }
    final count = value['count']! as int;
    final unitName = value['unit']! as String;
    final unit = SubscriptionCycleUnit.values
        .where((candidate) => candidate.name == unitName)
        .firstOrNull;
    if (count < 1 || count > 120 || unit == null) {
      throw const FormatException('待完善订阅计费周期格式无效');
    }
    return PendingSubscriptionBillingCycle(count: count, unit: unit);
  }

  final int count;
  final SubscriptionCycleUnit unit;

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'count': count,
    'unit': unit.name,
  };
}

/// 位于保险库加密边界内、但尚不是正式订阅的批量导入草稿。
///
/// 字段允许不完整；统计、提醒和正式订阅投影只能读取
/// [SubscriptionRecord]，不得把本类型混入其中。
final class PendingSubscriptionDraft {
  factory PendingSubscriptionDraft({
    required String draftId,
    required String accountId,
    String? planName,
    String? amount,
    String? currency,
    PendingSubscriptionBillingCycle? billingCycle,
    DateTime? subscriptionStartDate,
    DateTime? nextRenewalDate,
    bool? autoRenew,
    String? paymentMethod,
    int? reminderDays,
    String? notes,
    required DateTime createdAt,
    required DateTime updatedAt,
    PendingSubscriptionDraftSource source =
        PendingSubscriptionDraftSource.batchImport,
  }) {
    final normalizedId = _requiredText(draftId, 128);
    final normalizedAccountId = _requiredText(accountId, 128);
    final normalizedPlanName = _optionalText(planName, 200);
    final normalizedAmount = _optionalText(amount, 64);
    final normalizedCurrency = _optionalText(currency, 3)?.toUpperCase();
    if (normalizedCurrency != null &&
        !RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCurrency)) {
      throw ArgumentError('币种格式无效');
    }
    if (billingCycle != null &&
        (billingCycle.count < 1 || billingCycle.count > 120)) {
      throw ArgumentError('计费周期无效');
    }
    final normalizedStart = subscriptionStartDate == null
        ? null
        : subscriptionDateOnly(subscriptionStartDate);
    final normalizedRenewal = nextRenewalDate == null
        ? null
        : subscriptionDateOnly(nextRenewalDate);
    if (reminderDays != null && (reminderDays < 0 || reminderDays > 365)) {
      throw ArgumentError('提前提醒天数必须为0到365');
    }
    final normalizedCreated = _utcInstant(createdAt);
    final normalizedUpdated = _utcInstant(updatedAt);
    if (normalizedUpdated.isBefore(normalizedCreated)) {
      throw ArgumentError('草稿更新时间不能早于创建时间');
    }
    return PendingSubscriptionDraft._(
      draftId: normalizedId,
      accountId: normalizedAccountId,
      planName: normalizedPlanName,
      amount: normalizedAmount,
      currency: normalizedCurrency,
      billingCycle: billingCycle,
      subscriptionStartDate: normalizedStart,
      nextRenewalDate: normalizedRenewal,
      autoRenew: autoRenew,
      paymentMethod: _optionalText(paymentMethod, 100),
      reminderDays: reminderDays,
      notes: _optionalText(notes, 10000),
      createdAt: normalizedCreated,
      updatedAt: normalizedUpdated,
      source: source,
    );
  }

  const PendingSubscriptionDraft._({
    required this.draftId,
    required this.accountId,
    required this.planName,
    required this.amount,
    required this.currency,
    required this.billingCycle,
    required this.subscriptionStartDate,
    required this.nextRenewalDate,
    required this.autoRenew,
    required this.paymentMethod,
    required this.reminderDays,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
  });

  factory PendingSubscriptionDraft.fromEncryptedPayloadJson(Object? value) {
    try {
      if (value is! Map<Object?, Object?> ||
          value['draftId'] is! String ||
          value['accountId'] is! String ||
          value['createdAt'] is! String ||
          value['updatedAt'] is! String ||
          value['source'] != PendingSubscriptionDraftSource.batchImport.name) {
        throw const FormatException('待完善订阅草稿格式无效');
      }
      T? optional<T>(String name) {
        final field = value[name];
        if (field == null) return null;
        if (field is! T) {
          throw const FormatException('待完善订阅草稿格式无效');
        }
        return field as T;
      }

      return PendingSubscriptionDraft(
        draftId: value['draftId']! as String,
        accountId: value['accountId']! as String,
        planName: optional<String>('planName'),
        amount: optional<String>('amount'),
        currency: optional<String>('currency'),
        billingCycle: value['billingCycle'] == null
            ? null
            : PendingSubscriptionBillingCycle.fromEncryptedPayloadJson(
                value['billingCycle'],
              ),
        subscriptionStartDate: value['subscriptionStartDate'] == null
            ? null
            : parseSubscriptionDate(optional<String>('subscriptionStartDate')!),
        nextRenewalDate: value['nextRenewalDate'] == null
            ? null
            : parseSubscriptionDate(optional<String>('nextRenewalDate')!),
        autoRenew: optional<bool>('autoRenew'),
        paymentMethod: optional<String>('paymentMethod'),
        reminderDays: optional<int>('reminderDays'),
        notes: optional<String>('notes'),
        createdAt: _parseUtcInstant(value['createdAt']! as String),
        updatedAt: _parseUtcInstant(value['updatedAt']! as String),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError {
      throw const FormatException('待完善订阅草稿格式无效');
    }
  }

  final String draftId;
  final String accountId;
  final String? planName;
  final String? amount;
  final String? currency;
  final PendingSubscriptionBillingCycle? billingCycle;
  final DateTime? subscriptionStartDate;
  final DateTime? nextRenewalDate;
  final bool? autoRenew;
  final String? paymentMethod;
  final int? reminderDays;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PendingSubscriptionDraftSource source;

  List<String> get missingFormalFields => <String>[
    if (planName == null) 'planName',
    if (amount == null ||
        !RegExp(r'^(0|[1-9]\d{0,11})(\.\d{1,4})?$').hasMatch(amount!))
      'amount',
    if (currency == null) 'currency',
    if (billingCycle == null) 'billingCycle',
    if (subscriptionStartDate == null) 'subscriptionStartDate',
    if (nextRenewalDate == null) 'nextRenewalDate',
    if (subscriptionStartDate != null &&
        nextRenewalDate != null &&
        nextRenewalDate!.isBefore(subscriptionStartDate!))
      'subscriptionDateOrder',
    if (autoRenew == null) 'autoRenew',
    if (paymentMethod == null) 'paymentMethod',
    if (reminderDays == null) 'reminderDays',
  ];

  bool get isCompleteForFormalValidation => missingFormalFields.isEmpty;

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'draftId': draftId,
    'accountId': accountId,
    'planName': planName,
    'amount': amount,
    'currency': currency,
    'billingCycle': billingCycle?.toEncryptedPayloadJson(),
    'subscriptionStartDate': subscriptionStartDate == null
        ? null
        : formatSubscriptionDate(subscriptionStartDate!),
    'nextRenewalDate': nextRenewalDate == null
        ? null
        : formatSubscriptionDate(nextRenewalDate!),
    'autoRenew': autoRenew,
    'paymentMethod': paymentMethod,
    'reminderDays': reminderDays,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'source': source.name,
  };

  static String _requiredText(String value, int maximumLength) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.runes.length > maximumLength) {
      throw ArgumentError('草稿编号无效');
    }
    return normalized;
  }

  static String? _optionalText(String? value, int maximumLength) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.runes.length > maximumLength) {
      throw ArgumentError('草稿字段内容过长');
    }
    return normalized;
  }

  static DateTime _utcInstant(DateTime value) {
    final utc = value.toUtc();
    if (utc.year < 1970 || utc.year > 2300) {
      throw ArgumentError('草稿时间超出支持范围');
    }
    return utc;
  }

  static DateTime _parseUtcInstant(String value) {
    if (value.length > 32 || !value.endsWith('Z')) {
      throw const FormatException('待完善订阅草稿时间格式无效');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('待完善订阅草稿时间格式无效');
    }
    return _utcInstant(parsed);
  }
}
