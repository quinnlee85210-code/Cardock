import 'dart:collection';

import '../preferences/language_preferences.dart';

enum TemporaryWebHistoryMode { currentSessionOnly, summary, details }

extension TemporaryWebHistoryModeLabel on TemporaryWebHistoryMode {
  String get label => switch (this) {
    TemporaryWebHistoryMode.currentSessionOnly => '仅本次',
    TemporaryWebHistoryMode.summary => '历史摘要',
    TemporaryWebHistoryMode.details => '历史详情',
  };
}

final class TemporaryWebSessionPolicy {
  const TemporaryWebSessionPolicy({
    this.historyMode = TemporaryWebHistoryMode.currentSessionOnly,
    this.allowHistoryEditing = false,
    this.allowHistoricalPasswordReveal = false,
    this.connectionDuration = const Duration(minutes: 5),
  });

  static const Duration maximumLifetime = Duration(minutes: 30);
  static const List<Duration> allowedConnectionDurations = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];

  final TemporaryWebHistoryMode historyMode;
  final bool allowHistoryEditing;
  final bool allowHistoricalPasswordReveal;
  final Duration connectionDuration;

  TemporaryWebSessionPolicy copyWith({
    TemporaryWebHistoryMode? historyMode,
    bool? allowHistoryEditing,
    bool? allowHistoricalPasswordReveal,
    Duration? connectionDuration,
  }) => TemporaryWebSessionPolicy(
    historyMode: historyMode ?? this.historyMode,
    allowHistoryEditing: allowHistoryEditing ?? this.allowHistoryEditing,
    allowHistoricalPasswordReveal:
        allowHistoricalPasswordReveal ?? this.allowHistoricalPasswordReveal,
    connectionDuration: connectionDuration ?? this.connectionDuration,
  );
}

enum TemporaryWebSessionPhase {
  stopped,
  starting,
  waitingForPairing,
  connected,
}

enum TemporaryWebStopReason {
  user,
  idleTimeout,
  absoluteTimeout,
  phoneLocked,
  appBackgrounded,
  vaultChanged,
  networkChanged,
  browserDisconnected,
  pairingRejected,
  transportFailure,
  disposed,
}

enum TemporaryWebApprovalKind {
  deleteAccount,
  deleteSubscription,
  revealPassword,
  revealCustomField,
  saveAccount,
  batchImport,
}

final class TemporaryWebAddress {
  const TemporaryWebAddress({
    required this.address,
    required this.interfaceName,
  });

  final String address;
  final String interfaceName;

  String get label => '$address · $interfaceName';
}

final class TemporaryWebSessionSnapshot {
  const TemporaryWebSessionSnapshot({
    required this.phase,
    required this.policy,
    required this.pendingApprovals,
    this.language = CardockLanguage.simplifiedChinese,
    this.address,
    this.port,
    this.formattedConnectionCode,
    this.startedAt,
    this.lastMeaningfulActivityAt,
    this.stopReason,
    this.connectedClientAddress,
    this.errorMessage,
  });

  factory TemporaryWebSessionSnapshot.stopped({
    TemporaryWebSessionPolicy policy = const TemporaryWebSessionPolicy(),
    CardockLanguage language = CardockLanguage.simplifiedChinese,
    TemporaryWebStopReason? stopReason,
    String? errorMessage,
  }) => TemporaryWebSessionSnapshot(
    phase: TemporaryWebSessionPhase.stopped,
    policy: policy,
    pendingApprovals: const <TemporaryWebApproval>[],
    language: language,
    stopReason: stopReason,
    errorMessage: errorMessage,
  );

  final TemporaryWebSessionPhase phase;
  final TemporaryWebSessionPolicy policy;
  final CardockLanguage language;
  final String? address;
  final int? port;
  final String? formattedConnectionCode;
  final DateTime? startedAt;
  final DateTime? lastMeaningfulActivityAt;
  final TemporaryWebStopReason? stopReason;
  final String? connectedClientAddress;
  final String? errorMessage;
  final List<TemporaryWebApproval> pendingApprovals;

  bool get isRunning => phase != TemporaryWebSessionPhase.stopped;

  Uri? get browserUri {
    final host = address;
    final localPort = port;
    if (host == null || localPort == null) return null;
    return Uri(
      scheme: 'http',
      host: host,
      port: localPort,
      path: '/',
      queryParameters: <String, String>{'lang': language.storageCode},
    );
  }
}

final class TemporaryWebApproval {
  const TemporaryWebApproval({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.title,
    required this.detail,
    required this.createdAt,
    required this.expiresAt,
    required this.expectedRevision,
    required this.expectedDigest,
    this.duplicateConfirmationRequired = false,
    this.detailTranslationKey,
    this.detailTranslationValues = const <String, Object?>{},
  });

  final String id;
  final TemporaryWebApprovalKind kind;
  final String targetId;
  final String title;
  final String detail;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int expectedRevision;
  final String expectedDigest;
  final bool duplicateConfirmationRequired;
  final String? detailTranslationKey;
  final Map<String, Object?> detailTranslationValues;
}

enum TemporaryWebMutationDisposition { committed, rejected, resultUnknown }

final class TemporaryWebMutationResult {
  const TemporaryWebMutationResult._({
    required this.disposition,
    required this.revision,
    this.recordId,
    this.message,
  });

  factory TemporaryWebMutationResult.committed({
    required int revision,
    String? recordId,
  }) => TemporaryWebMutationResult._(
    disposition: TemporaryWebMutationDisposition.committed,
    revision: revision,
    recordId: recordId,
  );

  factory TemporaryWebMutationResult.rejected({
    required int revision,
    required String message,
  }) => TemporaryWebMutationResult._(
    disposition: TemporaryWebMutationDisposition.rejected,
    revision: revision,
    message: message,
  );

  factory TemporaryWebMutationResult.unknown({
    required int revision,
    required String message,
  }) => TemporaryWebMutationResult._(
    disposition: TemporaryWebMutationDisposition.resultUnknown,
    revision: revision,
    message: message,
  );

  final TemporaryWebMutationDisposition disposition;
  final int revision;
  final String? recordId;
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': switch (disposition) {
      TemporaryWebMutationDisposition.committed => 'committed',
      TemporaryWebMutationDisposition.rejected => 'rejected',
      TemporaryWebMutationDisposition.resultUnknown => 'resultUnknown',
    },
    'revision': revision,
    'recordId': recordId,
    'message': message,
  };
}

final class TemporaryWebOperationCache {
  TemporaryWebOperationCache({this.maximumEntries = 128});

  final int maximumEntries;
  final LinkedHashMap<String, Map<String, Object?>> _entries =
      LinkedHashMap<String, Map<String, Object?>>();

  Map<String, Object?>? operator [](String requestId) => _entries[requestId];

  void put(String requestId, Map<String, Object?> result) {
    _entries.remove(requestId);
    _entries[requestId] = Map<String, Object?>.unmodifiable(result);
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
