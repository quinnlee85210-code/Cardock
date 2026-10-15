import 'custom_field_companion.dart';
import 'dart:typed_data';

import 'import_duplicate_detector.dart';
import 'import_field_mapper.dart';
import 'import_models.dart';
import 'import_source_adapters.dart';
import 'tabular_import_parser.dart';

typedef ImportQuotaValidator =
    ImportQuotaValidationResult Function(
      int requestedAccounts,
      int requestedSubscriptions,
    );

typedef FormalSubscriptionValidator =
    bool Function(SubscriptionImportDraft draft);

final class ImportSessionSnapshot {
  const ImportSessionSnapshot({
    required this.phase,
    required this.vaultScopeId,
    required this.expectedVaultRevision,
    required this.selectedAccountRows,
    required this.selectedSubscriptionRows,
    required this.confirmedMaskedPasswordRows,
    required this.fieldSuggestions,
    required this.selectedDuplicateTargets,
    required this.selectedBrandSuggestions,
    required this.ignoredBrandSuggestionRows,
    required this.subscriptionAccountTargets,
    required this.duplicateCandidates,
    this.document,
    this.detection,
    this.selectedAdapter,
    this.accountDocument,
    this.subscriptionDocument,
    this.accountDetection,
    this.subscriptionDetection,
    this.accountMapping,
    this.subscriptionMapping,
    this.plan,
  });

  final ImportSessionPhase phase;
  final String? vaultScopeId;
  final int? expectedVaultRevision;
  final TabularDocument? document;
  final ImportSourceDetection? detection;
  final ImportSourceAdapter? selectedAdapter;
  final TabularDocument? accountDocument;
  final TabularDocument? subscriptionDocument;
  final ImportSourceDetection? accountDetection;
  final ImportSourceDetection? subscriptionDetection;
  final AccountMappingResult? accountMapping;
  final SubscriptionMappingResult? subscriptionMapping;
  final Set<int> selectedAccountRows;
  final Set<int> selectedSubscriptionRows;
  final Set<int> confirmedMaskedPasswordRows;
  final List<ImportFieldSuggestion> fieldSuggestions;
  final Map<int, String> selectedDuplicateTargets;
  final Map<int, String> selectedBrandSuggestions;
  final Set<int> ignoredBrandSuggestionRows;
  final Map<int, ImportSubscriptionAccountTarget> subscriptionAccountTargets;
  final List<ImportDuplicateCandidate> duplicateCandidates;
  final ImportPlan? plan;

  Map<String, Object?> toSafeSummaryJson() => <String, Object?>{
    'phase': phase.name,
    'vaultScopeId': vaultScopeId,
    'expectedVaultRevision': expectedVaultRevision,
    'document': document == null
        ? null
        : <String, Object?>{
            'encoding': document!.encoding.name,
            'delimiter': document!.delimiter,
            'columnCount': document!.columnCount,
            'rowCount': document!.rows.length,
            'issues': document!.issues
                .map((issue) => issue.toJson())
                .toList(growable: false),
          },
    'detection': detection?.toJson(),
    'selectedAdapter': selectedAdapter?.toMetadataJson(),
    'accountSource': accountDetection?.toJson(),
    'subscriptionSource': subscriptionDetection?.toJson(),
    'selectedAccountRows': selectedAccountRows.toList(growable: false),
    'selectedSubscriptionRows': selectedSubscriptionRows.toList(
      growable: false,
    ),
    'confirmedMaskedPasswordRows': confirmedMaskedPasswordRows.toList(
      growable: false,
    ),
    'accountPreviews': accountMapping?.drafts
        .map((draft) => draft.toSafePreviewJson())
        .toList(growable: false),
    'accountMappingReport': accountMapping == null
        ? null
        : <String, Object?>{
            'unmappedColumnCount': accountMapping!.unmappedColumns.length,
            'unmappedColumns': accountMapping!.unmappedColumns
                .map((column) => column.toJson())
                .toList(growable: false),
            'excludedSensitiveColumnCount':
                accountMapping!.excludedSensitiveColumns.length,
            'excludedSensitiveColumns': accountMapping!.excludedSensitiveColumns
                .map((column) => column.toJson())
                .toList(growable: false),
            'unsupportedRowCount': accountMapping!.unsupportedRowCount,
          },
    'subscriptionPreviews': subscriptionMapping?.drafts
        .map((draft) => draft.toSafePreviewJson())
        .toList(growable: false),
    'subscriptionMappingReport': subscriptionMapping == null
        ? null
        : <String, Object?>{
            'unmappedColumnCount': subscriptionMapping!.unmappedColumns.length,
            'unmappedColumns': subscriptionMapping!.unmappedColumns
                .map((column) => column.toJson())
                .toList(growable: false),
            'excludedSensitiveColumnCount':
                subscriptionMapping!.excludedSensitiveColumns.length,
            'excludedSensitiveColumns': subscriptionMapping!
                .excludedSensitiveColumns
                .map((column) => column.toJson())
                .toList(growable: false),
          },
    'fieldSuggestions': fieldSuggestions
        .map((suggestion) => suggestion.toJson())
        .toList(growable: false),
    'selectedDuplicateTargets': <String, String>{
      for (final entry in selectedDuplicateTargets.entries)
        entry.key.toString(): entry.value,
    },
    'selectedBrandSuggestions': <String, String>{
      for (final entry in selectedBrandSuggestions.entries)
        entry.key.toString(): entry.value,
    },
    'ignoredBrandSuggestionRows': ignoredBrandSuggestionRows.toList(
      growable: false,
    ),
    'subscriptionAccountTargets': <String, Object?>{
      for (final entry in subscriptionAccountTargets.entries)
        entry.key.toString(): entry.value.toJson(),
    },
    'duplicates': duplicateCandidates
        .map((candidate) => candidate.toSafePreviewJson())
        .toList(growable: false),
    'plan': plan?.toSummaryJson(),
  };
}

