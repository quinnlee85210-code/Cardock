import '../../features/subscriptions/domain/subscription_record.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../app_metadata.dart';
import '../security/vault_contract.dart';

enum ReadableExportFormat { csvZip, json }

final class ReadableExportOptions {
  const ReadableExportOptions({
    this.format = ReadableExportFormat.csvZip,
    this.includeTrash = false,
    this.includePasswords = false,
    this.includeSensitiveCustomFields = false,
  });
  final ReadableExportFormat format;
  final bool includeTrash, includePasswords, includeSensitiveCustomFields;
}

/// Explicit field allowlists: future secrets cannot enter an export implicitly.
final class ReadableExport {
  ReadableExport(this.snapshot, this.options, {DateTime? exportedAt})
    : exportedAt = (exportedAt ?? DateTime.now()).toUtc();
  final VaultSnapshot snapshot;
  final ReadableExportOptions options;
  final DateTime exportedAt;
  static const _accountKeys = [
    'id',
    'platformName',
    'category',
    'loginAccount',
    'username',
    'boundPhone',
    'boundEmail',
    'website',
    'notes',
    'passwordStoredAtUtc',
    'passwordSyncState',
    'passwordVerifiedAtUtc',
    'platformPasswordChangedAtUtc',
    'passwordReviewIntervalDays',
    'passwordReviewSnoozedUntilUtc',
  ];
  static const _subscriptionKeys = [
    'id',
    'accountId',
    'serviceName',
    'planName',
    'amount',
    'currency',
    'firstSubscribedOn',
    'nextRenewalOn',
    'cycleCount',
    'cycleUnit',
    'autoRenew',
    'paymentMethod',
    'notes',
    'expenseCategory',
    'reminderDaysBefore',
    'reminderEnabled',
    'status',
    'snoozedUntil',
    'snoozedUntilUtc',
    'cancelledOn',
    'accessEndsOn',
    'payment_method_id',
    'trial_info',
    'reminder_rules',
    'price_history',
    'cancellation_info',
    'history_incomplete',
  ];
  static const _expenseKeys = [
    'id',
    'subscriptionId',
    'accountId',
    'accountLabel',
    'source',
    'serviceName',
    'occurredOn',
    'amount',
    'currency',
    'kind',
    'expenseCategory',
    'scheduledRenewalOn',
    'recordedAtUtc',
    'paymentMethodId',
    'paymentMethodName',
  ];
  static const _historyKeys = [
    'accountId',
    'changedAtUtc',
    'previousStoredAtUtc',
  ];
  static const _deletedKeys = ['deleted_at', 'deletion_batch_id'];
  Map<String, Object?> get metadata => {
    'schema_version': 2,
    'vault_schema_version': VaultSnapshot.currentSchemaVersion,
    'exported_at': exportedAt.toIso8601String(),
    'app_version': AppMetadata.version,
    'includes_passwords': options.includePasswords,
    'includes_sensitive_custom_fields': options.includeSensitiveCustomFields,
    'includes_binding_contact_values': true,
    'includes_trash': options.includeTrash,
    'includes_plaintext_notes': true,
    'restore_format': false,
  };
  Map<String, Object?> _pick(
    Map<String, Object?> value,
    Iterable<String> keys,
  ) => {for (final key in keys) key: value[key]};
  List<String> get accountKeys => [
    ..._accountKeys,
    if (options.includePasswords) 'password',
    if (options.includeTrash) ..._deletedKeys,
  ];
  List<String> get subscriptionKeys => [
    ..._subscriptionKeys,
    if (options.includeTrash) ..._deletedKeys,
  ];
  Iterable<Map<String, Object?>> get accounts sync* {
    for (final record in snapshot.accounts) {
      yield _pick(record.toEncryptedPayloadJson(), accountKeys);
    }
    if (options.includeTrash) {
      for (final item in snapshot.trashAccounts) {
        yield _pick(item.record.toEncryptedPayloadJson(), accountKeys)
          ..['deleted_at'] = item.deletedAtUtc.toIso8601String()
          ..['deletion_batch_id'] = item.batchId;
      }
    }
  }

