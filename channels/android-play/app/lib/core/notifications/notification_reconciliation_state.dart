import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../security/vault_contract.dart';

/// A vault-private, non-business outbox item for eventually reconciling the
/// platform notification queue with the current encrypted vault snapshot.
///
/// The state deliberately contains no account, subscription, amount, date, or
/// notification copy. The current snapshot remains the only source of truth.
@immutable
final class NotificationReconciliationState {
  const NotificationReconciliationState({
    required this.operationId,
    required this.targetGeneration,
    required this.stateRevision,
    required this.createdAtUtc,
    required this.attemptCount,
    this.lastAttemptAtUtc,
  });

  factory NotificationReconciliationState.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const NotificationReconciliationFormatException();
    }
    final operationId = value['operationId'];
    final targetGeneration = value['targetGeneration'];
    final stateRevision = value['stateRevision'];
    final createdAtEpochMillis = value['createdAtEpochMillis'];
    final attemptCount = value['attemptCount'];
    final lastAttemptAtEpochMillis = value['lastAttemptAtEpochMillis'];
    if (operationId is! String ||
        operationId.length < 16 ||
        operationId.length > 128 ||
        targetGeneration is! int ||
        targetGeneration < 1 ||
        targetGeneration > 1000000000 ||
        stateRevision is! int ||
        stateRevision < 1 ||
        stateRevision > 1000000000 ||
        createdAtEpochMillis is! int ||
        createdAtEpochMillis < 0 ||
        attemptCount is! int ||
        attemptCount < 0 ||
        attemptCount > 1000000 ||
        (lastAttemptAtEpochMillis != null &&
            (lastAttemptAtEpochMillis is! int ||
                lastAttemptAtEpochMillis < 0))) {
      throw const NotificationReconciliationFormatException();
    }
    return NotificationReconciliationState(
      operationId: operationId,
      targetGeneration: targetGeneration,
      stateRevision: stateRevision,
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
        createdAtEpochMillis,
        isUtc: true,
      ),
      attemptCount: attemptCount,
      lastAttemptAtUtc: lastAttemptAtEpochMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              lastAttemptAtEpochMillis as int,
              isUtc: true,
            ),
    );
  }

  final String operationId;
  final int targetGeneration;
  final int stateRevision;
  final DateTime createdAtUtc;
  final int attemptCount;
  final DateTime? lastAttemptAtUtc;

  NotificationReconciliationState copyWith({
    int? stateRevision,
    int? attemptCount,
    DateTime? lastAttemptAtUtc,
  }) => NotificationReconciliationState(
    operationId: operationId,
    targetGeneration: targetGeneration,
    stateRevision: stateRevision ?? this.stateRevision,
    createdAtUtc: createdAtUtc,
    attemptCount: attemptCount ?? this.attemptCount,
    lastAttemptAtUtc: lastAttemptAtUtc ?? this.lastAttemptAtUtc,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'targetGeneration': targetGeneration,
    'stateRevision': stateRevision,
    'createdAtEpochMillis': createdAtUtc.toUtc().millisecondsSinceEpoch,
    'attemptCount': attemptCount,
    'lastAttemptAtEpochMillis': lastAttemptAtUtc
        ?.toUtc()
        .millisecondsSinceEpoch,
  };
}

/// Optional capability exposed only by a full writable vault session.
///
/// `prepare` is called before the main snapshot commit and is bound to the
/// generation that commit is expected to create. A process death can therefore
/// never lose the durable intent after the business snapshot is committed.
abstract interface class NotificationReconciliationVaultSession
    implements VaultSession {
  Future<NotificationReconciliationState?> readNotificationReconciliation();

  Future<NotificationReconciliationState> prepareNotificationReconciliation({
    required int targetGeneration,
  });

  Future<void> recordNotificationReconciliationFailure({
    required String operationId,
  });

  Future<void> completeNotificationReconciliation({
    required String operationId,
  });
}

final class NotificationReconciliationFormatException implements Exception {
  const NotificationReconciliationFormatException();
}

