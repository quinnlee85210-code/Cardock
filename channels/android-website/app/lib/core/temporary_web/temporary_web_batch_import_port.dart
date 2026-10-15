import 'package:flutter/foundation.dart';

const int temporaryWebMaximumBatchImportBytes = 10 * 1024 * 1024;
const int temporaryWebBatchImportChunkBytes = 192 * 1024;

final class TemporaryWebBatchImportException implements Exception {
  const TemporaryWebBatchImportException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'TemporaryWebBatchImportException($code)';
}

/// Defines the only account set that may influence a browser-side preview.
///
/// The browser never chooses this value. The phone controller derives it from
/// the session policy and supplies the matching redacted account projection.
enum TemporaryWebBatchPreviewScope {
  currentSessionAuthorizedOnly,
  authorizedHistory,
}

@immutable
final class TemporaryWebBatchImportRequest {
  const TemporaryWebBatchImportRequest({
    required this.fileName,
    required this.bytes,
    required this.sourceId,
    required this.expectedRevision,
    required this.previewScope,
    this.visibleAccounts = const <TemporaryWebBatchVisibleAccount>[],
    this.visibleAccountTargets = const <String, String>{},
  });

  final String fileName;
  final Uint8List bytes;
  final String sourceId;
  final int expectedRevision;
  final TemporaryWebBatchPreviewScope previewScope;
  final List<TemporaryWebBatchVisibleAccount> visibleAccounts;
  final Map<String, String> visibleAccountTargets;
}

@immutable
final class TemporaryWebBatchVisibleAccount {
  const TemporaryWebBatchVisibleAccount({
    required this.id,
    required this.platformName,
    this.loginAccount = '',
    this.phone = '',
    this.email = '',
    this.url = '',
    this.notes = '',
  });

  final String id;
  final String platformName;
  final String loginAccount;
  final String phone;
  final String email;
  final String url;
  final String notes;
}

@immutable
final class TemporaryWebBatchImportMapping {
  const TemporaryWebBatchImportMapping({
    required this.columnIndex,
    required this.sourceLabel,
    required this.targetField,
    required this.availableTargets,
    this.excludedAsSensitive = false,
  });

  final int columnIndex;
  final String sourceLabel;
  final String? targetField;
  final List<String> availableTargets;
  final bool excludedAsSensitive;

  Map<String, Object?> toJson() => <String, Object?>{
    'columnIndex': columnIndex,
    'sourceLabel': sourceLabel,
    'targetField': targetField,
    'availableTargets': availableTargets,
    'excludedAsSensitive': excludedAsSensitive,
  };
}

@immutable
final class TemporaryWebBatchImportRow {
  const TemporaryWebBatchImportRow({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.passwordStatus,
    required this.defaultResolution,
    this.issue,
    this.duplicateDescription,
    this.subscriptionTargetOptions = const <String, String>{},
    this.subscriptionTargetRequired = false,
    this.canImport = true,
    this.originalRowNumber = 0,
    this.fields = const <String, String>{},
    this.accountKeyAssociation,
  });

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final String passwordStatus;
  final String defaultResolution;
  final String? issue;
  final String? duplicateDescription;
  final Map<String, String> subscriptionTargetOptions;
  final bool subscriptionTargetRequired;
  final bool canImport;
  final int originalRowNumber;
  final Map<String, String> fields;
  final String? accountKeyAssociation;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'title': title,
    'subtitle': subtitle,
    'passwordStatus': passwordStatus,
    'defaultResolution': defaultResolution,
    'issue': issue,
    'duplicateDescription': duplicateDescription,
    'subscriptionTargetOptions': subscriptionTargetOptions,
    'subscriptionTargetRequired': subscriptionTargetRequired,
    'canImport': canImport,
    'originalRowNumber': originalRowNumber,
    'fields': fields,
    'accountKeyAssociation': accountKeyAssociation,
  };
}

@immutable
final class TemporaryWebBatchRevisionRequest {
  const TemporaryWebBatchRevisionRequest({
    required this.previewToken,
    required this.expectedRevision,
    this.mappingOverrides = const <int, String?>{},
    this.rowPatches = const <String, Map<String, String>>{},
    this.defaultValues = const <String, String>{},
    this.removeDocumentKind,
    this.activateDocumentKind,
  });