final class ImportSessionController {
  ImportSessionController({
    this._parser = const TabularImportParser(),
    ImportSourceRegistry? registry,
    ImportFieldMapper? mapper,
    ImportBrandSuggestionResolver? brandSuggestionResolver,
    this._duplicateDetector = const ImportDuplicateDetector(),
  }) : _registry = registry ?? ImportSourceRegistry.standard(),
       _mapper =
           mapper ??
           ImportFieldMapper(brandSuggestionResolver: brandSuggestionResolver) {
    if (mapper != null && brandSuggestionResolver != null) {
      throw ArgumentError(
        'Pass either mapper or brandSuggestionResolver, not both.',
      );
    }
  }

  final TabularImportParser _parser;
  final ImportSourceRegistry _registry;
  final ImportFieldMapper _mapper;
  final ImportDuplicateDetector _duplicateDetector;

  ImportSessionPhase _phase = ImportSessionPhase.idle;
  String? _vaultScopeId;
  int? _expectedVaultRevision;
  TabularDocument? _document;
  ImportSourceDetection? _detection;
  ImportSourceAdapter? _selectedAdapter;
  AccountMappingResult? _accountMapping;
  SubscriptionMappingResult? _subscriptionMapping;
  TabularDocument? _accountDocument;
  TabularDocument? _subscriptionDocument;
  ImportSourceDetection? _accountDetection;
  ImportSourceDetection? _subscriptionDetection;
  ImportSourceAdapter? _accountAdapter;
  ImportSourceAdapter? _subscriptionAdapter;
  List<ImportDuplicateCandidate> _duplicates =
      const <ImportDuplicateCandidate>[];
  final Set<int> _selectedAccountRows = <int>{};
  final Set<int> _selectedSubscriptionRows = <int>{};
  final Set<int> _confirmedMaskedPasswordRows = <int>{};
  List<ImportFieldSuggestion> _fieldSuggestions =
      const <ImportFieldSuggestion>[];
  final Map<int, String> _selectedDuplicateTargets = <int, String>{};
  final Map<int, String> _selectedBrandSuggestions = <int, String>{};
  final Set<int> _ignoredBrandSuggestionRows = <int>{};
  final Map<int, ImportSubscriptionAccountTarget> _subscriptionAccountTargets =
      <int, ImportSubscriptionAccountTarget>{};
  ImportPlan? _plan;
  CustomFieldCompanion? _customFields;
  List<CustomFieldCompanionRow> get customFieldRows => List.unmodifiable(
    _customFields?.rows ?? const <CustomFieldCompanionRow>[],
  );
  void attachCustomFields(TabularDocument document) {
    final mapping = _requireAccountMapping();
    _customFields = CustomFieldCompanion.parse(document, mapping.drafts);
    _plan = null;
  }

  void setCustomFieldDecision(
    int rowNumber, {
    required bool include,
    required bool replaceExisting,
    required bool sensitiveConfirmed,
  }) {
    final row = _customFields?.rows
        .where((r) => r.rowNumber == rowNumber)
        .firstOrNull;
    if (row == null) throw const FormatException('自定义字段行不存在。');
    row.useImportedValue = include;
    row.replaceExisting = replaceExisting;
    row.sensitiveConfirmed = sensitiveConfirmed;
    _plan = null;
  }

