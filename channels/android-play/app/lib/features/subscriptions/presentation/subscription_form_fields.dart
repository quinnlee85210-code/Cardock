import 'subscription_advanced_fields.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';
import 'package:flutter/services.dart';

import '../domain/subscription_record.dart';

enum SubscriptionCyclePreset { monthly, quarterly, halfYearly, yearly, custom }

enum SubscriptionRenewalDateMode { automatic, manual }

extension on SubscriptionCyclePreset {
  String get label => switch (this) {
    SubscriptionCyclePreset.monthly => '每月',
    SubscriptionCyclePreset.quarterly => '每季度',
    SubscriptionCyclePreset.halfYearly => '每半年',
    SubscriptionCyclePreset.yearly => '每年',
    SubscriptionCyclePreset.custom => '自定义',
  };
}

final class SubscriptionFormController {
  SubscriptionFormController({
    SubscriptionDetailsDraft? initial,
    this.availablePaymentMethods = const [],
    DateTime? today,
    String defaultCurrency = 'CNY',
    int defaultReminderDays = 7,
  }) : serviceNameController = TextEditingController(
         text: initial?.serviceName ?? '',
       ),
       planNameController = TextEditingController(
         text: initial?.planName ?? '',
       ),
       amountController = TextEditingController(text: initial?.amount ?? ''),
       expenseCategoryController = TextEditingController(
         text: initial?.expenseCategory ?? '',
       ),
       paymentMethodController = TextEditingController(
         text: initial?.paymentMethod ?? '',
       ) {
    final baseDate = subscriptionDateOnly(today ?? DateTime.now());
    firstSubscribedOn = initial?.firstSubscribedOn ?? baseDate;
    final normalizedDefaultCurrency = defaultCurrency.trim().toUpperCase();
    if (normalizedDefaultCurrency.isEmpty ||
        normalizedDefaultCurrency.runes.length > 12) {
      throw ArgumentError('默认币种格式无效');
    }
    if (defaultReminderDays < 0 || defaultReminderDays > 365) {
      throw ArgumentError('默认提醒天数必须为0到365');
    }
    advancedFields = subscriptionAdvancedFields(initial);
    management = initial?.management;
    currency = initial?.currency ?? normalizedDefaultCurrency;
    autoRenew = initial?.autoRenew ?? true;
    reminderDaysBefore = initial?.reminderDaysBefore ?? defaultReminderDays;
    reminderEnabled = initial?.reminderEnabled ?? true;
    status = initial?.status ?? SubscriptionStatus.active;
    cyclePreset = _inferPreset(initial);
    customCycleCountController = TextEditingController(
      text: initial?.cycleCount.toString() ?? '1',
    );
    customCycleUnit = initial?.cycleUnit ?? SubscriptionCycleUnit.month;
    if (initial == null) {
      nextRenewalOn = _calculateNextRenewalOn();
      renewalDateMode = SubscriptionRenewalDateMode.automatic;
    } else {
      // 已保存记录可能包含赠送天数等平台规则，编辑时必须原样保留。
      nextRenewalOn = initial.nextRenewalOn;
      renewalDateMode = SubscriptionRenewalDateMode.manual;
    }
  }

  final List<PaymentMethodRecord> availablePaymentMethods;
  final TextEditingController serviceNameController;
  final TextEditingController planNameController;
  final TextEditingController amountController;
  final TextEditingController expenseCategoryController;
  final TextEditingController paymentMethodController;
  late final TextEditingController customCycleCountController;

  late Map<String, Object?> advancedFields;
  SubscriptionManagement? management;
  late DateTime firstSubscribedOn;
  late DateTime nextRenewalOn;
  late String currency;
  late bool autoRenew;
  late int reminderDaysBefore;
  late bool reminderEnabled;
  late SubscriptionStatus status;
  late SubscriptionCyclePreset cyclePreset;
  late SubscriptionCycleUnit customCycleUnit;
  late SubscriptionRenewalDateMode renewalDateMode;
  bool renewalDateReachedSupportedLimit = false;

  VoidCallback? onDraftChanged;

  Iterable<TextEditingController> get textControllers => [
    serviceNameController,
    planNameController,
    amountController,
    expenseCategoryController,
    paymentMethodController,
    customCycleCountController,
  ];

