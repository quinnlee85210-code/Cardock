import 'subscription_record.dart';

enum SubscriptionExpenseKind { payment, refund }

enum SubscriptionExpenseSource {
  manual,
  subscriptionEntry,
  renewal,
  trialPayment,
  trialConversion,
}

const maximumConfirmedSubscriptionExpenses = 50000;

final class SubscriptionExpenseDraft {
  factory SubscriptionExpenseDraft({
    required String? subscriptionId,
    required String serviceName,
    required DateTime occurredOn,
    required String amount,
    required String currency,
    required SubscriptionExpenseKind kind,
    String? expenseCategory,
    DateTime? scheduledRenewalOn,
    String? accountId,
    String? paymentMethodId,
    String? paymentMethodName,
  }) {
    if (accountId != null && (accountId.isEmpty || accountId.length > 128)) {
      throw ArgumentError('关联账号无效');
    }
    if ((paymentMethodId?.length ?? 0) > 128 ||
        (paymentMethodName?.length ?? 0) > 100) {
      throw ArgumentError('支付方式快照内容过长');
    }
    final normalizedSubscriptionId = subscriptionId?.trim();
    if (normalizedSubscriptionId != null &&
        (normalizedSubscriptionId.isEmpty ||
            normalizedSubscriptionId.runes.length > 128)) {
      throw ArgumentError('关联订阅无效');
    }
    final normalizedServiceName = serviceName.trim();
    if (normalizedServiceName.isEmpty ||
        normalizedServiceName.runes.length > 100) {
      throw ArgumentError('订阅服务名称无效');
    }
    final normalizedAmount = amount.trim();
    if (!RegExp(
      r'^(0|[1-9]\d{0,11})(\.\d{1,4})?$',
    ).hasMatch(normalizedAmount)) {
      throw ArgumentError('金额格式无效，最多保留4位小数');
    }
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty || normalizedCurrency.runes.length > 12) {
      throw ArgumentError('币种格式无效');
    }
    final normalizedCategory = expenseCategory?.trim();
    if (normalizedCategory != null && normalizedCategory.runes.length > 100) {
      throw ArgumentError('费用分类内容过长');
    }
    return SubscriptionExpenseDraft._(
      subscriptionId: normalizedSubscriptionId,
      paymentMethodId: paymentMethodId,
      paymentMethodName: paymentMethodName,
      accountId: accountId,
      serviceName: normalizedServiceName,
      occurredOn: subscriptionDateOnly(occurredOn),
      amount: normalizedAmount,
      currency: normalizedCurrency,
      kind: kind,
      expenseCategory: normalizedCategory == null || normalizedCategory.isEmpty
          ? null
          : normalizedCategory,
      scheduledRenewalOn: scheduledRenewalOn == null
          ? null
          : subscriptionDateOnly(scheduledRenewalOn),
    );
  }

  const SubscriptionExpenseDraft._({
    required this.accountId,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.subscriptionId,
    required this.serviceName,
    required this.occurredOn,
    required this.amount,
    required this.currency,
    required this.kind,
    required this.expenseCategory,
    required this.scheduledRenewalOn,
  });

  final String? accountId;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final String? subscriptionId;
  final String serviceName;
  final DateTime occurredOn;
  final String amount;
  final String currency;
  final SubscriptionExpenseKind kind;
  final String? expenseCategory;
  final DateTime? scheduledRenewalOn;
}

/// 用户明确确认的一笔本机订阅支出或退款。
///
/// 这是用户确认记录，不是银行或订阅平台的联网对账结果。服务名、金额、币种
/// 与费用分类均保存快照；删除订阅时只解除关联，历史金额不会随卡片一起消失。
final class SubscriptionExpenseRecord {
  const SubscriptionExpenseRecord._({
    required this.isDeleted,
    required this.accountId,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.accountLabel,
    required this.source,
    required this.id,
    required this.subscriptionId,
    required this.serviceName,
    required this.occurredOn,
    required this.amount,
    required this.currency,
    required this.kind,
    required this.expenseCategory,
    required this.scheduledRenewalOn,
    required this.recordedAtUtc,
  });

