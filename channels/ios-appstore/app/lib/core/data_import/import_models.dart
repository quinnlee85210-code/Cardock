import 'browser_password_csv.dart';
import '../../features/accounts/domain/account_custom_field.dart';
import 'dart:collection';

enum ImportIssueSeverity { info, warning, error }

enum ImportValidationState { valid, warning, invalid }

enum ImportItemKind { account, subscription }

enum ImportTargetField {
  ignore,
  platformName,
  loginAccount,
  phone,
  email,
  password,
  url,
  notes,
  accountKey,
  planName,
  amount,
  currency,
  billingCycle,
  subscriptionStartDate,
  nextRenewalDate,
  autoRenew,
  paymentMethod,
  reminderDays,
}

enum TabularSourceEncoding { utf8, utf8Bom, utf16LeBom, utf16BeBom, xlsx, docx }

enum ImportDuplicateConfidence { related, medium, high }

enum ImportDuplicateOrigin { existingVault, currentImport }

enum ImportPasswordComparison {
  bothEmpty,
  same,
  different,
  existingEmpty,
  importedEmpty,
}

enum ImportDuplicateResolution {
  skip,
  importAsNew,
  fillEmptyFieldsOnly,
  fieldByField,
}

enum ImportSessionPhase {
  idle,
  documentLoaded,
  sourceSelected,
  mapped,
  duplicatesReviewed,
  planned,
  cleared,
}

enum ImportBrandSuggestionKind { none, exactUnique, multipleCandidates }

final class ImportBrandSuggestionResult {
  ImportBrandSuggestionResult._({
    required this.kind,
    required this.exactBrandId,
    required List<String> candidateBrandIds,
  }) : candidateBrandIds = List<String>.unmodifiable(candidateBrandIds);

  factory ImportBrandSuggestionResult.none() => ImportBrandSuggestionResult._(
    kind: ImportBrandSuggestionKind.none,
    exactBrandId: null,
    candidateBrandIds: const <String>[],
  );

  factory ImportBrandSuggestionResult.exactUnique(String brandId) {
    if (brandId.isEmpty) throw ArgumentError.value(brandId, 'brandId');
    return ImportBrandSuggestionResult._(
      kind: ImportBrandSuggestionKind.exactUnique,
      exactBrandId: brandId,
      candidateBrandIds: <String>[brandId],
    );
  }

  factory ImportBrandSuggestionResult.multipleCandidates(
    Iterable<String> brandIds,
  ) {
    final unique = brandIds.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.length < 2) {
      throw ArgumentError('Multiple brand suggestions require two candidates.');
    }
    return ImportBrandSuggestionResult._(
      kind: ImportBrandSuggestionKind.multipleCandidates,
      exactBrandId: null,
      candidateBrandIds: unique,
    );
  }

  final ImportBrandSuggestionKind kind;
  final String? exactBrandId;
  final List<String> candidateBrandIds;
}

final class ImportIssue {
  const ImportIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.rowNumber,
    this.columnNumber,
  });

  final ImportIssueSeverity severity;
  final String code;
  final String message;
  final int? rowNumber;
  final int? columnNumber;

  bool get isError => severity == ImportIssueSeverity.error;

  Map<String, Object?> toJson() => <String, Object?>{
    'severity': severity.name,
    'code': code,
    'message': message,
    'rowNumber': rowNumber,
    'columnNumber': columnNumber,
  };
}

final class TabularRow {
  TabularRow({
    required List<String> values,
    required this.originalRowNumber,
    List<ImportIssue> issues = const <ImportIssue>[],
  }) : values = List<String>.unmodifiable(values),
       issues = List<ImportIssue>.unmodifiable(issues);

  final List<String> values;
  final int originalRowNumber;
  final List<ImportIssue> issues;

  bool get isValid => !issues.any((issue) => issue.isError);

  String valueAt(int index) =>
      index >= 0 && index < values.length ? values[index] : '';
}

final class TabularDocument {
  TabularDocument({
    required List<String> headers,
    required List<TabularRow> rows,
    required this.encoding,
    required this.delimiter,
    required this.hasHeader,
    required this.originalByteLength,
    List<ImportIssue> issues = const <ImportIssue>[],
  }) : headers = List<String>.unmodifiable(headers),
       rows = List<TabularRow>.unmodifiable(rows),
       issues = List<ImportIssue>.unmodifiable(issues);