  Map<String, Object?> exportEditorFields() => {
    'advancedFields': advancedFields,
    'management': management?.toJson(),
    'texts': textControllers.map((item) => item.text).toList(),
    'firstSubscribedOn': firstSubscribedOn.toIso8601String(),
    'nextRenewalOn': nextRenewalOn.toIso8601String(),
    'currency': currency,
    'autoRenew': autoRenew,
    'reminderDaysBefore': reminderDaysBefore,
    'reminderEnabled': reminderEnabled,
    'status': status.name,
    'cyclePreset': cyclePreset.name,
    'customCycleUnit': customCycleUnit.name,
    'renewalDateMode': renewalDateMode.name,
    'renewalDateReachedSupportedLimit': renewalDateReachedSupportedLimit,
  };

  void restoreEditorFields(Map<String, Object?> fields) {
    if (fields['management'] != null) {
      management = SubscriptionManagement.fromJson(fields['management']);
    }
    if (fields['advancedFields'] case final Map<String, Object?> advanced) {
      advancedFields = Map.of(advanced);
    }
    final texts = fields['texts'];
    final controllers = textControllers.toList();
    if (texts is List && texts.length == controllers.length) {
      for (var index = 0; index < texts.length; index++) {
        if (texts[index] is String) {
          controllers[index].text = texts[index] as String;
        }
      }
    }
    DateTime date(String name, DateTime fallback) {
      final value = fields[name];
      final parsed = value is String ? DateTime.tryParse(value) : null;
      return parsed != null && parsed.year >= 1970 && parsed.year <= 2300
          ? parsed
          : fallback;
    }

    firstSubscribedOn = date('firstSubscribedOn', firstSubscribedOn);
    nextRenewalOn = date('nextRenewalOn', nextRenewalOn);
    if (fields['currency'] case final String value when value.isNotEmpty) {
      currency = value;
    }
    if (fields['autoRenew'] case final bool value) autoRenew = value;
    if (fields['reminderEnabled'] case final bool value) {
      reminderEnabled = value;
    }
    if (fields['reminderDaysBefore'] case final int value
        when value >= 0 && value <= 365) {
      reminderDaysBefore = value;
    }
    status =
        SubscriptionStatus.values
            .where((v) => v.name == fields['status'])
            .firstOrNull ??
        status;
    cyclePreset =
        SubscriptionCyclePreset.values
            .where((v) => v.name == fields['cyclePreset'])
            .firstOrNull ??
        cyclePreset;
    customCycleUnit =
        SubscriptionCycleUnit.values
            .where((v) => v.name == fields['customCycleUnit'])
            .firstOrNull ??
        customCycleUnit;
    renewalDateMode =
        SubscriptionRenewalDateMode.values
            .where((v) => v.name == fields['renewalDateMode'])
            .firstOrNull ??
        renewalDateMode;
    renewalDateReachedSupportedLimit =
        fields['renewalDateReachedSupportedLimit'] == true;
  }

  void setFirstSubscribedOn(DateTime value) {
    firstSubscribedOn = subscriptionDateOnly(value);
    _recalculateNextRenewalOn();
  }

  void setCyclePreset(SubscriptionCyclePreset value) {
    cyclePreset = value;
    _recalculateNextRenewalOn();
  }

  void setCustomCycleCount(String value) {
    if (customCycleCountController.text != value) {
      customCycleCountController.text = value;
    }
    if (cyclePreset == SubscriptionCyclePreset.custom) {
      _recalculateNextRenewalOn();
    }
  }

  void setCustomCycleUnit(SubscriptionCycleUnit value) {
    customCycleUnit = value;
    if (cyclePreset == SubscriptionCyclePreset.custom) {
      _recalculateNextRenewalOn();
    }
  }

  void setManualNextRenewalOn(DateTime value) {
    nextRenewalOn = subscriptionDateOnly(value);
    renewalDateMode = SubscriptionRenewalDateMode.manual;
    renewalDateReachedSupportedLimit = false;
  }

