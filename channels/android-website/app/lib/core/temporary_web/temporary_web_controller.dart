import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../platform/temporary_web_runtime_keeper.dart';
import '../preferences/language_preferences.dart';
import '../../features/accounts/domain/account_record.dart';
import '../../features/subscriptions/domain/subscription_record.dart';
import 'temporary_web_models.dart';
import 'temporary_web_batch_import_port.dart';
import 'temporary_web_projector.dart';
import 'temporary_web_vault_gateway.dart';

typedef TemporaryWebCommandHandler =
    Future<Map<String, Object?>> Function(
      Map<String, Object?> command,
      String remoteAddress,
    );

/// A browser reached the listener but failed the one-shot pairing handshake.
///
/// This marker deliberately carries no connection code, key material, or raw
/// request details. The controller uses it to distinguish a rejected pairing
/// from an unrelated listener failure.
final class TemporaryWebPairingRejectedException implements Exception {
  const TemporaryWebPairingRejectedException();

  @override
  String toString() => 'TemporaryWebPairingRejectedException';
}

abstract interface class TemporaryWebTransport {
  Future<TemporaryWebTransportBinding> start({
    required String address,
    required TemporaryWebCommandHandler onCommand,
    required void Function(String remoteAddress) onPaired,
    required void Function(Object error) onFatalError,
  });

  /// Synchronously makes every old callback and session key unusable.
  void revoke();

  Future<void> stop();
}

final class TemporaryWebTransportBinding {
  const TemporaryWebTransportBinding({
    required this.port,
    required this.formattedConnectionCode,
  });

  final int port;
  final String formattedConnectionCode;
}

abstract interface class TemporaryWebAddressProvider {
  Future<List<TemporaryWebAddress>> listPrivateIpv4Addresses();

  Future<bool> isStillAvailable(String address);
}

final class TemporaryWebSessionController extends ChangeNotifier {
  TemporaryWebSessionController(
    this._gateway,
    this._transport,
    this._addressProvider, {
    DateTime Function()? now,
    Duration Function()? monotonicNow,
    CardockLanguage language = CardockLanguage.simplifiedChinese,
    this._projector = const TemporaryWebRecordProjector(),
    this._batchImportPort,
    TemporaryWebRuntimeKeeper? runtimeKeeper,
  }) : _now = now ?? DateTime.now,
       _monotonicNow = monotonicNow ?? _createMonotonicClock(),
       _runtimeKeeper = runtimeKeeper ?? const NoopTemporaryWebRuntimeKeeper(),
       _language = language {
    _snapshot = TemporaryWebSessionSnapshot.stopped(language: language);
  }

  static const Duration _approvalLifetime = Duration(minutes: 2);
  static const Duration _passwordResultLifetime = Duration(seconds: 30);
  static const Duration _batchUploadLifetime = Duration(minutes: 2);
  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{16,80}$');

  final TemporaryWebVaultGateway _gateway;
  final TemporaryWebTransport _transport;
  final TemporaryWebAddressProvider _addressProvider;
  final DateTime Function() _now;
  final Duration Function() _monotonicNow;
  final TemporaryWebRecordProjector _projector;
  final TemporaryWebBatchImportPort? _batchImportPort;
  final TemporaryWebRuntimeKeeper _runtimeKeeper;
  CardockLanguage _language;
  final TemporaryWebOperationCache _operationCache =
      TemporaryWebOperationCache();
  final Set<String> _sessionAccountIds = <String>{};
  final Set<String> _sessionSubscriptionIds = <String>{};
  final Map<String, TemporaryWebApproval> _approvals =
      <String, TemporaryWebApproval>{};
  final Map<String, Duration> _approvalDeadlines = <String, Duration>{};
  final Map<String, _ApprovalResult> _approvalResults =
      <String, _ApprovalResult>{};
  final Map<String, TemporaryWebBatchPreparedCommit> _batchApprovalRequests =
      <String, TemporaryWebBatchPreparedCommit>{};
  final Map<String, _PendingAccountSave> _accountSaves = {};
  final Map<String, String> _customFieldReveals = {};
  final Random _random = Random.secure();
  _TemporaryWebBatchUpload? _batchUpload;

  TemporaryWebSessionSnapshot _snapshot = TemporaryWebSessionSnapshot.stopped();
  Future<void> _commandTail = Future<void>.value();
  Timer? _maintenanceTimer;
  Duration? _startedAtMonotonic;
  int _epoch = 0;
  bool _disposed = false;
  int _controlledOperationDepth = 0;
  bool _runtimeKeeperStarted = false;
  bool _vaultTemporarilyUnavailable = false;
  bool _vaultAccessStateCheckPending = false;
  int? _lastKnownVaultRevision;
  String? _vaultBindingId;

  TemporaryWebSessionSnapshot get snapshot => _snapshot;

  /// Updates both the phone-facing URL and the locale returned to the browser.
  /// An active browser picks up the change on its next authenticated request.
  void updateLanguage(CardockLanguage language) {
    if (_language == language) return;
    _language = language;
    _snapshot = _copySnapshot(language: language);
    _notify();
  }

  bool get isPerformingControlledOperation => _controlledOperationDepth > 0;
  Duration get connectionRemaining => _remainingUntil(
    startedAt: _startedAtMonotonic,
    limit: _snapshot.policy.connectionDuration,
  );

  Duration approvalRemaining(TemporaryWebApproval approval) {
    final deadline = _approvalDeadlines[approval.id];
    if (deadline == null) return Duration.zero;
    final remaining = deadline - _monotonicNow();
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get canStart =>
      !_disposed &&
      !_snapshot.isRunning &&
      _gateway.isEligibleForTemporaryWebSession &&
      (_gateway.vaultBindingId?.trim().isNotEmpty ?? false);

  /// Applies a phone vault access transition without tearing down a merely
  /// locked session. If a write is already in flight, the transition is
  /// applied synchronously when that controlled operation finishes.
  void handleVaultAccessStateChanged() {
    if (!_snapshot.isRunning) return;
    if (_controlledOperationDepth > 0) {
      _vaultAccessStateCheckPending = true;
      return;
    }
    _vaultAccessStateCheckPending = false;
    _synchronizeVaultAccessState();
  }

  Future<List<TemporaryWebAddress>> listAddresses() async {
    final addresses = await _addressProvider.listPrivateIpv4Addresses();
    return List<TemporaryWebAddress>.unmodifiable(addresses);
  }

  Future<void> start({
    required TemporaryWebAddress address,
    required TemporaryWebSessionPolicy policy,
  }) async {
    if (!canStart) {
      throw StateError('当前保险库状态不允许开启电脑临时录入。');
    }
    if (!TemporaryWebSessionPolicy.allowedConnectionDurations.contains(
      policy.connectionDuration,
    )) {
      throw ArgumentError('连接时长必须为 1、5、10 或 30 分钟。');
    }
    if (!await _addressProvider.isStillAvailable(address.address)) {
      throw StateError('所选局域网地址已不可用，请重新选择。');
    }
    final vaultBindingId = _gateway.vaultBindingId;
    if (_gateway.accessState != TemporaryWebVaultAccessState.ready ||
        vaultBindingId == null ||
        vaultBindingId.trim().isEmpty) {
      throw StateError('当前保险库状态不允许开启电脑临时录入。');
    }

    final epoch = ++_epoch;
    _resetSessionMemory();
    _lastKnownVaultRevision = _gateway.revision;
    _vaultBindingId = vaultBindingId;
    _snapshot = TemporaryWebSessionSnapshot(
      phase: TemporaryWebSessionPhase.starting,
      policy: policy,
      language: _language,
      address: address.address,
      pendingApprovals: const <TemporaryWebApproval>[],
    );
    _notify();

    try {
      final binding = await _transport.start(
        address: address.address,
        onCommand: (command, remoteAddress) =>
            _enqueueCommand(epoch, command, remoteAddress),
        onPaired: (remoteAddress) => _handlePaired(epoch, remoteAddress),
        onFatalError: (error) => _handleFatalError(epoch, error),
      );
      await _runtimeKeeper.start();
      _runtimeKeeperStarted = true;
      if (!_isCurrent(epoch)) {
        await _stopRuntimeKeeper();
        _transport.revoke();
        await _transport.stop();
        return;
      }
      final now = _now();
      final monotonicNow = _monotonicNow();
      _startedAtMonotonic = monotonicNow;
      _snapshot = TemporaryWebSessionSnapshot(
        phase: TemporaryWebSessionPhase.waitingForPairing,
        policy: policy,
        language: _language,
        address: address.address,
        port: binding.port,
        formattedConnectionCode: binding.formattedConnectionCode,
        startedAt: now,
        lastMeaningfulActivityAt: now,
        pendingApprovals: const <TemporaryWebApproval>[],
      );
      _maintenanceTimer?.cancel();
      _maintenanceTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(enforceTimeoutsAndNetworkState()),
      );
      _notify();
    } on Object catch (error) {
      if (_isCurrent(epoch)) {
        stop(
          TemporaryWebStopReason.transportFailure,
          errorMessage: '局域网临时服务启动失败：${_safeError(error)}',
        );
      }
      rethrow;
    }
  }