  final List<String> headers;
  final List<TabularRow> rows;
  final TabularSourceEncoding encoding;
  final String delimiter;
  final bool hasHeader;
  final int originalByteLength;
  final List<ImportIssue> issues;

  int get columnCount => headers.length;
  bool get hasErrors => issues.any((issue) => issue.isError);
}

final class ImportColumnReference {
  const ImportColumnReference({required this.index, required this.header});

  final int index;
  final String header;

  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'header': header,
  };
}

final class ImportFieldSuggestion {
  const ImportFieldSuggestion({
    required this.id,
    required this.rowNumber,
    required this.targetField,
    required this.value,
    this.accepted = false,
  });

  final String id;
  final int rowNumber;
  final ImportTargetField targetField;
  final String value;
  final bool accepted;

  ImportFieldSuggestion withAccepted(bool value) => ImportFieldSuggestion(
    id: id,
    rowNumber: rowNumber,
    targetField: targetField,
    value: this.value,
    accepted: value,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'rowNumber': rowNumber,
    'targetField': targetField.name,
    'value': value,
    'accepted': accepted,
  };
}

final class AccountImportDraft {
  AccountImportDraft({
    required this.originalRowNumber,
    required this.sourceId,
    this.adapterId = '',
    this.accountKey,
    this.accountKeyWasGenerated = false,
    this.platformName = '',
    this.loginAccount = '',
    this.phone = '',
    this.email = '',
    this.password = '',
    this.passwordLooksMasked = false,
    this.maskedPasswordConfirmed = false,
    this.url = '',
    this.notes = '',
    List<AccountCustomField> customFields = const <AccountCustomField>[],
    Set<String> replaceCustomFieldNames = const <String>{},
    Set<String> confirmedSensitiveCustomFieldIds = const <String>{},
    this.brandSuggestion,
    List<String> brandSuggestionCandidates = const <String>[],
    this.brandSuggestionIgnored = false,
    List<ImportIssue> issues = const <ImportIssue>[],
  }) : customFields = List.unmodifiable(customFields),
       replaceCustomFieldNames = Set.unmodifiable(replaceCustomFieldNames),
       confirmedSensitiveCustomFieldIds = Set.unmodifiable(
         confirmedSensitiveCustomFieldIds,
       ),
       brandSuggestionCandidates = List<String>.unmodifiable(
         brandSuggestionCandidates,
       ),
       issues = List<ImportIssue>.unmodifiable(issues);

  final int originalRowNumber;
  final String sourceId;
  final String adapterId;
  final String? accountKey;
  final bool accountKeyWasGenerated;
  final String platformName;
  final String loginAccount;
  final String phone;
  final String email;
  final String password;
  final bool passwordLooksMasked;
  final bool maskedPasswordConfirmed;
  final String url;
  final String notes;
  final List<AccountCustomField> customFields;
  final Set<String> replaceCustomFieldNames;
  final Set<String> confirmedSensitiveCustomFieldIds;
  final String? brandSuggestion;
  final List<String> brandSuggestionCandidates;
  final bool brandSuggestionIgnored;
  final List<ImportIssue> issues;

  bool get hasPassword => password.isNotEmpty;
  bool get hasImportablePassword =>
      hasPassword &&
      (!passwordLooksMasked ||
          (maskedPasswordConfirmed && !isBrowserPasswordSourceId(adapterId)));
  bool get isEmpty =>
      platformName.isEmpty &&
      loginAccount.isEmpty &&
      phone.isEmpty &&
      email.isEmpty &&
      password.isEmpty &&
      url.isEmpty &&
      notes.isEmpty;

  ImportValidationState get validationState {
    if (issues.any((issue) => issue.isError) || isEmpty) {
      return ImportValidationState.invalid;
    }
    if (issues.isNotEmpty) return ImportValidationState.warning;
    return ImportValidationState.valid;
  }