  void setExpenseCategoryIfEmpty(String? value) {
    if (expenseCategoryController.text.trim().isNotEmpty) return;
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      expenseCategoryController.text = normalized;
    }
  }

  void useAutomaticNextRenewalOn() {
    _recalculateNextRenewalOn();
  }

  SubscriptionDetailsDraft toDraft() {
    final (:count, :unit) = switch (cyclePreset) {
      SubscriptionCyclePreset.monthly => (
        count: 1,
        unit: SubscriptionCycleUnit.month,
      ),
      SubscriptionCyclePreset.quarterly => (
        count: 3,
        unit: SubscriptionCycleUnit.month,
      ),
      SubscriptionCyclePreset.halfYearly => (
        count: 6,
        unit: SubscriptionCycleUnit.month,
      ),
      SubscriptionCyclePreset.yearly => (
        count: 1,
        unit: SubscriptionCycleUnit.year,
      ),
      SubscriptionCyclePreset.custom => (
        count: int.tryParse(customCycleCountController.text.trim()) ?? 0,
        unit: customCycleUnit,
      ),
    };

    return applySubscriptionAdvancedFields(
      SubscriptionDetailsDraft(
        management: management,
        serviceName: serviceNameController.text,
        planName: planNameController.text,
        amount: amountController.text,
        currency: currency,
        firstSubscribedOn: firstSubscribedOn,
        nextRenewalOn: nextRenewalOn,
        cycleCount: count,
        cycleUnit: unit,
        autoRenew: autoRenew,
        paymentMethod: paymentMethodController.text,
        expenseCategory: expenseCategoryController.text,
        reminderDaysBefore: reminderDaysBefore,
        reminderEnabled: reminderEnabled,
        status: status,
      ),
      advancedFields,
    );
  }

  void dispose() {
    for (final controller in <TextEditingController>[
      serviceNameController,
      planNameController,
      amountController,
      expenseCategoryController,
      paymentMethodController,
      customCycleCountController,
    ]) {
      controller
        ..clear()
        ..dispose();
    }
  }

  void _recalculateNextRenewalOn() {
    final cycle = _resolvedCycle;
    if (cycle == null) {
      return;
    }
    nextRenewalOn = _calculateBoundedAutomaticRenewal(cycle);
    renewalDateMode = SubscriptionRenewalDateMode.automatic;
  }

  DateTime _calculateNextRenewalOn() {
    final cycle = _resolvedCycle;
    if (cycle == null) {
      throw StateError('计费周期无效');
    }
    return _calculateBoundedAutomaticRenewal(cycle);
  }

  DateTime _calculateBoundedAutomaticRenewal(
    ({int count, SubscriptionCycleUnit unit}) cycle,
  ) {
    try {
      return _boundedAutomaticRenewal(
        advanceSubscriptionDate(
          firstSubscribedOn,
          count: cycle.count,
          unit: cycle.unit,
        ),
      );
    } on ArgumentError {
      renewalDateReachedSupportedLimit = true;
      return DateTime(2300, 12, 31);
    }
  }

  DateTime _boundedAutomaticRenewal(DateTime candidate) {
    if (candidate.year > 2300) {
      renewalDateReachedSupportedLimit = true;
      return DateTime(2300, 12, 31);
    }
    renewalDateReachedSupportedLimit = false;
    return candidate;
  }

  ({int count, SubscriptionCycleUnit unit})? get _resolvedCycle {
    return switch (cyclePreset) {
      SubscriptionCyclePreset.monthly => (
        count: 1,
        unit: SubscriptionCycleUnit.month,
      ),
      SubscriptionCyclePreset.quarterly => (
        count: 3,
        unit: SubscriptionCycleUnit.month,
      ),
      SubscriptionCyclePreset.halfYearly => (
        count: 6,
        unit: SubscriptionCycleUnit.month,
      ),
      SubscriptionCyclePreset.yearly => (
        count: 1,
        unit: SubscriptionCycleUnit.year,
      ),
      SubscriptionCyclePreset.custom => switch (int.tryParse(
        customCycleCountController.text.trim(),
      )) {
        final int count when count >= 1 && count <= 120 => (
          count: count,
          unit: customCycleUnit,
        ),
        _ => null,
      },
    };
  }

  static SubscriptionCyclePreset _inferPreset(
    SubscriptionDetailsDraft? initial,
  ) {
    if (initial == null ||
        (initial.cycleCount == 1 &&
            initial.cycleUnit == SubscriptionCycleUnit.month)) {
      return SubscriptionCyclePreset.monthly;
    }
    if (initial.cycleCount == 3 &&
        initial.cycleUnit == SubscriptionCycleUnit.month) {
      return SubscriptionCyclePreset.quarterly;
    }
    if (initial.cycleCount == 6 &&
        initial.cycleUnit == SubscriptionCycleUnit.month) {
      return SubscriptionCyclePreset.halfYearly;
    }
    if (initial.cycleCount == 1 &&
        initial.cycleUnit == SubscriptionCycleUnit.year) {
      return SubscriptionCyclePreset.yearly;
    }
    return SubscriptionCyclePreset.custom;
  }
}

class SubscriptionFormFields extends StatefulWidget {
  const SubscriptionFormFields({
    required this.controller,
    required this.keyPrefix,
    this.allowStatus = true,
    super.key,
  });