  factory SubscriptionExpenseRecord.fromDraft({
    bool isDeleted = false,
    required String id,
    required SubscriptionExpenseDraft draft,
    DateTime? recordedAtUtc,
    String? accountLabel,
    SubscriptionExpenseSource source = SubscriptionExpenseSource.manual,
  }) {
    if (accountLabel != null && accountLabel.length > 1024) {
      throw ArgumentError('账号摘要过长');
    }
    final normalizedId = id.trim();
    if (normalizedId.isEmpty || normalizedId.runes.length > 128) {
      throw ArgumentError('支出记录编号无效');
    }
    final recordedAt = (recordedAtUtc ?? DateTime.now()).toUtc();
    _validateUtcInstant(recordedAt);
    return SubscriptionExpenseRecord._(
      isDeleted: isDeleted,
      id: normalizedId,
      subscriptionId: draft.subscriptionId,
      paymentMethodId: draft.paymentMethodId,
      paymentMethodName: draft.paymentMethodName,
      accountId: draft.accountId,
      accountLabel: accountLabel,
      source: source,
      serviceName: draft.serviceName,
      occurredOn: draft.occurredOn,
      amount: draft.amount,
      currency: draft.currency,
      kind: draft.kind,
      expenseCategory: draft.expenseCategory,
      scheduledRenewalOn: draft.scheduledRenewalOn,
      recordedAtUtc: recordedAt,
    );
  }

