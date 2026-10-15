import 'dart:math' as math;

part 'subscription_management.dart';

enum SubscriptionCycleUnit { day, week, month, year }

extension SubscriptionCycleUnitLabel on SubscriptionCycleUnit {
  String get label => switch (this) {
    SubscriptionCycleUnit.day => '天',
    SubscriptionCycleUnit.week => '周',
    SubscriptionCycleUnit.month => '月',
    SubscriptionCycleUnit.year => '年',
  };
}

enum SubscriptionStatus { active, paused, cancelled, expired }

extension SubscriptionStatusLabel on SubscriptionStatus {
  String get label => switch (this) {
    SubscriptionStatus.active => '正常',
    SubscriptionStatus.paused => '暂停',
    SubscriptionStatus.cancelled => '已取消',
    SubscriptionStatus.expired => '已到期',
  };
}

const subscriptionCurrencies = <String>[
  'CNY',
  'USD',
  'EUR',
  'CAD',
  'JPY',
  'GBP',
  'HKD',
  'AUD',
  'CHF',
  'SGD',
  'KRW',
  'TWD',
];
const maximumSubscriptionRenewalHistory = 200;

/// 用户选择的本机提醒延后目标。
///
/// 按日期延后继续使用本机日历日期，并在当天套用全局提醒时间；按时长延后
/// 则保存为 UTC 瞬时，避免跨午夜、时区或夏令时边界时丢失“几小时后”的语义。
final class SubscriptionSnoozeTarget {
  factory SubscriptionSnoozeTarget.calendarDate(DateTime value) =>
      SubscriptionSnoozeTarget._(
        calendarDate: subscriptionDateOnly(value),
        instantUtc: null,
      );

  factory SubscriptionSnoozeTarget.exactInstant(DateTime value) {
    final instant = value.toUtc();
    _validateSubscriptionInstant(instant);
    return SubscriptionSnoozeTarget._(calendarDate: null, instantUtc: instant);
  }

  factory SubscriptionSnoozeTarget.after(Duration duration, {DateTime? now}) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', '延后时长必须大于零');
    }
    return SubscriptionSnoozeTarget.exactInstant(
      (now ?? DateTime.now()).toUtc().add(duration),
    );
  }

  const SubscriptionSnoozeTarget._({
    required this.calendarDate,
    required this.instantUtc,
  });

  final DateTime? calendarDate;
  final DateTime? instantUtc;
}

final class SubscriptionDetailsDraft {
  factory SubscriptionDetailsDraft({
    required String serviceName,
    required DateTime firstSubscribedOn,
    required DateTime nextRenewalOn,
    int cycleCount = 1,
    SubscriptionCycleUnit cycleUnit = SubscriptionCycleUnit.month,
    String? planName,
    String? amount,
    String currency = 'CNY',
    bool autoRenew = true,
    String? paymentMethod,
    String? notes,
    String? expenseCategory,
    int reminderDaysBefore = 7,
    bool reminderEnabled = true,
    SubscriptionStatus status = SubscriptionStatus.active,
    SubscriptionManagement? management,
  }) {
    final firstDate = subscriptionDateOnly(firstSubscribedOn);
    final renewalDate = subscriptionDateOnly(nextRenewalOn);
    if (renewalDate.isBefore(firstDate)) {
      throw ArgumentError('下次续费日期不能早于首次订阅日期');
    }
    if (cycleCount < 1 || cycleCount > 120) {
      throw ArgumentError('计费周期数量必须为1到120');
    }
    if (reminderDaysBefore < 0 || reminderDaysBefore > 365) {
      throw ArgumentError('提前提醒天数必须为0到365');
    }

    final normalizedAmount = _normalizeAmount(amount);
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty || normalizedCurrency.runes.length > 12) {
      throw ArgumentError('币种格式无效');
    }

