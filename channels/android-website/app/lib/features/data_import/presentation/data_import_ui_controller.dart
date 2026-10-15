import 'package:flutter/foundation.dart';

enum DataImportWizardStep {
  source,
  file,
  mapping,
  passwordPreview,
  duplicates,
  confirmation,
  result,
}

enum DataImportRecordKind { account, subscription }

enum DataImportPasswordStatus {
  absent,
  encryptedForImport,
  excluded,
  maskedReviewRequired,
}

enum DataImportDuplicateResolution {
  skip,
  mergeMissingFields,
  fieldByField,
  createAnother,
}

enum DataImportPasswordComparison {
  bothEmpty,
  same,
  different,
  existingEmpty,
  importedEmpty,
}

@immutable
final class DataImportFieldComparison {
  const DataImportFieldComparison({
    required this.fieldName,
    this.existingValue = '',
    this.importedValue = '',
    this.passwordComparison,
  });

  final String fieldName;
  final String existingValue;
  final String importedValue;
  final DataImportPasswordComparison? passwordComparison;

  bool get isPassword => passwordComparison != null;
}

@immutable
final class DataImportFieldSuggestionView {
  const DataImportFieldSuggestionView({
    required this.id,
    required this.rowId,
    required this.targetField,
    required this.value,
    required this.accepted,
  });

  final String id;
  final String rowId;
  final String targetField;
  final String value;
  final bool accepted;
}

@immutable
final class DataImportSourceOption {
  const DataImportSourceOption({
    required this.id,
    required this.label,
    required this.description,
    this.verified = true,
  });

  final String id;
  final String label;
  final String description;
  final bool verified;
}

