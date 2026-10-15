import '../../../core/security/account_comparison.dart';

enum BindingType { phone, email }

/// Account references record scope; progress derives from current account fields.
final class BindingRetirementPlan {
  BindingRetirementPlan({
    required this.id,
    required this.type,
    required this.targetValue,
    required this.normalizedValue,
    required DateTime createdAtUtc,
    Set<String> accountIds = const {},
    DateTime? closedAtUtc,
  }) : createdAtUtc = createdAtUtc.toUtc(),
       closedAtUtc = closedAtUtc?.toUtc(),
       accountIds = Set.unmodifiable(accountIds) {
    final expected = type == BindingType.phone
        ? AccountComparison.phone(targetValue)
        : AccountComparison.email(targetValue);
    if (normalizedValue != expected ||
        id.isEmpty ||
        id.runes.length > 128 ||
        targetValue.trim().isEmpty ||
        targetValue.runes.length > 512 ||
        normalizedValue.isEmpty ||
        normalizedValue.runes.length > 512 ||
        this.accountIds.length > 10000 ||
        this.accountIds.any((id) => id.isEmpty || id.runes.length > 128) ||
        !_validInstant(this.createdAtUtc) ||
        this.closedAtUtc != null &&
            (!_validInstant(this.closedAtUtc!) ||
                this.closedAtUtc!.isBefore(this.createdAtUtc))) {
      throw ArgumentError('绑定资料停用计划无效');
    }
  }
  final String id, targetValue, normalizedValue;
  final BindingType type;
  final DateTime createdAtUtc;
  final DateTime? closedAtUtc;
  final Set<String> accountIds;
  bool get isClosed => closedAtUtc != null;
  BindingRetirementPlan copyWith({
    Set<String>? accountIds,
    DateTime? closedAtUtc,
  }) => BindingRetirementPlan(
    id: id,
    type: type,
    targetValue: targetValue,
    normalizedValue: normalizedValue,
    createdAtUtc: createdAtUtc,
    accountIds: accountIds ?? this.accountIds,
    closedAtUtc: closedAtUtc ?? this.closedAtUtc,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'targetValue': targetValue,
    'normalizedValue': normalizedValue,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'closedAtUtc': closedAtUtc?.toIso8601String(),
    'accountIds': accountIds.toList(),
  };
  factory BindingRetirementPlan.fromJson(Object? value) {
    try {
      if (value is! Map<Object?, Object?> ||
          value['id'] is! String ||
          value['type'] is! String ||
          value['targetValue'] is! String ||
          value['normalizedValue'] is! String ||
          value['accountIds'] is! List) {
        throw const FormatException('绑定资料停用计划无效');
      }
      final type = BindingType.values
          .where((candidate) => candidate.name == value['type'])
          .firstOrNull;
      final ids = value['accountIds'] as List;
      if (type == null ||
          ids.any((id) => id is! String) ||
          ids.toSet().length != ids.length) {
        throw const FormatException('绑定资料停用计划无效');
      }
      return BindingRetirementPlan(
        id: value['id'] as String,
        type: type,
        targetValue: value['targetValue'] as String,
        normalizedValue: value['normalizedValue'] as String,
        createdAtUtc: _readInstant(value['createdAtUtc']),
        closedAtUtc: value['closedAtUtc'] == null
            ? null
            : _readInstant(value['closedAtUtc']),
        accountIds: ids.cast<String>().toSet(),
      );
    } on ArgumentError {
      throw const FormatException('绑定资料停用计划无效');
    }
  }
}

bool _validInstant(DateTime value) =>
    value.isUtc && value.year >= 1970 && value.year <= 2300;
DateTime _readInstant(Object? value) {
  if (value is! String) throw const FormatException('计划时间无效');
  final date = DateTime.tryParse(value);
  if (date == null || !_validInstant(date) || date.toIso8601String() != value) {
    throw const FormatException('计划时间无效');
  }
  return date;
}