    return SubscriptionDetailsDraft._(
      serviceName: _requiredText(serviceName, '订阅服务', 100),
      planName: _optionalText(planName, '套餐名称', 100),
      amount: normalizedAmount,
      currency: normalizedCurrency,
      firstSubscribedOn: firstDate,
      nextRenewalOn: renewalDate,
      cycleCount: cycleCount,
      cycleUnit: cycleUnit,
      autoRenew: autoRenew,
      paymentMethod: _optionalText(paymentMethod, '支付方式', 100),
      notes: _optionalText(notes, '备注', 10000),
      expenseCategory: _optionalText(expenseCategory, '费用分类', 100),
      reminderDaysBefore: reminderDaysBefore,
      reminderEnabled: reminderEnabled,
      status: status,
      management: management,
    );
  }

  const SubscriptionDetailsDraft._({
    required this.serviceName,
    required this.currency,
    required this.firstSubscribedOn,
    required this.nextRenewalOn,
    required this.cycleCount,
    required this.cycleUnit,
    required this.autoRenew,
    required this.reminderDaysBefore,
    required this.reminderEnabled,
    required this.status,
    this.management,
    this.planName,
    this.amount,
    this.paymentMethod,
    this.notes,
    this.expenseCategory,
  });

  final String serviceName;
  final String? planName;
  final String? amount;
  final String currency;
  final DateTime firstSubscribedOn;
  final DateTime nextRenewalOn;
  final int cycleCount;
  final SubscriptionCycleUnit cycleUnit;
  final bool autoRenew;
  final String? paymentMethod;
  final String? notes;
  final String? expenseCategory;
  final int reminderDaysBefore;
  final bool reminderEnabled;
  final SubscriptionStatus status;
  final SubscriptionManagement? management;

  SubscriptionDetailsDraft copyWith({
    String? serviceName,
    String? planName,
    String? amount,
    String? currency,
    DateTime? firstSubscribedOn,
    DateTime? nextRenewalOn,
    int? cycleCount,
    SubscriptionCycleUnit? cycleUnit,
    bool? autoRenew,
    String? paymentMethod,
    String? notes,
    String? expenseCategory,
    int? reminderDaysBefore,
    bool? reminderEnabled,
    SubscriptionStatus? status,
    SubscriptionManagement? management,
  }) => SubscriptionDetailsDraft(
    serviceName: serviceName ?? this.serviceName,
    planName: planName ?? this.planName,
    amount: amount ?? this.amount,
    currency: currency ?? this.currency,
    firstSubscribedOn: firstSubscribedOn ?? this.firstSubscribedOn,
    nextRenewalOn: nextRenewalOn ?? this.nextRenewalOn,
    cycleCount: cycleCount ?? this.cycleCount,
    cycleUnit: cycleUnit ?? this.cycleUnit,
    autoRenew: autoRenew ?? this.autoRenew,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    notes: notes ?? this.notes,
    expenseCategory: expenseCategory ?? this.expenseCategory,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    status: status ?? this.status,
    management: management ?? this.management,
  );

  SubscriptionDetailsDraft withFallbackNotes(String? fallbackNotes) {
    if (notes != null ||
        fallbackNotes == null ||
        fallbackNotes.trim().isEmpty) {
      return this;
    }
    return SubscriptionDetailsDraft(
      serviceName: serviceName,
      planName: planName,
      amount: amount,
      currency: currency,
      firstSubscribedOn: firstSubscribedOn,
      nextRenewalOn: nextRenewalOn,
      cycleCount: cycleCount,
      cycleUnit: cycleUnit,
      autoRenew: autoRenew,
      paymentMethod: paymentMethod,
      notes: fallbackNotes,
      expenseCategory: expenseCategory,
      reminderDaysBefore: reminderDaysBefore,
      reminderEnabled: reminderEnabled,
      status: status,
      management: management,
    );
  }

  SubscriptionDetailsDraft withExpenseCategory(String? category) {
    if (expenseCategory != null ||
        category == null ||
        category.trim().isEmpty) {
      return this;
    }
    return SubscriptionDetailsDraft(
      serviceName: serviceName,
      planName: planName,
      amount: amount,
      currency: currency,
      firstSubscribedOn: firstSubscribedOn,
      nextRenewalOn: nextRenewalOn,
      cycleCount: cycleCount,
      cycleUnit: cycleUnit,
      autoRenew: autoRenew,
      paymentMethod: paymentMethod,
      notes: notes,
      expenseCategory: category,
      reminderDaysBefore: reminderDaysBefore,
      reminderEnabled: reminderEnabled,
      status: status,
      management: management,
    );
  }
}