@immutable
final class DataImportColumnMapping {
  const DataImportColumnMapping({
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
}

@immutable
final class DataImportPreviewRow {
  const DataImportPreviewRow({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.passwordStatus,
    this.selected = true,
    this.issue,
    this.duplicateDescription,
    this.duplicateResolution = DataImportDuplicateResolution.skip,
    this.maskedPasswordConfirmed = false,
    this.conflictingFields = const <String>{},
    this.fieldChoices = const <String, bool>{},
    this.fieldComparisons = const <String, DataImportFieldComparison>{},
    this.duplicateTargetOptions = const <String, String>{},
    this.selectedDuplicateTargetId,
    this.brandSuggestionOptions = const <String, String>{},
    this.selectedBrandSuggestionId,
    this.brandSuggestionsIgnored = false,
    this.subscriptionTargetOptions = const <String, String>{},
    this.selectedSubscriptionTargetId,
    this.subscriptionTargetRequired = false,
    this.titleTranslationKey,
    this.titleTranslationValues = const <String, Object?>{},
    this.issueTranslationKey,
    this.issueTranslationValues = const <String, Object?>{},
    this.duplicateDescriptionTranslationKey,
    this.duplicateDescriptionTranslationValues = const <String, Object?>{},
  });

  final String id;
  final DataImportRecordKind kind;
  final String title;
  final String subtitle;
  final DataImportPasswordStatus passwordStatus;
  final bool selected;
  final String? issue;
  final String? duplicateDescription;
  final DataImportDuplicateResolution duplicateResolution;
  final bool maskedPasswordConfirmed;
  final Set<String> conflictingFields;
  final Map<String, bool> fieldChoices;
  final Map<String, DataImportFieldComparison> fieldComparisons;
  final Map<String, String> duplicateTargetOptions;
  final String? selectedDuplicateTargetId;
  final Map<String, String> brandSuggestionOptions;
  final String? selectedBrandSuggestionId;
  final bool brandSuggestionsIgnored;
  final Map<String, String> subscriptionTargetOptions;
  final String? selectedSubscriptionTargetId;
  final bool subscriptionTargetRequired;
  final String? titleTranslationKey;
  final Map<String, Object?> titleTranslationValues;
  final String? issueTranslationKey;
  final Map<String, Object?> issueTranslationValues;
  final String? duplicateDescriptionTranslationKey;
  final Map<String, Object?> duplicateDescriptionTranslationValues;
}

@immutable
final class DataImportCommitSummary {
  const DataImportCommitSummary({
    required this.importedAccounts,
    required this.formalSubscriptions,
    required this.pendingSubscriptionDrafts,
    required this.mergedRecords,
    required this.skippedRecords,
    required this.unsupportedRecords,
    required this.rollbackAvailable,
    this.warning,
    this.preservedPasswords = 0,
    this.maskedPasswords = 0,
    this.emptyPasswords = 0,
    this.unmappedColumns = 0,
    this.unresolvedDuplicates = 0,
  });

  final int importedAccounts;
  final int formalSubscriptions;
  final int pendingSubscriptionDrafts;
  final int mergedRecords;
  final int skippedRecords;
  final int unsupportedRecords;
  final bool rollbackAvailable;
  final String? warning;
  final int preservedPasswords,
      maskedPasswords,
      emptyPasswords,
      unmappedColumns,
      unresolvedDuplicates;
}

@immutable
final class DataImportPlanSummary {
  const DataImportPlanSummary({
    required this.newAccounts,
    required this.updatedAccounts,
    required this.skippedAccounts,
    required this.formalSubscriptions,
    required this.pendingSubscriptionDrafts,
    required this.unsupportedItems,
    required this.quotaAllowed,
    this.remainingAccounts,
    this.remainingSubscriptions,
  });

  final int newAccounts;
  final int updatedAccounts;
  final int skippedAccounts;
  final int formalSubscriptions;
  final int pendingSubscriptionDrafts;
  final int unsupportedItems;
  final bool quotaAllowed;
  final int? remainingAccounts;
  final int? remainingSubscriptions;
}

@immutable
final class DataImportCustomFieldView {
  const DataImportCustomFieldView({
    required this.rowNumber,
    required this.accountKey,
    required this.name,
    required this.typeCode,
    required this.sensitive,
    required this.included,
    required this.replaceExisting,
    required this.confirmed,
    required this.conflict,
    required this.displayValue,
  });
  final int rowNumber;
  final String accountKey, name, typeCode, displayValue;
  final bool sensitive, included, replaceExisting, confirmed, conflict;
}

@immutable
final class DataImportUiState {
  const DataImportUiState({
    this.step = DataImportWizardStep.source,
    this.working = false,
    this.parseProgress,
    this.canWrite = true,
    this.selectedSourceId,
    this.fileName,
    this.fileSize = 0,
    this.additionalFileName,
    this.additionalFileSize = 0,
    this.detectedFormat,
    this.mappings = const <DataImportColumnMapping>[],
    this.customFields = const <DataImportCustomFieldView>[],
    this.rows = const <DataImportPreviewRow>[],
    this.warnings = const <String>[],
    this.fieldSuggestions = const <DataImportFieldSuggestionView>[],
    this.finalConfirmation = false,
    this.errorMessage,
    this.sourceMismatch = false,
    this.commitSummary,
    this.planSummary,
  });

  final bool sourceMismatch;
  final DataImportWizardStep step;
  final bool working;
  final double? parseProgress;
  final bool canWrite;
  final String? selectedSourceId;
  final String? fileName;
  final int fileSize;
  final String? additionalFileName;
  final int additionalFileSize;
  final String? detectedFormat;
  final List<DataImportColumnMapping> mappings;
  final List<DataImportCustomFieldView> customFields;
  final List<DataImportPreviewRow> rows;
  final List<String> warnings;
  final List<DataImportFieldSuggestionView> fieldSuggestions;
  final bool finalConfirmation;
  final String? errorMessage;
  final DataImportCommitSummary? commitSummary;
  final DataImportPlanSummary? planSummary;

  int get selectedCount => rows.where((row) => row.selected).length;
  int get accountCount => rows
      .where((row) => row.selected && row.kind == DataImportRecordKind.account)
      .length;
  int get subscriptionCount => rows
      .where(
        (row) => row.selected && row.kind == DataImportRecordKind.subscription,
      )
      .length;
  int get duplicateCount => rows
      .where((row) => row.selected && row.duplicateDescription != null)
      .length;
  bool get hasBlockingIssues =>
      rows.any((row) => row.selected && row.issue != null);
}

/// Presentation boundary for the migration wizard.
///
/// The implementation must delegate parsing, mapping, de-duplication, preview
/// token generation and commit to the shared authoritative import core. The UI
/// never treats browser- or widget-generated rows as commit authority.
abstract class DataImportUiController extends ChangeNotifier {
  DataImportUiState get state;

  List<DataImportSourceOption> get sources;

  Future<void> selectSource(String sourceId);
  Future<void> useGenericMapping() async {}

  Future<bool> loadFile({required String fileName, required Uint8List bytes});

  /// Adds the complementary account/subscription table to the current session.
  /// Implementations that do not support paired templates may replace the
  /// current document as a safe fallback.
  Future<bool> appendFile({
    required String fileName,
    required Uint8List bytes,
  }) => loadFile(fileName: fileName, bytes: bytes);

  Future<bool> loadCustomFieldFile({
    required String fileName,
    required Uint8List bytes,
  }) async => false;
  void setCustomFieldDecision(
    int rowNumber, {
    required bool include,
    required bool replaceExisting,
    required bool sensitiveConfirmed,
  }) {}

  Future<void> updateMapping({
    required int columnIndex,
    required String? targetField,
  });

  void setRowSelected(String rowId, bool selected);

  void setMaskedPasswordConfirmed(String rowId, bool confirmed);

  void removeRow(String rowId);

  void setDuplicateResolution(
    String rowId,
    DataImportDuplicateResolution resolution,
  );

  void setDuplicateFieldChoice(
    String rowId,
    String fieldName,
    bool useImportedValue,
  );

  void setDuplicateUpdateTarget(String rowId, String existingAccountId);

  void setSubscriptionAccountTarget(String rowId, String existingAccountId) {}

  void acceptFieldSuggestion(String suggestionId);

  void acceptAllFieldSuggestions();

  void ignoreAllFieldSuggestions();

  void selectBrandSuggestion(String rowId, String brandId);

  void ignoreBrandSuggestions(String rowId);

  void setFinalConfirmation(bool confirmed);

  Future<void> next();

  void back();

  Future<void> commit();

  void cancelParsing();

  /// Overwrites raw file buffers, passwords and preview material held in RAM.
  void clearSensitiveMemory();
}

typedef DataImportUiControllerFactory = DataImportUiController Function();