  final String previewToken;
  final int expectedRevision;
  final Map<int, String?> mappingOverrides;
  final Map<String, Map<String, String>> rowPatches;
  final Map<String, String> defaultValues;
  final String? removeDocumentKind;
  final String? activateDocumentKind;
}

@immutable
final class TemporaryWebBatchImportDocument {
  const TemporaryWebBatchImportDocument({
    required this.kind,
    required this.fileName,
    required this.sourceLabel,
    required this.detectedFormat,
    required this.rowCount,
  });

  final String kind;
  final String fileName;
  final String sourceLabel;
  final String detectedFormat;
  final int rowCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'fileName': fileName,
    'sourceLabel': sourceLabel,
    'detectedFormat': detectedFormat,
    'rowCount': rowCount,
  };
}

@immutable
final class TemporaryWebBatchImportPreview {
  const TemporaryWebBatchImportPreview({
    required this.previewToken,
    required this.revision,
    required this.sourceLabel,
    required this.detectedFormat,
    required this.mappings,
    required this.rows,
    this.warnings = const <String>[],
    this.activeDocumentKind,
    this.documents = const <TemporaryWebBatchImportDocument>[],
  });

  final String previewToken;
  final int revision;
  final String sourceLabel;
  final String detectedFormat;
  final List<TemporaryWebBatchImportMapping> mappings;
  final List<TemporaryWebBatchImportRow> rows;
  final List<String> warnings;
  final String? activeDocumentKind;
  final List<TemporaryWebBatchImportDocument> documents;

  Map<String, Object?> toJson() => <String, Object?>{
    'previewToken': previewToken,
    'revision': revision,
    'sourceLabel': sourceLabel,
    'detectedFormat': detectedFormat,
    'mappings': <Object?>[for (final mapping in mappings) mapping.toJson()],
    'rows': <Object?>[for (final row in rows) row.toJson()],
    'warnings': warnings,
    'activeDocumentKind': activeDocumentKind,
    'documents': <Object?>[for (final document in documents) document.toJson()],
  };
}

@immutable
final class TemporaryWebBatchCommitRequest {
  const TemporaryWebBatchCommitRequest({
    required this.previewToken,
    required this.expectedRevision,
    required this.selectedRowIds,
    required this.duplicateResolutions,
    this.subscriptionAccountTargets = const <String, String>{},
  });

  final String previewToken;
  final int expectedRevision;
  final Set<String> selectedRowIds;
  final Map<String, String> duplicateResolutions;
  final Map<String, String> subscriptionAccountTargets;
}

@immutable
final class TemporaryWebBatchCommitResult {
  const TemporaryWebBatchCommitResult({
    required this.importedAccounts,
    required this.formalSubscriptions,
    required this.pendingSubscriptionDrafts,
    required this.mergedRecords,
    required this.skippedRecords,
    required this.unsupportedRecords,
    required this.rollbackAvailable,
    this.warning,
  });

  final int importedAccounts;
  final int formalSubscriptions;
  final int pendingSubscriptionDrafts;
  final int mergedRecords;
  final int skippedRecords;
  final int unsupportedRecords;
  final bool rollbackAvailable;
  final String? warning;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': 'committed',
    'importedAccounts': importedAccounts,
    'formalSubscriptions': formalSubscriptions,
    'pendingSubscriptionDrafts': pendingSubscriptionDrafts,
    'mergedRecords': mergedRecords,
    'skippedRecords': skippedRecords,
    'unsupportedRecords': unsupportedRecords,
    'rollbackAvailable': rollbackAvailable,
    'warning': warning,
  };
}

@immutable
final class TemporaryWebBatchPreparedCommit {
  const TemporaryWebBatchPreparedCommit({
    required this.approvalToken,
    required this.expectedRevision,
    required this.selectedRecordCount,
    required this.newAccountCount,
    required this.updatedAccountCount,
    required this.skippedAccountCount,
    required this.formalSubscriptionCount,
    required this.pendingSubscriptionDraftCount,
    required this.unsupportedItemCount,
    required this.quotaAllowed,
    this.remainingAccounts,
    this.remainingSubscriptions,
  });