  ImportSessionSnapshot get snapshot => ImportSessionSnapshot(
    phase: _phase,
    vaultScopeId: _vaultScopeId,
    expectedVaultRevision: _expectedVaultRevision,
    document: _document,
    detection: _detection,
    selectedAdapter: _selectedAdapter,
    accountDocument: _accountDocument,
    subscriptionDocument: _subscriptionDocument,
    accountDetection: _accountDetection,
    subscriptionDetection: _subscriptionDetection,
    accountMapping: _accountMapping,
    subscriptionMapping: _subscriptionMapping,
    selectedAccountRows: Set<int>.unmodifiable(_selectedAccountRows),
    selectedSubscriptionRows: Set<int>.unmodifiable(_selectedSubscriptionRows),
    confirmedMaskedPasswordRows: Set<int>.unmodifiable(
      _confirmedMaskedPasswordRows,
    ),
    fieldSuggestions: List<ImportFieldSuggestion>.unmodifiable(
      _fieldSuggestions,
    ),
    selectedDuplicateTargets: Map<int, String>.unmodifiable(
      _selectedDuplicateTargets,
    ),
    selectedBrandSuggestions: Map<int, String>.unmodifiable(
      _selectedBrandSuggestions,
    ),
    ignoredBrandSuggestionRows: Set<int>.unmodifiable(
      _ignoredBrandSuggestionRows,
    ),
    subscriptionAccountTargets:
        Map<int, ImportSubscriptionAccountTarget>.unmodifiable(
          _subscriptionAccountTargets,
        ),
    duplicateCandidates: List<ImportDuplicateCandidate>.unmodifiable(
      _duplicates,
    ),
    plan: _plan,
  );

  ImportSessionSnapshot loadDocument(
    Uint8List bytes, {
    required String vaultScopeId,
    required int expectedVaultRevision,
    TabularParseOptions options = const TabularParseOptions(),
  }) => loadParsedDocument(
    _parser.parse(bytes, options: options),
    vaultScopeId: vaultScopeId,
    expectedVaultRevision: expectedVaultRevision,
  );

  ImportSessionSnapshot loadParsedDocument(
    TabularDocument document, {
    required String vaultScopeId,
    required int expectedVaultRevision,
  }) {
    _clearTransient();
    _vaultScopeId = vaultScopeId;
    _expectedVaultRevision = expectedVaultRevision;
    _document = document;
    _detection = _registry.detect(document);
    _selectedAdapter = _detection!.selectedAdapter;
    _phase = ImportSessionPhase.documentLoaded;
    return snapshot;
  }

  ImportSessionSnapshot selectAdapter(String adapterId) {
    _requireDocument();
    final adapter = _registry.adapterById(adapterId);
    if (!adapter.enabled || !adapter.verified) {
      throw StateError(
        'The requested source adapter is disabled or unverified.',
      );
    }
    if (isBrowserPasswordSourceId(adapter.id) &&
        adapter.confidenceFor(_requireDocument()) != 1) {
      throw const FormatException('所选浏览器来源与文件结构不匹配，请选择通用映射。');
    }
    _selectedAdapter = adapter;
    _customFields = null;
    _accountMapping = null;
    _subscriptionMapping = null;
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedAccountRows.clear();
    _selectedSubscriptionRows.clear();
    _confirmedMaskedPasswordRows.clear();
    _fieldSuggestions = const <ImportFieldSuggestion>[];
    _selectedDuplicateTargets.clear();
    _selectedBrandSuggestions.clear();
    _ignoredBrandSuggestionRows.clear();
    _subscriptionAccountTargets.clear();
    _plan = null;
    _phase = ImportSessionPhase.sourceSelected;
    return snapshot;
  }

  ImportSessionSnapshot mapAccounts({
    Map<int, ImportTargetField> overrides = const <int, ImportTargetField>{},
  }) {
    final document = _requireDocument();
    final adapter = _requireAdapter();
    _accountMapping = _mapper.mapAccounts(
      document,
      adapter: adapter,
      documentSlotId: 'account-document',
      overrides: overrides,
    );
    _accountDocument = document;
    _accountDetection = _detection;
    _accountAdapter = adapter;
    _fieldSuggestions = _accountMapping!.suggestions;
    _selectedBrandSuggestions.clear();
    _ignoredBrandSuggestionRows.clear();
    _subscriptionAccountTargets.clear();
    _selectedAccountRows
      ..clear()
      ..addAll(
        _accountMapping!.drafts
            .where(
              (draft) => draft.validationState != ImportValidationState.invalid,
            )
            .map((draft) => draft.originalRowNumber),
      );
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedDuplicateTargets.clear();
    _plan = null;
    _phase = ImportSessionPhase.mapped;
    return snapshot;
  }

