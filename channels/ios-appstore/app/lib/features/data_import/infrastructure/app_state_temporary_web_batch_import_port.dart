import 'dart:convert';
import 'dart:math';

import '../../../app/app_state.dart';
import '../../../core/branding/brand_catalog_loader.dart';
import '../../../core/branding/brand_matcher.dart';
import '../../../core/data_import/data_import.dart';
import '../../../core/entitlements/entitlement_guard.dart';
import '../../../core/entitlements/entitlement_model.dart';
import '../../../core/temporary_web/temporary_web_batch_import_port.dart';

/// App-layer bridge used by the encrypted temporary page.
///
/// The browser only receives a redacted preview. The parsed document, imported
/// passwords and authoritative [ImportPlan] stay in this in-memory port until
/// the phone approval callback invokes [commit].
final class AppStateTemporaryWebBatchImportPort
    implements TemporaryWebBatchImportPort {
  AppStateTemporaryWebBatchImportPort({required this._appState});

  final AppState _appState;
  final Random _random = Random.secure();
  ImportSessionController? _session;
  String? _previewToken;
  int? _previewRevision;
  ImportPlan? _preparedPlan;
  String? _preparedApprovalToken;
  TabularParseJob? _parseJob;
  List<TemporaryWebBatchVisibleAccount> _visibleAccounts =
      const <TemporaryWebBatchVisibleAccount>[];
  Map<String, String> _visibleAccountTargets = const <String, String>{};
  final Map<String, String> _documentFileNames = <String, String>{};
  final Map<String, String> _documentSourceLabels = <String, String>{};
  final Map<String, Map<int, ImportTargetField>> _documentMappingOverrides =
      <String, Map<int, ImportTargetField>>{};
  String? _activeDocumentKind;

  @override
  bool get isAvailable =>
      _appState.isEligibleForTemporaryWebSession &&
      _appState.importVaultScopeId != null;

  @override
  Future<TemporaryWebBatchImportPreview> preview(
    TemporaryWebBatchImportRequest request,
  ) async {
    final visibleIds = <String>{
      for (final account in request.visibleAccounts) account.id,
    };
    if (visibleIds.length != request.visibleAccounts.length ||
        visibleIds.length != request.visibleAccountTargets.length ||
        !visibleIds.containsAll(request.visibleAccountTargets.keys)) {
      clearSensitiveMemory();
      throw const FormatException('批量预览授权范围无效。');
    }
    final scopeId = _appState.importVaultScopeId;
    if (!isAvailable ||
        scopeId == null ||
        request.expectedRevision != _appState.localWebRevision) {
      clearSensitiveMemory();
      throw const FormatException('保险库状态已变化，请重新生成权威预览。');
    }
    if (_session != null &&
        (_previewRevision != request.expectedRevision ||
            _session!.snapshot.vaultScopeId != scopeId)) {
      clearSensitiveMemory();
      throw const FormatException('保险库状态已变化，请重新生成权威预览。');
    }
    if (request.bytes.isEmpty ||
        request.bytes.length > temporaryWebMaximumBatchImportBytes) {
      throw const FormatException('批量文件大小无效。');
    }
    final catalogFuture = const CardockBrandCatalogLoader().load();
    final parseJob = const TabularImportParser().parseInBackground(
      request.bytes,
      options: const TabularParseOptions(
        limits: TabularParseLimits(
          maximumFileBytes: temporaryWebMaximumBatchImportBytes,
          maximumDataRows: 5000,
        ),
      ),
    );
    _parseJob = parseJob;
    late final TabularDocument document;
    try {
      document = await parseJob.result;
    } on TabularParseCancelledException {
      throw const FormatException('批量文件解析已取消。');
    } on TabularParseException catch (error) {
      throw TemporaryWebBatchImportException(
        code: 'tabular_${error.code.name}',
        message: _tabularParseFailureMessage(error.code),
      );
    } on StateError {
      throw const TemporaryWebBatchImportException(
        code: 'tabular_background_failed',
        message: '手机端后台解析未完成，请重新选择文件；若仍失败，请结束并重新开启本次临时网页连接。',
      );
    } finally {
      if (identical(_parseJob, parseJob)) _parseJob = null;
    }
    final catalog = await catalogFuture;
    if (!isAvailable ||
        request.expectedRevision != _appState.localWebRevision ||
        scopeId != _appState.importVaultScopeId) {
      throw const FormatException('保险库状态已变化，请重新生成权威预览。');
    }
    final matcher = CardockBrandMatcher(catalog);
    final candidate = _newImportSession(matcher);
    candidate.loadParsedDocument(
      document,
      vaultScopeId: scopeId,
      expectedVaultRevision: request.expectedRevision,
    );
    if (request.sourceId != 'auto') candidate.selectAdapter(request.sourceId);
    final adapter = candidate.snapshot.selectedAdapter;
    if (adapter == null || !adapter.enabled || !adapter.verified) {
      candidate.clear();
      throw const FormatException('所选来源尚未完成格式验证。');
    }
    if (adapter.itemKind == ImportItemKind.subscription) {
      candidate.mapSubscriptions();
    } else {
      candidate.mapAccounts();
    }

    final kind = adapter.itemKind == ImportItemKind.subscription
        ? 'subscription'
        : 'account';
    final existingSession = _session;
    final session = existingSession ?? candidate;
    if (existingSession != null) {
      if (kind == 'subscription') {
        session.appendSubscriptionDocument(document, adapterId: adapter.id);
      } else {
        session.appendAccountDocument(document, adapterId: adapter.id);
      }
      candidate.clear();
    }
    if (session.snapshot.accountMapping != null) {
      session.detectDuplicates(
        _previewExistingAccounts(request.visibleAccounts),
      );
      for (final duplicate in session.snapshot.duplicateCandidates) {
        session.setDuplicateResolution(
          duplicate.id,
          ImportDuplicateResolution.skip,
        );
      }
    }

    if (!isAvailable ||
        request.expectedRevision != _appState.localWebRevision ||
        scopeId != _appState.importVaultScopeId) {
      session.clear();
      throw const FormatException('保险库状态已变化，请重新生成权威预览。');
    }
    final token = _newToken();
    _visibleAccounts = List<TemporaryWebBatchVisibleAccount>.unmodifiable(
      request.visibleAccounts,
    );
    _visibleAccountTargets = Map<String, String>.unmodifiable(
      request.visibleAccountTargets,
    );
    _documentFileNames[kind] = request.fileName;
    _documentSourceLabels[kind] = adapter.displayName;
    _documentMappingOverrides[kind] = <int, ImportTargetField>{};
    _activeDocumentKind = kind;
    _session = session;
    _previewToken = token;
    _previewRevision = request.expectedRevision;
    return _previewFor(session, token, request.expectedRevision);
  }

  @override
  Future<TemporaryWebBatchImportPreview> revisePreview(
    TemporaryWebBatchRevisionRequest request,
  ) async {
    final session = _session;
    final scopeId = _appState.importVaultScopeId;
    if (!isAvailable ||
        session == null ||
        scopeId == null ||
        request.previewToken != _previewToken ||
        request.expectedRevision != _previewRevision ||
        request.expectedRevision != _appState.localWebRevision) {
      clearSensitiveMemory();
      throw const TemporaryWebBatchImportException(
        code: 'stale_preview',
        message: '权威预览已失效，请重新选择文件生成预览。',
      );
    }
    try {
      final activateKind = request.activateDocumentKind;
      if (activateKind != null) {
        if (!const <String>{'account', 'subscription'}.contains(activateKind) ||
            request.removeDocumentKind != null ||
            request.mappingOverrides.isNotEmpty ||
            request.rowPatches.isNotEmpty ||
            request.defaultValues.isNotEmpty) {
          throw const FormatException('切换当前编辑文件请求无效。');
        }
        if (activateKind == 'account') {
          session.activateAccountDocument();
        } else {
          session.activateSubscriptionDocument();
        }
        _activeDocumentKind = activateKind;
        final token = _newToken();
        _previewToken = token;
        _previewRevision = request.expectedRevision;
        return _previewFor(session, token, request.expectedRevision);
      }
      final removeKind = request.removeDocumentKind;
      if (removeKind != null) {
        if (!const <String>{'account', 'subscription'}.contains(removeKind) ||
            request.mappingOverrides.isNotEmpty ||
            request.rowPatches.isNotEmpty ||
            request.defaultValues.isNotEmpty) {
          throw const FormatException('移除文件请求无效。');
        }
        final snapshot = session.snapshot;
        if (removeKind == 'account') {
          if (snapshot.accountDocument == null) {
            throw const FormatException('账号文件已不存在。');
          }
          session.removeAccountDocument();
        } else {
          if (snapshot.subscriptionDocument == null) {
            throw const FormatException('订阅文件已不存在。');
          }
          session.removeSubscriptionDocument();
        }
        _documentFileNames.remove(removeKind);
        _documentSourceLabels.remove(removeKind);
        _documentMappingOverrides.remove(removeKind);
        _activeDocumentKind = session.snapshot.subscriptionDocument != null
            ? 'subscription'
            : session.snapshot.accountDocument != null
            ? 'account'
            : null;
        final token = _newToken();
        _previewToken = token;
        _previewRevision = request.expectedRevision;
        return _previewFor(session, token, request.expectedRevision);
      }
      final overrides = <int, ImportTargetField>{};
      for (final entry in request.mappingOverrides.entries) {
        final targetName = entry.value;
        final target = targetName == null
            ? ImportTargetField.ignore
            : ImportTargetField.values
                  .where((candidate) => candidate.name == targetName)
                  .firstOrNull;
        if (target == null) throw const FormatException('字段映射决议无效。');
        overrides[entry.key] = target;
      }
      final adapter = session.snapshot.selectedAdapter;
      if (adapter == null) throw const FormatException('来源适配器已失效。');
      final kind = adapter.itemKind == ImportItemKind.subscription
          ? 'subscription'
          : 'account';
      final effectiveOverrides = <int, ImportTargetField>{
        ...?_documentMappingOverrides[kind],
        ...overrides,
      };
      if (adapter.itemKind == ImportItemKind.subscription) {
        session.mapSubscriptions(overrides: effectiveOverrides);
      } else {
        session.mapAccounts(overrides: effectiveOverrides);
      }

      if (request.rowPatches.isNotEmpty || request.defaultValues.isNotEmpty) {
        final canonical = _canonicalEditedDocument(
          session.snapshot,
          rowPatches: request.rowPatches,
          defaultValues: request.defaultValues,
        );
        final isSubscription = adapter.itemKind == ImportItemKind.subscription;
        if (isSubscription) {
          session.appendSubscriptionDocument(
            canonical,
            adapterId: 'cardock_subscriptions_template',
          );
          _activeDocumentKind = 'subscription';
          _documentSourceLabels['subscription'] = 'Cardock 订阅模板';
          _documentMappingOverrides['subscription'] =
              <int, ImportTargetField>{};
        } else {
          session.appendAccountDocument(
            canonical,
            adapterId: 'cardock_accounts_template',
          );
          _activeDocumentKind = 'account';
          _documentSourceLabels['account'] = 'Cardock 账号模板';
          _documentMappingOverrides['account'] = <int, ImportTargetField>{};
        }
      } else {
        _documentMappingOverrides[kind] = effectiveOverrides;
      }
      if (session.snapshot.accountMapping != null) {
        session.detectDuplicates(_previewExistingAccounts(_visibleAccounts));
        for (final candidate in session.snapshot.duplicateCandidates) {
          session.setDuplicateResolution(
            candidate.id,
            ImportDuplicateResolution.skip,
          );
        }
      }
      if (!isAvailable ||
          scopeId != _appState.importVaultScopeId ||
          request.expectedRevision != _appState.localWebRevision) {
        throw const FormatException('保险库状态已变化，请重新生成权威预览。');
      }
      final token = _newToken();
      _previewToken = token;
      _previewRevision = request.expectedRevision;
      return _previewFor(session, token, request.expectedRevision);
    } on Object {
      clearSensitiveMemory();
      rethrow;
    }
  }

  @override
  Future<TemporaryWebBatchPreparedCommit> prepareCommit(
    TemporaryWebBatchCommitRequest request,
  ) async {
    final session = _session;
    final token = _previewToken;
    final previewRevision = _previewRevision;
    if (!isAvailable ||
        session == null ||
        token == null ||
        request.previewToken != token ||
        request.expectedRevision != previewRevision ||
        request.expectedRevision != _appState.localWebRevision) {
      clearSensitiveMemory();
      throw const TemporaryWebBatchImportException(
        code: 'stale_preview',
        message: '权威预览已失效，请重新选择文件生成预览。',
      );
    }

    try {
      final snapshot = session.snapshot;
      final validIds = <String>{
        for (final draft
            in snapshot.accountMapping?.drafts ?? const <AccountImportDraft>[])
          _accountRowId(draft.originalRowNumber),
        for (final draft
            in snapshot.subscriptionMapping?.drafts ??
                const <SubscriptionImportDraft>[])
          _subscriptionRowId(draft.originalRowNumber),
      };
      if (request.selectedRowIds.isEmpty ||
          !validIds.containsAll(request.selectedRowIds)) {
        throw const FormatException('所选批量记录无效。');
      }
      if (!request.selectedRowIds.containsAll(
        request.subscriptionAccountTargets.keys,
      )) {
        throw const FormatException('订阅关联账号决议无效。');
      }

      for (final draft
          in snapshot.accountMapping?.drafts ?? const <AccountImportDraft>[]) {
        final selected = request.selectedRowIds.contains(
          _accountRowId(draft.originalRowNumber),
        );
        if (selected &&
            draft.validationState == ImportValidationState.invalid) {
          throw const FormatException('所选记录仍有阻断问题。');
        }
        session.setAccountRowSelected(draft.originalRowNumber, selected);
      }
      for (final draft
          in snapshot.subscriptionMapping?.drafts ??
              const <SubscriptionImportDraft>[]) {
        final rowId = _subscriptionRowId(draft.originalRowNumber);
        session.setSubscriptionRowSelected(
          draft.originalRowNumber,
          request.selectedRowIds.contains(rowId),
        );
        final existingAccountId = request.subscriptionAccountTargets[rowId];
        if (existingAccountId != null) {
          if (!_visibleAccountTargets.containsKey(existingAccountId)) {
            throw const FormatException('订阅关联账号不在本次网页授权可见范围内。');
          }
          if (!_appState.accounts.any(
            (account) => account.id == existingAccountId,
          )) {
            throw const FormatException('订阅关联账号已不可用。');
          }
          session.setSubscriptionAccountTarget(
            draft.originalRowNumber,
            existingAccountId: existingAccountId,
          );
        }
      }

      if (snapshot.accountMapping != null) {
        session.detectDuplicates(_existingAccounts());
        for (final candidate in session.snapshot.duplicateCandidates) {
          final rowId = _accountRowId(candidate.importRowNumber);
          if (!request.selectedRowIds.contains(rowId)) continue;
          final requested = request.duplicateResolutions[rowId];
          final resolution = switch (requested) {
            'skip' => ImportDuplicateResolution.skip,
            'fillEmptyFieldsOnly' =>
              ImportDuplicateResolution.fillEmptyFieldsOnly,
            'importAsNew' => ImportDuplicateResolution.importAsNew,
            _ => throw const FormatException('重复项处理决议无效。'),
          };
          session.setDuplicateResolution(candidate.id, resolution);
        }
      }
      session.buildPlan(
        quotaValidator: _validateQuota,
        isFormalSubscriptionValid: AppState.isFormalSubscriptionImportValid,
      );
      final plan = session.snapshot.plan;
      if (plan == null || !plan.canCommit) {
        final (code, message) = switch (plan) {
          ImportPlan(unresolvedBrandSuggestionCount: > 0) => (
            'brand_selection_required',
            '平台名称匹配到多个品牌，请先处理品牌建议。',
          ),
          ImportPlan(quota: final quota) when !quota.allowed => (
            'quota_changed',
            '免费版可用数量不足，本次整批未写入。',
          ),
          ImportPlan(hasWriteOperations: false) => (
            'no_import_changes',
            '所选记录均已跳过，没有可提交的新增或更新。',
          ),
          _ => ('invalid_plan', '批量导入计划仍有阻断问题。'),
        };
        throw TemporaryWebBatchImportException(code: code, message: message);
      }
      final approvalToken = _newToken();
      _preparedPlan = plan;
      _preparedApprovalToken = approvalToken;
      return TemporaryWebBatchPreparedCommit(
        approvalToken: approvalToken,
        expectedRevision: request.expectedRevision,
        selectedRecordCount: request.selectedRowIds.length,
        newAccountCount: plan.newAccounts.length,
        updatedAccountCount: plan.accountUpdates.length,
        skippedAccountCount: plan.skippedAccounts.length,
        formalSubscriptionCount: plan.formalSubscriptions.length,
        pendingSubscriptionDraftCount: plan.pendingSubscriptionDrafts.length,
        unsupportedItemCount: plan.unsupportedItemCount,
        quotaAllowed: plan.quota.allowed,
        remainingAccounts: plan.quota.remainingAccounts,
        remainingSubscriptions: plan.quota.remainingSubscriptions,
      );
    } on Object {
      clearSensitiveMemory();
      rethrow;
    }
  }

  @override
  Future<TemporaryWebBatchCommitResult> approveCommit(
    String approvalToken, {
    required int expectedRevision,
  }) async {
    final plan = _preparedPlan;
    if (!isAvailable ||
        plan == null ||
        approvalToken != _preparedApprovalToken ||
        expectedRevision != plan.expectedVaultRevision ||
        expectedRevision != _appState.localWebRevision) {
      clearSensitiveMemory();
      throw const FormatException('批量导入批准计划已失效。');
    }
    try {
      final result = await _appState.commitBatchImport(plan);
      if (!result.success) {
        throw FormatException(_failureMessage(result.failureCode));
      }
      return TemporaryWebBatchCommitResult(
        importedAccounts: result.addedAccountCount,
        formalSubscriptions: result.formalSubscriptionCount,
        pendingSubscriptionDrafts: result.pendingSubscriptionDraftCount,
        mergedRecords: result.updatedAccountCount,
        skippedRecords: result.skippedCount,
        unsupportedRecords: result.unsupportedItemCount,
        rollbackAvailable: result.rollbackAvailable,
      );
    } finally {
      clearSensitiveMemory();
    }
  }

  TemporaryWebBatchImportPreview _previewFor(
    ImportSessionController session,
    String token,
    int revision,
  ) {
    final snapshot = session.snapshot;
    final adapter = snapshot.selectedAdapter;
    return TemporaryWebBatchImportPreview(
      previewToken: token,
      revision: revision,
      sourceLabel:
          _documentSourceLabels[_activeDocumentKind] ??
          adapter?.displayName ??
          '',
      detectedFormat: _formatLabel(snapshot),
      mappings: adapter == null ? const [] : _mappings(snapshot),
      rows: _rows(snapshot),
      warnings: _warnings(snapshot),
      activeDocumentKind: _activeDocumentKind,
      documents: <TemporaryWebBatchImportDocument>[
        if (snapshot.accountDocument case final document?)
          TemporaryWebBatchImportDocument(
            kind: 'account',
            fileName: _documentFileNames['account'] ?? 'accounts.csv',
            sourceLabel: _documentSourceLabels['account'] ?? '账号表',
            detectedFormat: _formatDocument(document),
            rowCount: document.rows.length,
          ),
        if (snapshot.subscriptionDocument case final document?)
          TemporaryWebBatchImportDocument(
            kind: 'subscription',
            fileName: _documentFileNames['subscription'] ?? 'subscriptions.csv',
            sourceLabel: _documentSourceLabels['subscription'] ?? '订阅表',
            detectedFormat: _formatDocument(document),
            rowCount: document.rows.length,
          ),
      ],
    );
  }

  TabularDocument _canonicalEditedDocument(
    ImportSessionSnapshot snapshot, {
    required Map<String, Map<String, String>> rowPatches,
    required Map<String, String> defaultValues,
  }) {
    final source = snapshot.document;
    if (source == null) throw const FormatException('原始表格已失效。');
    final isSubscription =
        snapshot.selectedAdapter?.itemKind == ImportItemKind.subscription;
    final allowed = isSubscription
        ? const <String>{
            'accountKey',
            'planName',
            'amount',
            'currency',
            'billingCycle',
            'subscriptionStartDate',
            'nextRenewalDate',
            'autoRenew',
            'paymentMethod',
            'reminderDays',
            'notes',
          }
        : const <String>{
            'accountKey',
            'platformName',
            'loginAccount',
            'phone',
            'email',
            'url',
            'notes',
          };
    if (!allowed.containsAll(defaultValues.keys)) {
      throw const FormatException('批量默认值字段无效。');
    }
    final validRowIds = <String>{
      for (final draft
          in snapshot.accountMapping?.drafts ?? const <AccountImportDraft>[])
        _accountRowId(draft.originalRowNumber),
      for (final draft
          in snapshot.subscriptionMapping?.drafts ??
              const <SubscriptionImportDraft>[])
        _subscriptionRowId(draft.originalRowNumber),
    };
    if (!validRowIds.containsAll(rowPatches.keys) ||
        rowPatches.values.any((patch) => !allowed.containsAll(patch.keys))) {
      throw const FormatException('批量行编辑字段无效。');
    }

    String edited(String rowId, String field, String original) {
      final patch = rowPatches[rowId];
      if (patch != null && patch.containsKey(field)) return patch[field]!;
      if (original.isEmpty && defaultValues.containsKey(field)) {
        return defaultValues[field]!;
      }
      return original;
    }

    if (isSubscription) {
      const fields = <String>[
        'accountKey',
        'planName',
        'amount',
        'currency',
        'billingCycle',
        'subscriptionStartDate',
        'nextRenewalDate',
        'autoRenew',
        'paymentMethod',
        'reminderDays',
        'notes',
      ];
      const headers = <String>[
        'account_key',
        'plan_name',
        'amount',
        'currency',
        'billing_cycle',
        'subscription_start_date',
        'next_renewal_date',
        'auto_renew',
        'payment_method',
        'reminder_days',
        'notes',
      ];
      return TabularDocument(
        headers: headers,
        rows: <TabularRow>[
          for (final draft
              in snapshot.subscriptionMapping?.drafts ??
                  const <SubscriptionImportDraft>[])
            TabularRow(
              originalRowNumber: draft.originalRowNumber,
              values: <String>[
                for (final field in fields)
                  edited(
                    _subscriptionRowId(draft.originalRowNumber),
                    field,
                    switch (field) {
                      'accountKey' => draft.accountKey,
                      'planName' => draft.planName,
                      'amount' => draft.amount,
                      'currency' => draft.currency,
                      'billingCycle' => draft.billingCycle,
                      'subscriptionStartDate' => draft.subscriptionStartDate,
                      'nextRenewalDate' => draft.nextRenewalDate,
                      'autoRenew' => draft.autoRenew,
                      'paymentMethod' => draft.paymentMethod,
                      'reminderDays' => draft.reminderDays,
                      'notes' => draft.notes,
                      _ => '',
                    },
                  ),
              ],
            ),
        ],
        encoding: source.encoding,
        delimiter: source.delimiter,
        hasHeader: true,
        originalByteLength: source.originalByteLength,
      );
    }
    const fields = <String>[
      'accountKey',
      'platformName',
      'loginAccount',
      'phone',
      'email',
      'password',
      'url',
      'notes',
    ];
    const headers = <String>[
      'account_key',
      'platform_name',
      'login_account',
      'phone',
      'email',
      'password',
      'url',
      'notes',
    ];
    return TabularDocument(
      headers: headers,
      rows: <TabularRow>[
        for (final draft
            in snapshot.accountMapping?.drafts ?? const <AccountImportDraft>[])
          TabularRow(
            originalRowNumber: draft.originalRowNumber,
            values: <String>[
              for (final field in fields)
                field == 'password'
                    ? draft.password
                    : edited(
                        _accountRowId(draft.originalRowNumber),
                        field,
                        switch (field) {
                          'accountKey' => draft.accountKey ?? '',
                          'platformName' => draft.platformName,
                          'loginAccount' => draft.loginAccount,
                          'phone' => draft.phone,
                          'email' => draft.email,
                          'url' => draft.url,
                          'notes' => draft.notes,
                          _ => '',
                        },
                      ),
            ],
          ),
      ],
      encoding: source.encoding,
      delimiter: source.delimiter,
      hasHeader: true,
      originalByteLength: source.originalByteLength,
    );
  }

  List<ExistingAccountSummary> _existingAccounts() => <ExistingAccountSummary>[
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
  ];

  List<ExistingAccountSummary> _previewExistingAccounts(
    Iterable<TemporaryWebBatchVisibleAccount> accounts,
  ) => <ExistingAccountSummary>[
    for (final account in accounts)
      ExistingAccountSummary(
        id: account.id,
        platformName: account.platformName,
        loginAccount: account.loginAccount,
        phone: account.phone,
        email: account.email,
        url: account.url,
        password: '',
        notes: account.notes,
      ),
  ];

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
    final accounts = EntitlementGuard.maxAccounts - _appState.accounts.length;
    final subscriptions =
        EntitlementGuard.maxSubscriptions - _appState.subscriptions.length;
    final allowed =
        requestedAccounts <= accounts &&
        requestedSubscriptions <= subscriptions;
    return ImportQuotaValidationResult(
      allowed: allowed,
      requestedAccounts: requestedAccounts,
      requestedSubscriptions: requestedSubscriptions,
      remainingAccounts: max(0, accounts),
      remainingSubscriptions: max(0, subscriptions),
      errorCode: allowed ? null : 'free_limit',
    );
  }

  List<TemporaryWebBatchImportMapping> _mappings(
    ImportSessionSnapshot snapshot,
  ) {
    final document = snapshot.document;
    final adapter = snapshot.selectedAdapter;
    if (document == null || adapter == null) return const [];
    final appliedOverrides =
        _documentMappingOverrides[_activeDocumentKind] ??
        const <int, ImportTargetField>{};
    final excluded = <int>{
      for (final column
          in snapshot.accountMapping?.excludedSensitiveColumns ??
              const <ImportColumnReference>[])
        column.index,
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
            ImportTargetField.accountKey,
            ImportTargetField.platformName,
            ImportTargetField.loginAccount,
            ImportTargetField.phone,
            ImportTargetField.email,
            ImportTargetField.password,
            ImportTargetField.url,
            ImportTargetField.notes,
          ];
    return <TemporaryWebBatchImportMapping>[
      for (var index = 0; index < document.headers.length; index += 1)
        TemporaryWebBatchImportMapping(
          columnIndex: index,
          sourceLabel: document.headers[index],
          targetField: excluded.contains(index)
              ? null
              : switch (appliedOverrides.containsKey(index)
                    ? appliedOverrides[index]
                    : adapter.defaultMappings[normalizeImportHeader(
                        document.headers[index],
                      )]) {
                  final target? when target != ImportTargetField.ignore =>
                    target.name,
                  _ => null,
                },
          availableTargets: <String>[
            for (final target in available) target.name,
          ],
          excludedAsSensitive: excluded.contains(index),
        ),
    ];
  }

  List<TemporaryWebBatchImportRow> _rows(ImportSessionSnapshot snapshot) {
    final duplicates = <int, List<ImportDuplicateCandidate>>{};
    for (final candidate in snapshot.duplicateCandidates) {
      duplicates
          .putIfAbsent(candidate.importRowNumber, () => [])
          .add(candidate);
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
    return <TemporaryWebBatchImportRow>[
      for (final draft
          in snapshot.accountMapping?.drafts ?? const <AccountImportDraft>[])
        TemporaryWebBatchImportRow(
          id: _accountRowId(draft.originalRowNumber),
          kind: 'account',
          title: draft.platformName.isEmpty
              ? '第 ${draft.originalRowNumber} 行账号'
              : draft.platformName,
          subtitle: <String>[
            draft.loginAccount,
            draft.email,
            draft.phone,
            draft.brandSuggestion ?? '',
          ].where((value) => value.isNotEmpty).join(' · '),
          passwordStatus:
              draft.passwordLooksMasked && !draft.maskedPasswordConfirmed
              ? 'excluded'
              : draft.hasPassword
              ? 'encryptedForImport'
              : 'absent',
          defaultResolution: 'skip',
          issue: draft.validationState == ImportValidationState.invalid
              ? '该行缺少账号必要字段或包含无效值。'
              : draft.passwordLooksMasked && !draft.maskedPasswordConfirmed
              ? '疑似遮挡占位密码，默认不导入；只能在手机逐行确认。'
              : null,
          duplicateDescription:
              duplicates[draft.originalRowNumber]?.isNotEmpty == true
              ? '发现 ${duplicates[draft.originalRowNumber]!.length} 个疑似重复项。'
              : null,
          canImport: draft.validationState != ImportValidationState.invalid,
          originalRowNumber: draft.originalRowNumber,
          fields: <String, String>{
            'accountKey': draft.accountKey ?? '',
            'platformName': draft.platformName,
            'loginAccount': draft.loginAccount,
            'phone': draft.phone,
            'email': draft.email,
            'url': draft.url,
            'notes': draft.notes,
            'brandSuggestion': draft.brandSuggestion ?? '',
          },
          accountKeyAssociation: draft.accountKey?.isNotEmpty == true
              ? 'definesImportedAccountKey'
              : null,
        ),
      for (final draft
          in snapshot.subscriptionMapping?.drafts ??
              const <SubscriptionImportDraft>[])
        TemporaryWebBatchImportRow(
          id: _subscriptionRowId(draft.originalRowNumber),
          kind: 'subscription',
          title: draft.planName.isEmpty
              ? '第 ${draft.originalRowNumber} 行订阅草稿'
              : draft.planName,
          subtitle: <String>[
            draft.accountKey,
            draft.amount,
            draft.currency,
            draft.subscriptionStartDate,
            draft.nextRenewalDate,
          ].where((value) => value.isNotEmpty).join(' · '),
          passwordStatus: 'absent',
          defaultResolution: 'skip',
          issue: draft.missingOrInvalidFields.isEmpty
              ? (draft.accountKeyWasGenerated ||
                        !selectedImportedAccountKeys.contains(draft.accountKey)
                    ? '请选择关联账号，或改用同一批次包含相同 account_key 的双表导入。'
                    : null)
              : '将进入待完善订阅：${draft.missingOrInvalidFields.join(', ')}',
          subscriptionTargetRequired:
              draft.accountKeyWasGenerated ||
              !selectedImportedAccountKeys.contains(draft.accountKey),
          subscriptionTargetOptions: <String, String>{
            ..._visibleAccountTargets,
          },
          canImport:
              !(draft.accountKeyWasGenerated ||
                  !selectedImportedAccountKeys.contains(draft.accountKey)) ||
              _visibleAccountTargets.isNotEmpty,
          originalRowNumber: draft.originalRowNumber,
          fields: <String, String>{
            'accountKey': draft.accountKey,
            'planName': draft.planName,
            'amount': draft.amount,
            'currency': draft.currency,
            'billingCycle': draft.billingCycle,
            'subscriptionStartDate': draft.subscriptionStartDate,
            'nextRenewalDate': draft.nextRenewalDate,
            'autoRenew': draft.autoRenew,
            'paymentMethod': draft.paymentMethod,
            'reminderDays': draft.reminderDays,
            'notes': draft.notes,
          },
          accountKeyAssociation:
              !draft.accountKeyWasGenerated &&
                  selectedImportedAccountKeys.contains(draft.accountKey)
              ? 'linkedToImportedAccount'
              : 'missingImportedAccountKey',
        ),
    ];
  }

  List<String> _warnings(ImportSessionSnapshot snapshot) => <String>[
    for (final issue in snapshot.document?.issues ?? const <ImportIssue>[])
      issue.message,
    for (final issue
        in snapshot.accountMapping?.issues ?? const <ImportIssue>[])
      issue.message,
    for (final issue
        in snapshot.subscriptionMapping?.issues ?? const <ImportIssue>[])
      issue.message,
    if (snapshot.accountMapping case final mapping?)
      '未映射列 ${mapping.unmappedColumns.length} · 敏感排除列 ${mapping.excludedSensitiveColumns.length}',
    if (snapshot.subscriptionMapping case final mapping?)
      '未映射列 ${mapping.unmappedColumns.length}',
  ];

  String _formatLabel(ImportSessionSnapshot snapshot) {
    final document = snapshot.document;
    if (document == null) return '';
    return _formatDocument(document);
  }

  String _formatDocument(TabularDocument document) {
    final delimiter = switch (document.delimiter) {
      ',' => 'CSV',
      '\t' => 'TSV',
      ';' => '分号',
      _ => '表格',
    };
    return '${document.encoding.name} · $delimiter · ${document.rows.length} 行';
  }

  ImportSessionController _newImportSession(CardockBrandMatcher matcher) =>
      ImportSessionController(
        brandSuggestionResolver: (platformName, url) {
          var resolution = matcher.resolve(
            platformName,
            includeSuggestions: true,
          );
          if (resolution.entry == null &&
              resolution.suggestions.isEmpty &&
              url.trim().isNotEmpty) {
            final value = url.trim();
            final host =
                Uri.tryParse(
                  value.contains('://') ? value : 'https://$value',
                )?.host ??
                '';
            if (host.isNotEmpty) {
              resolution = matcher.resolve(host, includeSuggestions: true);
            }
          }
          final entry = resolution.entry;
          if (entry != null && resolution.isAutomaticallyBound) {
            return ImportBrandSuggestionResult.exactUnique(entry.brandId);
          }
          // This page has no brand-choice UI. Preserve the imported platform
          // instead of turning optional, ambiguous suggestions into a hidden
          // commit requirement. Exact unique matches above still bind normally.
          return ImportBrandSuggestionResult.none();
        },
      );

  String _newToken() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _accountRowId(int row) => 'account-row-$row';
  static String _subscriptionRowId(int row) => 'subscription-row-$row';

  static String _failureMessage(String? code) => switch (code) {
    'stale_preview' => '保险库数据已变化，权威预览已失效。',
    'quota_changed' => '免费版可用数量已变化，本次整批未写入。',
    'vault_not_writable' => '保险库当前不能写入。',
    _ => '手机端最终校验未通过，本次整批未写入。',
  };

  @override
  void clearSensitiveMemory() {
    _parseJob?.cancel();
    _parseJob = null;
    _session?.clear();
    _session = null;
    _previewToken = null;
    _previewRevision = null;
    _preparedPlan = null;
    _preparedApprovalToken = null;
    _visibleAccounts = const <TemporaryWebBatchVisibleAccount>[];
    _visibleAccountTargets = const <String, String>{};
    _documentFileNames.clear();
    _documentSourceLabels.clear();
    _documentMappingOverrides.clear();
    _activeDocumentKind = null;
  }
}