  final String approvalToken;
  final int expectedRevision;
  final int selectedRecordCount;
  final int newAccountCount;
  final int updatedAccountCount;
  final int skippedAccountCount;
  final int formalSubscriptionCount;
  final int pendingSubscriptionDraftCount;
  final int unsupportedItemCount;
  final bool quotaAllowed;
  final int? remainingAccounts;
  final int? remainingSubscriptions;

  String get safeApprovalDetail =>
      '当前真实保险库 · 已选 $selectedRecordCount 条\n'
      '新增账号 $newAccountCount · 更新账号 $updatedAccountCount · 跳过账号 $skippedAccountCount\n'
      '正式订阅 $formalSubscriptionCount · 待完善草稿 $pendingSubscriptionDraftCount · 不支持 $unsupportedItemCount\n'
      '额度复核：${quotaAllowed ? '通过' : '未通过'}'
      '${remainingAccounts == null ? '' : ' · 剩余账号 $remainingAccounts'}'
      '${remainingSubscriptions == null ? '' : ' · 剩余订阅 $remainingSubscriptions'}\n'
      '审批卡不显示密码原文；批准时会再次核对保险库代次和计划。';

  String get safeApprovalTranslationKey =>
      '当前真实保险库 · 已选 {selected} 条\n'
      '新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n'
      '正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n'
      '额度复核：${quotaAllowed ? '通过' : '未通过'}'
      '${remainingAccounts == null ? '' : ' · 剩余账号 {accounts}'}'
      '${remainingSubscriptions == null ? '' : ' · 剩余订阅 {subscriptions}'}\n'
      '审批卡不显示密码原文；批准时会再次核对保险库代次和计划。';

  Map<String, Object?> get safeApprovalTranslationValues => <String, Object?>{
    'selected': selectedRecordCount,
    'added': newAccountCount,
    'updated': updatedAccountCount,
    'skipped': skippedAccountCount,
    'formal': formalSubscriptionCount,
    'pending': pendingSubscriptionDraftCount,
    'unsupported': unsupportedItemCount,
    if (remainingAccounts != null) 'accounts': remainingAccounts,
    if (remainingSubscriptions != null) 'subscriptions': remainingSubscriptions,
  };

  Map<String, Object?> toSafeJson() => <String, Object?>{
    'approvalToken': approvalToken,
    'expectedRevision': expectedRevision,
    'selectedRecordCount': selectedRecordCount,
    'newAccountCount': newAccountCount,
    'updatedAccountCount': updatedAccountCount,
    'skippedAccountCount': skippedAccountCount,
    'formalSubscriptionCount': formalSubscriptionCount,
    'pendingSubscriptionDraftCount': pendingSubscriptionDraftCount,
    'unsupportedItemCount': unsupportedItemCount,
    'quotaAllowed': quotaAllowed,
    'remainingAccounts': remainingAccounts,
    'remainingSubscriptions': remainingSubscriptions,
  };
}

/// Bridges the encrypted temporary page to the same authoritative import
/// session used by the phone UI.
///
/// Implementations must never return password text. The preview token is
/// opaque, session-scoped and bound to [expectedRevision]. A commit must rebuild
/// and validate the authoritative plan instead of trusting browser rows.
abstract interface class TemporaryWebBatchImportPort {
  bool get isAvailable;

  Future<TemporaryWebBatchImportPreview> preview(
    TemporaryWebBatchImportRequest request,
  );

  /// Rebuilds the in-memory authoritative preview from browser mapping and
  /// field edits. No vault write is permitted here.
  Future<TemporaryWebBatchImportPreview> revisePreview(
    TemporaryWebBatchRevisionRequest request,
  );

  /// Rebuilds the authoritative plan before the phone approval is shown.
  Future<TemporaryWebBatchPreparedCommit> prepareCommit(
    TemporaryWebBatchCommitRequest request,
  );

  /// Commits only the plan previously bound to [approvalToken].
  Future<TemporaryWebBatchCommitResult> approveCommit(
    String approvalToken, {
    required int expectedRevision,
  });

  /// Synchronously destroys raw bytes, parsed rows, passwords and tokens.
  void clearSensitiveMemory();
}
