import 'import_models.dart';
import 'import_source_adapters.dart';

typedef ImportBrandSuggestionResolver =
    ImportBrandSuggestionResult? Function(String platformName, String url);

final class ImportFieldMapper {
  const ImportFieldMapper({this.brandSuggestionResolver});

  final ImportBrandSuggestionResolver? brandSuggestionResolver;

  AccountMappingResult mapAccounts(
    TabularDocument document, {
    required ImportSourceAdapter adapter,
    String documentSlotId = 'account-document',
    Map<int, ImportTargetField> overrides = const <int, ImportTargetField>{},
  }) {
    if (documentSlotId.isEmpty) {
      throw ArgumentError.value(documentSlotId, 'documentSlotId');
    }
    if (!adapter.enabled || !adapter.verified) {
      throw StateError('Disabled or unverified adapters cannot map records.');
    }
    if (adapter.itemKind != ImportItemKind.account && !adapter.isGeneric) {
      throw StateError('The selected adapter does not contain account rows.');
    }

    if (isBrowserPasswordSourceId(adapter.id)) {
      if (adapter.confidenceFor(document) != 1) {
        throw const FormatException('所选浏览器来源与文件结构不匹配，请选择通用映射。');
      }
      for (final entry in overrides.entries) {
        final expected =
            adapter.defaultMappings[normalizeImportHeader(
              document.headers[entry.key],
            )];
        if (entry.value != ImportTargetField.ignore &&
            entry.value != expected) {
          throw const FormatException('浏览器专用字段不可改映射到其他字段，请选择通用映射。');
        }
      }
    }
    final mapping = _resolveMapping(document, adapter, overrides);
    final globalIssues = <ImportIssue>[...mapping.issues];
    final drafts = <AccountImportDraft>[];
    final suggestions = <ImportFieldSuggestion>[];
    var unsupportedRows = 0;
    final accountKeys = <String>{};
    final typeIndex = _findHeaderIndex(document, adapter.typeHeader);

    for (final row in document.rows) {
      if (!row.isValid) {
        globalIssues.addAll(row.issues);
        continue;
      }
      if (typeIndex != null && adapter.acceptedTypeValue != null) {
        final actualType = row.valueAt(typeIndex).trim().toLowerCase();
        if (actualType != adapter.acceptedTypeValue) {
          unsupportedRows += 1;
          globalIssues.add(
            ImportIssue(
              severity: ImportIssueSeverity.info,
              code: 'unsupported_item_type',
              message: 'A non-login item was skipped.',
              rowNumber: row.originalRowNumber,
              columnNumber: typeIndex + 1,
            ),
          );
          continue;
        }
      }

      String valueFor(ImportTargetField target) {
        final index = mapping.byTarget[target];
        return index == null ? '' : row.valueAt(index);
      }

      final rowIssues = <ImportIssue>[];
      var notes = valueFor(ImportTargetField.notes);
      if (_containsBlockedSensitiveContent(notes)) {
        notes = '';
        rowIssues.add(
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: 'sensitive_content_excluded',
            message: 'Unsupported sensitive content was excluded from notes.',
            rowNumber: row.originalRowNumber,
          ),
        );
      }

      final password = valueFor(ImportTargetField.password);
      final passwordLooksMasked = isBrowserPasswordSourceId(adapter.id)
          ? browserPasswordLooksMasked(password)
          : _looksLikeMaskedPassword(password);
      if (passwordLooksMasked) {
        rowIssues.add(
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: 'masked_password_placeholder',
            message:
                'The password looks like a masked placeholder and requires review.',
            rowNumber: row.originalRowNumber,
            columnNumber: mapping.byTarget[ImportTargetField.password] == null
                ? null
                : mapping.byTarget[ImportTargetField.password]! + 1,
          ),
        );
      }