  AccountImportDraft copyWith({
    String? phone,
    String? email,
    String? password,
    bool? passwordLooksMasked,
    bool? maskedPasswordConfirmed,
    List<AccountCustomField>? customFields,
    Set<String>? replaceCustomFieldNames,
    Set<String>? confirmedSensitiveCustomFieldIds,
  }) => AccountImportDraft(
    originalRowNumber: originalRowNumber,
    sourceId: sourceId,
    adapterId: adapterId,
    accountKey: accountKey,
    accountKeyWasGenerated: accountKeyWasGenerated,
    platformName: platformName,
    loginAccount: loginAccount,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    password: password ?? this.password,
    passwordLooksMasked: passwordLooksMasked ?? this.passwordLooksMasked,
    maskedPasswordConfirmed:
        maskedPasswordConfirmed ?? this.maskedPasswordConfirmed,
    url: url,
    notes: notes,
    customFields: customFields ?? this.customFields,
    replaceCustomFieldNames:
        replaceCustomFieldNames ?? this.replaceCustomFieldNames,
    confirmedSensitiveCustomFieldIds:
        confirmedSensitiveCustomFieldIds ??
        this.confirmedSensitiveCustomFieldIds,
    brandSuggestion: brandSuggestion,
    brandSuggestionCandidates: brandSuggestionCandidates,
    brandSuggestionIgnored: brandSuggestionIgnored,
    issues: issues,
  );

  AccountImportDraft withBrandSuggestion(
    String? value, {
    required bool ignored,
  }) => AccountImportDraft(
    originalRowNumber: originalRowNumber,
    sourceId: sourceId,
    adapterId: adapterId,
    accountKey: accountKey,
    accountKeyWasGenerated: accountKeyWasGenerated,
    platformName: platformName,
    loginAccount: loginAccount,
    phone: phone,
    email: email,
    password: password,
    passwordLooksMasked: passwordLooksMasked,
    maskedPasswordConfirmed: maskedPasswordConfirmed,
    url: url,
    notes: notes,
    customFields: customFields,
    replaceCustomFieldNames: replaceCustomFieldNames,
    confirmedSensitiveCustomFieldIds: confirmedSensitiveCustomFieldIds,
    brandSuggestion: value,
    brandSuggestionCandidates: brandSuggestionCandidates,
    brandSuggestionIgnored: ignored,
    issues: issues,
  );

  Map<String, Object?> toSafePreviewJson() => <String, Object?>{
    'originalRowNumber': originalRowNumber,
    'sourceId': sourceId,
    'adapterId': adapterId,
    'accountKey': accountKey,
    'accountKeyWasGenerated': accountKeyWasGenerated,
    'platformName': platformName,
    'loginAccount': loginAccount,
    'phone': phone,
    'email': email,
    'passwordState': passwordLooksMasked && !maskedPasswordConfirmed
        ? 'maskedReviewRequired'
        : hasPassword
        ? 'provided'
        : 'missing',
    'url': url,
    'notes': notes,
    'brandSuggestion': brandSuggestion,
    'brandSuggestionCandidates': brandSuggestionCandidates,
    'brandSuggestionIgnored': brandSuggestionIgnored,
    'validationState': validationState.name,
    'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
  };
}

final class SubscriptionImportDraft {
  SubscriptionImportDraft({
    required this.originalRowNumber,
    required this.sourceId,
    this.adapterId = '',
    required this.accountKey,
    required this.accountKeyWasGenerated,
    this.accountTargetConfirmed = false,
    this.targetExistingAccountId,
    this.planName = '',
    this.amount = '',
    this.currency = '',
    this.billingCycle = '',
    this.subscriptionStartDate = '',
    this.nextRenewalDate = '',
    this.autoRenew = '',
    this.paymentMethod = '',
    this.reminderDays = '',
    this.notes = '',
    List<String> missingOrInvalidFields = const <String>[],
    List<ImportIssue> issues = const <ImportIssue>[],
  }) : missingOrInvalidFields = List<String>.unmodifiable(
         missingOrInvalidFields,
       ),
       issues = List<ImportIssue>.unmodifiable(issues);

