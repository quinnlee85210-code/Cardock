import 'package:unorm_dart/unorm_dart.dart' as unorm;

enum AccountCustomFieldType {
  text,
  sensitiveText,
  url,
  date,
  number;

  String get code =>
      this == AccountCustomFieldType.sensitiveText ? 'sensitive_text' : name;
}

String normalizeCustomFieldName(String value) =>
    unorm.nfkc(value).trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Values stay in the authenticated account payload, including empty values.
final class AccountCustomField {
  AccountCustomField({
    required this.id,
    required this.name,
    required this.type,
    this.value = '',
    required this.order,
    this.revision = 0,
  }) {
    if (id.isEmpty ||
        id.runes.length > 128 ||
        normalizedName.isEmpty ||
        name.runes.length > 100 ||
        order < 0 ||
        order > 1000000 ||
        revision < 0 ||
        revision > 9007199254740991 ||
        value.runes.length > 10000) {
      throw ArgumentError('自定义字段格式或长度无效');
    }
    if (value.isEmpty) return;
    if (type == AccountCustomFieldType.date) {
      final parsed = DateTime.tryParse(value);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          parsed == null ||
          parsed.year < 1 ||
          '${parsed.year.toString().padLeft(4, '0')}-'
                  '${parsed.month.toString().padLeft(2, '0')}-'
                  '${parsed.day.toString().padLeft(2, '0')}' !=
              value) {
        throw ArgumentError('日期字段请使用有效的 YYYY-MM-DD 日期');
      }
    }
    if (type == AccountCustomFieldType.number &&
        (value.length > 128 ||
            !RegExp(r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$').hasMatch(value))) {
      throw ArgumentError('数字字段请使用十进制字符串');
    }
    if (type == AccountCustomFieldType.url && value.runes.length > 2048) {
      throw ArgumentError('网址字段过长');
    }
  }

  final String id, name, value;
  final AccountCustomFieldType type;
  final int order, revision;
  bool get isSensitive => type == AccountCustomFieldType.sensitiveText;
  String get normalizedName => normalizeCustomFieldName(name);

  AccountCustomField copyWith({
    String? name,
    AccountCustomFieldType? type,
    String? value,
    int? order,
    int? revision,
  }) => AccountCustomField(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    value: value ?? this.value,
    order: order ?? this.order,
    revision: revision ?? this.revision,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.code,
    'value': value,
    'order': order,
    'revision': revision,
  };

  factory AccountCustomField.fromJson(Object? value) {
    try {
      if (value is! Map<Object?, Object?> ||
          value['id'] is! String ||
          value['name'] is! String ||
          value['type'] is! String ||
          value['value'] is! String ||
          value['order'] is! int ||
          (value['revision'] != null && value['revision'] is! int)) {
        throw const FormatException('自定义字段格式无效');
      }
      final type = AccountCustomFieldType.values
          .where(
            (candidate) =>
                candidate.code == value['type'] ||
                candidate.name == value['type'],
          )
          .firstOrNull;
      if (type == null) throw const FormatException('自定义字段类型未知');
      return AccountCustomField(
        id: value['id'] as String,
        name: value['name'] as String,
        type: type,
        value: value['value'] as String,
        order: value['order'] as int,
        revision: value['revision'] as int? ?? 0,
      );
    } on ArgumentError {
      throw const FormatException('自定义字段格式无效');
    }
  }
}

List<AccountCustomField> validateAccountCustomFields(
  Iterable<AccountCustomField> fields,
) {
  final result = fields.toList();
  if (result.length > 10 ||
      result.map((field) => field.id).toSet().length != result.length ||
      result.map((field) => field.normalizedName).toSet().length !=
          result.length ||
      result.map((field) => field.order).toSet().length != result.length) {
    throw ArgumentError('每个账号最多 10 个自定义字段，名称、标识和排序不能重复');
  }
  result.sort((a, b) => a.order.compareTo(b.order));
  return List.unmodifiable(result);
}