  void stop(TemporaryWebStopReason reason, {String? errorMessage}) {
    if (_disposed && reason != TemporaryWebStopReason.disposed) return;
    ++_epoch;
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    _transport.revoke();
    final policy = _snapshot.policy;
    _resetSessionMemory();
    _snapshot = TemporaryWebSessionSnapshot.stopped(
      policy: policy,
      language: _language,
      stopReason: reason,
      errorMessage: errorMessage,
    );
    _notify();
    unawaited(_stopRuntimeKeeper());
    unawaited(_transport.stop());
  }

  Future<void> enforceTimeoutsAndNetworkState() async {
    final epoch = _epoch;
    final current = _snapshot;
    if (!current.isRunning) return;
    if (_stopIfTimedOut()) return;

    final accessState = _controlledOperationDepth > 0
        ? TemporaryWebVaultAccessState.ready
        : _synchronizeVaultAccessState();
    if (accessState == TemporaryWebVaultAccessState.invalid) return;
    if (accessState == TemporaryWebVaultAccessState.ready) {
      _expireApprovals();
      _expireBatchUpload();
    }
    if (!_isCurrent(epoch)) return;
  }

  Future<void> approve(String approvalId) async {
    final epoch = _epoch;
    final previous = _commandTail;
    final completer = Completer<void>();
    _commandTail = completer.future;
    var operationStarted = false;
    await previous.catchError((Object _) {});
    try {
      if (!_isCurrent(epoch) || !_snapshot.isRunning) return;
      _beginControlledOperation();
      operationStarted = true;
      if (_stopIfTimedOut()) return;
      if (_synchronizeVaultAccessState() !=
          TemporaryWebVaultAccessState.ready) {
        return;
      }
      _recordMeaningfulActivity();
      await _approve(epoch, approvalId);
    } finally {
      if (operationStarted) _endControlledOperation();
      completer.complete();
    }
  }

  Future<void> _approve(int epoch, String approvalId) async {
    final approval = _approvals[approvalId];
    if (approval == null || !_snapshot.isRunning) return;
    if (_isApprovalExpired(approval.id)) {
      _finishApproval(approval, <String, Object?>{
        'status': 'expired',
        'message': '手机确认已超时。',
      });
      return;
    }

    final records = _gateway.readRecords();
    final digest = await _digestApprovalTarget(approval, records);
    if (!_isCurrent(epoch) || !_snapshot.isRunning) return;
    if (_isApprovalExpired(approval.id)) {
      _finishApproval(approval, <String, Object?>{
        'status': 'expired',
        'message': '手机确认已超时。',
      });
      return;
    }
    final latestRecords = _gateway.readRecords();
    if (records.revision != approval.expectedRevision ||
        latestRecords.revision != records.revision ||
        digest != approval.expectedDigest) {
      _finishApproval(approval, <String, Object?>{
        'status': 'stale',
        'message': '记录已发生变化，请在网页刷新后重新提交。',
      });
      return;
    }
    if (_synchronizeVaultAccessState() != TemporaryWebVaultAccessState.ready) {
      return;
    }
    if (!identical(_approvals[approvalId], approval)) return;

    switch (approval.kind) {
      case TemporaryWebApprovalKind.deleteAccount:
        final result = await _gateway.deleteAccount(approval.targetId);
        if (!_isCurrent(epoch)) return;
        if (result.disposition == TemporaryWebMutationDisposition.committed) {
          _lastKnownVaultRevision = result.revision;
          _sessionAccountIds.remove(approval.targetId);
          final remaining = _gateway.readRecords().subscriptions;
          final remainingIds = <String>{for (final item in remaining) item.id};
          _sessionSubscriptionIds.removeWhere(
            (id) => !remainingIds.contains(id),
          );
        }
        _finishApproval(approval, result.toJson());
        break;
      case TemporaryWebApprovalKind.deleteSubscription:
        final result = await _gateway.deleteSubscription(approval.targetId);
        if (!_isCurrent(epoch)) return;
        if (result.disposition == TemporaryWebMutationDisposition.committed) {
          _lastKnownVaultRevision = result.revision;
          _sessionSubscriptionIds.remove(approval.targetId);
        }
        _finishApproval(approval, result.toJson());
        break;
      case TemporaryWebApprovalKind.revealPassword:
        final account = records.accounts
            .where((candidate) => candidate.id == approval.targetId)
            .firstOrNull;
        _finishApproval(approval, <String, Object?>{
          'status': 'approved',
          'password': account?.password,
          'visibleForMilliseconds': _passwordResultLifetime.inMilliseconds,
        }, lifetime: _passwordResultLifetime);
        break;
      case TemporaryWebApprovalKind.revealCustomField:
        final fieldId = _customFieldReveals[approval.id];
        final account = records.accounts
            .where((a) => a.id == approval.targetId)
            .firstOrNull;
        final field = account?.customFields
            .where((f) => f.id == fieldId)
            .firstOrNull;
        _finishApproval(approval, <String, Object?>{
          'status': 'approved',
          'secret': field?.value,
          'visibleForMilliseconds': _passwordResultLifetime.inMilliseconds,
        }, lifetime: _passwordResultLifetime);
        break;
      case TemporaryWebApprovalKind.saveAccount:
        final pending = _accountSaves[approval.id];
        if (pending == null) {
          _finishApproval(approval, const {'status': 'rejected'});
          break;
        }
        late final TemporaryWebMutationResult result;
        if (pending.accountId == null) {
          final phoneGateway = _gateway;
          if (phoneGateway is! TemporaryWebPhoneApprovedAccountGateway) {
            _finishApproval(approval, const {
              'status': 'rejected',
              'message': '手机保存审批接口不可用。',
            });
            break;
          }
          result =
              await (phoneGateway as TemporaryWebPhoneApprovedAccountGateway)
                  .addAccountAfterPhoneApproval(
                    pending.draft,
                    expectedRevision: approval.expectedRevision,
                  );
        } else {
          result = await _gateway.updateAccount(
            accountId: pending.accountId!,
            draft: pending.draft,
            passwordMode: pending.passwordMode,
          );
        }
        if (!_isCurrent(epoch)) return;
        if (result.disposition == TemporaryWebMutationDisposition.committed) {
          _lastKnownVaultRevision = result.revision;
          if (pending.accountId == null && result.recordId != null) {
            _sessionAccountIds.add(result.recordId!);
          }
        }
        _finishApproval(approval, result.toJson());
        break;
      case TemporaryWebApprovalKind.batchImport:
        final prepared = _batchApprovalRequests[approval.id];
        final port = _batchImportPort;
        if (prepared == null || port == null || !port.isAvailable) {
          _finishApproval(approval, const <String, Object?>{
            'status': 'rejected',
            'message': '批量导入权威预览已失效，请重新生成。',
          });
          break;
        }
        try {
          final result = await port.approveCommit(
            prepared.approvalToken,
            expectedRevision: approval.expectedRevision,
          );
          if (!_isCurrent(epoch)) return;
          _lastKnownVaultRevision = _gateway.revision;
          _finishApproval(approval, result.toJson());
        } on Object {
          if (!_isCurrent(epoch)) return;
          _finishApproval(approval, const <String, Object?>{
            'status': 'rejected',
            'message': '手机端最终校验未通过，本次整批未写入。',
          });
        }
        break;
    }
  }

  Future<void> reject(String approvalId) async {
    final epoch = _epoch;
    final previous = _commandTail;
    final completer = Completer<void>();
    _commandTail = completer.future;
    var operationStarted = false;
    await previous.catchError((Object _) {});
    try {
      if (!_isCurrent(epoch) || !_snapshot.isRunning) return;
      _beginControlledOperation();
      operationStarted = true;
      if (_stopIfTimedOut()) return;
      if (_synchronizeVaultAccessState() !=
          TemporaryWebVaultAccessState.ready) {
        return;
      }
      final approval = _approvals[approvalId];
      if (approval == null) return;
      if (_isApprovalExpired(approval.id)) {
        _finishApproval(approval, <String, Object?>{
          'status': 'expired',
          'message': '手机确认已超时。',
        });
        return;
      }
      _recordMeaningfulActivity();
      _finishApproval(approval, <String, Object?>{
        'status': 'rejected',
        'message': '手机端已拒绝。',
      });
    } finally {
      if (operationStarted) _endControlledOperation();
      completer.complete();
    }
  }