      String? accountKey;
      var accountKeyWasGenerated = false;
      final accountKeyIndex = mapping.byTarget[ImportTargetField.accountKey];
      if (accountKeyIndex != null) {
        accountKey = row.valueAt(accountKeyIndex);
        if (accountKey.isEmpty) {
          accountKey =
              '$documentSlotId|generated-account:${row.originalRowNumber}';
          accountKeyWasGenerated = true;
        }
        if (!accountKeys.add(accountKey)) {
          rowIssues.add(
            ImportIssue(
              severity: ImportIssueSeverity.error,
              code: 'duplicate_account_key',
              message:
                  'The account key must be unique within the account file.',
              rowNumber: row.originalRowNumber,
              columnNumber: accountKeyIndex + 1,
            ),
          );
        }
      }

      var platformName = valueFor(ImportTargetField.platformName);
      final url = valueFor(ImportTargetField.url);
      if (isBrowserPasswordSourceId(adapter.id)) {
        final uri = Uri.tryParse(url.trim());
        final safeUrl =
            uri != null &&
            {'http', 'https'}.contains(uri.scheme.toLowerCase()) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty;
        if (url.trim().isNotEmpty && !safeUrl) {
          rowIssues.add(
            ImportIssue(
              severity: ImportIssueSeverity.error,
              code: 'unsafe_browser_url',
              message: 'Only http(s) website URLs are supported.',
              rowNumber: row.originalRowNumber,
            ),
          );
        }
        if (platformName.trim().isEmpty && safeUrl) platformName = uri.host;
      }
      final brandResult = brandSuggestionResolver?.call(platformName, url);
      final draft = AccountImportDraft(
        originalRowNumber: row.originalRowNumber,
        sourceId: '$documentSlotId|${adapter.id}|row:${row.originalRowNumber}',
        adapterId: adapter.id,
        accountKey: accountKey,
        accountKeyWasGenerated: accountKeyWasGenerated,
        platformName: platformName,
        loginAccount: valueFor(ImportTargetField.loginAccount),
        phone: valueFor(ImportTargetField.phone),
        email: valueFor(ImportTargetField.email),
        password: password,
        passwordLooksMasked: passwordLooksMasked,
        url: url,
        notes: notes,
        brandSuggestion:
            brandResult?.kind == ImportBrandSuggestionKind.exactUnique
            ? brandResult?.exactBrandId
            : null,
        brandSuggestionCandidates:
            brandResult?.candidateBrandIds ?? const <String>[],
        issues: rowIssues,
      );
      if (draft.isEmpty) {
        rowIssues.add(
          ImportIssue(
            severity: ImportIssueSeverity.error,
            code: 'empty_account_row',
            message: 'The row does not contain any supported account fields.',
            rowNumber: row.originalRowNumber,
          ),
        );
        globalIssues.addAll(rowIssues);
        continue;
      }
      if (draft.email.isEmpty && _looksLikeEmail(draft.loginAccount)) {
        suggestions.add(
          ImportFieldSuggestion(
            id: 'row:${row.originalRowNumber}:email',
            rowNumber: row.originalRowNumber,
            targetField: ImportTargetField.email,
            value: draft.loginAccount,
          ),
        );
      }
      if (draft.phone.isEmpty && _looksLikePhone(draft.loginAccount)) {
        suggestions.add(
          ImportFieldSuggestion(
            id: 'row:${row.originalRowNumber}:phone',
            rowNumber: row.originalRowNumber,
            targetField: ImportTargetField.phone,
            value: draft.loginAccount,
          ),
        );
      }
      drafts.add(
        rowIssues.isEmpty
            ? draft
            : AccountImportDraft(
                originalRowNumber: draft.originalRowNumber,
                sourceId: draft.sourceId,
                adapterId: draft.adapterId,
                accountKey: draft.accountKey,
                accountKeyWasGenerated: draft.accountKeyWasGenerated,
                platformName: draft.platformName,
                loginAccount: draft.loginAccount,
                phone: draft.phone,
                email: draft.email,
                password: draft.password,
                passwordLooksMasked: draft.passwordLooksMasked,
                maskedPasswordConfirmed: draft.maskedPasswordConfirmed,
                url: draft.url,
                notes: draft.notes,
                brandSuggestion: draft.brandSuggestion,
                brandSuggestionCandidates: draft.brandSuggestionCandidates,
                brandSuggestionIgnored: draft.brandSuggestionIgnored,
                issues: rowIssues,
              ),
      );
      globalIssues.addAll(rowIssues);
    }

    return AccountMappingResult(
      drafts: drafts,
      unmappedColumns: mapping.unmappedColumns,
      excludedSensitiveColumns: mapping.excludedSensitiveColumns,
      unsupportedRowCount: unsupportedRows,
      suggestions: suggestions,
      issues: globalIssues,
    );
  }

  SubscriptionMappingResult mapSubscriptions(
    TabularDocument document, {
    required ImportSourceAdapter adapter,
    String documentSlotId = 'subscription-document',
    Map<int, ImportTargetField> overrides = const <int, ImportTargetField>{},
  }) {
    if (documentSlotId.isEmpty) {
      throw ArgumentError.value(documentSlotId, 'documentSlotId');
    }
    if (!adapter.enabled || !adapter.verified) {
      throw StateError('Disabled or unverified adapters cannot map records.');
    }
    if (adapter.itemKind != ImportItemKind.subscription && !adapter.isGeneric) {
      throw StateError(
        'The selected adapter does not contain subscription rows.',
      );
    }
    final mapping = _resolveMapping(document, adapter, overrides);
    final globalIssues = <ImportIssue>[...mapping.issues];
    final drafts = <SubscriptionImportDraft>[];
    for (final row in document.rows) {
      if (!row.isValid) {
        globalIssues.addAll(row.issues);
        continue;
      }

      String valueFor(ImportTargetField target) {
        final index = mapping.byTarget[target];
        return index == null ? '' : row.valueAt(index);
      }

      var accountKey = valueFor(ImportTargetField.accountKey);
      final generated = accountKey.isEmpty;
      if (generated) {
        accountKey =
            '$documentSlotId|generated-subscription:${row.originalRowNumber}';
      }
      final rawValues = <String, String>{
        'plan_name': valueFor(ImportTargetField.planName),
        'amount': valueFor(ImportTargetField.amount),
        'currency': valueFor(ImportTargetField.currency),
        'billing_cycle': valueFor(ImportTargetField.billingCycle),
        'subscription_start_date': valueFor(
          ImportTargetField.subscriptionStartDate,
        ),
        'next_renewal_date': valueFor(ImportTargetField.nextRenewalDate),
        'auto_renew': valueFor(ImportTargetField.autoRenew),
        'payment_method': valueFor(ImportTargetField.paymentMethod),
        'reminder_days': valueFor(ImportTargetField.reminderDays),
      };
      final invalid = <String>[];
      for (final entry in rawValues.entries) {
        if (entry.value.isEmpty ||
            !_isValidSubscriptionValue(entry.key, entry.value)) {
          invalid.add(entry.key);
        }
      }
      final rowIssues = <ImportIssue>[
        for (final field in invalid)
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: 'subscription_field_missing_or_invalid',
            message: 'A subscription field is missing or invalid.',
            rowNumber: row.originalRowNumber,
            columnNumber: _columnForSubscriptionField(mapping, field),
          ),
      ];
      var notes = valueFor(ImportTargetField.notes);
      if (_containsBlockedSensitiveContent(notes)) {
        notes = '';
        rowIssues.add(
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: 'sensitive_content_excluded',
            message: 'Unsupported sensitive content was excluded from notes.',
            rowNumber: row.originalRowNumber,
          ),
        );
      }
      drafts.add(
        SubscriptionImportDraft(
          originalRowNumber: row.originalRowNumber,
          sourceId:
              '$documentSlotId|${adapter.id}|row:${row.originalRowNumber}',
          adapterId: adapter.id,
          accountKey: accountKey,
          accountKeyWasGenerated: generated,
          planName: rawValues['plan_name']!,
          amount: rawValues['amount']!,
          currency: rawValues['currency']!,
          billingCycle: rawValues['billing_cycle']!,
          subscriptionStartDate: rawValues['subscription_start_date']!,
          nextRenewalDate: rawValues['next_renewal_date']!,
          autoRenew: rawValues['auto_renew']!,
          paymentMethod: rawValues['payment_method']!,
          reminderDays: rawValues['reminder_days']!,
          notes: notes,
          missingOrInvalidFields: invalid,
          issues: rowIssues,
        ),
      );
      globalIssues.addAll(rowIssues);
    }

    return SubscriptionMappingResult(
      drafts: drafts,
      unmappedColumns: mapping.unmappedColumns,
      excludedSensitiveColumns: mapping.excludedSensitiveColumns,
      issues: globalIssues,
    );
  }

  _ResolvedMapping _resolveMapping(
    TabularDocument document,
    ImportSourceAdapter adapter,
    Map<int, ImportTargetField> overrides,
  ) {
    final byTarget = <ImportTargetField, int>{};
    final unmapped = <ImportColumnReference>[];
    final sensitive = <ImportColumnReference>[];
    final issues = <ImportIssue>[];
    for (var index = 0; index < document.headers.length; index += 1) {
      final header = document.headers[index];
      final normalized = normalizeImportHeader(header);
      if (adapter.sensitiveHeaders.contains(normalized) ||
          _isAlwaysSensitiveHeader(normalized)) {
        sensitive.add(ImportColumnReference(index: index, header: header));
        if (overrides[index] != null &&
            overrides[index] != ImportTargetField.ignore) {
          issues.add(
            ImportIssue(
              severity: ImportIssueSeverity.error,
              code: 'sensitive_column_mapping_blocked',
              message: 'An unsupported sensitive column cannot be mapped.',
              rowNumber: 1,
              columnNumber: index + 1,
            ),
          );
        }
        continue;
      }
      final target =
          overrides[index] ??
          adapter.defaultMappings[normalized] ??
          ImportTargetField.ignore;
      if (target == ImportTargetField.ignore) {
        unmapped.add(ImportColumnReference(index: index, header: header));
        continue;
      }
      if (byTarget.containsKey(target)) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.error,
            code: 'duplicate_target_mapping',
            message: 'Multiple source columns map to the same target field.',
            rowNumber: 1,
            columnNumber: index + 1,
          ),
        );
        unmapped.add(ImportColumnReference(index: index, header: header));
        continue;
      }
      byTarget[target] = index;
    }
    return _ResolvedMapping(
      byTarget: byTarget,
      unmappedColumns: unmapped,
      excludedSensitiveColumns: sensitive,
      issues: issues,
    );
  }

  int? _findHeaderIndex(TabularDocument document, String? header) {
    if (header == null) return null;
    final normalized = normalizeImportHeader(header);
    for (var index = 0; index < document.headers.length; index += 1) {
      if (normalizeImportHeader(document.headers[index]) == normalized) {
        return index;
      }
    }
    return null;
  }

  int? _columnForSubscriptionField(_ResolvedMapping mapping, String field) {
    final target = switch (field) {
      'plan_name' => ImportTargetField.planName,
      'amount' => ImportTargetField.amount,
      'currency' => ImportTargetField.currency,
      'billing_cycle' => ImportTargetField.billingCycle,
      'subscription_start_date' => ImportTargetField.subscriptionStartDate,
      'next_renewal_date' => ImportTargetField.nextRenewalDate,
      'auto_renew' => ImportTargetField.autoRenew,
      'payment_method' => ImportTargetField.paymentMethod,
      'reminder_days' => ImportTargetField.reminderDays,
      _ => ImportTargetField.ignore,
    };
    final index = mapping.byTarget[target];
    return index == null ? null : index + 1;
  }
}