  final SubscriptionFormController controller;
  final String keyPrefix;
  final bool allowStatus;

  @override
  State<SubscriptionFormFields> createState() => _SubscriptionFormFieldsState();
}

class _SubscriptionFormFieldsState extends State<SubscriptionFormFields> {
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.controller.onDraftChanged?.call();
  }

  Future<void> _pickDate({required bool firstSubscription}) async {
    final controller = widget.controller;
    final initialDate = firstSubscription
        ? controller.firstSubscribedOn
        : controller.nextRenewalOn;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2300),
      helpText: context.tr(firstSubscription ? '选择首次订阅日期' : '选择下次续费日期'),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      if (firstSubscription) {
        controller.setFirstSubscribedOn(selected);
      } else {
        controller.setManualNextRenewalOn(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final prefix = widget.keyPrefix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: ValueKey<String>('$prefix-service-name'),
          controller: controller.serviceNameController,
          maxLength: 100,
          textInputAction: TextInputAction.next,
          autocorrect: true,
          enableSuggestions: true,
          enableIMEPersonalizedLearning: true,
          decoration: InputDecoration(
            labelText: context.tr('订阅服务 *'),
            helperText: context.tr('例如：高级会员、云存储、专业版。'),
            counterText: '',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? context.tr('请输入订阅服务名称')
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey<String>('$prefix-plan-name'),
          controller: controller.planNameController,
          maxLength: 100,
          autocorrect: true,
          enableSuggestions: true,
          enableIMEPersonalizedLearning: true,
          decoration: InputDecoration(
            labelText: context.tr('套餐名称（可选）'),
            hintText: context.tr('月度版、家庭版、年度版'),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey<String>('$prefix-amount'),
                controller: controller.amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: context.tr('金额（可选）'),
                  hintText: context.tr('19.9'),
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  if (normalized.isEmpty) {
                    return null;
                  }
                  return RegExp(
                        r'^(0|[1-9]\d{0,11})(\.\d{1,4})?$',
                      ).hasMatch(normalized)
                      ? null
                      : context.tr('金额格式无效');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey<String>('$prefix-currency'),
                initialValue: controller.currency,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('币种')),
                items: [
                  for (final currency in <String>{
                    controller.currency,
                    ...subscriptionCurrencies,
                  })
                    DropdownMenuItem(
                      value: currency,
                      child: Text(currency, translate: false),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.currency = value;
                    controller.onDraftChanged?.call();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey<String>('$prefix-expense-category'),
          controller: controller.expenseCategoryController,
          maxLength: 100,
          autocorrect: true,
          enableSuggestions: true,
          enableIMEPersonalizedLearning: true,
          decoration: InputDecoration(
            labelText: context.tr('费用分类（可选）'),
            helperText: context.tr('默认可采用关联账号分类，也可以为这条订阅单独设置。'),
            hintText: context.tr('例如：影音娱乐、云服务'),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SubscriptionCyclePreset>(
          key: ValueKey<String>('$prefix-cycle-preset'),
          initialValue: controller.cyclePreset,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.tr('计费周期')),
          items: [
            for (final preset in SubscriptionCyclePreset.values)
              DropdownMenuItem(value: preset, child: Text(preset.label)),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => controller.setCyclePreset(value));
            }
          },
        ),
        if (controller.cyclePreset == SubscriptionCyclePreset.custom) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey<String>('$prefix-custom-cycle-count'),
                  controller: controller.customCycleCountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: context.tr('周期数量')),
                  validator: (value) {
                    final count = int.tryParse(value?.trim() ?? '');
                    return count == null || count < 1 || count > 120
                        ? context.tr('请输入1到120')
                        : null;
                  },
                  onChanged: (value) {
                    setState(() => controller.setCustomCycleCount(value));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<SubscriptionCycleUnit>(
                  key: ValueKey<String>('$prefix-custom-cycle-unit'),
                  initialValue: controller.customCycleUnit,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('周期单位')),
                  items: [
                    for (final unit in SubscriptionCycleUnit.values)
                      DropdownMenuItem(value: unit, child: Text(unit.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => controller.setCustomCycleUnit(value));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _DateField(
          fieldKey: ValueKey<String>('$prefix-first-date'),
          label: '首次订阅日期',
          value: controller.firstSubscribedOn,
          onTap: () => _pickDate(firstSubscription: true),
        ),
        const SizedBox(height: 12),
        _DateField(
          fieldKey: ValueKey<String>('$prefix-renewal-date'),
          label:
              controller.renewalDateMode ==
                  SubscriptionRenewalDateMode.automatic
              ? '下次续费日期（自动）'
              : '下次续费日期（手动）',
          value: controller.nextRenewalOn,
          onTap: () => _pickDate(firstSubscription: false),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                controller.renewalDateMode ==
                        SubscriptionRenewalDateMode.automatic
                    ? Icons.auto_awesome_outlined
                    : Icons.edit_calendar_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.renewalDateReachedSupportedLimit
                    ? '计算结果超过支持的日期范围，已暂设为2300-12-31，请调整首次日期或周期。'
                    : controller.renewalDateMode ==
                          SubscriptionRenewalDateMode.automatic
                    ? '已按首次订阅日期和计费周期自动计算。'
                    : '当前为手动日期，可用于记录赠送天数等特殊情况。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: controller.renewalDateReachedSupportedLimit
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
            if (controller.renewalDateMode ==
                SubscriptionRenewalDateMode.manual)
              TextButton(
                key: ValueKey<String>('$prefix-renewal-auto-reset'),
                onPressed: () {
                  setState(controller.useAutomaticNextRenewalOn);
                },
                child: const Text('恢复自动'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: ValueKey<String>('$prefix-auto-renew'),
          contentPadding: EdgeInsets.zero,
          title: const Text('自动续费'),
          subtitle: const Text('仅记录当前设置，不会代替平台执行续费或取消。'),
          value: controller.autoRenew,
          onChanged: (value) => setState(() => controller.autoRenew = value),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: '选择支付方式'),
          items: [
            for (final name in <String>{
              ...controller.availablePaymentMethods
                  .where((p) => !p.archived)
                  .map((p) => p.name),
              '微信支付',
              '支付宝',
              '银行卡',
              'App Store',
              'Google Play',
              'PayPal',
              '其他',
            })
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (name) {
            if (name != null) controller.paymentMethodController.text = name;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey<String>('$prefix-payment-method'),
          controller: controller.paymentMethodController,
          maxLength: 100,
          autocorrect: true,
          enableSuggestions: true,
          enableIMEPersonalizedLearning: true,
          decoration: InputDecoration(
            labelText: context.tr('支付方式（可选）'),
            helperText: context.tr('只填写支付宝、微信、银行卡等方式名称，不要填写卡号。'),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: ValueKey<String>('$prefix-reminder-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('本机到期提醒'),
          subtitle: const Text('提醒内容默认隐藏平台、账号与金额。'),
          value: controller.reminderEnabled,
          onChanged: (value) =>
              setState(() => controller.reminderEnabled = value),
        ),
        if (controller.reminderEnabled) ...[
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            key: ValueKey<String>('$prefix-reminder-days'),
            initialValue: controller.reminderDaysBefore,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('提前提醒')),
            items: [
              for (final days in <int>{
                controller.reminderDaysBefore,
                0,
                1,
                3,
                7,
                15,
                30,
              }.toList()..sort())
                DropdownMenuItem(
                  value: days,
                  child: Text(
                    days == 0
                        ? context.tr('续费当天')
                        : localizedDaysBefore(context.l10n.language, days),
                    translate: false,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.reminderDaysBefore = value;
                controller.advancedFields['renewalDays'] = value.toString();
                controller.onDraftChanged?.call();
              }
            },
          ),
        ],
        if (widget.allowStatus) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<SubscriptionStatus>(
            key: ValueKey<String>('$prefix-status'),
            initialValue: controller.status,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr('订阅状态'),
              helperText: context.tr('取消或恢复请使用订阅卡片上的专用操作。'),
            ),
            items: [
              for (final status in SubscriptionStatus.values)
                DropdownMenuItem(
                  value: status,
                  enabled: status != SubscriptionStatus.cancelled,
                  child: Text(
                    localizedSubscriptionStatus(context.l10n.language, status),
                    translate: false,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.status = value;
                controller.onDraftChanged?.call();
              }
            },
          ),
        ],
        SubscriptionAdvancedFields(
          fields: controller.advancedFields,
          trialResolved:
              controller.management?.trial != null &&
              !controller.management!.trial!.unresolved,
          onChanged: (fields) {
            controller.advancedFields = fields;
            controller.onDraftChanged?.call();
          },
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Key fieldKey;
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: fieldKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      title: Text(context.tr(label), translate: false),
      subtitle: Text(
        localizedRecordDate(context.l10n.language, value),
        translate: false,
      ),
      trailing: const Icon(Icons.calendar_month_outlined),
      onTap: onTap,
    );
  }
}