  final int originalRowNumber;
  final String sourceId;
  final String adapterId;
  final String accountKey;
  final bool accountKeyWasGenerated;
  final bool accountTargetConfirmed;
  final String? targetExistingAccountId;
  final String planName;
  final String amount;
  final String currency;
  final String billingCycle;
  final String subscriptionStartDate;
  final String nextRenewalDate;
  final String autoRenew;
  final String paymentMethod;
  final String reminderDays;
  final String notes;
  final List<String> missingOrInvalidFields;
  final List<ImportIssue> issues;

  bool get isSyntacticallyComplete =>
      accountKey.isNotEmpty &&
      (!accountKeyWasGenerated || accountTargetConfirmed) &&
      missingOrInvalidFields.isEmpty;

  SubscriptionImportDraft withAccountTarget({
    required String accountKey,
    String? existingAccountId,
  }) => SubscriptionImportDraft(
    originalRowNumber: originalRowNumber,
    sourceId: sourceId,
    adapterId: adapterId,
    accountKey: accountKey,
    accountKeyWasGenerated: false,
    accountTargetConfirmed: true,
    targetExistingAccountId: existingAccountId,
    planName: planName,
    amount: amount,
    currency: currency,
    billingCycle: billingCycle,
    subscriptionStartDate: subscriptionStartDate,
    nextRenewalDate: nextRenewalDate,
    autoRenew: autoRenew,
    paymentMethod: paymentMethod,
    reminderDays: reminderDays,
    notes: notes,
    missingOrInvalidFields: missingOrInvalidFields,
    issues: issues,
  );

  Map<String, Object?> toSafePreviewJson() => <String, Object?>{
    'originalRowNumber': originalRowNumber,
    'sourceId': sourceId,
    'adapterId': adapterId,
    'accountKey': accountKey,
    'accountKeyWasGenerated': accountKeyWasGenerated,
    'accountTargetConfirmed': accountTargetConfirmed,
    'targetExistingAccountId': targetExistingAccountId,
    'planName': planName,
    'amount': amount,
    'currency': currency,
    'billingCycle': billingCycle,
    'subscriptionStartDate': subscriptionStartDate,
    'nextRenewalDate': nextRenewalDate,
    'autoRenew': autoRenew,
    'paymentMethod': paymentMethod,
    'reminderDays': reminderDays,
    'notes': notes,
    'missingOrInvalidFields': missingOrInvalidFields,
    'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
  };
}

final class ImportSubscriptionAccountTarget {
  const ImportSubscriptionAccountTarget({
    required this.rowNumber,
    required this.accountKey,
    this.existingAccountId,
  });

  final int rowNumber;
  final String accountKey;
  final String? existingAccountId;

  Map<String, Object?> toJson() => <String, Object?>{
    'rowNumber': rowNumber,
    'accountKey': accountKey,
    'existingAccountId': existingAccountId,
  };
}

final class ExistingAccountSummary {
  const ExistingAccountSummary({
    required this.id,
    required this.platformName,
    this.loginAccount = '',
    this.phone = '',
    this.email = '',
    this.url = '',
    this.password = '',
    this.notes = '',
  });

  final String id;
  final String platformName;
  final String loginAccount;
  final String phone;
  final String email;
  final String url;
  final String password;
  final String notes;

  bool get hasPassword => password.isNotEmpty;
}

final class ImportDuplicateCandidate {
  ImportDuplicateCandidate({
    required this.id,
    required this.importRowNumber,
    required this.origin,
    required this.confidence,
    required Set<String> matchingFields,
    required Set<String> conflictingFields,
    this.existingAccountId,
    this.duplicateImportRowNumber,
    this.passwordComparison = ImportPasswordComparison.bothEmpty,
    this.hasExistingPassword = false,
    Map<String, bool> useImportedField = const <String, bool>{},
    this.resolution,
  }) : matchingFields = Set<String>.unmodifiable(matchingFields),
       conflictingFields = Set<String>.unmodifiable(conflictingFields),
       useImportedField = UnmodifiableMapView<String, bool>(
         Map<String, bool>.of(useImportedField),
       );

