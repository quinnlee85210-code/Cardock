import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../security/device_backup_config.dart';
import '../security/offline_password_advisor.dart';
import '../security/vault_contract.dart';
import 'document_storage.dart';
import 'portable_backup_codec.dart';

final class AutoBackupStatus {
  const AutoBackupStatus({
    this.enabled = false,
    this.busy = false,
    this.permission,
    this.validCount = 0,
    this.retention = 3,
    this.intervalDays = 15,
    this.nextDueAt,
    this.cleanupPending = false,
    this.dirtySince,
    this.lastWritten,
    this.lastVerified,
    this.lastFailure,
    this.failureCode,
    this.failures = 0,
  });
  final bool enabled, busy, cleanupPending;
  final bool? permission;
  final int validCount, retention, failures, intervalDays;
  final DateTime? dirtySince, lastWritten, lastVerified, lastFailure, nextDueAt;
  final String? failureCode;
}

/// One serialized writer, no key while locked. Each verified backup advances
/// a durable UTC deadline. Unlock catches up once, even if data is unchanged.
final class AutoBackupController extends ChangeNotifier {
  AutoBackupController({
    DocumentStorage? storage,
    PortableBackupCodec? codec,
    DateTime Function()? now,
  }) : storage = storage ?? const AndroidDocumentStorage(),
       codec = codec ?? PortableBackupCodec(),
       now = now ?? DateTime.now;
  final DocumentStorage storage;
  final PortableBackupCodec codec;
  final DateTime Function() now;
  static const supportedIntervals = {7, 15, 30};
  static const retryDelay = Duration(minutes: 15);
  DeviceBackupConfigSession? _session;
  VaultSnapshot? _snapshot;
  Map<String, Object?>? _config;
  String? _currentDigest;
  Timer? _timer;
  Completer<bool>? _immediateRequest;
  int _immediateRequestedRevision = 0;
  bool _drainingImmediate = false;
  int _epoch = 0, _revision = 0;
  bool _busy = false, _disposed = false, _configBlocked = false;
  AutoBackupStatus status = const AutoBackupStatus();