  static const _customFieldKeys = [
    'account_key',
    'field_id',
    'field_order',
    'field_name',
    'field_type',
    'field_value',
    'value_state',
    'deleted_at',
    'deletion_batch_id',
  ];
  Iterable<Map<String, Object?>> get customFields sync* {
    for (final record in snapshot.accounts) {
      for (final field in record.customFields) {
        final redacted =
            field.isSensitive && !options.includeSensitiveCustomFields;
        yield {
          'account_key': record.id,
          'field_id': field.id,
          'field_order': field.order,
          'field_name': field.name,
          'field_type': field.type.code,
          'field_value': redacted ? '' : field.value,
          'value_state': redacted
              ? 'redacted'
              : (field.value.isEmpty ? 'empty' : 'present'),
        };
      }
    }
    if (options.includeTrash) {
      for (final item in snapshot.trashAccounts) {
        for (final field in item.record.customFields) {
          final redacted =
              field.isSensitive && !options.includeSensitiveCustomFields;
          yield {
            'account_key': item.record.id,
            'field_id': field.id,
            'field_order': field.order,
            'field_name': field.name,
            'field_type': field.type.code,
            'field_value': redacted ? '' : field.value,
            'value_state': redacted
                ? 'redacted'
                : (field.value.isEmpty ? 'empty' : 'present'),
            'deleted_at': item.deletedAtUtc.toIso8601String(),
            'deletion_batch_id': item.batchId,
          };
        }
      }
    }
  }

  static const _bindingKeys = [
    'id',
    'type',
    'targetValue',
    'createdAtUtc',
    'closedAtUtc',
    'accountIds',
  ];
  Iterable<Map<String, Object?>> get bindingRetirementPlans => snapshot
      .bindingRetirementPlans
      .map((plan) => _pick(plan.toJson(), _bindingKeys));

  Iterable<Map<String, Object?>> get subscriptions sync* {
    for (final record in snapshot.subscriptions) {
      yield _subscriptionRow(record);
    }
    if (options.includeTrash) {
      for (final item in snapshot.trashSubscriptions) {
        yield _subscriptionRow(item.record)
          ..['deleted_at'] = item.deletedAtUtc.toIso8601String()
          ..['deletion_batch_id'] = item.batchId;
      }
    }
  }

  Map<String, Object?> _subscriptionRow(SubscriptionRecord record) => {
    ..._pick(record.toEncryptedPayloadJson(), subscriptionKeys),
    'payment_method_id': record.management?.paymentMethodId,
    'trial_info': record.management?.trial?.toJson(),
    'reminder_rules': record.effectiveReminderRules
        .map((r) => r.toJson())
        .toList(),
    'price_history':
        record.management?.priceHistory.map((p) => p.toJson()).toList() ?? [],
    'cancellation_info': record.management?.cancellation?.toJson(),
    'history_incomplete': record.management?.historyIncomplete ?? true,
  };
  Iterable<SubscriptionRecord> get _exportSubscriptions => [
    ...snapshot.subscriptions,
    if (options.includeTrash)
      ...snapshot.trashSubscriptions.map((t) => t.record),
  ];
  static const _trialKeys = [
    'subscriptionId',
    'startsOn',
    'endsOn',
    'amount',
    'currency',
    'expectedAutoConvert',
    'firstPaidOn',
    'formalAmount',
    'formalCurrency',
    'formalCycleCount',
    'formalCycleUnit',
    'outcome',
    'convertedOn',
    'lastConfirmedAt',
    'paymentConfirmed',
  ];
  static const _reminderKeys = ['subscriptionId', 'event', 'daysBefore'];
  static const _priceKeys = [
    'subscriptionId',
    'id',
    'effectiveOn',
    'amount',
    'currency',
    'cycleCount',
    'cycleUnit',
    'kind',
    'createdAt',
    'note',
  ];
  static const _paymentKeys = [
    'id',
    'name',
    'type',
    'shortLabel',
    'note',
    'archived',
  ];
  Iterable<Map<String, Object?>> get trials => [
    for (final s in _exportSubscriptions)
      if (s.management?.trial != null)
        {'subscriptionId': s.id, ...s.management!.trial!.toJson()},
  ];
  Iterable<Map<String, Object?>> get reminders => [
    for (final s in _exportSubscriptions)
      for (final r in s.effectiveReminderRules)
        {'subscriptionId': s.id, ...r.toJson()},
  ];
  Iterable<Map<String, Object?>> get prices => [
    for (final s in _exportSubscriptions)
      for (final p in s.management?.priceHistory ?? <SubscriptionPricePoint>[])
        {'subscriptionId': s.id, ...p.toJson()},
  ];
  Iterable<Map<String, Object?>> get paymentMethods =>
      snapshot.paymentMethods.map((p) => p.toJson());

