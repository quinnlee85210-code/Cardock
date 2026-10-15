import '../../../core/data_import/custom_field_companion.dart';
import 'dart:async';
import 'dart:typed_data';

import '../../../app/app_state.dart';
import '../../../core/branding/brand_catalog_loader.dart';
import '../../../core/branding/brand_matcher.dart';
import '../../../core/data_import/data_import.dart';
import '../../../core/entitlements/entitlement_guard.dart';
import '../../../core/entitlements/entitlement_model.dart';
import 'data_import_ui_controller.dart';

final class AppDataImportUiController extends DataImportUiController {
  AppDataImportUiController({
    required this._appState,
    Timer Function(Duration, void Function()) timerFactory = Timer.new,
  }) : _createSensitiveTimer = timerFactory,
       _registry = ImportSourceRegistry.standard() {
    _state = DataImportUiState(
      canWrite: _canWrite,
      selectedSourceId: _selectedSourceId,
    );
    _appState.addListener(_handleAppStateChanged);
  }

  final Timer Function(Duration, void Function()) _createSensitiveTimer;
  final AppState _appState;
  final ImportSourceRegistry _registry;
  ImportSessionController? _session;
  Future<ImportSessionController>? _sessionFuture;
  DataImportUiState _state = const DataImportUiState();
  String _selectedSourceId = 'auto';
  bool _sourceMismatch = false;
  String? _fileName;
  int _fileSize = 0;
  String? _additionalFileName;
  int _additionalFileSize = 0;
  final Map<int, ImportTargetField> _overrides = <int, ImportTargetField>{};
  final Set<String> _removedRows = <String>{};
  final Map<String, String> _brandLabels = <String, String>{};
  TabularParseJob? _parseJob;
  StreamSubscription<TabularParseProgress>? _parseProgressSubscription;
  bool _disposed = false;
  Timer? _sensitiveDeadline;

  bool get _canWrite =>
      _appState.isUnlocked &&
      _appState.hasFullVaultAccess &&
      _appState.canManageSecurity &&
      !_appState.isBusy &&
      _appState.importVaultScopeId != null;

  @override
  DataImportUiState get state => _state;

  @override
  List<DataImportSourceOption> get sources =>
      List<DataImportSourceOption>.unmodifiable(<DataImportSourceOption>[
        const DataImportSourceOption(
          id: 'auto',
          label: '自动检测',
          description: '优先匹配已验证的来源；无法唯一识别时使用通用表格并要求核对映射。',
        ),
        for (final adapter in _registry.adapters)
          if (adapter.enabled &&
              adapter.verified &&
              adapter.id != 'chrome_google_csv')
            DataImportSourceOption(
              id: adapter.id,
              label: adapter.displayName,
              description: adapter.itemKind == ImportItemKind.account
                  ? '已验证的账号导入格式'
                  : '已验证的订阅导入格式',
            ),
      ]);

  Future<ImportSessionController> _ensureSession() =>
      _sessionFuture ??= _createSession();

  Future<ImportSessionController> _createSession() async {
    final catalog = await const CardockBrandCatalogLoader().load();
    if (_disposed) throw StateError('Data import controller was disposed.');
    _brandLabels
      ..clear()
      ..addEntries(
        catalog.entries.map(
          (entry) =>
              MapEntry<String, String>(entry.brandId, entry.canonicalName),
        ),
      );

    ImportBrandSuggestionResult brandSuggestion(
      String platformName,
      String url,
    ) {
      CardockBrandResolution resolve(String value) =>
          CardockBrandMatcher(catalog).resolve(value, includeSuggestions: true);
      var resolution = resolve(platformName);
      if (resolution.entry == null &&
          resolution.suggestions.isEmpty &&
          url.trim().isNotEmpty) {
        final value = url.trim();
        final host =
            Uri.tryParse(
              value.contains('://') ? value : 'https://$value',
            )?.host ??
            '';
        if (host.isNotEmpty) resolution = resolve(host);
      }
      final entry = resolution.entry;
      if (entry != null && resolution.isAutomaticallyBound) {
        return ImportBrandSuggestionResult.exactUnique(entry.brandId);
      }
      final candidates = resolution.suggestions
          .map((suggestion) => suggestion.entry.brandId)
          .toSet();
      return candidates.length >= 2
          ? ImportBrandSuggestionResult.multipleCandidates(candidates)
          : ImportBrandSuggestionResult.none();
    }

    final value = ImportSessionController(
      brandSuggestionResolver: brandSuggestion,
    );
    _session = value;
    return value;
  }

  @override
  Future<void> selectSource(String sourceId) async {
    if (!_canWrite || _state.working) return;
    if (sourceId != 'auto') {
      final adapter = _registry.adapterById(sourceId);
      if (!adapter.enabled || !adapter.verified) {
        _setError('该来源尚未完成格式验证，当前不能启用。');
        return;
      }
    }
    _selectedSourceId = sourceId;
    _state = _copyState(clearError: true, selectedSourceId: sourceId);
    notifyListeners();
  }