final class SubscriptionDraft {
  factory SubscriptionDraft({
    required String? accountId,
    required SubscriptionDetailsDraft details,
  }) {
    final normalizedAccountId = accountId?.trim();
    if (normalizedAccountId != null &&
        (normalizedAccountId.isEmpty ||
            normalizedAccountId.runes.length > 128)) {
      throw ArgumentError('关联账号无效');
    }
    return SubscriptionDraft._(
      accountId: normalizedAccountId,
      details: details,
    );
  }

  const SubscriptionDraft._({required this.accountId, required this.details});

  final String? accountId;
  final SubscriptionDetailsDraft details;
}

/// 一次用户确认“已续费”的本机审计记录。
///
/// 这里只记录日期变化，不记录账号、平台或支付信息，避免重复保存敏感内容。
final class SubscriptionRenewalRecord {
  factory SubscriptionRenewalRecord({
    required DateTime recordedOn,
    required DateTime previousRenewalOn,
    required DateTime nextRenewalOn,
  }) {
    final previous = subscriptionDateOnly(previousRenewalOn);
    final next = subscriptionDateOnly(nextRenewalOn);
    if (!next.isAfter(previous)) {
      throw ArgumentError('续费后的日期必须晚于原续费日期');
    }
    return SubscriptionRenewalRecord._(
      recordedOn: subscriptionDateOnly(recordedOn),
      previousRenewalOn: previous,
      nextRenewalOn: next,
    );
  }

  const SubscriptionRenewalRecord._({
    required this.recordedOn,
    required this.previousRenewalOn,
    required this.nextRenewalOn,
  });

  factory SubscriptionRenewalRecord.fromEncryptedPayloadJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('续费历史格式无效');
    }
    try {
      String dateField(String name) {
        final field = value[name];
        if (field is! String || field.length != 10) {
          throw const FormatException('续费历史格式无效');
        }
        return field;
      }

      return SubscriptionRenewalRecord(
        recordedOn: parseSubscriptionDate(dateField('recordedOn')),
        previousRenewalOn: parseSubscriptionDate(
          dateField('previousRenewalOn'),
        ),
        nextRenewalOn: parseSubscriptionDate(dateField('nextRenewalOn')),
      );
    } on ArgumentError {
      throw const FormatException('续费历史格式无效');
    }
  }

  final DateTime recordedOn;
  final DateTime previousRenewalOn;
  final DateTime nextRenewalOn;

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'recordedOn': formatSubscriptionDate(recordedOn),
    'previousRenewalOn': formatSubscriptionDate(previousRenewalOn),
    'nextRenewalOn': formatSubscriptionDate(nextRenewalOn),
  };
}

final class SubscriptionRecord {
  const SubscriptionRecord._({
    required this.id,
    required this.accountId,
    required this.serviceName,
    required this.currency,
    required this.firstSubscribedOn,
    required this.nextRenewalOn,
    required this.cycleCount,
    required this.cycleUnit,
    required this.autoRenew,
    required this.reminderDaysBefore,
    required this.reminderEnabled,
    required this.status,
    this.management,
    required this.renewalHistory,
    this.planName,
    this.amount,
    this.paymentMethod,
    this.notes,
    this.expenseCategory,
    this.snoozedUntil,
    this.snoozedUntilUtc,
    this.cancelledOn,
    this.accessEndsOn,
  });