  Iterable<Map<String, Object?>> get expenses => snapshot.subscriptionExpenses
      .where((expense) => !expense.isDeleted)
      .map((e) => _pick(e.toEncryptedPayloadJson(), _expenseKeys));
  Iterable<Map<String, Object?>> get history sync* {
    for (final account in [
      ...snapshot.accounts,
      if (options.includeTrash) ...snapshot.trashAccounts.map((e) => e.record),
    ]) {
      for (final event in account.passwordChangeHistory) {
        yield {
          'accountId': account.id,
          'changedAtUtc': event.changedAtUtc.toIso8601String(),
          'previousStoredAtUtc': event.previousStoredAtUtc?.toIso8601String(),
        };
      }
    }
  }

  Stream<List<int>> bytes() =>
      options.format == ReadableExportFormat.json ? _json() : _zip();
  Stream<List<int>> _json() async* {
    final header = jsonEncode(metadata);
    yield utf8.encode(header.substring(0, header.length - 1));
    for (final table in <String, Iterable<Map<String, Object?>>>{
      'accounts': accounts,
      'account_custom_fields': customFields,
      'binding_retirement_plans': bindingRetirementPlans,
      'subscriptions': subscriptions,
      'expense_records': expenses,
      'password_change_history': history,
      'payment_methods': paymentMethods,
      'subscription_trials': trials,
      'subscription_reminders': reminders,
      'subscription_price_history': prices,
    }.entries) {
      yield utf8.encode(',${jsonEncode(table.key)}:[');
      var first = true;
      for (final row in table.value) {
        yield utf8.encode('${first ? '' : ','}${jsonEncode(row)}');
        first = false;
      }
      yield const [93];
    }
    yield const [125];
  }