  final String id;
  final int importRowNumber;
  final ImportDuplicateOrigin origin;
  final ImportDuplicateConfidence confidence;
  final Set<String> matchingFields;
  final Set<String> conflictingFields;
  final String? existingAccountId;
  final int? duplicateImportRowNumber;
  final ImportPasswordComparison passwordComparison;
  final bool hasExistingPassword;
  final Map<String, bool> useImportedField;
  final ImportDuplicateResolution? resolution;

  bool get isResolved =>
      resolution != null &&
      (resolution != ImportDuplicateResolution.fieldByField ||
          conflictingFields.every(useImportedField.containsKey));

  ImportDuplicateCandidate withResolution(ImportDuplicateResolution value) =>
      ImportDuplicateCandidate(
        id: id,
        importRowNumber: importRowNumber,
        origin: origin,
        confidence: confidence,
        matchingFields: matchingFields,
        conflictingFields: conflictingFields,
        existingAccountId: existingAccountId,
        duplicateImportRowNumber: duplicateImportRowNumber,
        passwordComparison: passwordComparison,
        hasExistingPassword: hasExistingPassword,
        useImportedField: value == ImportDuplicateResolution.fieldByField
            ? useImportedField
            : const <String, bool>{},
        resolution: value,
      );

  ImportDuplicateCandidate withFieldChoice(
    String fieldName, {
    required bool useImportedValue,
  }) {
    if (resolution != ImportDuplicateResolution.fieldByField) {
      throw StateError('Field choices require fieldByField resolution.');
    }
    if (!conflictingFields.contains(fieldName)) {
      throw ArgumentError.value(
        fieldName,
        'fieldName',
        'The field is not a reported conflict.',
      );
    }
    return ImportDuplicateCandidate(
      id: id,
      importRowNumber: importRowNumber,
      origin: origin,
      confidence: confidence,
      matchingFields: matchingFields,
      conflictingFields: conflictingFields,
      existingAccountId: existingAccountId,
      duplicateImportRowNumber: duplicateImportRowNumber,
      passwordComparison: passwordComparison,
      hasExistingPassword: hasExistingPassword,
      useImportedField: <String, bool>{
        ...useImportedField,
        fieldName: useImportedValue,
      },
      resolution: resolution,
    );
  }

  Map<String, Object?> toSafePreviewJson() => <String, Object?>{
    'id': id,
    'importRowNumber': importRowNumber,
    'origin': origin.name,
    'confidence': confidence.name,
    'matchingFields': matchingFields.toList(growable: false),
    'conflictingFields': conflictingFields.toList(growable: false),
    'existingAccountId': existingAccountId,
    'duplicateImportRowNumber': duplicateImportRowNumber,
    'passwordComparison': passwordComparison.name,
    'hasExistingPassword': hasExistingPassword,
    'useImportedField': useImportedField,
    'resolution': resolution?.name,
  };
}

final class AccountMappingResult {
  AccountMappingResult({
    required List<AccountImportDraft> drafts,
    required List<ImportColumnReference> unmappedColumns,
    required List<ImportColumnReference> excludedSensitiveColumns,
    required this.unsupportedRowCount,
    List<ImportFieldSuggestion> suggestions = const <ImportFieldSuggestion>[],
    List<ImportIssue> issues = const <ImportIssue>[],
  }) : drafts = List<AccountImportDraft>.unmodifiable(drafts),
       unmappedColumns = List<ImportColumnReference>.unmodifiable(
         unmappedColumns,
       ),
       excludedSensitiveColumns = List<ImportColumnReference>.unmodifiable(
         excludedSensitiveColumns,
       ),
       suggestions = List<ImportFieldSuggestion>.unmodifiable(suggestions),
       issues = List<ImportIssue>.unmodifiable(issues);

  final List<AccountImportDraft> drafts;
  final List<ImportColumnReference> unmappedColumns;
  final List<ImportColumnReference> excludedSensitiveColumns;
  final int unsupportedRowCount;
  final List<ImportFieldSuggestion> suggestions;
  final List<ImportIssue> issues;
}