  factory SubscriptionRecord.fromDraft({
    required String id,
    required SubscriptionDraft draft,
  }) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty || normalizedId.runes.length > 128) {
      throw ArgumentError('订阅记录编号无效');
    }
    return _fromValidatedDetails(
      id: normalizedId,
      accountId: draft.accountId,
      details: draft.details,
      renewalHistory: const <SubscriptionRenewalRecord>[],
    );
  }

  factory SubscriptionRecord.fromEncryptedPayloadJson(
    Object? value, {
    bool allowStandalone = false,
    bool allowInstantSnooze = false,
    bool allowExpenseCategory = false,
    bool allowManagement = true,
  }) {
    try {
      if (value is! Map<Object?, Object?>) {
        throw const FormatException('订阅记录格式无效');
      }

      String requiredString(String name, {int maximumLength = 128}) {
        final field = value[name];
        if (field is! String ||
            field.isEmpty ||
            field.runes.length > maximumLength) {
          throw const FormatException('订阅记录格式无效');
        }
        return field;
      }

      String? optionalString(String name, {int maximumLength = 100}) {
        final field = value[name];
        if (field == null) {
          return null;
        }
        if (field is! String || field.runes.length > maximumLength) {
          throw const FormatException('订阅记录格式无效');
        }
        return field;
      }

      String? accountId() {
        final field = value['accountId'];
        if (field == null && allowStandalone) {
          return null;
        }
        if (field is! String || field.isEmpty || field.runes.length > 128) {
          throw const FormatException('订阅记录格式无效');
        }
        return field;
      }

      DateTime? optionalDate(String name) {
        final field = value[name];
        if (field == null) {
          return null;
        }
        if (field is! String) {
          throw const FormatException('订阅记录格式无效');
        }
        return parseSubscriptionDate(field);
      }

      DateTime? optionalUtcInstant(String name) {
        final field = value[name];
        if (field == null) {
          return null;
        }
        if (!allowInstantSnooze || field is! String) {
          throw const FormatException('订阅记录格式无效');
        }
        return parseSubscriptionUtcInstant(field);
      }

      final cycleCount = value['cycleCount'];
      final autoRenew = value['autoRenew'];
      final reminderDaysBefore = value['reminderDaysBefore'];
      final reminderEnabledValue = value['reminderEnabled'];
      if (cycleCount is! int ||
          autoRenew is! bool ||
          reminderDaysBefore is! int ||
          (reminderEnabledValue != null && reminderEnabledValue is! bool)) {
        throw const FormatException('订阅记录格式无效');
      }

      final historyValue = value['renewalHistory'];
      if (historyValue != null && historyValue is! List<Object?>) {
        throw const FormatException('订阅记录格式无效');
      }
      final history = <SubscriptionRenewalRecord>[
        for (final item in historyValue as List<Object?>? ?? const <Object?>[])
          SubscriptionRenewalRecord.fromEncryptedPayloadJson(item),
      ];
      if (history.length > maximumSubscriptionRenewalHistory) {
        throw const FormatException('订阅记录格式无效');
      }
      if (!allowExpenseCategory && value['expenseCategory'] != null) {
        throw const FormatException('订阅记录格式无效');
      }

      if (!allowManagement && value['management'] != null) {
        throw const FormatException('旧版本不支持订阅扩展数据');
      }
      final details = SubscriptionDetailsDraft(
        management: value['management'] == null
            ? null
            : SubscriptionManagement.fromJson(value['management']),
        serviceName: requiredString('serviceName', maximumLength: 100),
        planName: optionalString('planName'),
        amount: optionalString('amount'),
        currency: requiredString('currency', maximumLength: 12),
        firstSubscribedOn: parseSubscriptionDate(
          requiredString('firstSubscribedOn', maximumLength: 10),
        ),
        nextRenewalOn: parseSubscriptionDate(
          requiredString('nextRenewalOn', maximumLength: 10),
        ),
        cycleCount: cycleCount,
        cycleUnit: _cycleUnitFromName(
          requiredString('cycleUnit', maximumLength: 16),
        ),
        autoRenew: autoRenew,
        paymentMethod: optionalString('paymentMethod'),
        notes: optionalString('notes', maximumLength: 10000),
        expenseCategory: allowExpenseCategory
            ? optionalString('expenseCategory')
            : null,
        reminderDaysBefore: reminderDaysBefore,
        reminderEnabled: reminderEnabledValue as bool? ?? true,
        status: _statusFromName(requiredString('status', maximumLength: 16)),
      );
      final snoozedUntil = optionalDate('snoozedUntil');
      final snoozedUntilUtc = optionalUtcInstant('snoozedUntilUtc');
      final cancelledOn = optionalDate('cancelledOn');
      final accessEndsOn = optionalDate('accessEndsOn');
      if ((snoozedUntil != null && snoozedUntilUtc != null) ||
          (accessEndsOn != null &&
              cancelledOn != null &&
              accessEndsOn.isBefore(cancelledOn))) {
        throw const FormatException('订阅记录格式无效');
      }

      return _fromValidatedDetails(
        id: requiredString('id'),
        accountId: accountId(),
        details: details,
        renewalHistory: List<SubscriptionRenewalRecord>.unmodifiable(history),
        snoozedUntil: snoozedUntil,
        snoozedUntilUtc: snoozedUntilUtc,
        cancelledOn: cancelledOn,
        accessEndsOn: accessEndsOn,
      );
    } on FormatException {
      rethrow;
    } on ArgumentError {
      throw const FormatException('订阅记录格式无效');
    }
  }

  final String id;
  final String? accountId;
  final String serviceName;
  final String? planName;
  final String? amount;
  final String currency;
  final DateTime firstSubscribedOn;
  final DateTime nextRenewalOn;
  final int cycleCount;
  final SubscriptionCycleUnit cycleUnit;
  final bool autoRenew;
  final String? paymentMethod;
  final String? notes;
  final String? expenseCategory;
  final int reminderDaysBefore;
  final bool reminderEnabled;
  final SubscriptionStatus status;
  final SubscriptionManagement? management;

  /// 按本机日历日期延后；当天仍使用全局提醒时间。
  final DateTime? snoozedUntil;

  /// 精确延后的 UTC 瞬时；与 [snoozedUntil] 互斥。
  final DateTime? snoozedUntilUtc;
  final DateTime? cancelledOn;
  final DateTime? accessEndsOn;
  final List<SubscriptionRenewalRecord> renewalHistory;

  SubscriptionDetailsDraft get details => SubscriptionDetailsDraft(
    serviceName: serviceName,
    planName: planName,
    amount: amount,
    currency: currency,
    firstSubscribedOn: firstSubscribedOn,
    nextRenewalOn: nextRenewalOn,
    cycleCount: cycleCount,
    cycleUnit: cycleUnit,
    autoRenew: autoRenew,
    paymentMethod: paymentMethod,
    notes: notes,
    expenseCategory: expenseCategory,
    reminderDaysBefore: reminderDaysBefore,
    reminderEnabled: reminderEnabled,
    status: status,
    management: management,
  );

  bool get isUnresolvedTrial => management?.trial?.unresolved ?? false;
  bool get isFormalSubscription =>
      management?.trial == null ||
      management!.trial!.outcome == TrialOutcome.converted;

  SubscriptionRecord withManagement(SubscriptionManagement value) => applyDraft(
    SubscriptionDraft(
      accountId: accountId,
      details: details.copyWith(management: value),
    ),
  );

  List<SubscriptionReminderRule> get effectiveReminderRules =>
      management?.reminderRules ??
      (reminderEnabled
          ? [
              SubscriptionReminderRule(
                event: SubscriptionReminderEvent.renewal,
                daysBefore: [reminderDaysBefore],
              ),
            ]
          : []);

  String get cycleLabel {
    if (cycleCount == 1) {
      return '每${cycleUnit.label}';
    }
    final unit = cycleUnit == SubscriptionCycleUnit.month
        ? '个月'
        : cycleUnit.label;
    return '每$cycleCount$unit';
  }

  /// 编辑基础资料时保留延期、取消日期和续费历史等审计字段。
  SubscriptionRecord applyDraft(SubscriptionDraft draft) {
    final nextStatus = draft.details.status;
    return _fromValidatedDetails(
      id: id,
      accountId: draft.accountId,
      details: draft.details
          .withFallbackNotes(notes)
          .copyWith(management: draft.details.management ?? management),
      renewalHistory: renewalHistory,
      snoozedUntil:
          draft.details.reminderEnabled &&
              nextStatus == SubscriptionStatus.active
          ? snoozedUntil
          : null,
      snoozedUntilUtc:
          draft.details.reminderEnabled &&
              nextStatus == SubscriptionStatus.active
          ? snoozedUntilUtc
          : null,
      cancelledOn: nextStatus == SubscriptionStatus.cancelled
          ? cancelledOn
          : null,
      accessEndsOn: nextStatus == SubscriptionStatus.cancelled
          ? accessEndsOn
          : null,
    );
  }

  /// 将“下次续费日期”严格推进一个已保存周期，不追赶多期。
  SubscriptionRecord markRenewed({DateTime? recordedOn}) {
    if (!isFormalSubscription) throw StateError('请先在详情确认试用结果。');
    if (status == SubscriptionStatus.cancelled) {
      throw StateError('已取消订阅需先恢复后再记录续费');
    }
    final nextDate = advanceSubscriptionDate(
      nextRenewalOn,
      count: cycleCount,
      unit: cycleUnit,
      preserveMonthEnd: true,
    );
    final event = SubscriptionRenewalRecord(
      recordedOn: recordedOn ?? DateTime.now(),
      previousRenewalOn: nextRenewalOn,
      nextRenewalOn: nextDate,
    );
    final history = <SubscriptionRenewalRecord>[...renewalHistory, event];
    if (history.length > maximumSubscriptionRenewalHistory) {
      history.removeRange(
        0,
        history.length - maximumSubscriptionRenewalHistory,
      );
    }
    return _fromValidatedDetails(
      id: id,
      accountId: accountId,
      details: SubscriptionDetailsDraft(
        serviceName: serviceName,
        planName: planName,
        amount: amount,
        currency: currency,
        firstSubscribedOn: firstSubscribedOn,
        nextRenewalOn: nextDate,
        cycleCount: cycleCount,
        cycleUnit: cycleUnit,
        autoRenew: autoRenew,
        paymentMethod: paymentMethod,
        notes: notes,
        expenseCategory: expenseCategory,
        reminderDaysBefore: reminderDaysBefore,
        reminderEnabled: reminderEnabled,
        status: SubscriptionStatus.active,
        management: management,
      ),
      renewalHistory: List<SubscriptionRenewalRecord>.unmodifiable(history),
    );
  }

  SubscriptionRecord snoozeReminderUntil(DateTime date) {
    if (status != SubscriptionStatus.active) {
      throw StateError('只有正常订阅可以延后提醒');
    }
    return _fromValidatedDetails(
      id: id,
      accountId: accountId,
      details: SubscriptionDetailsDraft(
        serviceName: serviceName,
        planName: planName,
        amount: amount,
        currency: currency,
        firstSubscribedOn: firstSubscribedOn,
        nextRenewalOn: nextRenewalOn,
        cycleCount: cycleCount,
        cycleUnit: cycleUnit,
        autoRenew: autoRenew,
        paymentMethod: paymentMethod,
        notes: notes,
        expenseCategory: expenseCategory,
        reminderDaysBefore: reminderDaysBefore,
        reminderEnabled: true,
        status: status,
        management: management,
      ),
      renewalHistory: renewalHistory,
      snoozedUntil: subscriptionDateOnly(date),
    );
  }

  SubscriptionRecord snoozeReminder(SubscriptionSnoozeTarget target) {
    if (status != SubscriptionStatus.active) {
      throw StateError('只有正常订阅可以延后提醒');
    }
    return _fromValidatedDetails(
      id: id,
      accountId: accountId,
      details: SubscriptionDetailsDraft(
        serviceName: serviceName,
        planName: planName,
        amount: amount,
        currency: currency,
        firstSubscribedOn: firstSubscribedOn,
        nextRenewalOn: nextRenewalOn,
        cycleCount: cycleCount,
        cycleUnit: cycleUnit,
        autoRenew: autoRenew,
        paymentMethod: paymentMethod,
        notes: notes,
        expenseCategory: expenseCategory,
        reminderDaysBefore: reminderDaysBefore,
        reminderEnabled: true,
        status: status,
        management: management,
      ),
      renewalHistory: renewalHistory,
      snoozedUntil: target.calendarDate,
      snoozedUntilUtc: target.instantUtc,
    );
  }

  SubscriptionRecord cancel({DateTime? cancelledOn, DateTime? accessEndsOn}) {
    final cancelledDate = subscriptionDateOnly(cancelledOn ?? DateTime.now());
    final accessDate = accessEndsOn == null
        ? null
        : subscriptionDateOnly(accessEndsOn);
    if (accessDate != null && accessDate.isBefore(cancelledDate)) {
      throw ArgumentError('权益截止日期不能早于取消日期');
    }
    return _fromValidatedDetails(
      id: id,
      accountId: accountId,
      details: SubscriptionDetailsDraft(
        serviceName: serviceName,
        planName: planName,
        amount: amount,
        currency: currency,
        firstSubscribedOn: firstSubscribedOn,
        nextRenewalOn: nextRenewalOn,
        cycleCount: cycleCount,
        cycleUnit: cycleUnit,
        // 取消只是本机状态，不能据此声称平台自动续费已关闭。
        autoRenew: autoRenew,
        paymentMethod: paymentMethod,
        notes: notes,
        expenseCategory: expenseCategory,
        reminderDaysBefore: reminderDaysBefore,
        reminderEnabled: false,
        status: SubscriptionStatus.cancelled,
        management: isUnresolvedTrial
            ? management!.copyWith(
                trial: management!.trial!.resolve(
                  TrialOutcome.cancelled,
                  now: DateTime.now(),
                ),
              )
            : management,
      ),
      renewalHistory: renewalHistory,
      cancelledOn: cancelledDate,
      accessEndsOn: accessDate,
    );
  }

  SubscriptionRecord restore() => _fromValidatedDetails(
    id: id,
    accountId: accountId,
    details: SubscriptionDetailsDraft(
      serviceName: serviceName,
      planName: planName,
      amount: amount,
      currency: currency,
      firstSubscribedOn: firstSubscribedOn,
      nextRenewalOn: nextRenewalOn,
      cycleCount: cycleCount,
      cycleUnit: cycleUnit,
      autoRenew: autoRenew,
      paymentMethod: paymentMethod,
      notes: notes,
      expenseCategory: expenseCategory,
      reminderDaysBefore: reminderDaysBefore,
      reminderEnabled: true,
      status: SubscriptionStatus.active,
      management: management,
    ),
    renewalHistory: renewalHistory,
  );

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'id': id,
    'accountId': accountId,
    'management': management?.toJson(),
    'serviceName': serviceName,
    'planName': planName,
    'amount': amount,
    'currency': currency,
    'firstSubscribedOn': formatSubscriptionDate(firstSubscribedOn),
    'nextRenewalOn': formatSubscriptionDate(nextRenewalOn),
    'cycleCount': cycleCount,
    'cycleUnit': cycleUnit.name,
    'autoRenew': autoRenew,
    'paymentMethod': paymentMethod,
    'notes': notes,
    'expenseCategory': expenseCategory,
    'reminderDaysBefore': reminderDaysBefore,
    'reminderEnabled': reminderEnabled,
    'status': status.name,
    'snoozedUntil': snoozedUntil == null
        ? null
        : formatSubscriptionDate(snoozedUntil!),
    'snoozedUntilUtc': snoozedUntilUtc == null
        ? null
        : formatSubscriptionUtcInstant(snoozedUntilUtc!),
    'cancelledOn': cancelledOn == null
        ? null
        : formatSubscriptionDate(cancelledOn!),
    'accessEndsOn': accessEndsOn == null
        ? null
        : formatSubscriptionDate(accessEndsOn!),
    'renewalHistory': <Object?>[
      for (final event in renewalHistory) event.toEncryptedPayloadJson(),
    ],
  };

  static SubscriptionRecord _fromValidatedDetails({
    required String id,
    required String? accountId,
    required SubscriptionDetailsDraft details,
    required List<SubscriptionRenewalRecord> renewalHistory,
    DateTime? snoozedUntil,
    DateTime? snoozedUntilUtc,
    DateTime? cancelledOn,
    DateTime? accessEndsOn,
  }) {
    if (snoozedUntil != null && snoozedUntilUtc != null) {
      throw ArgumentError('日期延后与精确延后不能同时存在');
    }
    final normalizedSnoozedUntil = snoozedUntil == null
        ? null
        : subscriptionDateOnly(snoozedUntil);
    final normalizedSnoozedUntilUtc = snoozedUntilUtc?.toUtc();
    if (normalizedSnoozedUntilUtc != null) {
      _validateSubscriptionInstant(normalizedSnoozedUntilUtc);
    }
    return SubscriptionRecord._(
      id: id,
      accountId: accountId,
      serviceName: details.serviceName,
      planName: details.planName,
      amount: details.amount,
      currency: details.currency,
      firstSubscribedOn: details.firstSubscribedOn,
      nextRenewalOn: details.nextRenewalOn,
      cycleCount: details.cycleCount,
      cycleUnit: details.cycleUnit,
      autoRenew: details.autoRenew,
      paymentMethod: details.paymentMethod,
      notes: details.notes,
      expenseCategory: details.expenseCategory,
      reminderDaysBefore: details.reminderDaysBefore,
      reminderEnabled: details.reminderEnabled,
      status: details.status,
      management: details.management,
      snoozedUntil: normalizedSnoozedUntil,
      snoozedUntilUtc: normalizedSnoozedUntilUtc,
      cancelledOn: cancelledOn,
      accessEndsOn: accessEndsOn,
      renewalHistory: renewalHistory,
    );
  }
}