bool _isAlwaysSensitiveHeader(String normalized) {
  const values = <String>{
    'fields',
    'totp',
    'logintotp',
    'otpauth',
    'passkey',
    'webauthn',
    'recoverycode',
    'recoverycodes',
    'privatekey',
    'sshprivatekey',
    'apiprivatekey',
    'creditcard',
    'cardnumber',
    'secretanswer',
    'onetimepassword',
    '动态验证码',
    '恢复码',
    '私钥',
    '秘密问题答案',
  };
  return values.contains(normalized);
}

bool _containsBlockedSensitiveContent(String value) {
  final normalized = value.trimLeft().toLowerCase();
  return normalized.startsWith('otpauth://') ||
      (normalized.contains('-----begin ') &&
          normalized.contains(' private key-----')) ||
      normalized.startsWith('webauthn:') ||
      normalized.startsWith('passkey:');
}

bool _looksLikeMaskedPassword(String value) {
  if (value.length < 4) return false;
  final runes = value.runes.toList(growable: false);
  const masked = <int>{0x002A, 0x2022, 0x25CF, 0x0058, 0x0078};
  return runes.every(masked.contains);
}

bool _looksLikeEmail(String value) {
  final candidate = value.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(candidate);
}

bool _looksLikePhone(String value) {
  final candidate = value.trim();
  if (candidate.isEmpty || candidate.contains('@')) return false;
  final compact = candidate.replaceAll(RegExp(r'[\s\-().]'), '');
  return RegExp(r'^\+?\d{7,15}$').hasMatch(compact);
}

