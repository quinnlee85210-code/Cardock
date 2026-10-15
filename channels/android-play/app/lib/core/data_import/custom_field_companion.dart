import '../../features/accounts/domain/account_custom_field.dart';
import 'import_models.dart';

/// Cardock-only companion rows never pass through third-party adapters.
final class CustomFieldCompanionRow {
  CustomFieldCompanionRow({
    required this.rowNumber,
    required this.accountKey,
    required this.field,
    this.useImportedValue = true,
    this.sensitiveConfirmed = false,
    this.replaceExisting = false,
  });
  final int rowNumber;
  final String accountKey;
  final AccountCustomField field;
  bool useImportedValue;
  bool sensitiveConfirmed;
  bool replaceExisting;
}

final class CustomFieldCompanion {
  CustomFieldCompanion._(this.rows);
  final List<CustomFieldCompanionRow> rows;
  static const headers = [
    'account_key',
    'field_order',
    'field_name',
    'field_type',
    'field_value',
  ];
  static const _aliases = <String, String>{
    '账号关联标识': 'account_key',
    '账号关联键': 'account_key',
    'アカウントキー': 'account_key',
    '字段顺序': 'field_order',
    '項目順': 'field_order',
    '字段名称': 'field_name',
    '項目名': 'field_name',
    '字段类型': 'field_type',
    '項目タイプ': 'field_type',
    '字段值': 'field_value',
    '項目値': 'field_value',
  };
  factory CustomFieldCompanion.parse(
    TabularDocument document,
    Iterable<AccountImportDraft> accounts,
  ) {
    if (document.hasErrors || document.rows.any((r) => !r.isValid)) {
      throw const FormatException('自定义字段伴随文件存在无效行。');
    }
    final positions = <String, int>{};
    for (var i = 0; i < document.headers.length; i++) {
      final name = document.headers[i].trim();
      final key = _aliases[name] ?? name.toLowerCase();
      if (headers.contains(key)) {
        if (positions.containsKey(key)) {
          throw const FormatException('自定义字段伴随文件表头重复。');
        }
        positions[key] = i;
      }
    }
    if (headers.any((h) => !positions.containsKey(h))) {
      throw const FormatException('请选择 Cardock 账号自定义字段模板。');
    }
    final byKey = <String, List<AccountImportDraft>>{};
    for (final account in accounts) {
      if (account.adapterId != 'cardock_accounts_template') {
        throw const FormatException('自定义字段伴随文件仅适用于 Cardock 账号模板。');
      }
      if (account.accountKey != null && !account.accountKeyWasGenerated) {
        byKey.putIfAbsent(account.accountKey!, () => []).add(account);
      }
    }
    final rows = <CustomFieldCompanionRow>[];
    final grouped = <String, List<AccountCustomField>>{};
    final nonce = DateTime.now().microsecondsSinceEpoch;
    for (final row in document.rows) {
      String cell(String key) => row.valueAt(positions[key]!);
      final key = cell('account_key').trim();
      if (key.isEmpty || byKey[key]?.length != 1) {
        throw const FormatException('account_key 未唯一关联本次导入的账号。');
      }
      final type = AccountCustomFieldType.values
          .where((t) => t.code == cell('field_type').trim())
          .firstOrNull;
      final order = int.tryParse(cell('field_order').trim());
      if (type == null || order == null || order < 0) {
        throw const FormatException('字段类型或顺序无效。');
      }
      final field = AccountCustomField(
        id: 'import-$nonce-${row.originalRowNumber}',
        name: cell('field_name'),
        type: type,
        value: cell('field_value'),
        order: order,
      );
      grouped.putIfAbsent(key, () => []).add(field);
      rows.add(
        CustomFieldCompanionRow(
          rowNumber: row.originalRowNumber,
          accountKey: key,
          field: field,
          useImportedValue: !field.isSensitive,
        ),
      );
    }
    // Reject an entire account's fields rather than silently keeping the first ten.
    for (final fields in grouped.values) {
      validateAccountCustomFields(fields);
    }
    return CustomFieldCompanion._(rows);
  }

  AccountImportDraft apply(AccountImportDraft draft) {
    final selected = rows.where(
      (row) => row.accountKey == draft.accountKey && row.useImportedValue,
    );
    return draft.copyWith(
      customFields: [for (final row in selected) row.field],
      replaceCustomFieldNames: {
        for (final row in selected)
          if (row.replaceExisting) row.field.normalizedName,
      },
      confirmedSensitiveCustomFieldIds: {
        for (final row in selected)
          if (row.sensitiveConfirmed) row.field.id,
      },
    );
  }
}

/// Revalidated at the transaction boundary. No partial updates are produced.
List<AccountCustomField> mergeImportedCustomFields(
  Iterable<AccountCustomField> existing,
  AccountImportDraft imported,
) {
  final incoming = validateAccountCustomFields(imported.customFields);
  if (incoming.isNotEmpty &&
      imported.adapterId != 'cardock_accounts_template') {
    throw const FormatException('自定义字段伴随文件仅适用于 Cardock 账号模板。');
  }
  if (incoming.any(
    (f) =>
        f.isSensitive &&
        !imported.confirmedSensitiveCustomFieldIds.contains(f.id),
  )) {
    throw const FormatException('敏感字段必须在手机逐条确认。');
  }
  final result = List<AccountCustomField>.of(existing);
  for (final field in incoming) {
    final index = result.indexWhere(
      (current) => current.normalizedName == field.normalizedName,
    );
    if (index >= 0) {
      if (!imported.replaceCustomFieldNames.contains(field.normalizedName)) {
        continue;
      }
      final current = result[index];
      result[index] = current.copyWith(
        name: field.name,
        type: field.type,
        value: field.value,
        order: field.order,
        revision: current.revision + 1,
      );
    } else {
      result.add(field);
    }
  }
  return validateAccountCustomFields([
    for (var i = 0; i < result.length; i++) result[i].copyWith(order: i),
  ]);
}