  factory SubscriptionExpenseRecord.fromEncryptedPayloadJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('订阅支出记录格式无效');
    }
    try {
      if (value['isDeleted'] != null && value['isDeleted'] is! bool) {
        throw const FormatException('订阅支出记录格式无效');
      }
      String requiredString(String name, {int maximumLength = 128}) {
        final field = value[name];
        if (field is! String ||
            field.isEmpty ||
            field.runes.length > maximumLength) {
          throw const FormatException('订阅支出记录格式无效');
        }
        return field;
      }

      String? optionalString(String name, {int maximumLength = 128}) {
        final field = value[name];
        if (field == null) return null;
        if (field is! String || field.runes.length > maximumLength) {
          throw const FormatException('订阅支出记录格式无效');
        }
        return field;
      }

      final kindName = requiredString('kind', maximumLength: 16);
      final kind = SubscriptionExpenseKind.values
          .where((candidate) => candidate.name == kindName)
          .firstOrNull;
      if (kind == null) {
        throw const FormatException('订阅支出记录格式无效');
      }
      final recordedAtRaw = requiredString('recordedAtUtc', maximumLength: 32);
      final recordedAt = DateTime.tryParse(recordedAtRaw);
      if (recordedAt == null ||
          !recordedAt.isUtc ||
          recordedAt.toIso8601String() != recordedAtRaw) {
        throw const FormatException('订阅支出记录格式无效');
      }
      _validateUtcInstant(recordedAt);
      final scheduledRaw = optionalString(
        'scheduledRenewalOn',
        maximumLength: 10,
      );
      return SubscriptionExpenseRecord.fromDraft(
        isDeleted: value['isDeleted'] == true,
        id: requiredString('id'),
        draft: SubscriptionExpenseDraft(
          subscriptionId: optionalString('subscriptionId'),
          accountId: optionalString('accountId'),
          paymentMethodId: optionalString('paymentMethodId'),
          paymentMethodName: optionalString(
            'paymentMethodName',
            maximumLength: 100,
          ),
          serviceName: requiredString('serviceName', maximumLength: 100),
          occurredOn: parseSubscriptionDate(
            requiredString('occurredOn', maximumLength: 10),
          ),
          amount: requiredString('amount', maximumLength: 20),
          currency: requiredString('currency', maximumLength: 12),
          kind: kind,
          expenseCategory: optionalString(
            'expenseCategory',
            maximumLength: 100,
          ),
          scheduledRenewalOn: scheduledRaw == null
              ? null
              : parseSubscriptionDate(scheduledRaw),
        ),
        recordedAtUtc: recordedAt,
        accountLabel: optionalString('accountLabel', maximumLength: 1024),
        source: value['source'] == null
            ? SubscriptionExpenseSource.manual
            : SubscriptionExpenseSource.values.firstWhere(
                (source) => source.name == value['source'],
                orElse: () => throw const FormatException('费用来源无效'),
              ),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError {
      throw const FormatException('订阅支出记录格式无效');
    }
  }

  // Keep the billing identity to prevent deleted charges being inferred again.
  final bool isDeleted;
  final String id;
  final String? accountId;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final String? subscriptionId;
  final String serviceName;
  final DateTime occurredOn;
  final String amount;
  final String currency;
  final SubscriptionExpenseKind kind;
  final String? expenseCategory;
  final DateTime? scheduledRenewalOn;
  final DateTime recordedAtUtc;
  final String? accountLabel;
  final SubscriptionExpenseSource source;

  SubscriptionExpenseRecord corrected(
    SubscriptionExpenseDraft draft, {
    bool deleted = false,
  }) => SubscriptionExpenseRecord.fromDraft(
    id: id,
    draft: SubscriptionExpenseDraft(
      subscriptionId: subscriptionId,
      accountId: accountId,
      serviceName: draft.serviceName,
      occurredOn: draft.occurredOn,
      amount: draft.amount,
      currency: draft.currency,
      kind: kind,
      expenseCategory: draft.expenseCategory,
      scheduledRenewalOn: scheduledRenewalOn,
      paymentMethodId: draft.paymentMethodId,
      paymentMethodName: draft.paymentMethodName,
    ),
    source: source,
    accountLabel: accountLabel,
    recordedAtUtc: recordedAtUtc,
    isDeleted: deleted,
  );

  SubscriptionExpenseDraft get draft => SubscriptionExpenseDraft(
    subscriptionId: subscriptionId,
    accountId: accountId,
    serviceName: serviceName,
    occurredOn: occurredOn,
    amount: amount,
    currency: currency,
    kind: kind,
    expenseCategory: expenseCategory,
    scheduledRenewalOn: scheduledRenewalOn,
    paymentMethodId: paymentMethodId,
    paymentMethodName: paymentMethodName,
  );

  SubscriptionExpenseRecord withAccountContext({
    required String? accountId,
    required String? accountLabel,
  }) => SubscriptionExpenseRecord._(
    isDeleted: isDeleted,
    id: id,
    subscriptionId: subscriptionId,
    paymentMethodId: paymentMethodId,
    paymentMethodName: paymentMethodName,
    accountId: accountId,
    accountLabel: accountLabel,
    source: source,
    serviceName: serviceName,
    occurredOn: occurredOn,
    amount: amount,
    currency: currency,
    kind: kind,
    expenseCategory: expenseCategory,
    scheduledRenewalOn: scheduledRenewalOn,
    recordedAtUtc: recordedAtUtc,
  );

  SubscriptionExpenseRecord withPaymentMethod({
    required String? id,
    required String? name,
  }) => SubscriptionExpenseRecord._(
    isDeleted: isDeleted,
    id: this.id,
    subscriptionId: subscriptionId,
    accountId: accountId,
    accountLabel: accountLabel,
    source: source,
    serviceName: serviceName,
    occurredOn: occurredOn,
    amount: amount,
    currency: currency,
    kind: kind,
    expenseCategory: expenseCategory,
    scheduledRenewalOn: scheduledRenewalOn,
    recordedAtUtc: recordedAtUtc,
    paymentMethodId: id,
    paymentMethodName: name,
  );

  SubscriptionExpenseRecord unlinkSubscription() {
    if (subscriptionId == null) return this;
    return SubscriptionExpenseRecord._(
      isDeleted: isDeleted,
      id: id,
      subscriptionId: null,
      paymentMethodId: paymentMethodId,
      paymentMethodName: paymentMethodName,
      accountId: accountId,
      accountLabel: accountLabel,
      source: source,
      serviceName: serviceName,
      occurredOn: occurredOn,
      amount: amount,
      currency: currency,
      kind: kind,
      expenseCategory: expenseCategory,
      scheduledRenewalOn: scheduledRenewalOn,
      recordedAtUtc: recordedAtUtc,
    );
  }

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'isDeleted': isDeleted,
    'id': id,
    'subscriptionId': subscriptionId,
    'accountId': accountId,
    'paymentMethodId': paymentMethodId,
    'paymentMethodName': paymentMethodName,
    'accountLabel': accountLabel,
    'source': source.name,
    'serviceName': serviceName,
    'occurredOn': formatSubscriptionDate(occurredOn),
    'amount': amount,
    'currency': currency,
    'kind': kind.name,
    'expenseCategory': expenseCategory,
    'scheduledRenewalOn': scheduledRenewalOn == null
        ? null
        : formatSubscriptionDate(scheduledRenewalOn!),
    'recordedAtUtc': recordedAtUtc.toIso8601String(),
  };
}

void _validateUtcInstant(DateTime value) {
  if (!value.isUtc || value.year < 1970 || value.year > 2300) {
    throw ArgumentError('UTC时刻超出支持范围');
  }
}