  static Future<String> businessDigest(VaultSnapshot snapshot) async {
    final json = snapshot.toEncryptedPayloadJson()
      ..remove('preferences')
      ..remove('recentAccountIds');
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    try {
      return base64Encode((await Sha256().hash(bytes)).bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  bool _current(int epoch) => !_disposed && _session != null && epoch == _epoch;
  void detach() {
    _cancelImmediate();
    _drainingImmediate = false;
    _epoch++;
    _revision++;
    _timer?.cancel();
    _timer = null;
    _session = null;
    _snapshot = null;
    _config = null;
    _configBlocked = false;
    _currentDigest = null;
    _busy = false;
    status = const AutoBackupStatus();
    // Called while AppState is replacing a session; the owner notifies once.
  }

  Future<void> attach(
    DeviceBackupConfigSession session,
    VaultSnapshot snapshot,
  ) async {
    detach();
    _session = session;
    _snapshot = snapshot;
    final epoch = _epoch;
    try {
      final value = await session.readDeviceBackupConfig();
      if (!_current(epoch)) return;
      _validate(value);
      if (value != null && value['version'] == 1) {
        final upgraded = Map<String, Object?>.from(value)
          ..addAll({
            'version': 2,
            'intervalDays': 15,
            'retention': 3,
            'nextDueAt':
                (DateTime.tryParse(value['lastWritten'] as String? ?? '') ??
                        now())
                    .toUtc()
                    .add(const Duration(days: 15))
                    .toIso8601String(),
          });
        await session.writeDeviceBackupConfig(upgraded);
        if (!_current(epoch)) return;
        _config = upgraded;
      } else {
        _config = value;
      }
      await observe(_snapshot ?? snapshot);
      if (!_current(epoch)) return;
      await refreshPermission();
      if (_current(epoch)) _schedule();
    } on Object {
      if (_current(epoch)) {
        _timer?.cancel();
        _config = null;
        _configBlocked = true;
        _publish(failure: 'config_unreadable');
      }
    }
  }

  Future<void> observe(VaultSnapshot snapshot) async {
    if (_session == null) return;
    _snapshot = snapshot;
    final epoch = _epoch, revision = ++_revision;
    final digest = await businessDigest(snapshot);
    if (!_current(epoch) || revision != _revision) return;
    if (_currentDigest == digest) return;
    _currentDigest = digest;
    final config = _config;
    if (config != null && config['enabled'] == true) {
      config['dirtySince'] = config['digest'] == digest
          ? null
          : config['dirtySince'] ?? now().toUtc().toIso8601String();
      try {
        if (!_busy) await _session!.writeDeviceBackupConfig(config);
      } on Object {
        // Recomputed from the committed snapshot on the next unlock.
      }
    }
    if (_current(epoch)) _publish();
  }

  Future<bool> requestImmediate() {
    if (_disposed || _session == null || _config?['enabled'] != true) {
      return Future.value(false);
    }
    // Requests during an immediate write join the same completion. If they
    // observe a newer snapshot, the writer catches up before completing it.
    _immediateRequestedRevision = _revision;
    final existing = _immediateRequest;
    if (existing != null) return existing.future;
    final requested = Completer<bool>();
    _immediateRequest = requested;
    if (!_busy && !_drainingImmediate) unawaited(_drainImmediate());
    return requested.future;
  }

  void _cancelImmediate() {
    final request = _immediateRequest;
    _immediateRequest = null;
    _immediateRequestedRevision = 0;
    if (request != null && !request.isCompleted) request.complete(false);
  }

  Future<void> _drainImmediate() async {
    if (_busy || _drainingImmediate) return;
    final request = _immediateRequest;
    if (request == null) return;
    final epoch = _epoch;
    _drainingImmediate = true;
    try {
      while (_current(epoch) && identical(_immediateRequest, request)) {
        final writtenRevision = _revision;
        final success = await runNow();
        if (!_current(epoch) || !identical(_immediateRequest, request)) return;
        if (success && _immediateRequestedRevision > writtenRevision) continue;
        _immediateRequest = null;
        _immediateRequestedRevision = 0;
        request.complete(success);
        return;
      }
    } on Object {
      if (identical(_immediateRequest, request)) _cancelImmediate();
    } finally {
      if (_current(epoch)) {
        _drainingImmediate = false;
        _schedule();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || _session == null || _config?['enabled'] != true) {
      _cancelImmediate();
      return;
    }
    if (_busy) return;
    if (_immediateRequest != null) {
      // Rotation and writes also call _schedule in finally; never reenter an
      // active immediate operation between its rotation and ciphertext write.
      if (!_drainingImmediate) unawaited(_drainImmediate());
      return;
    }
    final config = _config!;
    final current = now().toUtc();
    final due = DateTime.parse(config['nextDueAt'] as String);
    var delay = config['cleanupPending'] == true
        ? Duration.zero
        : due.difference(current);
    if (delay.isNegative) delay = Duration.zero;
    final failed = DateTime.tryParse(config['lastFailure'] as String? ?? '');
    if (failed != null && config['failureCode'] != null) {
      final retryIn = failed.add(retryDelay).difference(current);
      if (retryIn > delay) delay = retryIn;
    }
    // Re-evaluate long deadlines daily so wall-clock changes cannot extend a
    // stale monotonic timer for an entire month.
    if (delay > const Duration(days: 1)) delay = const Duration(days: 1);
    final epoch = _epoch;
    _timer = Timer(delay, () async {
      if (!_current(epoch)) return;
      await runIfDue();
      if (_current(epoch)) _schedule();
    });
  }

  Future<bool> runIfDue() async {
    final config = _config;
    if (_session == null ||
        _busy ||
        config == null ||
        config['enabled'] != true) {
      return false;
    }
    if (config['cleanupPending'] == true) return _resumeRotation();
    if (now().toUtc().isBefore(DateTime.parse(config['nextDueAt'] as String))) {
      return false;
    }
    return runNow();
  }

  Future<bool> updateInterval(int days) async {
    final config = _config, session = _session;
    if (!supportedIntervals.contains(days) ||
        _busy ||
        session == null ||
        config == null) {
      return false;
    }
    final epoch = _epoch;
    final candidate = Map<String, Object?>.from(config)
      ..addAll({
        'intervalDays': days,
        'nextDueAt':
            (DateTime.tryParse(config['lastWritten'] as String? ?? '') ?? now())
                .toUtc()
                .add(Duration(days: days))
                .toIso8601String(),
      });
    _busy = true;
    _timer?.cancel();
    _publish();
    try {
      await session.writeDeviceBackupConfig(candidate);
      if (!_current(epoch)) return false;
      _config = candidate;
      return true;
    } on Object {
      return false;
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _publish();
        _schedule();
      }
    }
  }

  Future<void> refreshPermission() async {
    final config = _config;
    if (_session == null || config == null) return;
    final epoch = _epoch;
    try {
      final permission = await storage.hasPermission(config['tree'] as String);
      if (!_current(epoch)) return;
      config['permission'] = permission;
      // A retained file is counted only if its ciphertext still matches the
      // bytes whose full decryption succeeded earlier; no password guesswork.
      var valid = 0;
      for (final file in _files(config)) {
        if (!_current(epoch)) return;
        try {
          final bytes = await storage.read(file['uri'] as String);
          if (base64Encode((await Sha256().hash(bytes)).bytes) ==
              file['hash']) {
            valid++;
          }
        } on Object {
          /* unavailable files are excluded, never deleted */
        }
      }
      if (!_current(epoch)) return;
      config['validCount'] = valid;
      _publish(failure: permission ? null : 'permission_revoked');
    } on Object catch (error) {
      if (_current(epoch)) _publish(failure: documentFailureCode(error));
    }
  }

  Future<bool> configure({
    required String tree,
    required String password,
    int intervalDays = 15,
  }) async {
    if (_session == null ||
        _busy ||
        _configBlocked ||
        !supportedIntervals.contains(intervalDays)) {
      return false;
    }
    if (!OfflinePasswordAdvisor.assess(password).accepted) {
      _publish(failure: 'invalid_password');
      return false;
    }
    final epoch = _epoch;
    if (_config?['cleanupPending'] == true && !await _resumeRotation()) {
      return false;
    }
    if (!_current(epoch)) return false;
    // Do not commit the enabled state until the very first file has been read
    // back from SAF and authenticated by the existing portable backup codec.
    final candidate = <String, Object?>{
      'version': 2,
      'enabled': true,
      'tree': tree,
      'password': password,
      'retention': 3,
      'intervalDays': intervalDays,
      'files': _config?['tree'] == tree ? (_config?['files'] ?? []) : [],
      'dirtySince': now().toUtc().toIso8601String(),
      'failures': 0,
    };
    return _write(candidate);
  }

  Future<bool> disable() async {
    final config = _config, session = _session;
    if (config == null || session == null || _busy) return false;
    final epoch = _epoch;
    final next = Map<String, Object?>.from(config)..['enabled'] = false;
    _busy = true;
    _timer?.cancel();
    _publish();
    try {
      await session.writeDeviceBackupConfig(next);
      if (!_current(epoch)) return false;
      _config = next;
      return true;
    } on Object {
      return false;
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _publish();
        _schedule();
      }
    }
  }

  Future<bool> runNow() async {
    final config = _config;
    if (_session == null ||
        config == null ||
        config['enabled'] != true ||
        _busy) {
      return false;
    }
    final epoch = _epoch;
    if (config['cleanupPending'] == true && !await _resumeRotation()) {
      return false;
    }
    if (!_current(epoch)) return false;
    return _write(Map<String, Object?>.from(_config!));
  }

  Future<bool> _write(Map<String, Object?> candidate) async {
    final session = _session, snapshot = _snapshot;
    if (session == null || snapshot == null || _busy) return false;
    final epoch = _epoch;
    _busy = true;
    _timer?.cancel();
    _publish();
    Uint8List? encrypted;
    String? createdUri;
    var verifiedFile = false;
    var failureStage = 'permission_revoked';
    var success = false;
    try {
      final tree = candidate['tree'] as String;
      if (!await storage.hasPermission(tree)) {
        throw const _BackupFailure('permission_revoked');
      }
      if (!_current(epoch)) return false;
      final digest = await businessDigest(snapshot);
      if (!_current(epoch)) return false;
      failureStage = 'encryption_failed';
      encrypted = await codec.encryptV2(
        snapshot: snapshot,
        backupMasterPassword: candidate['password'] as String,
        createdAtUtc: now(),
        isAuthorized: () => _current(epoch),
      );
      if (!_current(epoch)) return false;
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      failureStage = 'write_failed';
      final uri = createdUri = await storage.createBackup(
        tree,
        'Cardock-${now().toUtc().millisecondsSinceEpoch}-$id.asmbackup',
      );
      if (!_current(epoch)) return false;
      await storage.write(uri, encrypted);
      if (!_current(epoch)) return false;
      failureStage = 'read_failed';
      final readBack = await storage.read(uri);
      if (!_current(epoch)) return false;
      failureStage = 'verification_failed';
      final verification = await codec.read(
        bytes: readBack,
        backupMasterPassword: candidate['password'] as String,
        isAuthorized: () => _current(epoch),
      );
      if (!_current(epoch)) return false;
      if (jsonEncode(verification.snapshot.toEncryptedPayloadJson()) !=
          jsonEncode(snapshot.toEncryptedPayloadJson())) {
        throw const _BackupFailure('verification_failed');
      }
      verifiedFile = true;
      final timestamp = now().toUtc().toIso8601String();
      final files = [
        ..._files(candidate),
        <String, Object?>{
          'uri': uri,
          'hash': base64Encode((await Sha256().hash(readBack)).bytes),
          'verified': timestamp,
        },
      ];
      candidate.addAll({
        'files': files,
        'digest': digest,
        'permission': true,
        'lastWritten': timestamp,
        'lastVerified': timestamp,
        'failures': 0,
        'lastFailure': null,
        'failureCode': null,
        'validCount': files.length,
        'dirtySince': _currentDigest == digest ? null : timestamp,
        'nextDueAt': now()
            .toUtc()
            .add(Duration(days: candidate['intervalDays'] as int))
            .toIso8601String(),
        'cleanupPending': files.length > 3,
      });
      if (!_current(epoch)) return false;
      failureStage = 'config_write_failed';
      await session.writeDeviceBackupConfig(candidate);
      if (!_current(epoch)) return false;
      _config = candidate;
      // Persist the verified file before deleting any previous backup.
      await _rotate(candidate, epoch);
      if (!_current(epoch)) return false;
      success = true;
      await refreshPermission();
      if (!_current(epoch)) return false;
      return true;
    } on Object catch (error) {
      if (_current(epoch)) {
        final config = _config;
        final code = error is _BackupFailure
            ? error.code
            : documentFailureCode(error) == 'verification_failed'
            ? failureStage
            : documentFailureCode(error);
        if (config != null) {
          config['failureCode'] = code;
          config['lastFailure'] = now().toUtc().toIso8601String();
          config['failures'] = (config['failures'] as int? ?? 0) + 1;
          config['dirtySince'] ??= now().toUtc().toIso8601String();
          try {
            await session.writeDeviceBackupConfig(config);
          } on Object {
            /* old valid files retained */
          }
        }
        if (_current(epoch)) _publish(failure: code);
      }
      return false;
    } finally {
      // Clean up only this operation's newly created, unverified ciphertext.
      // Never delete the last valid file or infer ownership from its name.
      if (!verifiedFile && createdUri != null) {
        try {
          await storage.deleteOwned(candidate['tree'] as String, createdUri);
        } on Object {
          // Provider cleanup is best-effort. This file is never registered or
          // counted as valid, and the operation still reports its failure.
        }
      }
      encrypted?.fillRange(0, encrypted.length, 0);
      if (_current(epoch)) {
        _busy = false;
        _publish(failure: success ? null : status.failureCode);
        _schedule();
      }
    }
  }

  Future<void> _rotate(Map<String, Object?> candidate, int epoch) async {
    final files = _files(candidate);
    candidate['files'] = files;
    while (files.length > 3) {
      if (!_current(epoch)) return;
      try {
        await storage.deleteOwned(
          candidate['tree'] as String,
          files.first['uri'] as String,
        );
      } on Object catch (error) {
        if (documentFailureCode(error) != 'directory_missing') {
          throw const _BackupFailure('cleanup_failed');
        }
      }
      if (!_current(epoch)) return;
      files.removeAt(0);
      candidate['validCount'] = files.length;
      await _session!.writeDeviceBackupConfig(candidate);
    }
    if (!_current(epoch)) return;
    candidate['cleanupPending'] = false;
    await _session!.writeDeviceBackupConfig(candidate);
  }

  Future<bool> _resumeRotation() async {
    final config = _config;
    if (_session == null || _busy || config == null) return false;
    final epoch = _epoch;
    _busy = true;
    _timer?.cancel();
    _publish();
    try {
      final files = _files(config);
      if (files.length > 3) {
        // After an interruption, ensure the new recovery point is still valid
        // before continuing any deletion. Never infer ownership from a name.
        final latest = files.last;
        final bytes = await storage.read(latest['uri'] as String);
        if (!_current(epoch)) return false;
        if (base64Encode((await Sha256().hash(bytes)).bytes) !=
            latest['hash']) {
          throw const _BackupFailure('verification_failed');
        }
        await codec.read(
          bytes: bytes,
          backupMasterPassword: config['password'] as String,
          isAuthorized: () => _current(epoch),
        );
        if (!_current(epoch)) return false;
      }
      await _rotate(config, epoch);
      if (!_current(epoch)) return false;
      config.addAll({'failureCode': null, 'lastFailure': null, 'failures': 0});
      await _session!.writeDeviceBackupConfig(config);
      if (!_current(epoch)) return false;
      await refreshPermission();
      return _current(epoch);
    } on Object catch (error) {
      if (_current(epoch)) {
        config.addAll({
          'failureCode': error is _BackupFailure
              ? error.code
              : documentFailureCode(error),
          'lastFailure': now().toUtc().toIso8601String(),
          'failures': (config['failures'] as int? ?? 0) + 1,
        });
        try {
          await _session!.writeDeviceBackupConfig(config);
        } on Object {
          /* retry on unlock */
        }
      }
      return false;
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _publish();
        _schedule();
      }
    }
  }

  static List<Map<String, Object?>> _files(Map<String, Object?> value) =>
      (value['files'] as List? ?? [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
  static void _validate(Map<String, Object?>? value) {
    if (value == null) return;
    if (!{1, 2}.contains(value['version']) ||
        value['enabled'] is! bool ||
        value['password'] is! String ||
        value['tree'] is! String ||
        value['retention'] is! int ||
        !{3, 5, 10}.contains(value['retention']) ||
        _files(value).length > 100) {
      throw const FormatException('Invalid device backup config');
    }
    if (value['version'] == 2 &&
        (value['intervalDays'] is! int ||
            !supportedIntervals.contains(value['intervalDays']) ||
            value['retention'] != 3 ||
            value['nextDueAt'] is! String ||
            DateTime.tryParse(value['nextDueAt'] as String) == null ||
            (value['cleanupPending'] != null &&
                value['cleanupPending'] is! bool))) {
      throw const FormatException('Invalid scheduled backup config');
    }
    for (final file in _files(value)) {
      if (file['uri'] is! String || file['hash'] is! String) {
        throw const FormatException();
      }
    }
  }

  void _publish({String? failure}) {
    if (_disposed || _session == null) return;
    final config = _config ?? <String, Object?>{};
    DateTime? date(String key) =>
        DateTime.tryParse(config[key] as String? ?? '');
    status = AutoBackupStatus(
      enabled: config['enabled'] == true,
      busy: _busy,
      permission: config['permission'] as bool?,
      retention: 3,
      intervalDays: config['intervalDays'] as int? ?? 15,
      nextDueAt: date('nextDueAt'),
      cleanupPending: config['cleanupPending'] == true,
      validCount: config['validCount'] as int? ?? 0,
      dirtySince: date('dirtySince'),
      lastWritten: date('lastWritten'),
      lastVerified: date('lastVerified'),
      lastFailure: date('lastFailure'),
      failureCode: failure ?? config['failureCode'] as String?,
      failures: config['failures'] as int? ?? 0,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    _disposed = true;
    super.dispose();
  }
}

final class _BackupFailure implements Exception {
  const _BackupFailure(this.code);
  final String code;
}