final class SubscriptionMappingResult {
  SubscriptionMappingResult({
    required List<SubscriptionImportDraft> drafts,
    required List<ImportColumnReference> unmappedColumns,
    required List<ImportColumnReference> excludedSensitiveColumns,
    List<ImportIssue> issues = const <ImportIssue>[],
  }) : drafts = List<SubscriptionImportDraft>.unmodifiable(drafts),
       unmappedColumns = List<ImportColumnReference>.unmodifiable(
         unmappedColumns,
       ),
       excludedSensitiveColumns = List<ImportColumnReference>.unmodifiable(
         excludedSensitiveColumns,
       ),
       issues = List<ImportIssue>.unmodifiable(issues);

  final List<SubscriptionImportDraft> drafts;
  final List<ImportColumnReference> unmappedColumns;
  final List<ImportColumnReference> excludedSensitiveColumns;
  final List<ImportIssue> issues;
}

final class AccountUpdatePlan {
  AccountUpdatePlan({
    required this.draft,
    required this.resolution,
    this.existingAccountId,
    Map<String, bool> useImportedField = const <String, bool>{},
  }) : useImportedField = UnmodifiableMapView<String, bool>(
         Map<String, bool>.of(useImportedField),
       );

  final AccountImportDraft draft;
  final ImportDuplicateResolution resolution;
  final String? existingAccountId;
  final Map<String, bool> useImportedField;
}

final class ImportQuotaValidationResult {
  const ImportQuotaValidationResult({
    required this.allowed,
    required this.requestedAccounts,
    required this.requestedSubscriptions,
    this.remainingAccounts,
    this.remainingSubscriptions,
    this.errorCode,
  });

  const ImportQuotaValidationResult.unlimited({
    required int requestedAccounts,
    required int requestedSubscriptions,
  }) : this(
         allowed: true,
         requestedAccounts: requestedAccounts,
         requestedSubscriptions: requestedSubscriptions,
       );

  final bool allowed;
  final int requestedAccounts;
  final int requestedSubscriptions;
  final int? remainingAccounts;
  final int? remainingSubscriptions;
  final String? errorCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'allowed': allowed,
    'requestedAccounts': requestedAccounts,
    'requestedSubscriptions': requestedSubscriptions,
    'remainingAccounts': remainingAccounts,
    'remainingSubscriptions': remainingSubscriptions,
    'errorCode': errorCode,
  };
}

final class ImportPlan {
  ImportPlan({
    required this.vaultScopeId,
    required this.expectedVaultRevision,
    required List<AccountImportDraft> newAccounts,
    required List<AccountUpdatePlan> accountUpdates,
    required List<AccountImportDraft> skippedAccounts,
    required List<SubscriptionImportDraft> formalSubscriptions,
    required List<SubscriptionImportDraft> pendingSubscriptionDrafts,
    required this.unsupportedItemCount,
    required this.unresolvedDuplicateCount,
    this.unresolvedSubscriptionAccountCount = 0,
    required this.quota,
    Set<int> selectedAccountRows = const <int>{},
    Set<int> selectedSubscriptionRows = const <int>{},
    Map<String, ImportDuplicateResolution> duplicateResolutions =
        const <String, ImportDuplicateResolution>{},
    Map<int, String> selectedDuplicateTargets = const <int, String>{},
  }) : newAccounts = List<AccountImportDraft>.unmodifiable(newAccounts),
       accountUpdates = List<AccountUpdatePlan>.unmodifiable(accountUpdates),
       skippedAccounts = List<AccountImportDraft>.unmodifiable(skippedAccounts),
       formalSubscriptions = List<SubscriptionImportDraft>.unmodifiable(
         formalSubscriptions,
       ),
       pendingSubscriptionDrafts = List<SubscriptionImportDraft>.unmodifiable(
         pendingSubscriptionDrafts,
       ),
       selectedAccountRows = Set<int>.unmodifiable(selectedAccountRows),
       selectedSubscriptionRows = Set<int>.unmodifiable(
         selectedSubscriptionRows,
       ),
       duplicateResolutions =
           UnmodifiableMapView<String, ImportDuplicateResolution>(
             Map<String, ImportDuplicateResolution>.of(duplicateResolutions),
           ),
       selectedDuplicateTargets = UnmodifiableMapView<int, String>(
         Map<int, String>.of(selectedDuplicateTargets),
       );

