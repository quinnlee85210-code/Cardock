import 'dart:collection';

const Set<String> temporaryWebBatchDuplicateResolutionValues = <String>{
  'skip',
  'fillEmptyFieldsOnly',
  'importAsNew',
};

final class TemporaryWebBatchDecisionRow {
  const TemporaryWebBatchDecisionRow({
    required this.id,
    required this.kind,
    required this.canImport,
    required this.hasDuplicate,
    required this.defaultResolution,
    required this.subscriptionTargetRequired,
    this.duplicateContext = '',
    this.subscriptionTargetIds = const <String>{},
  });

  final String id;
  final String kind;
  final bool canImport;
  final bool hasDuplicate;
  final String defaultResolution;
  final bool subscriptionTargetRequired;
  final String duplicateContext;
  final Set<String> subscriptionTargetIds;
}

final class TemporaryWebBatchDecisionSnapshot {
  TemporaryWebBatchDecisionSnapshot({
    required Set<String> selectedRowIds,
    required Map<String, String> duplicateResolutions,
    required Map<String, String> subscriptionTargets,
  }) : selectedRowIds = Set<String>.unmodifiable(selectedRowIds),
       duplicateResolutions = UnmodifiableMapView<String, String>(
         Map<String, String>.of(duplicateResolutions),
       ),
       subscriptionTargets = UnmodifiableMapView<String, String>(
         Map<String, String>.of(subscriptionTargets),
       );

  final Set<String> selectedRowIds;
  final Map<String, String> duplicateResolutions;
  final Map<String, String> subscriptionTargets;
}

/// Reconciles browser-only, non-sensitive decisions with a new authoritative
/// phone preview.
///
/// Decisions are restored only when the same row ID still belongs to the same
/// document kind and the decision is still valid in the new preview. A kind in
/// [resetDocumentKinds] is treated as a replacement even when its new rows
/// reuse the old file's row numbers, preventing stale decisions from being
/// applied to different business records.
TemporaryWebBatchDecisionSnapshot reconcileTemporaryWebBatchDecisions({
  required Iterable<TemporaryWebBatchDecisionRow> previousRows,
  required Set<String> previousSelectedRowIds,
  required Map<String, String> previousDuplicateResolutions,
  required Map<String, String> previousSubscriptionTargets,
  required Iterable<TemporaryWebBatchDecisionRow> rows,
  Set<String> resetDocumentKinds = const <String>{},
}) {
  final previousById = <String, TemporaryWebBatchDecisionRow>{};
  for (final row in previousRows) {
    if (previousById.containsKey(row.id)) {
      throw const FormatException('Duplicate previous batch row ID.');
    }
    previousById[row.id] = row;
  }

  final seenIds = <String>{};
  final selected = <String>{};
  final duplicateResolutions = <String, String>{};
  final subscriptionTargets = <String, String>{};
  for (final row in rows) {
    if (!seenIds.add(row.id)) {
      throw const FormatException('Duplicate batch row ID.');
    }
    final previous = previousById[row.id];
    final preserve =
        !resetDocumentKinds.contains(row.kind) && previous?.kind == row.kind;

    String? retainedSubscriptionTarget;
    if (row.subscriptionTargetRequired) {
      if (preserve) {
        final previousTarget = previousSubscriptionTargets[row.id];
        if (previousTarget != null &&
            row.subscriptionTargetIds.contains(previousTarget)) {
          retainedSubscriptionTarget = previousTarget;
        }
      }
      if (retainedSubscriptionTarget == null &&
          row.subscriptionTargetIds.length == 1) {
        retainedSubscriptionTarget = row.subscriptionTargetIds.single;
      }
      if (retainedSubscriptionTarget != null) {
        subscriptionTargets[row.id] = retainedSubscriptionTarget;
      }
    }

    final wasSelected = previousSelectedRowIds.contains(row.id);
    final hasRequiredTarget =
        !row.subscriptionTargetRequired || retainedSubscriptionTarget != null;
    if (row.canImport && hasRequiredTarget && (preserve ? wasSelected : true)) {
      selected.add(row.id);
    }

    if (row.hasDuplicate) {
      final previousResolution = previousDuplicateResolutions[row.id];
      final resolution =
          preserve &&
              previous?.duplicateContext == row.duplicateContext &&
              temporaryWebBatchDuplicateResolutionValues.contains(
                previousResolution,
              )
          ? previousResolution!
          : row.defaultResolution;
      if (!temporaryWebBatchDuplicateResolutionValues.contains(resolution)) {
        throw const FormatException('Invalid batch duplicate resolution.');
      }
      duplicateResolutions[row.id] = resolution;
    }
  }

  return TemporaryWebBatchDecisionSnapshot(
    selectedRowIds: selected,
    duplicateResolutions: duplicateResolutions,
    subscriptionTargets: subscriptionTargets,
  );
}