/// Authenticated codec used by the encrypted vault companion file.
///
/// All meaningful fields are encrypted with the current vault DEK. AAD binds
/// the payload to this file format and concrete vault instance so a valid item
/// cannot be copied between the primary and decoy vaults.
final class NotificationReconciliationCodec {
  NotificationReconciliationCodec({AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  static const String magic = 'ASM_NOTIFICATION_RECONCILIATION';
  static const int version = 1;
  static const int maximumEncodedBytes = 64 * 1024;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  final AesGcm _cipher;

  Future<Uint8List> encodePending({
    required NotificationReconciliationState state,
    required SecretKeyData dataKey,
    required List<int> vaultInstanceId,
  }) => _encode(
    kind: 'pending',
    stateRevision: state.stateRevision,
    state: state,
    dataKey: dataKey,
    vaultInstanceId: vaultInstanceId,
  );

  Future<Uint8List> encodeCleared({
    required int stateRevision,
    required SecretKeyData dataKey,
    required List<int> vaultInstanceId,
  }) => _encode(
    kind: 'cleared',
    stateRevision: stateRevision,
    dataKey: dataKey,
    vaultInstanceId: vaultInstanceId,
  );

  Future<DecodedNotificationReconciliationState> decode({
    required List<int> encoded,
    required SecretKeyData dataKey,
    required List<int> vaultInstanceId,
  }) async {
    if (encoded.isEmpty || encoded.length > maximumEncodedBytes) {
      throw const NotificationReconciliationFormatException();
    }
    List<int>? clearText;
    try {
      final outer = jsonDecode(utf8.decode(encoded));
      if (outer is! Map<String, Object?> ||
          outer['magic'] != magic ||
          outer['version'] != version ||
          outer['box'] is! String) {
        throw const NotificationReconciliationFormatException();
      }
      final concatenation = base64Decode(outer['box']! as String);
      if (concatenation.length < _nonceLength + _macLength + 1) {
        throw const NotificationReconciliationFormatException();
      }
      final box = SecretBox.fromConcatenation(
        concatenation,
        nonceLength: _nonceLength,
        macLength: _macLength,
        copy: true,
      );
      clearText = await _cipher.decrypt(
        box,
        secretKey: dataKey,
        aad: _aad(vaultInstanceId),
      );
      final payload = jsonDecode(utf8.decode(clearText));
      if (payload is! Map<String, Object?> ||
          payload['kind'] is! String ||
          payload['stateRevision'] is! int) {
        throw const NotificationReconciliationFormatException();
      }
      final stateRevision = payload['stateRevision']! as int;
      if (stateRevision < 1 || stateRevision > 1000000000) {
        throw const NotificationReconciliationFormatException();
      }
      return switch (payload['kind']) {
        'pending' => DecodedNotificationReconciliationState.pending(
          NotificationReconciliationState.fromJson(payload['state']),
        ),
        'cleared' => DecodedNotificationReconciliationState.cleared(
          stateRevision,
        ),
        _ => throw const NotificationReconciliationFormatException(),
      };
    } on SecretBoxAuthenticationError {
      throw const NotificationReconciliationFormatException();
    } on NotificationReconciliationFormatException {
      rethrow;
    } on Object {
      throw const NotificationReconciliationFormatException();
    } finally {
      if (clearText != null) {
        clearText.fillRange(0, clearText.length, 0);
      }
    }
  }

  Future<Uint8List> _encode({
    required String kind,
    required int stateRevision,
    required SecretKeyData dataKey,
    required List<int> vaultInstanceId,
    NotificationReconciliationState? state,
  }) async {
    if (dataKey.hasBeenDestroyed ||
        (vaultInstanceId.length != 16 && vaultInstanceId.length != 32) ||
        stateRevision < 1 ||
        stateRevision > 1000000000 ||
        (kind == 'pending') != (state != null)) {
      throw const NotificationReconciliationFormatException();
    }
    final clearText = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'kind': kind,
          'stateRevision': stateRevision,
          if (state != null) 'state': state.toJson(),
        }),
      ),
    );
    try {
      final box = await _cipher.encrypt(
        clearText,
        secretKey: dataKey,
        nonce: _cipher.newNonce(),
        aad: _aad(vaultInstanceId),
      );
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'magic': magic,
            'version': version,
            'box': base64Encode(box.concatenation()),
          }),
        ),
      );
    } finally {
      clearText.fillRange(0, clearText.length, 0);
    }
  }

  List<int> _aad(List<int> vaultInstanceId) => <int>[
    ...utf8.encode('$magic:$version:'),
    ...vaultInstanceId,
  ];
}

final class DecodedNotificationReconciliationState {
  const DecodedNotificationReconciliationState.pending(this.pending)
    : clearedStateRevision = null;

  const DecodedNotificationReconciliationState.cleared(
    this.clearedStateRevision,
  ) : pending = null;

  final NotificationReconciliationState? pending;
  final int? clearedStateRevision;

  int get stateRevision => pending?.stateRevision ?? clearedStateRevision!;
}