  static String csvCell(Object? value) {
    var text = value is Map || value is List
        ? jsonEncode(value)
        : value?.toString() ?? '';
    // Check past control/space prefixes too; quoting alone does not neutralize
    // spreadsheet formulas. Numeric schema amounts remain decimal strings.
    if (RegExp(r'^[\s\x00-\x1f]*[=+\-@]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  Stream<List<int>> _csv(
    List<String> keys,
    Iterable<Map<String, Object?>> rows,
  ) async* {
    yield const [0xef, 0xbb, 0xbf];
    yield utf8.encode('${keys.map(csvCell).join(',')}\r\n');
    for (final row in rows) {
      yield utf8.encode(
        '${keys.map((key) => csvCell(row[key])).join(',')}\r\n',
      );
    }
  }

  Stream<List<int>> _zip() async* {
    final sources = <String, Stream<List<int>>>{
      'accounts.csv': _csv(accountKeys, accounts),
      'account_custom_fields.csv': _csv(_customFieldKeys, customFields),
      'binding_retirement_plans.csv': _csv(
        _bindingKeys,
        bindingRetirementPlans,
      ),
      'subscriptions.csv': _csv(subscriptionKeys, subscriptions),
      'expense_records.csv': _csv(_expenseKeys, expenses),
      'password_change_history.csv': _csv(_historyKeys, history),
      'subscription_trials.csv': _csv(_trialKeys, trials),
      'subscription_reminders.csv': _csv(_reminderKeys, reminders),
      'subscription_price_history.csv': _csv(_priceKeys, prices),
      'payment_methods.csv': _csv(_paymentKeys, paymentMethods),
      'metadata.json': Stream.value(utf8.encode(jsonEncode(metadata))),
      'README.txt': Stream.value(
        utf8.encode(
          'PLAINTEXT / 明文 / 平文\n'
          'This archive is not an .asmbackup and cannot overwrite or restore a vault.\n'
          'accounts.id = subscriptions.accountId; subscriptions.id = expense_records.subscriptionId.\n'
          'Historical expenses may reference deleted records omitted from this export.\n'
          'Dates: ISO 8601; instant timestamps: UTC; amounts: decimal strings; null: empty CSV cell.\n'
          'Includes current passwords: ${options.includePasswords}. Includes plaintext notes: true.\n'
          'Password history contains dates only, never previous password values.\n'
          'Includes sensitive custom field values: ${options.includeSensitiveCustomFields}. Redacted values are empty.\n'
          'Binding retirement plans contain phone numbers or email addresses.\n'
          'subscription_* tables use subscriptionId; payment_method_id references payment_methods.id.\n'
          'Trial outcomes require manual confirmation; forecasts and monthly equivalents are not payments.\n'
          'History incomplete means compatibility estimates, not evidence of past prices. Nested CSV values are JSON.\n'
          'CSV uses UTF-8 BOM, quoted cells and CRLF. Formula-like user values have an apostrophe prefix.\n'
          '明文备注和所选当前密码不再受保险库保护。请妥善保存。此文件不能用于 Cardock 恢复。\n'
          '平文のメモと選択した現在のパスワードは保護されません。保管に注意してください。復元には使用できません。\n',
        ),
      ),
    };
    yield* _StreamingZip.encode(sources);
  }
}

/// Deflate + ZIP data descriptors allow direct SAF streaming without plaintext
/// temp files or a second complete in-memory copy of the archive.
abstract final class _StreamingZip {
  static Uint8List _header(int size, List<(int, int, int)> fields) {
    final bytes = Uint8List(size), data = ByteData(size);
    for (final (offset, width, value) in fields) {
      if (width == 2) {
        data.setUint16(offset, value, Endian.little);
      } else {
        data.setUint32(offset, value, Endian.little);
      }
    }
    bytes.setAll(0, data.buffer.asUint8List());
    return bytes;
  }

  static int _crc(int crc, List<int> bytes) {
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    return crc;
  }

  static Stream<List<int>> encode(
    Map<String, Stream<List<int>>> sources,
  ) async* {
    var offset = 0;
    final directory = <List<int>>[];
    for (final entry in sources.entries) {
      final name = utf8.encode(entry.key), start = offset;
      final header = _header(30, [
        (0, 4, 0x04034b50),
        (4, 2, 20),
        (6, 2, 0x808),
        (8, 2, 8),
        (26, 2, name.length),
      ]);
      yield header;
      yield name;
      offset += header.length + name.length;
      var crc = 0xffffffff, size = 0, compressed = 0;
      final clear = entry.value.map((bytes) {
        crc = _crc(crc, bytes);
        size += bytes.length;
        return bytes;
      });
      await for (final chunk in ZLibEncoder(raw: true).bind(clear)) {
        yield chunk;
        compressed += chunk.length;
        offset += chunk.length;
      }
      crc ^= 0xffffffff;
      if (size > 0x7fffffff || offset > 0x7fffffff) {
        throw const FormatException('Export too large');
      }
      final descriptor = _header(16, [
        (0, 4, 0x08074b50),
        (4, 4, crc),
        (8, 4, compressed),
        (12, 4, size),
      ]);
      yield descriptor;
      offset += descriptor.length;
      directory.add([
        ..._header(46, [
          (0, 4, 0x02014b50),
          (4, 2, 20),
          (6, 2, 20),
          (8, 2, 0x808),
          (10, 2, 8),
          (16, 4, crc),
          (20, 4, compressed),
          (24, 4, size),
          (28, 2, name.length),
          (42, 4, start),
        ]),
        ...name,
      ]);
    }
    final start = offset;
    for (final record in directory) {
      yield record;
      offset += record.length;
    }
    yield _header(22, [
      (0, 4, 0x06054b50),
      (8, 2, directory.length),
      (10, 2, directory.length),
      (12, 4, offset - start),
      (16, 4, start),
    ]);
  }
}