String _tabularParseFailureMessage(TabularParseFailureCode code) =>
    switch (code) {
      TabularParseFailureCode.fileTooLarge => '文件超过 10 MiB 上限，请缩小后重新选择。',
      TabularParseFailureCode.emptyFile => '文件没有可读取的表格记录，请检查首个工作表后重新选择。',
      TabularParseFailureCode.unknownEncoding ||
      TabularParseFailureCode.invalidEncoding =>
        '文本编码无法识别；请另存为 UTF-8 CSV，或使用有效的 XLSX 文件。',
      TabularParseFailureCode.invalidOfficeDocument =>
        'Office 文件结构无法解析；请确认是有效 XLSX/DOCX，并重新导出后再试。',
      TabularParseFailureCode.invalidDelimitedText =>
        '表格结构无法解析；XLSX 请检查首个工作表，CSV 请检查引号和分隔符。',
      TabularParseFailureCode.unsupportedDelimiter => '仅支持逗号、制表符或分号分隔的文本表格。',
      TabularParseFailureCode.tooManyRows => '表格超过 5000 条数据行上限，请拆分后重试。',
      TabularParseFailureCode.tooManyColumns => '表格列数过多，请只保留需要导入的列。',
      TabularParseFailureCode.fieldTooLarge => '表格中有单个字段超过 64 KiB，请缩短后重试。',
      TabularParseFailureCode.missingHeader => '首行没有可用表头，请使用 Cardock 模板表头。',
    };

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