  ImportSessionSnapshot mapSubscriptions({
    Map<int, ImportTargetField> overrides = const <int, ImportTargetField>{},
  }) {
    final document = _requireDocument();
    final adapter = _requireAdapter();
    _subscriptionMapping = _mapper.mapSubscriptions(
      document,
      adapter: adapter,
      documentSlotId: 'subscription-document',
      overrides: overrides,
    );
    _subscriptionDocument = document;
    _subscriptionDetection = _detection;
    _subscriptionAdapter = adapter;
    _subscriptionAccountTargets.clear();
    _selectedSubscriptionRows
      ..clear()
      ..addAll(
        _subscriptionMapping!.drafts.map((draft) => draft.originalRowNumber),
      );
    _plan = null;
    _phase = ImportSessionPhase.mapped;
    return snapshot;
  }

  ImportSessionSnapshot appendAccountDocument(
    TabularDocument document, {
    String? adapterId,
    Map<int, ImportTargetField> overrides = const <int, ImportTargetField>{},
  }) {
    _requireSessionIdentity();
    final detection = _registry.detect(document);
    final adapter = adapterId == null
        ? detection.selectedAdapter
        : _registry.adapterById(adapterId);
    if (!adapter.enabled ||
        !adapter.verified ||
        (adapter.itemKind != ImportItemKind.account && !adapter.isGeneric)) {
      throw StateError('The selected adapter cannot map account rows.');
    }
    _document = document;
    _detection = detection;
    _selectedAdapter = adapter;
    return mapAccounts(overrides: overrides);
  }

  ImportSessionSnapshot appendSubscriptionDocument(
    TabularDocument document, {
    String? adapterId,
    Map<int, ImportTargetField> overrides = const <int, ImportTargetField>{},
  }) {
    _requireSessionIdentity();
    final detection = _registry.detect(document);
    final adapter = adapterId == null
        ? detection.selectedAdapter
        : _registry.adapterById(adapterId);
    if (!adapter.enabled ||
        !adapter.verified ||
        (adapter.itemKind != ImportItemKind.subscription &&
            !adapter.isGeneric)) {
      throw StateError('The selected adapter cannot map subscription rows.');
    }
    _document = document;
    _detection = detection;
    _selectedAdapter = adapter;
    return mapSubscriptions(overrides: overrides);
  }

  ImportSessionSnapshot removeAccountDocument() {
    _requireSessionIdentity();
    _accountDocument = null;
    _accountDetection = null;
    _accountAdapter = null;
    _accountMapping = null;
    _selectedAccountRows.clear();
    _confirmedMaskedPasswordRows.clear();
    _fieldSuggestions = const <ImportFieldSuggestion>[];
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedDuplicateTargets.clear();
    _selectedBrandSuggestions.clear();
    _ignoredBrandSuggestionRows.clear();
    _subscriptionAccountTargets.clear();
    _plan = null;
    _activateRemainingDocument();
    return snapshot;
  }

  ImportSessionSnapshot removeSubscriptionDocument() {
    _requireSessionIdentity();
    _subscriptionDocument = null;
    _subscriptionDetection = null;
    _subscriptionAdapter = null;
    _subscriptionMapping = null;
    _selectedSubscriptionRows.clear();
    _subscriptionAccountTargets.clear();
    _plan = null;
    _activateRemainingDocument();
    return snapshot;
  }

  ImportSessionSnapshot activateAccountDocument() {
    _requireSessionIdentity();
    final document = _accountDocument;
    final adapter = _accountAdapter;
    if (document == null || adapter == null) {
      throw StateError('No account document is loaded.');
    }
    _document = document;
    _detection = _accountDetection;
    _selectedAdapter = adapter;
    _phase = ImportSessionPhase.mapped;
    return snapshot;
  }

  ImportSessionSnapshot activateSubscriptionDocument() {
    _requireSessionIdentity();
    final document = _subscriptionDocument;
    final adapter = _subscriptionAdapter;
    if (document == null || adapter == null) {
      throw StateError('No subscription document is loaded.');
    }
    _document = document;
    _detection = _subscriptionDetection;
    _selectedAdapter = adapter;
    _phase = ImportSessionPhase.mapped;
    return snapshot;
  }