  Future<Map<String, Object?>> _enqueueCommand(
    int epoch,
    Map<String, Object?> command,
    String remoteAddress,
  ) async {
    final previous = _commandTail;
    final completer = Completer<void>();
    _commandTail = completer.future;
    var operationStarted = false;
    await previous.catchError((Object _) {});
    try {
      if (!_isCurrent(epoch) ||
          _snapshot.phase != TemporaryWebSessionPhase.connected) {
        return const <String, Object?>{
          'status': 'sessionEnded',
          'message': '网页会话已结束。',
        };
      }
      _beginControlledOperation();
      operationStarted = true;
      return await _handleCommand(epoch, command, remoteAddress);
    } finally {
      if (operationStarted) {
        _endControlledOperation();
      }
      completer.complete();
    }
  }

  Future<Map<String, Object?>> _handleCommand(
    int epoch,
    Map<String, Object?> command,
    String remoteAddress,
  ) async {
    if (_snapshot.connectedClientAddress != remoteAddress) {
      return const <String, Object?>{
        'status': 'rejected',
        'message': '客户端地址与已确认会话不一致。',
      };
    }
    if (_stopIfTimedOut()) return _sessionEndedResult();
    final action = _requiredString(command, 'action', maximumLength: 48);
    final accessState = _synchronizeVaultAccessState();
    if (accessState == TemporaryWebVaultAccessState.invalid) {
      return const <String, Object?>{
        'status': 'sessionEnded',
        'message': '手机保险库状态已变化。',
      };
    }
    if (action == 'sessionStatus') {
      return <String, Object?>{
        'status': 'ok',
        'vaultAccess': _vaultAccessName(accessState),
        'locale': _language.storageCode,
        'timeouts': _timeoutState(),
      };
    }
    if (action == 'activity') {
      _recordMeaningfulActivity();
      return <String, Object?>{
        'status': 'ok',
        'vaultAccess': _vaultAccessName(accessState),
        'locale': _language.storageCode,
        'timeouts': _timeoutState(),
      };
    }
    if (action == 'disconnect') {
      Future<void>.microtask(() {
        if (_isCurrent(epoch)) stop(TemporaryWebStopReason.user);
      });
      return const <String, Object?>{'status': 'ok'};
    }
    if (accessState == TemporaryWebVaultAccessState.temporarilyUnavailable) {
      return _phoneUnlockRequiredResult();
    }
    if (action == 'approvalResult') {
      return _takeApprovalResult(
        _requiredString(command, 'approvalId', maximumLength: 80),
      );
    }
    if (action == 'operationResult') {
      final requestId = _requiredRequestId(command);
      return _operationCache[requestId] ??
          const <String, Object?>{
            'status': 'notFound',
            'message': '本会话中没有该操作结果。',
          };
    }

    _recordMeaningfulActivity();
    if (action == 'snapshot') {
      final data = _projectCurrentRecords();
      _lastKnownVaultRevision = data['revision']! as int;
      return <String, Object?>{
        'status': 'ok',
        'vaultAccess': 'ready',
        'locale': _language.storageCode,
        'data': data,
      };
    }

    final requestId = _requiredRequestId(command);
    final cached = _operationCache[requestId];
    if (cached != null) return cached;

    Map<String, Object?> response;
    try {
      response = await _handleMutation(epoch, action, command);
    } on TemporaryWebBatchImportException catch (error) {
      response = <String, Object?>{
        'status': 'rejected',
        'errorCode': error.code,
        'message': error.message,
      };
    } on FormatException catch (error) {
      response = <String, Object?>{
        'status': 'rejected',
        'message': error.message,
      };
    } on ArgumentError catch (error) {
      response = <String, Object?>{
        'status': 'rejected',
        'message': error.message?.toString() ?? '提交内容无效。',
      };
    }
    if (!_isCurrent(epoch)) return response;
    _trackCommittedRevision(response);
    if (response['status'] != 'phoneUnlockRequired') {
      _operationCache.put(requestId, response);
    }
    return response;
  }