/// 从指定日期推进一个计费周期。
///
/// 月/年周期会保持“月末”语义：1月31日到2月末，再推进一期仍回到3月末；
/// 2月29日的年度周期在非闰年落到2月末，之后遇到闰年仍为2月末。
DateTime advanceSubscriptionDate(
  DateTime source, {
  required int count,
  required SubscriptionCycleUnit unit,
  bool preserveMonthEnd = false,
}) {
  final date = subscriptionDateOnly(source);
  if (count < 1 || count > 120) {
    throw ArgumentError('计费周期数量必须为1到120');
  }

  final candidate = switch (unit) {
    SubscriptionCycleUnit.day => DateTime(
      date.year,
      date.month,
      date.day + count,
    ),
    SubscriptionCycleUnit.week => DateTime(
      date.year,
      date.month,
      date.day + count * 7,
    ),
    SubscriptionCycleUnit.month => _addCalendarMonths(
      date,
      count,
      preserveMonthEnd: preserveMonthEnd,
    ),
    SubscriptionCycleUnit.year => _addCalendarMonths(
      date,
      count * 12,
      preserveMonthEnd: preserveMonthEnd,
    ),
  };
  return subscriptionDateOnly(candidate);
}

DateTime _addCalendarMonths(
  DateTime source,
  int months, {
  required bool preserveMonthEnd,
}) {
  final sourceLastDay = DateTime(source.year, source.month + 1, 0).day;
  final sourceIsMonthEnd = source.day == sourceLastDay;
  final zeroBasedMonth = source.month - 1 + months;
  final year = source.year + zeroBasedMonth ~/ 12;
  final month = zeroBasedMonth % 12 + 1;
  final targetLastDay = DateTime(year, month + 1, 0).day;
  final targetDay = preserveMonthEnd && sourceIsMonthEnd
      ? targetLastDay
      : math.min(source.day, targetLastDay);
  return DateTime(year, month, targetDay);
}