bool _isValidSubscriptionValue(String field, String rawValue) {
  final value = rawValue.trim();
  return switch (field) {
    'plan_name' => value.isNotEmpty,
    'amount' => RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value),
    'currency' => RegExp(r'^[A-Za-z]{3}$').hasMatch(value),
    'billing_cycle' => switch (_normalizeBillingCycle(value)) {
      null || 'custom' => false,
      _ => true,
    },
    'subscription_start_date' => _isStrictDate(value),
    'next_renewal_date' => _isStrictDate(value),
    'auto_renew' => _parseAutoRenew(value) != null,
    'payment_method' => value.isNotEmpty,
    'reminder_days' => int.tryParse(value) != null && int.parse(value) >= 0,
    _ => false,
  };
}

String? normalizeSubscriptionBillingCycle(String value) =>
    _normalizeBillingCycle(value.trim());

String? _normalizeBillingCycle(String value) {
  final normalized = value.toLowerCase();
  const aliases = <String, String>{
    'monthly': 'monthly',
    '每月': 'monthly',
    '毎月': 'monthly',
    'quarterly': 'quarterly',
    '每季度': 'quarterly',
    '四半期': 'quarterly',
    'semiannual': 'semiannual',
    '每半年': 'semiannual',
    '半年ごと': 'semiannual',
    'annual': 'annual',
    '每年': 'annual',
    '毎年': 'annual',
    'custom': 'custom',
    '自定义': 'custom',
    'カスタム': 'custom',
  };
  return aliases[normalized];
}

bool? parseSubscriptionAutoRenew(String value) => _parseAutoRenew(value.trim());

bool? _parseAutoRenew(String value) {
  return switch (value.toLowerCase()) {
    'true' || 'yes' || '1' || '是' || 'はい' => true,
    'false' || 'no' || '0' || '否' || 'いいえ' => false,
    _ => null,
  };
}

DateTime? parseSubscriptionDate(String value) {
  final normalized = value.trim();
  if (!_isStrictDate(normalized)) return null;
  return DateTime.parse(normalized);
}

bool _isStrictDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}

final class _ResolvedMapping {
  const _ResolvedMapping({
    required this.byTarget,
    required this.unmappedColumns,
    required this.excludedSensitiveColumns,
    required this.issues,
  });

  final Map<ImportTargetField, int> byTarget;
  final List<ImportColumnReference> unmappedColumns;
  final List<ImportColumnReference> excludedSensitiveColumns;
  final List<ImportIssue> issues;
}