  Future<Map<String, Object?>> _handleMutation(
    int epoch,
    String action,
    Map<String, Object?> command,
  ) async {
    final expectedRevision = _requiredInt(command, 'expectedRevision');
    final records = _gateway.readRecords();
    if (records.revision != expectedRevision) {
      return <String, Object?>{
        'status': 'conflict',
        'revision': records.revision,
        'message': '手机数据已变化，请刷新网页后再操作。',
      };
    }
    final body = _requiredMap(command, 'body');

    switch (action) {
      case 'addAccount':
        return _requestAccountSave(epoch, records, body);
      case 'updateAccount':
        final accountId = _requiredString(body, 'id', maximumLength: 128);
        final existing = records.accounts
            .where((candidate) => candidate.id == accountId)
            .firstOrNull;
        if (existing == null) throw const FormatException('账号记录不存在。');
        final isCurrent = _sessionAccountIds.contains(accountId);
        if (!isCurrent && !_canEditHistoricalRecords) {
          throw const FormatException('本会话未允许编辑历史账号。');
        }
        if (body.containsKey('customFields') ||
            existing.customFields.isNotEmpty) {
          return _requestAccountSave(epoch, records, body, existing: existing);
        }
        final passwordMode = _passwordMode(body['passwordMode']);
        final result = await _gateway.updateAccount(
          accountId: accountId,
          draft: _accountDraft(body),
          passwordMode: passwordMode,
        );
        if (!_isCurrent(epoch)) return _writeResultUnknown();
        return result.toJson();
      case 'deleteAccount':
        return _requestAccountDeletion(epoch, records, body);
      case 'addSubscription':
        final draft = _subscriptionDraft(body);
        _requireVisibleAccount(records, draft.accountId);
        final result = await _gateway.addSubscription(draft);
        if (!_isCurrent(epoch)) return _writeResultUnknown();
        if (result.disposition == TemporaryWebMutationDisposition.committed &&
            result.recordId != null) {
          _sessionSubscriptionIds.add(result.recordId!);
        }
        return result.toJson();
      case 'updateSubscription':
        final id = _requiredString(body, 'id', maximumLength: 128);
        final existing = records.subscriptions
            .where((candidate) => candidate.id == id)
            .firstOrNull;
        if (existing == null) throw const FormatException('订阅记录不存在。');
        final isCurrent = _sessionSubscriptionIds.contains(id);
        if (!isCurrent && !_canEditHistoricalRecords) {
          throw const FormatException('本会话未允许编辑历史订阅。');
        }
        final draft = _subscriptionDraft(body);
        _requireVisibleAccount(records, draft.accountId);
        final result = await _gateway.updateSubscription(
          subscriptionId: id,
          draft: draft,
        );
        if (!_isCurrent(epoch)) return _writeResultUnknown();
        return result.toJson();
      case 'deleteSubscription':
        return _requestSubscriptionDeletion(epoch, records, body);
      case 'requestCustomField':
        return _requestCustomField(epoch, records, body);
      case 'requestHistoricalPassword':
        return _requestHistoricalPassword(epoch, records, body);
      case 'batchImportUploadStart':
        final port = _batchImportPort;
        if (port == null || !port.isAvailable) {
          return const <String, Object?>{
            'status': 'unavailable',
            'message': '手机端批量导入尚不可用。',
          };
        }
        final sessionId = _requiredString(body, 'sessionId', maximumLength: 80);
        if (!_requestIdPattern.hasMatch(sessionId)) {
          throw const FormatException('sessionId 格式无效。');
        }
        final totalBytes = _requiredInt(body, 'totalBytes');
        final totalChunks = _requiredInt(body, 'totalChunks');
        final expectedChunks =
            (totalBytes + temporaryWebBatchImportChunkBytes - 1) ~/
            temporaryWebBatchImportChunkBytes;
        if (totalBytes < 1 ||
            totalBytes > temporaryWebMaximumBatchImportBytes ||
            totalChunks < 1 ||
            totalChunks > 64 ||
            totalChunks != expectedChunks) {
          throw const FormatException('批量文件分块参数无效。');
        }
        _destroyBatchUpload();
        _batchUpload = _TemporaryWebBatchUpload(
          sessionId: sessionId,
          fileName: _requiredString(body, 'fileName', maximumLength: 255),
          sourceId:
              _optionalString(body, 'sourceId', maximumLength: 64) ?? 'auto',
          expectedRevision: expectedRevision,
          totalBytes: totalBytes,
          totalChunks: totalChunks,
          expiresAtMonotonic: _monotonicNow() + _batchUploadLifetime,
        );
        return const <String, Object?>{'status': 'ok', 'nextSequence': 0};
      case 'batchImportUploadChunk':
        _expireBatchUpload();
        final upload = _batchUpload;
        if (upload == null) {
          throw const FormatException('批量文件分块会话不存在或已超时。');
        }
        final sessionId = _requiredString(body, 'sessionId', maximumLength: 80);
        final sequence = _requiredInt(body, 'sequence');
        final totalChunks = _requiredInt(body, 'totalChunks');
        if (sessionId != upload.sessionId ||
            totalChunks != upload.totalChunks ||
            expectedRevision != upload.expectedRevision ||
            sequence != upload.nextSequence) {
          _destroyBatchUpload();
          throw const FormatException('批量文件分块重复、缺失或乱序。');
        }
        final encoded = _requiredString(
          body,
          'contentBase64',
          maximumLength: ((temporaryWebBatchImportChunkBytes + 2) ~/ 3) * 4,
        );
        Uint8List chunk;
        try {
          chunk = base64Decode(encoded);
        } on FormatException {
          _destroyBatchUpload();
          throw const FormatException('批量文件分块编码无效。');
        }
        try {
          upload.add(sequence: sequence, chunk: chunk);
          return <String, Object?>{
            'status': 'ok',
            'nextSequence': upload.nextSequence,
          };
        } on FormatException {
          _destroyBatchUpload();
          rethrow;
        } finally {
          chunk.fillRange(0, chunk.length, 0);
        }
      case 'batchImportUploadFinish':
        _expireBatchUpload();
        final port = _batchImportPort;
        final upload = _batchUpload;
        if (port == null || !port.isAvailable || upload == null) {
          _destroyBatchUpload();
          return const <String, Object?>{
            'status': 'unavailable',
            'message': '批量文件分块会话不存在或已超时。',
          };
        }
        final sessionId = _requiredString(body, 'sessionId', maximumLength: 80);
        final totalChunks = _requiredInt(body, 'totalChunks');
        if (sessionId != upload.sessionId ||
            totalChunks != upload.totalChunks ||
            expectedRevision != upload.expectedRevision ||
            !upload.isComplete) {
          _destroyBatchUpload();
          throw const FormatException('批量文件分块不完整。');
        }
        final bytes = upload.takeBytes();
        _batchUpload = null;
        try {
          final visibleAccounts = _visibleBatchAccounts();
          final preview = await port.preview(
            TemporaryWebBatchImportRequest(
              fileName: upload.fileName,
              bytes: bytes,
              sourceId: upload.sourceId,
              expectedRevision: expectedRevision,
              previewScope: _historyRecordsAreVisible
                  ? TemporaryWebBatchPreviewScope.authorizedHistory
                  : TemporaryWebBatchPreviewScope.currentSessionAuthorizedOnly,
              visibleAccounts: visibleAccounts,
              visibleAccountTargets: _visibleBatchAccountTargets(),
            ),
          );
          if (!_isCurrent(epoch)) return _writeResultUnknown();
          return <String, Object?>{'status': 'ok', 'data': preview.toJson()};
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      case 'batchImportCommit':
        final port = _batchImportPort;
        if (port == null || !port.isAvailable) {
          return const <String, Object?>{
            'status': 'unavailable',
            'message': '手机端批量导入尚不可用。',
          };
        }
        final selectedRowIds = _requiredStringSet(
          body,
          'selectedRowIds',
          maximumItems: 5000,
          maximumItemLength: 128,
        );
        if (selectedRowIds.isEmpty) {
          throw const FormatException('至少选择一条可导入记录。');
        }
        final resolutions = _requiredStringMap(
          body,
          'duplicateResolutions',
          maximumItems: 5000,
          maximumKeyLength: 128,
          maximumValueLength: 32,
        );
        final subscriptionTargets = _requiredStringMap(
          body,
          'subscriptionAccountTargets',
          maximumItems: 5000,
          maximumKeyLength: 128,
          maximumValueLength: 256,
        );
        final currentlyVisibleTargets = _visibleBatchAccountTargets();
        if (subscriptionTargets.values.any(
          (targetId) => !currentlyVisibleTargets.containsKey(targetId),
        )) {
          throw const FormatException('订阅关联账号不在本次网页授权可见范围内。');
        }
        final request = TemporaryWebBatchCommitRequest(
          previewToken: _requiredString(
            body,
            'previewToken',
            maximumLength: 256,
          ),
          expectedRevision: expectedRevision,
          selectedRowIds: selectedRowIds,
          duplicateResolutions: resolutions,
          subscriptionAccountTargets: subscriptionTargets,
        );
        final prepared = await port.prepareCommit(request);
        if (!_isCurrent(epoch)) {
          port.clearSensitiveMemory();
          return _writeResultUnknown();
        }
        if (prepared.expectedRevision != expectedRevision ||
            !prepared.quotaAllowed) {
          port.clearSensitiveMemory();
          throw const FormatException('批量导入权威计划未通过最终校验。');
        }
        final digest = await _digestJson(prepared.toSafeJson());
        if (!_isCurrent(epoch)) {
          port.clearSensitiveMemory();
          return _writeResultUnknown();
        }
        final response = _createApproval(
          kind: TemporaryWebApprovalKind.batchImport,
          targetId: 'batch-import',
          title: '确认批量导入',
          detail: prepared.safeApprovalDetail,
          detailTranslationKey: prepared.safeApprovalTranslationKey,
          detailTranslationValues: prepared.safeApprovalTranslationValues,
          expectedRevision: expectedRevision,
          expectedDigest: digest,
        );
        final approvalId = response['approvalId']! as String;
        _batchApprovalRequests[approvalId] = prepared;
        return response;
      case 'batchImportRevise':
        final port = _batchImportPort;
        if (port == null || !port.isAvailable) {
          return const <String, Object?>{
            'status': 'unavailable',
            'message': '手机端批量导入尚不可用。',
          };
        }
        final rawMappings = _requiredStringMap(
          body,
          'mappingOverrides',
          maximumItems: 256,
          maximumKeyLength: 8,
          maximumValueLength: 64,
        );
        final mappings = <int, String?>{};
        for (final entry in rawMappings.entries) {
          final index = int.tryParse(entry.key);
          if (index == null || index < 0 || index > 255) {
            throw const FormatException('字段映射序号无效。');
          }
          mappings[index] = entry.value == 'ignore' ? null : entry.value;
        }
        final preview = await port.revisePreview(
          TemporaryWebBatchRevisionRequest(
            previewToken: _requiredString(
              body,
              'previewToken',
              maximumLength: 256,
            ),
            expectedRevision: expectedRevision,
            mappingOverrides: mappings,
            rowPatches: _requiredNestedStringMap(
              body,
              'rowPatches',
              maximumRows: 5000,
              maximumFieldsPerRow: 16,
              maximumKeyLength: 128,
              maximumFieldLength: 64,
              maximumValueLength: 4096,
            ),
            defaultValues: _requiredStringMap(
              body,
              'defaultValues',
              maximumItems: 16,
              maximumKeyLength: 64,
              maximumValueLength: 4096,
            ),
            removeDocumentKind: _optionalString(
              body,
              'removeDocumentKind',
              maximumLength: 32,
            ),
            activateDocumentKind: _optionalString(
              body,
              'activateDocumentKind',
              maximumLength: 32,
            ),
          ),
        );
        if (!_isCurrent(epoch)) {
          port.clearSensitiveMemory();
          return _writeResultUnknown();
        }
        return <String, Object?>{'status': 'ok', 'data': preview.toJson()};
      case 'batchImportClear':
        _clearBatchImportState();
        return const <String, Object?>{'status': 'ok'};
      default:
        throw const FormatException('不支持的网页操作。');
    }
  }

  Future<Map<String, Object?>> _requestAccountDeletion(
    int epoch,
    TemporaryWebVaultRecords records,
    Map<String, Object?> body,
  ) async {
    final id = _requiredString(body, 'id', maximumLength: 128);
    final account = records.accounts
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (account == null) throw const FormatException('账号记录不存在。');
    if (!_sessionAccountIds.contains(id) && !_historyRecordsAreVisible) {
      throw const FormatException('该历史账号不在本会话可见范围内。');
    }
    final linked = records.subscriptions
        .where((subscription) => subscription.accountId == id)
        .toList(growable: false);
    final canDeleteDirectly =
        _sessionAccountIds.contains(id) &&
        linked.every(
          (subscription) => _sessionSubscriptionIds.contains(subscription.id),
        );
    if (canDeleteDirectly) {
      final result = await _gateway.deleteAccount(id);
      if (!_isCurrent(epoch)) return _writeResultUnknown();
      if (result.disposition == TemporaryWebMutationDisposition.committed) {
        _sessionAccountIds.remove(id);
        for (final subscription in linked) {
          _sessionSubscriptionIds.remove(subscription.id);
        }
      }
      return result.toJson();
    }

    final digest = await _digestAccount(account, linked);
    if (!_isCurrent(epoch)) return _sessionEndedResult();
    return _createApproval(
      kind: TemporaryWebApprovalKind.deleteAccount,
      targetId: id,
      title: '确认删除历史账号',
      detail: linked.isEmpty
          ? '将删除“${account.platformName}”。'
          : '将删除“${account.platformName}”及 ${linked.length} 条关联订阅。',
      expectedRevision: records.revision,
      expectedDigest: digest,
    );
  }

  Future<Map<String, Object?>> _requestSubscriptionDeletion(
    int epoch,
    TemporaryWebVaultRecords records,
    Map<String, Object?> body,
  ) async {
    final id = _requiredString(body, 'id', maximumLength: 128);
    final subscription = records.subscriptions
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (subscription == null) throw const FormatException('订阅记录不存在。');
    if (!_sessionSubscriptionIds.contains(id) && !_historyRecordsAreVisible) {
      throw const FormatException('该历史订阅不在本会话可见范围内。');
    }
    if (_sessionSubscriptionIds.contains(id)) {
      final result = await _gateway.deleteSubscription(id);
      if (!_isCurrent(epoch)) return _writeResultUnknown();
      if (result.disposition == TemporaryWebMutationDisposition.committed) {
        _sessionSubscriptionIds.remove(id);
      }
      return result.toJson();
    }

    final digest = await _digestJson(subscription.toEncryptedPayloadJson());
    if (!_isCurrent(epoch)) return _sessionEndedResult();
    return _createApproval(
      kind: TemporaryWebApprovalKind.deleteSubscription,
      targetId: id,
      title: '确认删除历史订阅',
      detail: '将删除“${subscription.serviceName}”。',
      expectedRevision: records.revision,
      expectedDigest: digest,
    );
  }

  Future<Map<String, Object?>> _requestAccountSave(
    int epoch,
    TemporaryWebVaultRecords records,
    Map<String, Object?> body, {
    AccountRecord? existing,
  }) async {
    final gateway = _gateway;
    if (existing == null &&
        gateway is! TemporaryWebPhoneApprovedAccountGateway) {
      throw const FormatException('手机保存审批接口不可用。');
    }
    final draft = _accountDraft(body, existing: existing);
    final passwordMode = existing == null
        ? AccountPasswordUpdateMode.replace
        : _passwordMode(body['passwordMode']);
    final pending = _PendingAccountSave(draft, existing?.id, passwordMode);
    final digest = await _digestJson(pending.toJson(existing));
    if (!_isCurrent(epoch)) return _sessionEndedResult();
    final duplicates = existing == null
        ? (gateway as TemporaryWebPhoneApprovedAccountGateway)
              .duplicateAccountLabels(draft)
        : const <String>[];
    final result = _createApproval(
      kind: TemporaryWebApprovalKind.saveAccount,
      targetId: existing?.id ?? 'new-account',
      title: '确认保存电脑录入账号',
      detail: duplicates.isEmpty
          ? '将保存“${draft.platformName}”及其自定义字段。'
          : '发现相似账号：${duplicates.join('；')}。请返回手机核对或恢复；只有选择“仍然新增”才会新增。',
      duplicateConfirmationRequired: duplicates.isNotEmpty,
      expectedRevision: records.revision,
      expectedDigest: digest,
    );
    _accountSaves[result['approvalId']! as String] = pending;
    return result;
  }

  Future<Map<String, Object?>> _requestCustomField(
    int epoch,
    TemporaryWebVaultRecords records,
    Map<String, Object?> body,
  ) async {
    final id = _requiredString(body, 'id', maximumLength: 128);
    if (!_sessionAccountIds.contains(id) &&
        _snapshot.policy.historyMode != TemporaryWebHistoryMode.details) {
      throw const FormatException('本会话未允许查看历史详情。');
    }
    final fieldId = _requiredString(body, 'fieldId', maximumLength: 128);
    final account = records.accounts.where((a) => a.id == id).firstOrNull;
    final field = account?.customFields
        .where((f) => f.id == fieldId)
        .firstOrNull;
    if (account == null || field == null || !field.isSensitive) {
      throw const FormatException('敏感字段不可用。');
    }
    final digest = await _digestJson(account.toEncryptedPayloadJson());
    if (!_isCurrent(epoch)) return _sessionEndedResult();
    final result = _createApproval(
      kind: TemporaryWebApprovalKind.revealCustomField,
      targetId: id,
      title: '确认临时显示敏感字段',
      detail: '网页将显示“${account.platformName}”的“${field.name}” 30 秒。',
      expectedRevision: records.revision,
      expectedDigest: digest,
    );
    _customFieldReveals[result['approvalId']! as String] = fieldId;
    return result;
  }

  Future<Map<String, Object?>> _requestHistoricalPassword(
    int epoch,
    TemporaryWebVaultRecords records,
    Map<String, Object?> body,
  ) async {
    if (!_historyRecordsAreVisible ||
        !_snapshot.policy.allowHistoricalPasswordReveal) {
      throw const FormatException('本会话未允许查看历史密码。');
    }
    final id = _requiredString(body, 'id', maximumLength: 128);
    if (_sessionAccountIds.contains(id)) {
      throw const FormatException('本次新建账号的密码已随详情提供。');
    }
    final account = records.accounts
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (account == null) throw const FormatException('账号记录不存在。');
    if (account.password == null) {
      return const <String, Object?>{
        'status': 'notAvailable',
        'message': '该账号没有保存密码。',
      };
    }
    final digest = await _digestJson(account.toEncryptedPayloadJson());
    if (!_isCurrent(epoch)) return _sessionEndedResult();
    return _createApproval(
      kind: TemporaryWebApprovalKind.revealPassword,
      targetId: id,
      title: '确认临时显示历史密码',
      detail: '网页将显示“${account.platformName}”的密码 30 秒。',
      expectedRevision: records.revision,
      expectedDigest: digest,
    );
  }

  Map<String, Object?> _createApproval({
    required TemporaryWebApprovalKind kind,
    required String targetId,
    required String title,
    required String detail,
    required int expectedRevision,
    required String expectedDigest,
    bool duplicateConfirmationRequired = false,
    String? detailTranslationKey,
    Map<String, Object?> detailTranslationValues = const <String, Object?>{},
  }) {
    final now = _now();
    final monotonicDeadline = _monotonicNow() + _approvalLifetime;
    final id = _randomId();
    _approvals[id] = TemporaryWebApproval(
      id: id,
      kind: kind,
      targetId: targetId,
      title: title,
      detail: detail,
      createdAt: now,
      expiresAt: now.add(_approvalLifetime),
      expectedRevision: expectedRevision,
      expectedDigest: expectedDigest,
      duplicateConfirmationRequired: duplicateConfirmationRequired,
      detailTranslationKey: detailTranslationKey,
      detailTranslationValues: detailTranslationValues,
    );
    _approvalDeadlines[id] = monotonicDeadline;
    _refreshApprovalSnapshot();
    return <String, Object?>{
      'status': 'pendingPhoneApproval',
      'approvalId': id,
      'expiresAt': now.add(_approvalLifetime).toUtc().toIso8601String(),
    };
  }

  void _finishApproval(
    TemporaryWebApproval approval,
    Map<String, Object?> result, {
    Duration lifetime = _approvalLifetime,
  }) {
    _accountSaves.remove(approval.id);
    _customFieldReveals.remove(approval.id);
    if (approval.kind == TemporaryWebApprovalKind.batchImport) {
      _batchApprovalRequests.remove(approval.id);
      _batchImportPort?.clearSensitiveMemory();
    }
    _approvals.remove(approval.id);
    _approvalDeadlines.remove(approval.id);
    _approvalResults[approval.id] = _ApprovalResult(
      value: Map<String, Object?>.unmodifiable(result),
      expiresAtMonotonic: _monotonicNow() + lifetime,
    );
    _refreshApprovalSnapshot();
  }

  Map<String, Object?> _takeApprovalResult(String approvalId) {
    _expireApprovals();
    if (_approvals.containsKey(approvalId)) {
      return const <String, Object?>{'status': 'pendingPhoneApproval'};
    }
    final result = _approvalResults.remove(approvalId);
    if (result == null || _hasReached(result.expiresAtMonotonic)) {
      return const <String, Object?>{
        'status': 'notFound',
        'message': '确认结果不存在或已过期。',
      };
    }
    if (result.value.containsKey('secret') ||
        result.value.containsKey('password')) {
      final remaining =
          (result.expiresAtMonotonic - _monotonicNow()).inMilliseconds;
      if (remaining <= 0) return const {'status': 'expired'};
      return {
        ...result.value,
        'visibleForMilliseconds': remaining.clamp(
          1,
          _passwordResultLifetime.inMilliseconds,
        ),
      };
    }
    return result.value;
  }

  void _handlePaired(int epoch, String remoteAddress) {
    if (!_isCurrent(epoch) ||
        _snapshot.phase != TemporaryWebSessionPhase.waitingForPairing) {
      return;
    }
    _snapshot = _copySnapshot(
      phase: TemporaryWebSessionPhase.connected,
      connectedClientAddress: remoteAddress,
      lastMeaningfulActivityAt: _now(),
      clearConnectionCode: true,
    );
    _notify();
  }

  void _handleFatalError(int epoch, Object error) {
    if (!_isCurrent(epoch)) return;
    if (error is TemporaryWebPairingRejectedException) {
      stop(
        TemporaryWebStopReason.pairingRejected,
        errorMessage: '连接码验证失败或配对请求已失效。请重新开启本次临时连接。',
      );
      return;
    }
    stop(
      TemporaryWebStopReason.transportFailure,
      errorMessage: '网页连接异常：${_safeError(error)}',
    );
  }

  void _recordMeaningfulActivity() {
    _snapshot = _copySnapshot(lastMeaningfulActivityAt: _now());
    _notify();
  }

  TemporaryWebVaultAccessState _synchronizeVaultAccessState() {
    final accessState = _gateway.accessState;
    switch (accessState) {
      case TemporaryWebVaultAccessState.invalid:
        stop(TemporaryWebStopReason.vaultChanged);
        return TemporaryWebVaultAccessState.invalid;
      case TemporaryWebVaultAccessState.temporarilyUnavailable:
        if (!_vaultTemporarilyUnavailable) {
          _vaultTemporarilyUnavailable = true;
          _clearBatchImportState(refreshApprovals: false);
          _operationCache.clear();
          _accountSaves.clear();
          _customFieldReveals.clear();
          _approvals.clear();
          _approvalDeadlines.clear();
          _approvalResults.clear();
          _batchApprovalRequests.clear();
          _refreshApprovalSnapshot();
        }
        return TemporaryWebVaultAccessState.temporarilyUnavailable;
      case TemporaryWebVaultAccessState.ready:
        if (_vaultTemporarilyUnavailable) {
          final knownRevision = _lastKnownVaultRevision;
          final knownBindingId = _vaultBindingId;
          final currentBindingId = _gateway.vaultBindingId;
          if (knownRevision == null ||
              knownBindingId == null ||
              currentBindingId == null ||
              currentBindingId != knownBindingId ||
              _gateway.revision != knownRevision) {
            stop(TemporaryWebStopReason.vaultChanged);
            return TemporaryWebVaultAccessState.invalid;
          }
          _vaultTemporarilyUnavailable = false;
        }
        return TemporaryWebVaultAccessState.ready;
    }
  }

  String _vaultAccessName(TemporaryWebVaultAccessState state) =>
      switch (state) {
        TemporaryWebVaultAccessState.ready => 'ready',
        TemporaryWebVaultAccessState.temporarilyUnavailable => 'locked',
        TemporaryWebVaultAccessState.invalid => 'invalid',
      };

  Map<String, Object?> _phoneUnlockRequiredResult() => <String, Object?>{
    'status': 'phoneUnlockRequired',
    'vaultAccess': 'locked',
    'locale': _language.storageCode,
    'timeouts': _timeoutState(),
    'message': '手机暂时锁定，连接仍保留；请先解锁同一个保险库，再点击“刷新”或重新提交。',
  };

  void _trackCommittedRevision(Map<String, Object?> response) {
    if (response['status'] != 'committed') return;
    final revision = response['revision'];
    if (revision is int) _lastKnownVaultRevision = revision;
  }

  Future<void> _stopRuntimeKeeper() async {
    if (!_runtimeKeeperStarted) return;
    _runtimeKeeperStarted = false;
    try {
      await _runtimeKeeper.stop();
    } on Object {
      // The listener and encrypted session are already revoked independently.
    }
  }

  bool get _historyRecordsAreVisible =>
      _snapshot.policy.historyMode !=
      TemporaryWebHistoryMode.currentSessionOnly;

  bool get _canEditHistoricalRecords =>
      _snapshot.policy.historyMode == TemporaryWebHistoryMode.details &&
      _snapshot.policy.allowHistoryEditing;

  void _requireVisibleAccount(
    TemporaryWebVaultRecords records,
    String? accountId,
  ) {
    if (accountId == null) return;
    final exists = records.accounts.any((account) => account.id == accountId);
    if (!exists) throw const FormatException('关联账号不存在。');
    if (!_sessionAccountIds.contains(accountId) && !_historyRecordsAreVisible) {
      throw const FormatException('关联账号不在本会话可见范围内。');
    }
  }

  bool _stopIfTimedOut() {
    if (!_snapshot.isRunning) return false;
    if (connectionRemaining == Duration.zero) {
      stop(TemporaryWebStopReason.absoluteTimeout);
      return true;
    }
    return false;
  }

  bool _hasReached(Duration deadline) =>
      _monotonicNow().compareTo(deadline) >= 0;

  bool _isApprovalExpired(String approvalId) {
    final deadline = _approvalDeadlines[approvalId];
    return deadline == null || _hasReached(deadline);
  }

  Duration _remainingUntil({
    required Duration? startedAt,
    required Duration limit,
  }) {
    if (startedAt == null) return limit;
    final elapsed = _monotonicNow() - startedAt;
    final remaining = limit - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Map<String, Object?> _timeoutState() => <String, Object?>{
    'connectionDurationMilliseconds':
        _snapshot.policy.connectionDuration.inMilliseconds,
    'connectionRemainingMilliseconds': connectionRemaining.inMilliseconds,
  };

  Map<String, Object?> _projectCurrentRecords() => <String, Object?>{
    ..._projector.project(
      records: _gateway.readRecords(),
      policy: _snapshot.policy,
      sessionAccountIds: _sessionAccountIds,
      sessionSubscriptionIds: _sessionSubscriptionIds,
    ),
    'timeouts': _timeoutState(),
    'batchImportAvailable': _batchImportPort?.isAvailable == true,
  };

  Map<String, String> _visibleBatchAccountTargets() {
    final projection = _projector.project(
      records: _gateway.readRecords(),
      policy: _snapshot.policy,
      sessionAccountIds: _sessionAccountIds,
      sessionSubscriptionIds: _sessionSubscriptionIds,
    );
    final accounts = projection['accounts'];
    if (accounts is! List) return const <String, String>{};
    final result = <String, String>{};
    for (final raw in accounts) {
      if (raw is! Map) continue;
      final id = raw['id'];
      final platformName = raw['platformName'];
      final loginAccount = raw['loginAccount'];
      if (id is! String || id.isEmpty || platformName is! String) continue;
      final label = <String>[
        platformName,
        if (loginAccount is String) loginAccount,
      ].where((value) => value.isNotEmpty).join(' · ');
      result[id] = label.isEmpty ? '已有账号' : label;
    }
    return Map<String, String>.unmodifiable(result);
  }

  List<TemporaryWebBatchVisibleAccount> _visibleBatchAccounts() {
    final projection = _projector.project(
      records: _gateway.readRecords(),
      policy: _snapshot.policy,
      sessionAccountIds: _sessionAccountIds,
      sessionSubscriptionIds: _sessionSubscriptionIds,
    );
    final accounts = projection['accounts'];
    if (accounts is! List) {
      return const <TemporaryWebBatchVisibleAccount>[];
    }
    final result = <TemporaryWebBatchVisibleAccount>[];
    for (final raw in accounts) {
      if (raw is! Map) continue;
      final id = raw['id'];
      final platformName = raw['platformName'];
      if (id is! String || id.isEmpty || platformName is! String) continue;
      String value(String key) => raw[key] is String ? raw[key]! as String : '';
      result.add(
        TemporaryWebBatchVisibleAccount(
          id: id,
          platformName: platformName,
          loginAccount: value('loginAccount'),
          phone: value('boundPhone'),
          email: value('boundEmail'),
          url: value('website'),
          notes: value('notes'),
        ),
      );
    }
    return List<TemporaryWebBatchVisibleAccount>.unmodifiable(result);
  }

  Future<String> _digestApprovalTarget(
    TemporaryWebApproval approval,
    TemporaryWebVaultRecords records,
  ) async {
    switch (approval.kind) {
      case TemporaryWebApprovalKind.deleteAccount:
        final account = records.accounts
            .where((candidate) => candidate.id == approval.targetId)
            .firstOrNull;
        if (account == null) return '';
        final linked = records.subscriptions
            .where((item) => item.accountId == account.id)
            .toList(growable: false);
        return _digestAccount(account, linked);
      case TemporaryWebApprovalKind.deleteSubscription:
        final subscription = records.subscriptions
            .where((candidate) => candidate.id == approval.targetId)
            .firstOrNull;
        return subscription == null
            ? ''
            : _digestJson(subscription.toEncryptedPayloadJson());
      case TemporaryWebApprovalKind.saveAccount:
        final pending = _accountSaves[approval.id];
        if (pending == null) return '';
        final existing = records.accounts
            .where((a) => a.id == pending.accountId)
            .firstOrNull;
        return _digestJson(pending.toJson(existing));
      case TemporaryWebApprovalKind.revealCustomField:
      case TemporaryWebApprovalKind.revealPassword:
        final account = records.accounts
            .where((candidate) => candidate.id == approval.targetId)
            .firstOrNull;
        return account == null
            ? ''
            : _digestJson(account.toEncryptedPayloadJson());
      case TemporaryWebApprovalKind.batchImport:
        final prepared = _batchApprovalRequests[approval.id];
        if (prepared == null) return '';
        return _digestJson(prepared.toSafeJson());
    }
  }

  Future<String> _digestAccount(
    AccountRecord account,
    List<SubscriptionRecord> linked,
  ) => _digestJson(<String, Object?>{
    'account': account.toEncryptedPayloadJson(),
    'subscriptions': <Object?>[
      for (final item in linked) item.toEncryptedPayloadJson(),
    ],
  });

  Future<String> _digestJson(Object value) async {
    final hash = await Sha256().hash(utf8.encode(jsonEncode(value)));
    return base64Url.encode(hash.bytes).replaceAll('=', '');
  }

  AccountDraft _accountDraft(
    Map<String, Object?> body, {
    AccountRecord? existing,
  }) => AccountDraft(
    platformName: _requiredString(body, 'platformName', maximumLength: 100),
    category: _optionalString(body, 'category', maximumLength: 100),
    loginAccount: _optionalString(body, 'loginAccount', maximumLength: 512),
    username: _optionalString(body, 'username', maximumLength: 512),
    boundPhone: _optionalString(body, 'boundPhone', maximumLength: 100),
    boundEmail: _optionalString(body, 'boundEmail', maximumLength: 320),
    password: _optionalString(body, 'password', maximumLength: 4096),
    website: _optionalString(body, 'website', maximumLength: 2048),
    notes: _optionalString(body, 'notes', maximumLength: 10000),
    customFields: _customFields(body, existing),
  );

  List<AccountCustomField> _customFields(
    Map<String, Object?> body,
    AccountRecord? existing,
  ) {
    if (!body.containsKey('customFields')) {
      return existing?.customFields ?? const [];
    }
    final raw = body['customFields'];
    if (raw is! List || raw.length > 10) {
      throw const FormatException('每个账号最多 10 个自定义字段。');
    }
    final fields = <AccountCustomField>[];
    for (final item in raw) {
      if (item is! Map) throw const FormatException('自定义字段无效。');
      final value = Map<String, Object?>.from(item);
      if (value['valueState'] == 'redacted') {
        final old = existing?.customFields
            .where((field) => field.id == value['id'])
            .firstOrNull;
        if (old == null || !old.isSensitive || value['type'] != old.type.code) {
          throw const FormatException('隐藏字段必须保留原类型或明确输入新值。');
        }
        value['value'] = old.value;
      }
      fields.add(AccountCustomField.fromJson(value));
    }
    return validateAccountCustomFields(fields);
  }

  SubscriptionDraft _subscriptionDraft(Map<String, Object?> body) {
    final unitName = _requiredString(body, 'cycleUnit', maximumLength: 16);
    final statusName = _requiredString(body, 'status', maximumLength: 16);
    final unit = SubscriptionCycleUnit.values
        .where((candidate) => candidate.name == unitName)
        .firstOrNull;
    final status = SubscriptionStatus.values
        .where((candidate) => candidate.name == statusName)
        .firstOrNull;
    if (unit == null || status == null) {
      throw const FormatException('订阅周期或状态无效。');
    }
    return SubscriptionDraft(
      accountId: _optionalString(body, 'accountId', maximumLength: 128),
      details: SubscriptionDetailsDraft(
        serviceName: _requiredString(body, 'serviceName', maximumLength: 100),
        planName: _optionalString(body, 'planName', maximumLength: 100),
        amount: _optionalString(body, 'amount', maximumLength: 32),
        currency: _requiredString(body, 'currency', maximumLength: 12),
        firstSubscribedOn: parseSubscriptionDate(
          _requiredString(body, 'firstSubscribedOn', maximumLength: 10),
        ),
        nextRenewalOn: parseSubscriptionDate(
          _requiredString(body, 'nextRenewalOn', maximumLength: 10),
        ),
        cycleCount: _requiredInt(body, 'cycleCount'),
        cycleUnit: unit,
        autoRenew: _requiredBool(body, 'autoRenew'),
        paymentMethod: _optionalString(
          body,
          'paymentMethod',
          maximumLength: 100,
        ),
        reminderDaysBefore: _requiredInt(body, 'reminderDaysBefore'),
        reminderEnabled: _requiredBool(body, 'reminderEnabled'),
        status: status,
      ),
    );
  }

  AccountPasswordUpdateMode _passwordMode(Object? value) => switch (value) {
    'preserve' => AccountPasswordUpdateMode.preserve,
    'replace' => AccountPasswordUpdateMode.replace,
    'clear' => AccountPasswordUpdateMode.clear,
    _ => throw const FormatException('密码修改方式无效。'),
  };

  void _expireApprovals() {
    var changed = false;
    for (final approval in List<TemporaryWebApproval>.of(_approvals.values)) {
      if (_isApprovalExpired(approval.id)) {
        _accountSaves.remove(approval.id);
        _customFieldReveals.remove(approval.id);
        _approvals.remove(approval.id);
        _approvalDeadlines.remove(approval.id);
        if (approval.kind == TemporaryWebApprovalKind.batchImport) {
          _batchApprovalRequests.remove(approval.id);
          _batchImportPort?.clearSensitiveMemory();
        }
        _approvalResults[approval.id] = _ApprovalResult(
          value: const <String, Object?>{
            'status': 'expired',
            'message': '手机确认已超时。',
          },
          expiresAtMonotonic: _monotonicNow() + _approvalLifetime,
        );
        changed = true;
      }
    }
    _approvalResults.removeWhere(
      (_, result) => _hasReached(result.expiresAtMonotonic),
    );
    if (changed) _refreshApprovalSnapshot();
  }

  void _refreshApprovalSnapshot() {
    final approvals = _approvals.values.toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    _snapshot = _copySnapshot(
      pendingApprovals: List<TemporaryWebApproval>.unmodifiable(approvals),
    );
    _notify();
  }

  TemporaryWebSessionSnapshot _copySnapshot({
    TemporaryWebSessionPhase? phase,
    CardockLanguage? language,
    DateTime? lastMeaningfulActivityAt,
    String? connectedClientAddress,
    List<TemporaryWebApproval>? pendingApprovals,
    bool clearConnectionCode = false,
  }) => TemporaryWebSessionSnapshot(
    phase: phase ?? _snapshot.phase,
    policy: _snapshot.policy,
    language: language ?? _snapshot.language,
    address: _snapshot.address,
    port: _snapshot.port,
    formattedConnectionCode: clearConnectionCode
        ? null
        : _snapshot.formattedConnectionCode,
    startedAt: _snapshot.startedAt,
    lastMeaningfulActivityAt:
        lastMeaningfulActivityAt ?? _snapshot.lastMeaningfulActivityAt,
    stopReason: _snapshot.stopReason,
    connectedClientAddress:
        connectedClientAddress ?? _snapshot.connectedClientAddress,
    errorMessage: _snapshot.errorMessage,
    pendingApprovals: pendingApprovals ?? _snapshot.pendingApprovals,
  );

  void _resetSessionMemory() {
    _clearBatchImportState(refreshApprovals: false);
    _operationCache.clear();
    _sessionAccountIds.clear();
    _sessionSubscriptionIds.clear();
    _accountSaves.clear();
    _customFieldReveals.clear();
    _approvals.clear();
    _approvalDeadlines.clear();
    _approvalResults.clear();
    _startedAtMonotonic = null;
    _vaultTemporarilyUnavailable = false;
    _vaultAccessStateCheckPending = false;
    _lastKnownVaultRevision = null;
    _vaultBindingId = null;
  }

  void _expireBatchUpload() {
    final upload = _batchUpload;
    if (upload != null && _hasReached(upload.expiresAtMonotonic)) {
      _destroyBatchUpload();
    }
  }

  void _destroyBatchUpload() {
    _batchUpload?.destroy();
    _batchUpload = null;
  }

  void _clearBatchImportState({bool refreshApprovals = true}) {
    _destroyBatchUpload();
    _batchImportPort?.clearSensitiveMemory();
    final batchIds = _approvals.values
        .where(
          (approval) => approval.kind == TemporaryWebApprovalKind.batchImport,
        )
        .map((approval) => approval.id)
        .toList(growable: false);
    for (final id in batchIds) {
      _approvals.remove(id);
      _approvalDeadlines.remove(id);
      _approvalResults.remove(id);
      _batchApprovalRequests.remove(id);
    }
    _batchApprovalRequests.clear();
    if (refreshApprovals && batchIds.isNotEmpty) _refreshApprovalSnapshot();
  }

  String _randomId() {
    final bytes = Uint8List(18);
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = _random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void _beginControlledOperation() {
    _controlledOperationDepth += 1;
  }

  void _endControlledOperation() {
    if (_controlledOperationDepth == 0) return;
    _controlledOperationDepth -= 1;
    if (_controlledOperationDepth == 0 && _vaultAccessStateCheckPending) {
      _vaultAccessStateCheckPending = false;
      if (_snapshot.isRunning) _synchronizeVaultAccessState();
    }
    _notify();
  }

  Map<String, Object?> _writeResultUnknown() => const <String, Object?>{
    'status': 'resultUnknown',
    'message': '手机保险库在写入期间结束了旧网页会话；请在手机端核对结果。',
  };

  Map<String, Object?> _sessionEndedResult() => const <String, Object?>{
    'status': 'sessionEnded',
    'message': '旧网页会话已结束。',
  };

  bool _isCurrent(int epoch) => !_disposed && epoch == _epoch;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _safeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return text.length <= 160 ? text : '${text.substring(0, 160)}…';
  }

  static Duration Function() _createMonotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop(TemporaryWebStopReason.disposed);
    _disposed = true;
    super.dispose();
  }
}

final class _ApprovalResult {
  const _ApprovalResult({
    required this.value,
    required this.expiresAtMonotonic,
  });

