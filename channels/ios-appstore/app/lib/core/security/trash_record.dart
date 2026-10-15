import '../../features/accounts/domain/account_record.dart';
import '../../features/subscriptions/domain/pending_subscription_draft.dart';
import '../../features/subscriptions/domain/subscription_record.dart';

const trashRetention = Duration(days: 30);

/// Deleted records remain inside their own authenticated vault snapshot.
/// Absence from both active and trash collections represents permanent removal.
final class TrashAccount {
  TrashAccount({
    required this.record,
    required DateTime deletedAtUtc,
    required this.batchId,
    List<PendingSubscriptionDraft> pendingDrafts = const [],
  }) : deletedAtUtc = deletedAtUtc.toUtc(),
       pendingDrafts = List.unmodifiable(pendingDrafts) {
    _validateDeletion(this.deletedAtUtc, batchId);
    if (this.pendingDrafts.any((draft) => draft.accountId != record.id)) {
      throw const FormatException('Invalid trash relationship');
    }
  }

  final AccountRecord record;
  final DateTime deletedAtUtc;
  final String batchId;
  final List<PendingSubscriptionDraft> pendingDrafts;
  DateTime get expiresAtUtc => deletedAtUtc.add(trashRetention);
  bool expired(DateTime now) => !now.toUtc().isBefore(expiresAtUtc);

  factory TrashAccount.fromJson(
    Object? value, {
    bool allowStage3Metadata = true,
  }) {
    final map = _deletionMap(value);
    final drafts = map['pendingDrafts'];
    if (drafts is! List || drafts.length > 50000) {
      throw const FormatException('Invalid trash drafts');
    }
    return TrashAccount(
      record: AccountRecord.fromEncryptedPayloadJson(
        map['record'],
        allowStage3Metadata: allowStage3Metadata,
      ),
      deletedAtUtc: _deletionDate(map['deletedAtUtc']),
      batchId: map['batchId'] as String,
      pendingDrafts: drafts
          .map(PendingSubscriptionDraft.fromEncryptedPayloadJson)
          .toList(),
    );
  }

  Map<String, Object?> toJson() => {
    'record': record.toEncryptedPayloadJson(),
    'deletedAtUtc': deletedAtUtc.toIso8601String(),
    'batchId': batchId,
    'pendingDrafts': pendingDrafts
        .map((draft) => draft.toEncryptedPayloadJson())
        .toList(),
  };
}

final class TrashSubscription {
  TrashSubscription({
    required this.record,
    required DateTime deletedAtUtc,
    required this.batchId,
  }) : deletedAtUtc = deletedAtUtc.toUtc() {
    _validateDeletion(this.deletedAtUtc, batchId);
  }

  final SubscriptionRecord record;
  final DateTime deletedAtUtc;
  final String batchId;
  DateTime get expiresAtUtc => deletedAtUtc.add(trashRetention);
  bool expired(DateTime now) => !now.toUtc().isBefore(expiresAtUtc);

  factory TrashSubscription.fromJson(Object? value) {
    final map = _deletionMap(value);
    return TrashSubscription(
      record: SubscriptionRecord.fromEncryptedPayloadJson(
        map['record'],
        allowStandalone: true,
        allowInstantSnooze: true,
        allowExpenseCategory: true,
      ),
      deletedAtUtc: _deletionDate(map['deletedAtUtc']),
      batchId: map['batchId'] as String,
    );
  }

  Map<String, Object?> toJson() => {
    'record': record.toEncryptedPayloadJson(),
    'deletedAtUtc': deletedAtUtc.toIso8601String(),
    'batchId': batchId,
  };
}

Map<Object?, Object?> _deletionMap(Object? value) {
  if (value is! Map<Object?, Object?> || value['batchId'] is! String) {
    throw const FormatException('Invalid trash record');
  }
  return value;
}

DateTime _deletionDate(Object? value) {
  if (value is! String || value.length > 64) {
    throw const FormatException('Invalid deletion date');
  }
  final date = DateTime.tryParse(value);
  if (date == null || !date.isUtc) {
    throw const FormatException('Invalid deletion date');
  }
  return date;
}

void _validateDeletion(DateTime date, String batchId) {
  if (date.year < 1970 ||
      date.year > 9998 ||
      batchId.isEmpty ||
      batchId.length > 128) {
    throw const FormatException('Invalid deletion metadata');
  }
}