  final String vaultScopeId;
  final int expectedVaultRevision;
  final List<AccountImportDraft> newAccounts;
  final List<AccountUpdatePlan> accountUpdates;
  final List<AccountImportDraft> skippedAccounts;
  final List<SubscriptionImportDraft> formalSubscriptions;
  final List<SubscriptionImportDraft> pendingSubscriptionDrafts;
  final int unsupportedItemCount;
  final int unresolvedDuplicateCount;
  final int unresolvedSubscriptionAccountCount;
  final ImportQuotaValidationResult quota;
  final Set<int> selectedAccountRows;
  final Set<int> selectedSubscriptionRows;
  final Map<String, ImportDuplicateResolution> duplicateResolutions;
  final Map<int, String> selectedDuplicateTargets;

  int get writeOperationCount =>
      newAccounts.length +
      accountUpdates.length +
      formalSubscriptions.length +
      pendingSubscriptionDrafts.length;

  bool get hasWriteOperations => writeOperationCount > 0;

  int get unresolvedBrandSuggestionCount =>
      <AccountImportDraft>[
        ...newAccounts,
        for (final update in accountUpdates) update.draft,
      ].where((draft) {
        return draft.brandSuggestionCandidates.length > 1 &&
            draft.brandSuggestion == null &&
            !draft.brandSuggestionIgnored;
      }).length;

  bool get canCommit =>
      hasWriteOperations &&
      unresolvedDuplicateCount == 0 &&
      unresolvedBrandSuggestionCount == 0 &&
      unresolvedSubscriptionAccountCount == 0 &&
      quota.allowed;

  Map<String, Object?> toSummaryJson() => <String, Object?>{
    'vaultScopeId': vaultScopeId,
    'expectedVaultRevision': expectedVaultRevision,
    'newAccountCount': newAccounts.length,
    'updatedAccountCount': accountUpdates.length,
    'skippedAccountCount': skippedAccounts.length,
    'formalSubscriptionCount': formalSubscriptions.length,
    'pendingSubscriptionDraftCount': pendingSubscriptionDrafts.length,
    'unsupportedItemCount': unsupportedItemCount,
    'unresolvedDuplicateCount': unresolvedDuplicateCount,
    'unresolvedBrandSuggestionCount': unresolvedBrandSuggestionCount,
    'unresolvedSubscriptionAccountCount': unresolvedSubscriptionAccountCount,
    'writeOperationCount': writeOperationCount,
    'hasWriteOperations': hasWriteOperations,
    'quota': quota.toJson(),
    'selectedAccountRows': selectedAccountRows.toList(growable: false),
    'selectedSubscriptionRows': selectedSubscriptionRows.toList(
      growable: false,
    ),
    'duplicateResolutions': <String, String>{
      for (final entry in duplicateResolutions.entries)
        entry.key: entry.value.name,
    },
    'selectedDuplicateTargets': <String, String>{
      for (final entry in selectedDuplicateTargets.entries)
        entry.key.toString(): entry.value,
    },
    'canCommit': canCommit,
  };
}

final class ImportCommitResult {
  const ImportCommitResult({
    required this.success,
    required this.addedAccountCount,
    required this.updatedAccountCount,
    required this.skippedCount,
    required this.formalSubscriptionCount,
    required this.pendingSubscriptionDraftCount,
    required this.unsupportedItemCount,
    this.resultingVaultRevision,
    this.rollbackAvailable = false,
    this.failureCode,
  });

  final bool success;
  final int addedAccountCount;
  final int updatedAccountCount;
  final int skippedCount;
  final int formalSubscriptionCount;
  final int pendingSubscriptionDraftCount;
  final int unsupportedItemCount;
  final int? resultingVaultRevision;
  final bool rollbackAvailable;
  final String? failureCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'success': success,
    'addedAccountCount': addedAccountCount,
    'updatedAccountCount': updatedAccountCount,
    'skippedCount': skippedCount,
    'formalSubscriptionCount': formalSubscriptionCount,
    'pendingSubscriptionDraftCount': pendingSubscriptionDraftCount,
    'unsupportedItemCount': unsupportedItemCount,
    'resultingVaultRevision': resultingVaultRevision,
    'rollbackAvailable': rollbackAvailable,
    'failureCode': failureCode,
  };
}