  final Map<String, Object?> value;
  final Duration expiresAtMonotonic;
}

final class _TemporaryWebBatchUpload {
  _TemporaryWebBatchUpload({
    required this.sessionId,
    required this.fileName,
    required this.sourceId,
    required this.expectedRevision,
    required this.totalBytes,
    required this.totalChunks,
    required this.expiresAtMonotonic,
  });

  final String sessionId;
  final String fileName;
  final String sourceId;
  final int expectedRevision;
  final int totalBytes;
  final int totalChunks;
  final Duration expiresAtMonotonic;
  final BytesBuilder _builder = BytesBuilder();
  int nextSequence = 0;
  int _receivedBytes = 0;

  bool get isComplete =>
      nextSequence == totalChunks && _receivedBytes == totalBytes;

  void add({required int sequence, required Uint8List chunk}) {
    if (sequence != nextSequence || sequence >= totalChunks) {
      throw const FormatException('批量文件分块重复、缺失或乱序。');
    }
    final expectedLength = sequence == totalChunks - 1
        ? totalBytes - temporaryWebBatchImportChunkBytes * sequence
        : temporaryWebBatchImportChunkBytes;
    if (chunk.length != expectedLength ||
        _receivedBytes + chunk.length > totalBytes) {
      throw const FormatException('批量文件分块长度无效。');
    }
    _builder.add(chunk);
    _receivedBytes += chunk.length;
    nextSequence += 1;
  }