  @override
  Future<bool> loadFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!_canWrite || _state.working) return false;
    final scope = _appState.importVaultScopeId;
    if (scope == null) {
      _setError('保险库当前不能写入，请重新完整解锁。');
      return false;
    }
    _sensitiveDeadline?.cancel();
    _sensitiveDeadline = _createSensitiveTimer(
      const Duration(minutes: 5),
      clearSensitiveMemory,
    );
    _setWorking(true);
    final expectedRevision = _appState.localWebRevision;
    final sessionFuture = _ensureSession();
    final job = const TabularImportParser().parseInBackground(
      bytes,
      options: const TabularParseOptions(
        limits: TabularParseLimits(
          maximumFileBytes: 10 * 1024 * 1024,
          maximumDataRows: 5000,
        ),
      ),
    );
    _parseJob = job;
    _state = _copyState(parseProgress: 0);
    if (!_disposed) notifyListeners();
    _parseProgressSubscription = job.progress.listen((progress) {
      if (_parseJob != job || _disposed) return;
      _state = _copyState(parseProgress: progress.fraction);
      notifyListeners();
    });
    try {
      final document = await job.result;
      final session = await sessionFuture;
      if (_parseJob != job ||
          !_canWrite ||
          scope != _appState.importVaultScopeId ||
          expectedRevision != _appState.localWebRevision) {
        return false;
      }
      session.loadParsedDocument(
        document,
        vaultScopeId: scope,
        expectedVaultRevision: expectedRevision,
      );
      _sourceMismatch = false;
      _fileName = fileName;
      _fileSize = bytes.length;
      if (_selectedSourceId != 'auto') {
        final requested = _registry.adapterById(_selectedSourceId);
        if (isBrowserPasswordSourceId(requested.id) &&
            (requested.confidenceFor(document) != 1 ||
                !fileName.toLowerCase().endsWith('.csv'))) {
          _sourceMismatch = true;
          _setError(
            '所选来源：${requested.displayName}；实际识别：${session.snapshot.selectedAdapter!.displayName}。文件结构不匹配，尚未生成导入计划；可改用通用映射。',
          );
          return false;
        }
        session.selectAdapter(_selectedSourceId);
      }
      if (_selectedSourceId == 'auto' &&
          !fileName.toLowerCase().endsWith('.csv') &&
          isBrowserPasswordSourceId(session.snapshot.selectedAdapter!.id)) {
        session.selectAdapter('generic_tabular');
      }
      _overrides.clear();
      _removedRows.clear();
      _mapSelectedKind(session);
      _fileName = fileName;
      _fileSize = bytes.length;
      _publish(step: DataImportWizardStep.file);
      return true;
    } on TabularParseCancelledException {
      // Cancellation is an explicit zero-write outcome.
      return false;
    } on Object {
      _setError('文件解析或来源检测失败；本机数据未改变。');
      return false;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      if (_parseJob == job) _parseJob = null;
      await _parseProgressSubscription?.cancel();
      _parseProgressSubscription = null;
      _state = _copyState(working: false, parseProgress: -1);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  Future<void> useGenericMapping() async {
    if (!_canWrite || _state.working || !_sourceMismatch) return;
    final session = _session;
    if (session?.snapshot.document == null) return;
    session!.selectAdapter('generic_tabular');
    _selectedSourceId = 'generic_tabular';
    _sourceMismatch = false;
    _overrides.clear();
    _mapSelectedKind(session);
    _publish(step: DataImportWizardStep.mapping);
  }

  @override
  Future<bool> appendFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!_canWrite || _state.working) return false;
    final session = _session;
    final scope = _appState.importVaultScopeId;
    if (session == null || scope == null) {
      _setError('请先读取第一张账号或订阅表。');
      return false;
    }
    final before = session.snapshot;
    if ((before.accountMapping == null && before.subscriptionMapping == null) ||
        (before.accountMapping != null && before.subscriptionMapping != null)) {
      _setError('当前会话不能再追加文件；如需重选请清空后重新开始。');
      return false;
    }
    _setWorking(true);
    final expectedRevision = _appState.localWebRevision;
    final job = const TabularImportParser().parseInBackground(
      bytes,
      options: const TabularParseOptions(
        limits: TabularParseLimits(
          maximumFileBytes: 10 * 1024 * 1024,
          maximumDataRows: 5000,
        ),
      ),
    );
    _parseJob = job;
    _state = _copyState(parseProgress: 0);
    if (!_disposed) notifyListeners();
    _parseProgressSubscription = job.progress.listen((progress) {
      if (_parseJob != job || _disposed) return;
      _state = _copyState(parseProgress: progress.fraction);
      notifyListeners();
    });
    try {
      final document = await job.result;
      if (_parseJob != job ||
          !_canWrite ||
          scope != _appState.importVaultScopeId ||
          expectedRevision != _appState.localWebRevision) {
        return false;
      }
      final adapter = _registry.detect(document).selectedAdapter;
      if (!adapter.enabled || !adapter.verified) {
        throw const FormatException('追加文件来源尚未完成格式验证。');
      }
      if (before.accountMapping != null) {
        if (adapter.itemKind != ImportItemKind.subscription) {
          throw const FormatException('第二个文件必须是已验证的订阅表。');
        }
        session.appendSubscriptionDocument(document, adapterId: adapter.id);
      } else {
        if (adapter.itemKind != ImportItemKind.account) {
          throw const FormatException('第二个文件必须是已验证的账号表。');
        }
        session.appendAccountDocument(document, adapterId: adapter.id);
      }
      _overrides.clear();
      _additionalFileName = fileName;
      _additionalFileSize = bytes.length;
      _publish(step: DataImportWizardStep.mapping);
      return true;
    } on TabularParseCancelledException {
      // Cancellation is an explicit zero-write outcome.
      return false;
    } on Object {
      _setError('第二个文件无法作为配套账号/订阅表追加；本机数据未改变。');
      return false;
    } finally {
      if (_parseJob == job) _parseJob = null;
      await _parseProgressSubscription?.cancel();
      _parseProgressSubscription = null;
      _state = _copyState(working: false, parseProgress: -1);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  Future<bool> loadCustomFieldFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final session = _session;
    final scope = _appState.importVaultScopeId;
    final revision = _appState.localWebRevision;
    if (session == null || !_canWrite || _state.working) return false;
    _setWorking(true);
    final job = const TabularImportParser().parseInBackground(bytes);
    _parseJob = job;
    try {
      final document = await job.result;
      if (_parseJob != job ||
          !_canWrite ||
          scope != _appState.importVaultScopeId ||
          revision != _appState.localWebRevision) {
        return false;
      }
      session.attachCustomFields(document);
      _publish();
      return true;
    } on FormatException catch (error) {
      _setError(error.message);
      return false;
    } on ArgumentError catch (error) {
      _setError(error.message?.toString() ?? '自定义字段伴随文件无效；本机数据未改变。');
      return false;
    } on Object {
      _setError('自定义字段伴随文件无效；本机数据未改变。');
      return false;
    } finally {
      if (_parseJob == job) _parseJob = null;
      _state = _copyState(working: false);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void setCustomFieldDecision(
    int rowNumber, {
    required bool include,
    required bool replaceExisting,
    required bool sensitiveConfirmed,
  }) {
    if (!_canWrite || _state.working) return;
    _session?.setCustomFieldDecision(
      rowNumber,
      include: include,
      replaceExisting: replaceExisting,
      sensitiveConfirmed: sensitiveConfirmed,
    );
    _publish();
  }

  List<DataImportCustomFieldView> _customFieldViews() => [
    for (final row in _session?.customFieldRows ?? [])
      DataImportCustomFieldView(
        rowNumber: row.rowNumber,
        accountKey: row.accountKey,
        name: row.field.name,
        typeCode: row.field.type.code,
        sensitive: row.field.isSensitive,
        included: row.useImportedValue,
        replaceExisting: row.replaceExisting,
        confirmed: row.sensitiveConfirmed,
        conflict: _appState.accounts.any(
          (account) =>
              (_session?.snapshot.duplicateCandidates.any(
                    (candidate) =>
                        candidate.existingAccountId == account.id &&
                        _session!.snapshot.accountMapping!.drafts.any(
                          (draft) =>
                              draft.originalRowNumber ==
                                  candidate.importRowNumber &&
                              draft.accountKey == row.accountKey,
                        ),
                  ) ??
                  false) &&
              account.customFields.any(
                (field) => field.normalizedName == row.field.normalizedName,
              ),
        ),
        displayValue: row.field.isSensitive ? '••••••' : row.field.value,
      ),
  ];

  void _mapSelectedKind(ImportSessionController session) {
    final adapter = session.snapshot.selectedAdapter;
    if (adapter == null) throw StateError('No source adapter was selected.');
    if (adapter.itemKind == ImportItemKind.subscription) {
      session.mapSubscriptions(overrides: _overrides);
    } else {
      session.mapAccounts(overrides: _overrides);
    }
  }

  @override
  Future<void> updateMapping({
    required int columnIndex,
    required String? targetField,
  }) async {
    final session = _session;
    if (session == null || !_canWrite || _state.working) return;
    final target = targetField == null
        ? ImportTargetField.ignore
        : ImportTargetField.values
              .where((candidate) => candidate.name == targetField)
              .firstOrNull;
    if (target == null) {
      _setError('字段映射无效。');
      return;
    }
    _overrides[columnIndex] = target;
    try {
      _mapSelectedKind(session);
      _publish(step: DataImportWizardStep.mapping);
    } on Object {
      _setError('字段映射冲突，请核对重复目标和被排除的敏感列。');
    }
  }

  @override
  void setRowSelected(String rowId, bool selected) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null || row == null || !_canWrite) return;
    if (_isAccountRowId(rowId)) {
      session.setAccountRowSelected(row, selected);
    } else if (_isSubscriptionRowId(rowId)) {
      session.setSubscriptionRowSelected(row, selected);
    } else {
      return;
    }
    if (selected) _removedRows.remove(rowId);
    _publish();
  }

  @override
  void setMaskedPasswordConfirmed(String rowId, bool confirmed) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null ||
        row == null ||
        !_isAccountRowId(rowId) ||
        !_canWrite) {
      return;
    }
    try {
      session.setMaskedPasswordConfirmed(row, confirmed: confirmed);
      _publish();
    } on ArgumentError {
      _setError('该行没有需要确认的遮挡占位密码。');
    }
  }

  @override
  void removeRow(String rowId) {
    final row = _rowNumber(rowId);
    if (row == null) return;
    _removedRows.add(rowId);
    setRowSelected(rowId, false);
  }

  @override
  void setDuplicateResolution(
    String rowId,
    DataImportDuplicateResolution resolution,
  ) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null ||
        row == null ||
        !_isAccountRowId(rowId) ||
        !_canWrite) {
      return;
    }
    final coreResolution = switch (resolution) {
      DataImportDuplicateResolution.skip => ImportDuplicateResolution.skip,
      DataImportDuplicateResolution.mergeMissingFields =>
        ImportDuplicateResolution.fillEmptyFieldsOnly,
      DataImportDuplicateResolution.fieldByField =>
        ImportDuplicateResolution.fieldByField,
      DataImportDuplicateResolution.createAnother =>
        ImportDuplicateResolution.importAsNew,
    };
    final rowCandidates = session.snapshot.duplicateCandidates
        .where((candidate) => candidate.importRowNumber == row)
        .toList(growable: false);
    for (final candidate in rowCandidates) {
      session.setDuplicateResolution(candidate.id, coreResolution);
    }
    if (coreResolution == ImportDuplicateResolution.fieldByField) {
      for (final candidate in session.snapshot.duplicateCandidates.where(
        (candidate) => candidate.importRowNumber == row,
      )) {
        for (final field in candidate.conflictingFields) {
          if (field == 'password' ||
              candidate.useImportedField.containsKey(field)) {
            continue;
          }
          session.setDuplicateFieldChoice(
            candidate.id,
            fieldName: field,
            useImportedValue: false,
          );
        }
      }
    }
    if (coreResolution == ImportDuplicateResolution.fillEmptyFieldsOnly ||
        coreResolution == ImportDuplicateResolution.fieldByField) {
      final targets = session.snapshot.duplicateCandidates
          .where(
            (candidate) =>
                candidate.importRowNumber == row &&
                candidate.origin == ImportDuplicateOrigin.existingVault,
          )
          .map((candidate) => candidate.existingAccountId)
          .whereType<String>()
          .toSet();
      if (targets.length == 1) {
        session.setDuplicateUpdateTarget(row, targets.single);
      }
    }
    _publish();
  }

  @override
  void setDuplicateFieldChoice(
    String rowId,
    String fieldName,
    bool useImportedValue,
  ) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null ||
        row == null ||
        !_isAccountRowId(rowId) ||
        !_canWrite) {
      return;
    }
    for (final candidate in session.snapshot.duplicateCandidates.where(
      (candidate) =>
          candidate.importRowNumber == row &&
          candidate.resolution == ImportDuplicateResolution.fieldByField &&
          candidate.conflictingFields.contains(fieldName),
    )) {
      session.setDuplicateFieldChoice(
        candidate.id,
        fieldName: fieldName,
        useImportedValue: useImportedValue,
      );
    }
    _publish();
  }

  @override
  void setDuplicateUpdateTarget(String rowId, String existingAccountId) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null ||
        row == null ||
        !_isAccountRowId(rowId) ||
        !_canWrite) {
      return;
    }
    try {
      session.setDuplicateUpdateTarget(row, existingAccountId);
      _publish();
    } on ArgumentError {
      _setError('所选已有账号不再是当前重复候选。');
    }
  }

  @override
  void setSubscriptionAccountTarget(String rowId, String existingAccountId) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null ||
        row == null ||
        !_isSubscriptionRowId(rowId) ||
        !_canWrite) {
      return;
    }
    try {
      session.setSubscriptionAccountTarget(
        row,
        existingAccountId: existingAccountId,
      );
      _publish();
    } on ArgumentError {
      _setError('所选关联账号已不可用，请重新选择。');
    }
  }

  @override
  void acceptFieldSuggestion(String suggestionId) {
    final session = _session;
    if (session == null || !_canWrite) return;
    session.acceptFieldSuggestion(suggestionId);
    _publish();
  }

  @override
  void acceptAllFieldSuggestions() {
    final session = _session;
    if (session == null || !_canWrite) return;
    session.acceptAllFieldSuggestions();
    _publish();
  }

  @override
  void ignoreAllFieldSuggestions() {
    final session = _session;
    if (session == null || !_canWrite) return;
    session.ignoreAllFieldSuggestions();
    _publish();
  }

  @override
  void selectBrandSuggestion(String rowId, String brandId) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null ||
        row == null ||
        !_isAccountRowId(rowId) ||
        !_canWrite) {
      return;
    }
    session.selectBrandSuggestion(row, brandId);
    _publish();
  }

  @override
  void ignoreBrandSuggestions(String rowId) {
    final session = _session;
    final row = _rowNumber(rowId);
    if (session == null ||
        row == null ||
        !_isAccountRowId(rowId) ||
        !_canWrite) {
      return;
    }
    session.ignoreBrandSuggestions(row);
    _publish();
  }

  @override
  void setFinalConfirmation(bool confirmed) {
    _state = _copyState(finalConfirmation: confirmed, clearError: true);
    notifyListeners();
  }

  @override
  Future<void> next() async {
    if (!_canWrite || _state.working) return;
    try {
      switch (_state.step) {
        case DataImportWizardStep.source:
          _publish(step: DataImportWizardStep.file);
          return;
        case DataImportWizardStep.file:
          if (_session?.snapshot.accountMapping == null &&
              _session?.snapshot.subscriptionMapping == null) {
            _setError('请先选择并读取一个文件。');
            return;
          }
          _publish(step: DataImportWizardStep.mapping);
          return;
        case DataImportWizardStep.mapping:
          _publish(step: DataImportWizardStep.passwordPreview);
          return;
        case DataImportWizardStep.passwordPreview:
          _prepareDuplicates();
          _publish(step: DataImportWizardStep.duplicates);
          return;
        case DataImportWizardStep.duplicates:
          _buildPlan();
          if (_session?.snapshot.plan?.canCommit != true) {
            final plan = _session?.snapshot.plan;
            _setError(
              plan?.unresolvedSubscriptionAccountCount != 0
                  ? '请先为每条订阅选择本次导入的账号或保险库中的已有账号。'
                  : '仍有未处理的重复项或免费版数量限制，未进入最终确认。',
            );
            return;
          }
          _publish(step: DataImportWizardStep.confirmation);
          return;
        case DataImportWizardStep.confirmation:
        case DataImportWizardStep.result:
          return;
      }
    } on Object {
      _setError('当前步骤无法继续；请核对映射、重复项和数量限制。');
    }
  }

  void _prepareDuplicates() {
    final session = _session;
    if (session == null || session.snapshot.accountMapping == null) return;
    session.detectDuplicates(<ExistingAccountSummary>[
      for (final account in _appState.accounts)
        ExistingAccountSummary(
          id: account.id,
          platformName: account.platformName,
          loginAccount: account.loginAccount ?? '',
          phone: account.boundPhone ?? '',
          email: account.boundEmail ?? '',
          url: account.website ?? '',
          password: account.password ?? '',
          notes: account.notes ?? '',
        ),
    ]);
    for (final candidate in session.snapshot.duplicateCandidates) {
      if (!candidate.isResolved) {
        session.setDuplicateResolution(
          candidate.id,
          ImportDuplicateResolution.skip,
        );
      }
    }
  }

  void _buildPlan() {
    final session = _session;
    if (session == null) throw StateError('No import session.');
    session.buildPlan(
      quotaValidator: _validateQuota,
      isFormalSubscriptionValid: AppState.isFormalSubscriptionImportValid,
    );
    final plan = session.snapshot.plan!;
    for (final imported in plan.newAccounts) {
      mergeImportedCustomFields([], imported);
    }
    for (final update in plan.accountUpdates) {
      final existing = _appState.accounts
          .where((a) => a.id == update.existingAccountId)
          .firstOrNull;
      if (existing != null) {
        mergeImportedCustomFields(existing.customFields, update.draft);
      }
    }
  }

  ImportQuotaValidationResult _validateQuota(
    int requestedAccounts,
    int requestedSubscriptions,
  ) {
    if (_appState.productEntitlement.hasFullVersion) {
      return ImportQuotaValidationResult.unlimited(
        requestedAccounts: requestedAccounts,
        requestedSubscriptions: requestedSubscriptions,
      );
    }
    final remainingAccounts =
        EntitlementGuard.maxAccounts - _appState.accounts.length;
    final remainingSubscriptions =
        EntitlementGuard.maxSubscriptions - _appState.subscriptions.length;
    final allowed =
        requestedAccounts <= remainingAccounts &&
        requestedSubscriptions <= remainingSubscriptions;
    return ImportQuotaValidationResult(
      allowed: allowed,
      requestedAccounts: requestedAccounts,
      requestedSubscriptions: requestedSubscriptions,
      remainingAccounts: remainingAccounts < 0 ? 0 : remainingAccounts,
      remainingSubscriptions: remainingSubscriptions < 0
          ? 0
          : remainingSubscriptions,
      errorCode: allowed ? null : 'free_limit',
    );
  }

  @override
  void back() {
    if (_state.working || _state.step == DataImportWizardStep.source) return;
    _publish(step: DataImportWizardStep.values[_state.step.index - 1]);
  }

  @override
  Future<void> commit() async {
    if (!_canWrite || _state.working || !_state.finalConfirmation) return;
    final plan = _session?.snapshot.plan;
    if (plan == null || !plan.canCommit) {
      _setError('权威预览计划无效，请返回重新核对。');
      return;
    }
    final mapping = _session?.snapshot.accountMapping;
    final maskedCount =
        mapping?.drafts.where((d) => d.passwordLooksMasked).length ?? 0;
    final emptyCount = mapping?.drafts.where((d) => !d.hasPassword).length ?? 0;
    final unmappedCount = mapping?.unmappedColumns.length ?? 0;
    final preservedCount = plan.accountUpdates.where((update) {
      final previous = _appState.accounts
          .where((a) => a.id == update.existingAccountId)
          .firstOrNull;
      if (previous?.password == null || previous!.password!.isEmpty) {
        return false;
      }
      return !update.draft.hasImportablePassword ||
          update.resolution == ImportDuplicateResolution.fillEmptyFieldsOnly ||
          update.useImportedField['password'] != true ||
          update.draft.password == previous.password;
    }).length;
    _setWorking(true);
    try {
      final result = await _appState.commitBatchImport(plan);
      if (!result.success) {
        _setError(_commitFailureMessage(result.failureCode));
        return;
      }
      _state = DataImportUiState(
        step: DataImportWizardStep.result,
        canWrite: _canWrite,
        commitSummary: DataImportCommitSummary(
          importedAccounts: result.addedAccountCount,
          formalSubscriptions: result.formalSubscriptionCount,
          pendingSubscriptionDrafts: result.pendingSubscriptionDraftCount,
          mergedRecords: result.updatedAccountCount,
          skippedRecords: result.skippedCount,
          unsupportedRecords: result.unsupportedItemCount,
          rollbackAvailable: result.rollbackAvailable,
          preservedPasswords: preservedCount,
          maskedPasswords: maskedCount,
          emptyPasswords: emptyCount,
          unmappedColumns: unmappedCount,
          unresolvedDuplicates: plan.unresolvedDuplicateCount,
        ),
      );
      _session?.clear();
      _sensitiveDeadline?.cancel();
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  String _commitFailureMessage(String? code) => switch (code) {
    'stale_preview' => '保险库数据已变化，权威预览已失效；请重新导入文件。',
    'quota_changed' => '免费版可用数量已变化，本次整批未写入。',
    'vault_not_writable' => '保险库已锁定或处于订阅只读视图，本次整批未写入。',
    'storage_failed' => '本机加密写入失败，本次整批未提交。',
    _ => '批量导入校验失败，本次整批未写入。',
  };

  @override
  void cancelParsing() {
    final job = _parseJob;
    _parseJob = null;
    job?.cancel();
    unawaited(_parseProgressSubscription?.cancel());
    _parseProgressSubscription = null;
    if (!_disposed) {
      _state = _copyState(working: false, parseProgress: -1, clearError: true);
      notifyListeners();
    }
  }

  @override
  void clearSensitiveMemory() {
    _sensitiveDeadline?.cancel();
    _sensitiveDeadline = null;
    cancelParsing();
    _sourceMismatch = false;
    _session?.clear();
    _overrides.clear();
    _removedRows.clear();
    _fileName = null;
    _fileSize = 0;
    _additionalFileName = null;
    _additionalFileSize = 0;
    _state = DataImportUiState(
      canWrite: _canWrite,
      selectedSourceId: _selectedSourceId,
    );
    if (!_disposed) notifyListeners();
  }

  void _handleAppStateChanged() {
    if (!_canWrite) {
      clearSensitiveMemory();
      _state = DataImportUiState(
        canWrite: false,
        selectedSourceId: _selectedSourceId,
        errorMessage: '保险库状态已变化，迁移内存已清空。',
      );
      if (!_disposed) notifyListeners();
    } else if (!_state.canWrite) {
      _state = _copyState(canWrite: true, clearError: true);
      if (!_disposed) notifyListeners();
    }
  }

  void _publish({DataImportWizardStep? step}) {
    final snapshot = _session?.snapshot;
    final document = snapshot?.document;
    _state = DataImportUiState(
      step: step ?? _state.step,
      working: _state.working,
      parseProgress: _state.parseProgress,
      canWrite: _canWrite,
      selectedSourceId: _selectedSourceId,
      sourceMismatch: _sourceMismatch,
      fileName: _fileName,
      fileSize: _fileSize,
      additionalFileName: _additionalFileName,
      additionalFileSize: _additionalFileSize,
      detectedFormat: document == null
          ? null
          : '${document.encoding.name} · ${_delimiterLabel(document.delimiter)} · '
                '${snapshot!.selectedAdapter?.displayName ?? ''}',
      mappings: _mappingRows(snapshot),
      customFields: _customFieldViews(),
      rows: _previewRows(snapshot),
      warnings: _warnings(snapshot),
      fieldSuggestions: _fieldSuggestionViews(snapshot),
      finalConfirmation: _state.finalConfirmation,
      planSummary: snapshot?.plan == null
          ? null
          : DataImportPlanSummary(
              newAccounts: snapshot!.plan!.newAccounts.length,
              updatedAccounts: snapshot.plan!.accountUpdates.length,
              skippedAccounts: snapshot.plan!.skippedAccounts.length,
              formalSubscriptions: snapshot.plan!.formalSubscriptions.length,
              pendingSubscriptionDrafts:
                  snapshot.plan!.pendingSubscriptionDrafts.length,
              unsupportedItems: snapshot.plan!.unsupportedItemCount,
              quotaAllowed: snapshot.plan!.quota.allowed,
              remainingAccounts: snapshot.plan!.quota.remainingAccounts,
              remainingSubscriptions:
                  snapshot.plan!.quota.remainingSubscriptions,
            ),
    );
    notifyListeners();
  }

  List<DataImportColumnMapping> _mappingRows(ImportSessionSnapshot? snapshot) {
    final document = snapshot?.document;
    final adapter = snapshot?.selectedAdapter;
    if (document == null || adapter == null) {
      return const <DataImportColumnMapping>[];
    }
    final excluded = <int>{
      ...?snapshot?.accountMapping?.excludedSensitiveColumns.map(
        (column) => column.index,
      ),
    };
    final available = adapter.itemKind == ImportItemKind.subscription
        ? const <ImportTargetField>[
            ImportTargetField.accountKey,
            ImportTargetField.planName,
            ImportTargetField.amount,
            ImportTargetField.currency,
            ImportTargetField.billingCycle,
            ImportTargetField.subscriptionStartDate,
            ImportTargetField.nextRenewalDate,
            ImportTargetField.autoRenew,
            ImportTargetField.paymentMethod,
            ImportTargetField.reminderDays,
            ImportTargetField.notes,
          ]
        : const <ImportTargetField>[
            ImportTargetField.platformName,
            ImportTargetField.loginAccount,
            ImportTargetField.phone,
            ImportTargetField.email,
            ImportTargetField.password,
            ImportTargetField.url,
            ImportTargetField.notes,
            ImportTargetField.accountKey,
          ];
    return List<DataImportColumnMapping>.unmodifiable(<DataImportColumnMapping>[
      for (var index = 0; index < document.headers.length; index += 1)
        DataImportColumnMapping(
          columnIndex: index,
          sourceLabel: document.headers[index],
          targetField: excluded.contains(index)
              ? null
              : _mappedTargetName(adapter, document.headers[index], index),
          availableTargets: <String>[
            if (isBrowserPasswordSourceId(adapter.id))
              adapter
                  .defaultMappings[normalizeImportHeader(
                    document.headers[index],
                  )]!
                  .name
            else
              for (final target in available) target.name,
          ],
          excludedAsSensitive: excluded.contains(index),
        ),
    ]);
  }

  String? _mappedTargetName(
    ImportSourceAdapter adapter,
    String header,
    int index,
  ) {
    final target =
        _overrides[index] ??
        adapter.defaultMappings[normalizeImportHeader(header)] ??
        ImportTargetField.ignore;
    return target == ImportTargetField.ignore ? null : target.name;
  }

  List<DataImportPreviewRow> _previewRows(ImportSessionSnapshot? snapshot) {
    if (snapshot == null) return const <DataImportPreviewRow>[];
    final duplicatesByRow = <int, List<ImportDuplicateCandidate>>{};
    for (final candidate in snapshot.duplicateCandidates) {
      duplicatesByRow
          .putIfAbsent(
            candidate.importRowNumber,
            () => <ImportDuplicateCandidate>[],
          )
          .add(candidate);
    }
    String duplicateTargetLabel(String id) {
      final account = _appState.accounts
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      if (account == null) return '已有账号';
      return <String>[
        account.platformName,
        account.loginAccount ?? '',
      ].where((value) => value.isNotEmpty).join(' · ');
    }

    final selectedImportedAccountKeys =
        (snapshot.accountMapping?.drafts ?? const <AccountImportDraft>[])
            .where(
              (draft) => snapshot.selectedAccountRows.contains(
                draft.originalRowNumber,
              ),
            )
            .map((draft) => draft.accountKey)
            .whereType<String>()
            .toSet();
    Map<String, String> duplicateTargetOptions(int rowNumber) {
      final result = <String, String>{};
      for (final candidate
          in duplicatesByRow[rowNumber] ?? const <ImportDuplicateCandidate>[]) {
        final id = candidate.existingAccountId;
        if (id != null) result[id] = duplicateTargetLabel(id);
      }
      return result;
    }

    Map<String, DataImportFieldComparison> fieldComparisons(
      AccountImportDraft draft,
    ) {
      final candidates =
          duplicatesByRow[draft.originalRowNumber] ??
          const <ImportDuplicateCandidate>[];
      final explicitTarget =
          snapshot.selectedDuplicateTargets[draft.originalRowNumber];
      final targetIds = candidates
          .where(
            (candidate) =>
                candidate.origin == ImportDuplicateOrigin.existingVault,
          )
          .map((candidate) => candidate.existingAccountId)
          .whereType<String>()
          .toSet();
      final targetId =
          explicitTarget ?? (targetIds.length == 1 ? targetIds.single : null);
      if (targetId == null) {
        return const <String, DataImportFieldComparison>{};
      }
      final existing = _appState.accounts
          .where((account) => account.id == targetId)
          .firstOrNull;
      final duplicate = candidates
          .where((candidate) => candidate.existingAccountId == targetId)
          .firstOrNull;
      if (existing == null || duplicate == null) {
        return const <String, DataImportFieldComparison>{};
      }
      final passwordComparison = switch (duplicate.passwordComparison) {
        ImportPasswordComparison.bothEmpty =>
          DataImportPasswordComparison.bothEmpty,
        ImportPasswordComparison.same => DataImportPasswordComparison.same,
        ImportPasswordComparison.different =>
          DataImportPasswordComparison.different,
        ImportPasswordComparison.existingEmpty =>
          DataImportPasswordComparison.existingEmpty,
        ImportPasswordComparison.importedEmpty =>
          DataImportPasswordComparison.importedEmpty,
      };
      return <String, DataImportFieldComparison>{
        'platformName': DataImportFieldComparison(
          fieldName: 'platformName',
          existingValue: existing.platformName,
          importedValue: draft.platformName,
        ),
        'loginAccount': DataImportFieldComparison(
          fieldName: 'loginAccount',
          existingValue: existing.loginAccount ?? '',
          importedValue: draft.loginAccount,
        ),
        'phone': DataImportFieldComparison(
          fieldName: 'phone',
          existingValue: existing.boundPhone ?? '',
          importedValue: draft.phone,
        ),
        'email': DataImportFieldComparison(
          fieldName: 'email',
          existingValue: existing.boundEmail ?? '',
          importedValue: draft.email,
        ),
        'url': DataImportFieldComparison(
          fieldName: 'url',
          existingValue: existing.website ?? '',
          importedValue: draft.url,
        ),
        'notes': DataImportFieldComparison(
          fieldName: 'notes',
          existingValue: existing.notes ?? '',
          importedValue: draft.notes,
        ),
        'password': DataImportFieldComparison(
          fieldName: 'password',
          passwordComparison: passwordComparison,
        ),
      };
    }

    return List<DataImportPreviewRow>.unmodifiable(<DataImportPreviewRow>[
      for (final draft
          in snapshot.accountMapping?.drafts ?? const <AccountImportDraft>[])
        if (!_removedRows.contains('account-row-${draft.originalRowNumber}'))
          DataImportPreviewRow(
            id: 'account-row-${draft.originalRowNumber}',
            kind: DataImportRecordKind.account,
            title: draft.platformName.isEmpty
                ? '第 ${draft.originalRowNumber} 行账号'
                : draft.platformName,
            titleTranslationKey: draft.platformName.isEmpty
                ? '第 {row} 行账号'
                : null,
            titleTranslationValues: <String, Object?>{
              'row': draft.originalRowNumber,
            },
            subtitle: <String>[
              draft.loginAccount,
              draft.email,
              _brandLabels[snapshot.selectedBrandSuggestions[draft
                          .originalRowNumber] ??
                      draft.brandSuggestion] ??
                  '',
            ].where((value) => value.isNotEmpty).join(' · '),
            passwordStatus:
                draft.passwordLooksMasked &&
                    !snapshot.confirmedMaskedPasswordRows.contains(
                      draft.originalRowNumber,
                    )
                ? (isBrowserPasswordSourceId(draft.adapterId)
                      ? DataImportPasswordStatus.excluded
                      : DataImportPasswordStatus.maskedReviewRequired)
                : draft.hasPassword
                ? DataImportPasswordStatus.encryptedForImport
                : DataImportPasswordStatus.absent,
            maskedPasswordConfirmed: snapshot.confirmedMaskedPasswordRows
                .contains(draft.originalRowNumber),
            selected: snapshot.selectedAccountRows.contains(
              draft.originalRowNumber,
            ),
            issue: draft.validationState == ImportValidationState.invalid
                ? '该行缺少账号必要字段或包含无效值。'
                : null,
            issueTranslationKey:
                draft.validationState == ImportValidationState.invalid
                ? '该行缺少账号必要字段或包含无效值。'
                : null,
            duplicateDescription:
                duplicatesByRow[draft.originalRowNumber]?.isNotEmpty == true
                ? '发现 ${duplicatesByRow[draft.originalRowNumber]!.length} 个疑似重复项。'
                : null,
            duplicateDescriptionTranslationKey:
                duplicatesByRow[draft.originalRowNumber]?.isNotEmpty == true
                ? '发现 {count} 个疑似重复项。'
                : null,
            duplicateDescriptionTranslationValues: <String, Object?>{
              'count': duplicatesByRow[draft.originalRowNumber]?.length ?? 0,
            },
            duplicateResolution: _uiResolution(
              duplicatesByRow[draft.originalRowNumber]?.firstOrNull?.resolution,
            ),
            conflictingFields: <String>{
              for (final candidate
                  in duplicatesByRow[draft.originalRowNumber] ??
                      const <ImportDuplicateCandidate>[])
                ...candidate.conflictingFields,
            },
            fieldChoices: <String, bool>{
              for (final candidate
                  in duplicatesByRow[draft.originalRowNumber] ??
                      const <ImportDuplicateCandidate>[])
                ...candidate.useImportedField,
            },
            fieldComparisons: fieldComparisons(draft),
            duplicateTargetOptions: duplicateTargetOptions(
              draft.originalRowNumber,
            ),
            selectedDuplicateTargetId:
                snapshot.selectedDuplicateTargets[draft.originalRowNumber],
            brandSuggestionOptions: <String, String>{
              for (final id in draft.brandSuggestionCandidates)
                id: _brandLabels[id] ?? id,
            },
            selectedBrandSuggestionId:
                snapshot.selectedBrandSuggestions[draft.originalRowNumber] ??
                draft.brandSuggestion,
            brandSuggestionsIgnored: snapshot.ignoredBrandSuggestionRows
                .contains(draft.originalRowNumber),
          ),
      for (final draft
          in snapshot.subscriptionMapping?.drafts ??
              const <SubscriptionImportDraft>[])
        if (!_removedRows.contains(
          'subscription-row-${draft.originalRowNumber}',
        ))
          DataImportPreviewRow(
            id: 'subscription-row-${draft.originalRowNumber}',
            kind: DataImportRecordKind.subscription,
            title: draft.planName.isEmpty
                ? '第 ${draft.originalRowNumber} 行订阅草稿'
                : draft.planName,
            titleTranslationKey: draft.planName.isEmpty
                ? '第 {row} 行订阅草稿'
                : null,
            titleTranslationValues: <String, Object?>{
              'row': draft.originalRowNumber,
            },
            subtitle: <String>[
              draft.accountKey,
              draft.amount,
              draft.currency,
              draft.nextRenewalDate,
            ].where((value) => value.isNotEmpty).join(' · '),
            passwordStatus: DataImportPasswordStatus.absent,
            selected: snapshot.selectedSubscriptionRows.contains(
              draft.originalRowNumber,
            ),
            subscriptionTargetOptions: <String, String>{
              for (final account in _appState.accounts)
                account.id: <String>[
                  account.platformName,
                  account.loginAccount ?? '',
                ].where((value) => value.isNotEmpty).join(' · '),
            },
            selectedSubscriptionTargetId: snapshot
                .subscriptionAccountTargets[draft.originalRowNumber]
                ?.existingAccountId,
            subscriptionTargetRequired:
                snapshot.subscriptionAccountTargets[draft.originalRowNumber] ==
                    null &&
                (draft.accountKeyWasGenerated ||
                    !selectedImportedAccountKeys.contains(draft.accountKey)),
            issue:
                snapshot.subscriptionAccountTargets[draft.originalRowNumber] ==
                        null &&
                    (draft.accountKeyWasGenerated ||
                        !selectedImportedAccountKeys.contains(draft.accountKey))
                ? '请选择关联账号，或先追加含相同 account_key 的账号表。'
                : null,
            issueTranslationKey:
                snapshot.subscriptionAccountTargets[draft.originalRowNumber] ==
                        null &&
                    (draft.accountKeyWasGenerated ||
                        !selectedImportedAccountKeys.contains(draft.accountKey))
                ? '请选择关联账号，或先追加含相同 account_key 的账号表。'
                : null,
          ),
    ]);
  }

  DataImportDuplicateResolution _uiResolution(
    ImportDuplicateResolution? resolution,
  ) => switch (resolution) {
    ImportDuplicateResolution.fillEmptyFieldsOnly =>
      DataImportDuplicateResolution.mergeMissingFields,
    ImportDuplicateResolution.fieldByField =>
      DataImportDuplicateResolution.fieldByField,
    ImportDuplicateResolution.importAsNew =>
      DataImportDuplicateResolution.createAnother,
    _ => DataImportDuplicateResolution.skip,
  };

  List<String> _warnings(ImportSessionSnapshot? snapshot) => <String>[
    if ((snapshot?.accountMapping?.drafts.any(
              (d) => _appState.hasSimilarTrashAccount(d.platformName),
            ) ??
            false) ||
        (snapshot?.subscriptionMapping?.drafts.any(
              (d) => _appState.hasSimilarTrashSubscription(d.planName),
            ) ??
            false))
      '回收站中有相似记录，可先恢复；这些记录不会阻止本次导入。',

    for (final issue in snapshot?.document?.issues ?? const <ImportIssue>[])
      issue.message,
    for (final issue
        in snapshot?.accountMapping?.issues ?? const <ImportIssue>[])
      issue.message,
    for (final issue
        in snapshot?.subscriptionMapping?.issues ?? const <ImportIssue>[])
      issue.message,
  ];

  List<DataImportFieldSuggestionView> _fieldSuggestionViews(
    ImportSessionSnapshot? snapshot,
  ) => <DataImportFieldSuggestionView>[
    for (final suggestion
        in snapshot?.fieldSuggestions ?? const <ImportFieldSuggestion>[])
      DataImportFieldSuggestionView(
        id: suggestion.id,
        rowId: 'account-row-${suggestion.rowNumber}',
        targetField: suggestion.targetField.name,
        value: suggestion.value,
        accepted: suggestion.accepted,
      ),
  ];

  int? _rowNumber(String rowId) {
    final match = RegExp(
      r'^(?:account|subscription)-row-(\d+)$',
    ).firstMatch(rowId);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  bool _isAccountRowId(String rowId) => rowId.startsWith('account-row-');

  bool _isSubscriptionRowId(String rowId) =>
      rowId.startsWith('subscription-row-');

  String _delimiterLabel(String delimiter) => switch (delimiter) {
    '\t' => 'TSV',
    ';' => '分号',
    ',' => 'CSV',
    _ => delimiter,
  };

  void _setWorking(bool value) {
    _state = _copyState(working: value, clearError: value);
    if (!_disposed) notifyListeners();
  }

  void _setError(String message) {
    _state = _copyState(errorMessage: message, working: false);
    if (!_disposed) notifyListeners();
  }

  DataImportUiState _copyState({
    DataImportWizardStep? step,
    bool? working,
    double? parseProgress,
    bool? canWrite,
    String? selectedSourceId,
    bool? finalConfirmation,
    String? errorMessage,
    bool clearError = false,
  }) => DataImportUiState(
    step: step ?? _state.step,
    working: working ?? _state.working,
    parseProgress: parseProgress == -1
        ? null
        : parseProgress ?? _state.parseProgress,
    canWrite: canWrite ?? _state.canWrite,
    selectedSourceId: selectedSourceId ?? _state.selectedSourceId,
    sourceMismatch: _sourceMismatch,
    fileName: _state.fileName,
    fileSize: _state.fileSize,
    additionalFileName: _state.additionalFileName,
    additionalFileSize: _state.additionalFileSize,
    detectedFormat: _state.detectedFormat,
    mappings: _state.mappings,
    customFields: _state.customFields,
    rows: _state.rows,
    warnings: _state.warnings,
    fieldSuggestions: _state.fieldSuggestions,
    finalConfirmation: finalConfirmation ?? _state.finalConfirmation,
    errorMessage: clearError ? null : errorMessage ?? _state.errorMessage,
    commitSummary: _state.commitSummary,
    planSummary: _state.planSummary,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sensitiveDeadline?.cancel();
    _appState.removeListener(_handleAppStateChanged);
    _parseJob?.cancel();
    unawaited(_parseProgressSubscription?.cancel());
    _session?.clear();
    _session = null;
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