  void _activateRemainingDocument() {
    if (_subscriptionDocument case final document?) {
      _document = document;
      _detection = _subscriptionDetection;
      _selectedAdapter = _subscriptionAdapter;
      _phase = ImportSessionPhase.mapped;
      return;
    }
    if (_accountDocument case final document?) {
      _document = document;
      _detection = _accountDetection;
      _selectedAdapter = _accountAdapter;
      _phase = ImportSessionPhase.mapped;
      return;
    }
    _document = null;
    _detection = null;
    _selectedAdapter = null;
    _phase = ImportSessionPhase.idle;
  }

  ImportSessionSnapshot setAccountRowSelected(int rowNumber, bool selected) {
    _requireAccountMapping();
    if (selected) {
      _selectedAccountRows.add(rowNumber);
    } else {
      _selectedAccountRows.remove(rowNumber);
      _confirmedMaskedPasswordRows.remove(rowNumber);
      _selectedDuplicateTargets.remove(rowNumber);
    }
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedDuplicateTargets.clear();
    _plan = null;
    _phase = ImportSessionPhase.mapped;
    return snapshot;
  }

  ImportSessionSnapshot setSubscriptionRowSelected(
    int rowNumber,
    bool selected,
  ) {
    _requireSubscriptionMapping();
    if (selected) {
      _selectedSubscriptionRows.add(rowNumber);
    } else {
      _selectedSubscriptionRows.remove(rowNumber);
    }
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot detectDuplicates(
    List<ExistingAccountSummary> existing,
  ) {
    final mapping = _requireAccountMapping();
    final selected = mapping.drafts
        .where(
          (draft) => _selectedAccountRows.contains(draft.originalRowNumber),
        )
        .map(_accountDraftForPlan)
        .toList(growable: false);
    _duplicates = _duplicateDetector.detect(
      imported: selected,
      existing: existing,
    );
    _selectedDuplicateTargets.clear();
    _phase = _duplicates.every((candidate) => candidate.isResolved)
        ? ImportSessionPhase.duplicatesReviewed
        : ImportSessionPhase.mapped;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot setDuplicateResolution(
    String candidateId,
    ImportDuplicateResolution resolution,
  ) {
    final index = _duplicates.indexWhere(
      (candidate) => candidate.id == candidateId,
    );
    if (index < 0) throw ArgumentError.value(candidateId, 'candidateId');
    final mutable = List<ImportDuplicateCandidate>.of(_duplicates);
    mutable[index] = mutable[index].withResolution(resolution);
    _duplicates = List<ImportDuplicateCandidate>.unmodifiable(mutable);
    _phase = _duplicates.every((candidate) => candidate.isResolved)
        ? ImportSessionPhase.duplicatesReviewed
        : ImportSessionPhase.mapped;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot setDuplicateFieldChoice(
    String candidateId, {
    required String fieldName,
    required bool useImportedValue,
  }) {
    final index = _duplicates.indexWhere(
      (candidate) => candidate.id == candidateId,
    );
    if (index < 0) throw ArgumentError.value(candidateId, 'candidateId');
    final mutable = List<ImportDuplicateCandidate>.of(_duplicates);
    mutable[index] = mutable[index].withFieldChoice(
      fieldName,
      useImportedValue: useImportedValue,
    );
    _duplicates = List<ImportDuplicateCandidate>.unmodifiable(mutable);
    _phase = _duplicates.every((candidate) => candidate.isResolved)
        ? ImportSessionPhase.duplicatesReviewed
        : ImportSessionPhase.mapped;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot setMaskedPasswordConfirmed(
    int rowNumber, {
    required bool confirmed,
  }) {
    final mapping = _requireAccountMapping();
    final draft = mapping.drafts
        .where((candidate) => candidate.originalRowNumber == rowNumber)
        .firstOrNull;
    if (draft == null) throw ArgumentError.value(rowNumber, 'rowNumber');
    if (isBrowserPasswordSourceId(draft.adapterId)) {
      throw StateError('浏览器来源的掩码密码不可强制导入。');
    }
    if (!draft.passwordLooksMasked) {
      throw ArgumentError.value(
        rowNumber,
        'rowNumber',
        'The row does not contain a masked password placeholder.',
      );
    }
    if (confirmed) {
      _confirmedMaskedPasswordRows.add(rowNumber);
    } else {
      _confirmedMaskedPasswordRows.remove(rowNumber);
    }
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedDuplicateTargets.clear();
    _phase = ImportSessionPhase.mapped;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot acceptFieldSuggestion(String suggestionId) {
    final index = _fieldSuggestions.indexWhere(
      (suggestion) => suggestion.id == suggestionId,
    );
    if (index < 0) throw ArgumentError.value(suggestionId, 'suggestionId');
    final mutable = List<ImportFieldSuggestion>.of(_fieldSuggestions);
    mutable[index] = mutable[index].withAccepted(true);
    _fieldSuggestions = List<ImportFieldSuggestion>.unmodifiable(mutable);
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedDuplicateTargets.clear();
    _phase = ImportSessionPhase.mapped;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot acceptAllFieldSuggestions() {
    _requireAccountMapping();
    _fieldSuggestions = List<ImportFieldSuggestion>.unmodifiable(
      _fieldSuggestions.map((suggestion) => suggestion.withAccepted(true)),
    );
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedDuplicateTargets.clear();
    _phase = ImportSessionPhase.mapped;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot ignoreAllFieldSuggestions() {
    _requireAccountMapping();
    _fieldSuggestions = List<ImportFieldSuggestion>.unmodifiable(
      _fieldSuggestions.map((suggestion) => suggestion.withAccepted(false)),
    );
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedDuplicateTargets.clear();
    _phase = ImportSessionPhase.mapped;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot setDuplicateUpdateTarget(
    int rowNumber,
    String existingAccountId,
  ) {
    final valid = _duplicates.any(
      (candidate) =>
          candidate.importRowNumber == rowNumber &&
          candidate.origin == ImportDuplicateOrigin.existingVault &&
          candidate.existingAccountId == existingAccountId,
    );
    if (!valid) {
      throw ArgumentError.value(
        existingAccountId,
        'existingAccountId',
        'The account is not a duplicate candidate for this row.',
      );
    }
    _selectedDuplicateTargets[rowNumber] = existingAccountId;
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot selectBrandSuggestion(int rowNumber, String brandId) {
    final mapping = _requireAccountMapping();
    final draft = mapping.drafts
        .where((candidate) => candidate.originalRowNumber == rowNumber)
        .firstOrNull;
    if (draft == null || !draft.brandSuggestionCandidates.contains(brandId)) {
      throw ArgumentError.value(
        brandId,
        'brandId',
        'The brand is not a suggestion candidate for this row.',
      );
    }
    _selectedBrandSuggestions[rowNumber] = brandId;
    _ignoredBrandSuggestionRows.remove(rowNumber);
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot ignoreBrandSuggestions(int rowNumber) {
    final mapping = _requireAccountMapping();
    final exists = mapping.drafts.any(
      (draft) =>
          draft.originalRowNumber == rowNumber &&
          draft.brandSuggestionCandidates.isNotEmpty,
    );
    if (!exists) throw ArgumentError.value(rowNumber, 'rowNumber');
    _selectedBrandSuggestions.remove(rowNumber);
    _ignoredBrandSuggestionRows.add(rowNumber);
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot setSubscriptionAccountTarget(
    int rowNumber, {
    String? importedAccountKey,
    String? existingAccountId,
  }) {
    final mapping = _requireSubscriptionMapping();
    if (!mapping.drafts.any((draft) => draft.originalRowNumber == rowNumber)) {
      throw ArgumentError.value(rowNumber, 'rowNumber');
    }
    if ((importedAccountKey == null) == (existingAccountId == null)) {
      throw ArgumentError(
        'Pass exactly one of importedAccountKey or existingAccountId.',
      );
    }
    late final String accountKey;
    if (importedAccountKey != null) {
      final accounts = _requireAccountMapping();
      final exists = accounts.drafts.any(
        (draft) =>
            draft.accountKey == importedAccountKey &&
            _selectedAccountRows.contains(draft.originalRowNumber),
      );
      if (!exists) {
        throw ArgumentError.value(
          importedAccountKey,
          'importedAccountKey',
          'The selected import account key is unavailable.',
        );
      }
      accountKey = importedAccountKey;
    } else {
      if (existingAccountId!.trim().isEmpty) {
        throw ArgumentError.value(existingAccountId, 'existingAccountId');
      }
      accountKey = existingAccountId;
    }
    _subscriptionAccountTargets[rowNumber] = ImportSubscriptionAccountTarget(
      rowNumber: rowNumber,
      accountKey: accountKey,
      existingAccountId: existingAccountId,
    );
    _plan = null;
    return snapshot;
  }

  ImportSessionSnapshot buildPlan({
    ImportQuotaValidator? quotaValidator,
    FormalSubscriptionValidator? isFormalSubscriptionValid,
  }) {
    final vaultScopeId = _vaultScopeId;
    final revision = _expectedVaultRevision;
    if (vaultScopeId == null || revision == null) {
      throw StateError('A vault scope and revision are required.');
    }

    final newAccounts = <AccountImportDraft>[];
    final updates = <AccountUpdatePlan>[];
    final skipped = <AccountImportDraft>[];
    var unsupported = 0;
    final accountMapping = _accountMapping;
    if (accountMapping != null) {
      unsupported += accountMapping.unsupportedRowCount;
      final candidatesByRow = <int, List<ImportDuplicateCandidate>>{};
      for (final candidate in _duplicates) {
        candidatesByRow
            .putIfAbsent(
              candidate.importRowNumber,
              () => <ImportDuplicateCandidate>[],
            )
            .add(candidate);
      }
      for (final sourceDraft in accountMapping.drafts) {
        final draft = _accountDraftForPlan(sourceDraft);
        if (!_selectedAccountRows.contains(draft.originalRowNumber)) {
          skipped.add(draft);
          continue;
        }
        final candidates =
            candidatesByRow[draft.originalRowNumber] ??
            const <ImportDuplicateCandidate>[];
        if (candidates.isEmpty) {
          newAccounts.add(draft);
          continue;
        }
        final resolutions = candidates
            .map((candidate) => candidate.resolution)
            .whereType<ImportDuplicateResolution>()
            .toSet();
        if (resolutions.isEmpty) {
          continue;
        }
        if (resolutions.length > 1) {
          throw StateError(
            'All duplicate candidates for one row must use one resolution.',
          );
        }
        final resolution = resolutions.single;
        switch (resolution) {
          case ImportDuplicateResolution.skip:
            skipped.add(draft);
          case ImportDuplicateResolution.importAsNew:
            newAccounts.add(draft);
          case ImportDuplicateResolution.fillEmptyFieldsOnly:
          case ImportDuplicateResolution.fieldByField:
            final targets = candidates
                .where(
                  (candidate) =>
                      candidate.origin == ImportDuplicateOrigin.existingVault,
                )
                .map((candidate) => candidate.existingAccountId)
                .whereType<String>()
                .toSet();
            if (targets.isEmpty) {
              throw StateError(
                'Updating requires a matching existing-vault account.',
              );
            }
            final target = targets.length == 1
                ? targets.single
                : _selectedDuplicateTargets[draft.originalRowNumber];
            if (target == null || !targets.contains(target)) {
              throw StateError(
                'Updating multiple candidates requires an explicit target.',
              );
            }
            updates.add(
              AccountUpdatePlan(
                draft: draft,
                resolution: resolution,
                existingAccountId: target,
                useImportedField:
                    candidates
                        .where(
                          (candidate) => candidate.existingAccountId == target,
                        )
                        .map((candidate) => candidate.useImportedField)
                        .firstOrNull ??
                    const <String, bool>{},
              ),
            );
        }
      }
    }

    final formalSubscriptions = <SubscriptionImportDraft>[];
    final pendingSubscriptions = <SubscriptionImportDraft>[];
    var unresolvedSubscriptionAccounts = 0;
    final selectedAccountKeys = <String>{
      if (accountMapping != null)
        for (final draft in accountMapping.drafts)
          if (_selectedAccountRows.contains(draft.originalRowNumber) &&
              draft.accountKey != null)
            draft.accountKey!,
    };
    final subscriptionMapping = _subscriptionMapping;
    if (subscriptionMapping != null) {
      for (final sourceDraft in subscriptionMapping.drafts) {
        if (!_selectedSubscriptionRows.contains(
          sourceDraft.originalRowNumber,
        )) {
          continue;
        }
        var draft = sourceDraft;
        var accountResolved = false;
        final target =
            _subscriptionAccountTargets[sourceDraft.originalRowNumber];
        if (target != null) {
          accountResolved =
              target.existingAccountId != null ||
              selectedAccountKeys.contains(target.accountKey);
          if (accountResolved) {
            draft = sourceDraft.withAccountTarget(
              accountKey: target.accountKey,
              existingAccountId: target.existingAccountId,
            );
          }
        } else if (!sourceDraft.accountKeyWasGenerated &&
            selectedAccountKeys.contains(sourceDraft.accountKey)) {
          accountResolved = true;
        }
        if (!accountResolved) unresolvedSubscriptionAccounts += 1;
        final valid =
            accountResolved &&
            draft.isSyntacticallyComplete &&
            (isFormalSubscriptionValid?.call(draft) ?? false);
        if (valid) {
          formalSubscriptions.add(draft);
        } else {
          pendingSubscriptions.add(draft);
        }
      }
    }

    final unresolved = _duplicates
        .where(
          (candidate) =>
              _selectedAccountRows.contains(candidate.importRowNumber) &&
              !candidate.isResolved,
        )
        .length;
    final quota =
        quotaValidator?.call(newAccounts.length, formalSubscriptions.length) ??
        ImportQuotaValidationResult.unlimited(
          requestedAccounts: newAccounts.length,
          requestedSubscriptions: formalSubscriptions.length,
        );
    final duplicateResolutions = <String, ImportDuplicateResolution>{
      for (final candidate in _duplicates)
        if (candidate.resolution != null) candidate.id: candidate.resolution!,
    };
    _plan = ImportPlan(
      vaultScopeId: vaultScopeId,
      expectedVaultRevision: revision,
      newAccounts: newAccounts,
      accountUpdates: updates,
      skippedAccounts: skipped,
      formalSubscriptions: formalSubscriptions,
      pendingSubscriptionDrafts: pendingSubscriptions,
      unsupportedItemCount: unsupported,
      unresolvedDuplicateCount: unresolved,
      unresolvedSubscriptionAccountCount: unresolvedSubscriptionAccounts,
      quota: quota,
      selectedAccountRows: _selectedAccountRows,
      selectedSubscriptionRows: _selectedSubscriptionRows,
      duplicateResolutions: duplicateResolutions,
      selectedDuplicateTargets: _selectedDuplicateTargets,
    );
    _phase = ImportSessionPhase.planned;
    return snapshot;
  }

  AccountImportDraft _accountDraftForPlan(AccountImportDraft draft) {
    var output = _customFields?.apply(draft) ?? draft;
    if (_ignoredBrandSuggestionRows.contains(draft.originalRowNumber)) {
      output = output.withBrandSuggestion(null, ignored: true);
    } else {
      final selectedBrand = _selectedBrandSuggestions[draft.originalRowNumber];
      if (selectedBrand != null) {
        output = output.withBrandSuggestion(selectedBrand, ignored: false);
      }
    }
    for (final suggestion in _fieldSuggestions) {
      if (!suggestion.accepted ||
          suggestion.rowNumber != draft.originalRowNumber) {
        continue;
      }
      switch (suggestion.targetField) {
        case ImportTargetField.email:
          if (output.email.isEmpty) {
            output = output.copyWith(email: suggestion.value);
          }
        case ImportTargetField.phone:
          if (output.phone.isEmpty) {
            output = output.copyWith(phone: suggestion.value);
          }
        default:
          throw StateError('Unsupported import field suggestion target.');
      }
    }
    if (!output.passwordLooksMasked) return output;
    final confirmed =
        !isBrowserPasswordSourceId(output.adapterId) &&
        _confirmedMaskedPasswordRows.contains(output.originalRowNumber);
    return output.copyWith(
      password: confirmed ? output.password : '',
      maskedPasswordConfirmed: confirmed,
    );
  }

  ImportSessionSnapshot clear() {
    _clearTransient();
    _vaultScopeId = null;
    _expectedVaultRevision = null;
    _document = null;
    _detection = null;
    _selectedAdapter = null;
    _phase = ImportSessionPhase.cleared;
    return snapshot;
  }

  void _clearTransient() {
    _customFields = null;
    _accountMapping = null;
    _subscriptionMapping = null;
    _accountDocument = null;
    _subscriptionDocument = null;
    _accountDetection = null;
    _subscriptionDetection = null;
    _accountAdapter = null;
    _subscriptionAdapter = null;
    _duplicates = const <ImportDuplicateCandidate>[];
    _selectedAccountRows.clear();
    _selectedSubscriptionRows.clear();
    _confirmedMaskedPasswordRows.clear();
    _fieldSuggestions = const <ImportFieldSuggestion>[];
    _selectedDuplicateTargets.clear();
    _selectedBrandSuggestions.clear();
    _ignoredBrandSuggestionRows.clear();
    _subscriptionAccountTargets.clear();
    _plan = null;
  }

  TabularDocument _requireDocument() {
    final value = _document;
    if (value == null) throw StateError('No import document is loaded.');
    return value;
  }

  void _requireSessionIdentity() {
    if (_vaultScopeId == null || _expectedVaultRevision == null) {
      throw StateError('A vault scope and revision are required.');
    }
  }

  ImportSourceAdapter _requireAdapter() {
    final value = _selectedAdapter;
    if (value == null) throw StateError('No import source is selected.');
    return value;
  }

  AccountMappingResult _requireAccountMapping() {
    final value = _accountMapping;
    if (value == null) throw StateError('Account rows are not mapped.');
    return value;
  }

  SubscriptionMappingResult _requireSubscriptionMapping() {
    final value = _subscriptionMapping;
    if (value == null) throw StateError('Subscription rows are not mapped.');
    return value;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