  Uint8List takeBytes() {
    if (!isComplete) throw const FormatException('批量文件分块不完整。');
    final bytes = _builder.takeBytes();
    if (bytes.length != totalBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const FormatException('批量文件分块总长度无效。');
    }
    _receivedBytes = 0;
    return bytes;
  }

  void destroy() {
    final bytes = _builder.takeBytes();
    bytes.fillRange(0, bytes.length, 0);
    _receivedBytes = 0;
    nextSequence = 0;
  }
}

Map<String, Object?> _requiredMap(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$key 格式无效。');
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}

String _requiredRequestId(Map<String, Object?> source) {
  final value = _requiredString(source, 'requestId', maximumLength: 80);
  if (!TemporaryWebSessionController._requestIdPattern.hasMatch(value)) {
    throw const FormatException('requestId 格式无效。');
  }
  return value;
}

String _requiredString(
  Map<String, Object?> source,
  String key, {
  required int maximumLength,
}) {
  final value = source[key];
  if (value is! String || value.isEmpty || value.runes.length > maximumLength) {
    throw FormatException('$key 格式无效。');
  }
  return value;
}

String? _optionalString(
  Map<String, Object?> source,
  String key, {
  required int maximumLength,
}) {
  final value = source[key];
  if (value == null || value == '') return null;
  if (value is! String || value.runes.length > maximumLength) {
    throw FormatException('$key 格式无效。');
  }
  return value;
}

int _requiredInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! int) throw FormatException('$key 格式无效。');
  return value;
}