DateTime subscriptionDateOnly(DateTime value) {
  if (value.year < 1970 || value.year > 2300) {
    throw ArgumentError('日期超出支持范围');
  }
  return DateTime(value.year, value.month, value.day);
}

String formatSubscriptionDate(DateTime value) {
  final date = subscriptionDateOnly(value);
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-'
      '${twoDigits(date.month)}-${twoDigits(date.day)}';
}

DateTime parseSubscriptionDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const FormatException('日期格式无效');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const FormatException('日期格式无效');
  }
  try {
    return subscriptionDateOnly(parsed);
  } on ArgumentError {
    throw const FormatException('日期格式无效');
  }
}

String formatSubscriptionUtcInstant(DateTime value) {
  final instant = value.toUtc();
  _validateSubscriptionInstant(instant);
  return instant.toIso8601String();
}

DateTime parseSubscriptionUtcInstant(String value) {
  if (value.length > 32 ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3,6})?Z$',
      ).hasMatch(value)) {
    throw const FormatException('UTC时刻格式无效');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('UTC时刻格式无效');
  }
  try {
    _validateSubscriptionInstant(parsed);
  } on ArgumentError {
    throw const FormatException('UTC时刻格式无效');
  }
  return parsed;
}

void _validateSubscriptionInstant(DateTime value) {
  if (!value.isUtc || value.year < 1970 || value.year > 2300) {
    throw ArgumentError('UTC时刻超出支持范围');
  }
}

String _requiredText(String value, String fieldName, int maximumLength) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError('$fieldName不能为空');
  }
  if (normalized.runes.length > maximumLength) {
    throw ArgumentError('$fieldName内容过长');
  }
  return normalized;
}

String? _optionalText(String? value, String fieldName, int maximumLength) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  if (normalized.runes.length > maximumLength) {
    throw ArgumentError('$fieldName内容过长');
  }
  return normalized;
}

String? _normalizeAmount(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  if (!RegExp(r'^(0|[1-9]\d{0,11})(\.\d{1,4})?$').hasMatch(normalized)) {
    throw ArgumentError('金额格式无效，最多保留4位小数');
  }
  return normalized;
}

SubscriptionCycleUnit _cycleUnitFromName(String value) {
  for (final unit in SubscriptionCycleUnit.values) {
    if (unit.name == value) {
      return unit;
    }
  }
  throw const FormatException('计费周期单位无效');
}

SubscriptionStatus _statusFromName(String value) {
  for (final status in SubscriptionStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  throw const FormatException('订阅状态无效');
}