bool _requiredBool(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! bool) throw FormatException('$key 格式无效。');
  return value;
}

Set<String> _requiredStringSet(
  Map<String, Object?> source,
  String key, {
  required int maximumItems,
  required int maximumItemLength,
}) {
  final value = source[key];
  if (value is! List<Object?> || value.length > maximumItems) {
    throw FormatException('$key 格式无效。');
  }
  final result = <String>{};
  for (final item in value) {
    if (item is! String ||
        item.isEmpty ||
        item.runes.length > maximumItemLength ||
        !result.add(item)) {
      throw FormatException('$key 格式无效。');
    }
  }
  return Set<String>.unmodifiable(result);
}

Map<String, String> _requiredStringMap(
  Map<String, Object?> source,
  String key, {
  required int maximumItems,
  required int maximumKeyLength,
  required int maximumValueLength,
}) {
  final value = source[key];
  if (value is! Map<Object?, Object?> || value.length > maximumItems) {
    throw FormatException('$key 格式无效。');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final itemKey = entry.key;
    final itemValue = entry.value;
    if (itemKey is! String ||
        itemKey.isEmpty ||
        itemKey.runes.length > maximumKeyLength ||
        itemValue is! String ||
        itemValue.isEmpty ||
        itemValue.runes.length > maximumValueLength) {
      throw FormatException('$key 格式无效。');
    }
    result[itemKey] = itemValue;
  }
  return Map<String, String>.unmodifiable(result);
}

Map<String, Map<String, String>> _requiredNestedStringMap(
  Map<String, Object?> source,
  String key, {
  required int maximumRows,
  required int maximumFieldsPerRow,
  required int maximumKeyLength,
  required int maximumFieldLength,
  required int maximumValueLength,
}) {
  final value = source[key];
  if (value is! Map<Object?, Object?> || value.length > maximumRows) {
    throw FormatException('$key 格式无效。');
  }
  final result = <String, Map<String, String>>{};
  for (final rowEntry in value.entries) {
    final rowId = rowEntry.key;
    final fields = rowEntry.value;
    if (rowId is! String ||
        rowId.isEmpty ||
        rowId.runes.length > maximumKeyLength ||
        fields is! Map<Object?, Object?> ||
        fields.length > maximumFieldsPerRow) {
      throw FormatException('$key 格式无效。');
    }
    final validated = <String, String>{};
    for (final fieldEntry in fields.entries) {
      final field = fieldEntry.key;
      final fieldValue = fieldEntry.value;
      if (field is! String ||
          field.isEmpty ||
          field.runes.length > maximumFieldLength ||
          fieldValue is! String ||
          fieldValue.runes.length > maximumValueLength) {
        throw FormatException('$key 格式无效。');
      }
      validated[field] = fieldValue;
    }
    result[rowId] = Map<String, String>.unmodifiable(validated);
  }
  return Map<String, Map<String, String>>.unmodifiable(result);
}

final class _PendingAccountSave {
  const _PendingAccountSave(this.draft, this.accountId, this.passwordMode);
  final AccountDraft draft;
  final String? accountId;
  final AccountPasswordUpdateMode passwordMode;
  Map<String, Object?> toJson(AccountRecord? existing) => {
    'draft': AccountRecord.fromDraft(
      id: 'pending',
      draft: draft,
    ).toEncryptedPayloadJson(),
    'accountId': accountId,
    'passwordMode': passwordMode.name,
    'existing': existing?.toEncryptedPayloadJson(),
  };
}
