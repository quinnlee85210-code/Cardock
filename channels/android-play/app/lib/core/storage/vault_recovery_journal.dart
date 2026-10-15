import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../security/vault_contract.dart';
import 'portable_backup_codec.dart';

enum VaultRecoveryState { prepared, committed, rolledBack }

final class VaultRecoveryEntry {
  VaultRecoveryEntry({
    required this.transactionId,
    required this.createdAtUtc,
    required this.sourceGeneration,
    required this.revision,
    required this.state,
    required List<int> encryptedVaultBytes,
  }) : encryptedVaultBytes = Uint8List.fromList(encryptedVaultBytes);

  final String transactionId;
  final DateTime createdAtUtc;
  final int sourceGeneration;
  final int revision;
  final VaultRecoveryState state;
  final Uint8List encryptedVaultBytes;

  void destroy() =>
      encryptedVaultBytes.fillRange(0, encryptedVaultBytes.length, 0);
}

abstract interface class VaultRecoveryJournal {
  Future<VaultRecoveryEntry?> read();

  /// 废弃本机恢复前回滚凭据。
  ///
  /// 主密码轮换前必须先清除仍由旧主密码保护的回滚副本，避免旧密码
  /// 在换密后继续解出历史业务数据。独立导出的 .asmbackup 不在此范围。
  Future<void> clear();

  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  });

  Future<void> markCommitted(String transactionId);

  Future<void> markRolledBack(String transactionId);
}

final class NoopVaultRecoveryJournal implements VaultRecoveryJournal {
  const NoopVaultRecoveryJournal();

  @override
  Future<VaultRecoveryEntry?> read() async => null;

  @override
  Future<void> clear() async {}

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) async => 'noop';

  @override
  Future<void> markCommitted(String transactionId) async {}

  @override
  Future<void> markRolledBack(String transactionId) async {}
}

final class FileVaultRecoveryJournal implements VaultRecoveryJournal {
  FileVaultRecoveryJournal({required this._fileProvider});

  factory FileVaultRecoveryJournal.appSupport() => FileVaultRecoveryJournal(
    fileProvider: () async {
      final support = await getApplicationSupportDirectory();
      return File(
        '${support.path}${Platform.pathSeparator}recovery'
        '${Platform.pathSeparator}last_restore_rollback_v1.json',
      );
    },
  );

  static const _magic = 'ASM_LOCAL_RESTORE_ROLLBACK';
  static const _legacyVersion = 1;
  static const _previousVersion = 2;
  static const _version = 3;
  static const _discardedState = 'discarded';
  static const _maximumJournalBytes = 24 * 1024 * 1024;
  static const _maximumRevision = 1000000000;

  final Future<File> Function() _fileProvider;

  @override
  Future<VaultRecoveryEntry?> read() async {
    final latest = await _readLatestCandidate();
    if (latest == null) return null;
    if (latest.isTombstone) {
      latest.destroy();
      return null;
    }
    return latest.entry;
  }

  @override
  Future<void> clear() async {
    final latest = await _readLatestCandidate();
    if (latest == null) return;

    late final int firstRevision;
    try {
      firstRevision = _incrementRevision(latest.revision);
    } finally {
      latest.destroy();
    }

    // 第一份已验证 tombstone 是不可逆的逻辑提交点。即使进程在后续
    // 冗余写入或旧文件清理时中断，更高 revision 也会阻止旧凭据复活。
    await _commitTombstone(firstRevision);

    // 第二份交替槽 tombstone 只增加抗单槽损坏能力。第一份已经提交后，
    // 后续失败不得把“已废弃”误报成失败并诱导调用方继续使用旧凭据。
    try {
      await _commitTombstone(_incrementRevision(firstRevision));
    } on Object {
      // 第一份 tombstone 仍是权威状态。
    }

    await _deleteRetiredCandidatesBestEffort();
  }

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) async {
    if (encryptedVaultBytes.isEmpty ||
        encryptedVaultBytes.length > maximumPortableBackupBytes ||
        sourceGeneration < 1 ||
        sourceGeneration > 1000000000) {
      throw const VaultStorageException();
    }
    final revision = await _nextRevision();
    final transactionId = _newTransactionId();
    await _write(
      transactionId: transactionId,
      createdAtUtc: DateTime.now().toUtc(),
      sourceGeneration: sourceGeneration,
      revision: revision,
      state: VaultRecoveryState.prepared,
      encryptedVaultBytes: encryptedVaultBytes,
    );
    return transactionId;
  }

  @override
  Future<void> markCommitted(String transactionId) =>
      _changeState(transactionId, VaultRecoveryState.committed);

  @override
  Future<void> markRolledBack(String transactionId) =>
      _changeState(transactionId, VaultRecoveryState.rolledBack);

  Future<void> _changeState(
    String transactionId,
    VaultRecoveryState state,
  ) async {
    final current = await read();
    if (current == null || current.transactionId != transactionId) {
      current?.destroy();
      throw const VaultStorageException();
    }
    try {
      await _write(
        transactionId: current.transactionId,
        createdAtUtc: current.createdAtUtc,
        sourceGeneration: current.sourceGeneration,
        revision: _incrementRevision(current.revision),
        state: state,
        encryptedVaultBytes: current.encryptedVaultBytes,
      );
    } finally {
      current.destroy();
    }
  }

  Future<void> _write({
    required String transactionId,
    required DateTime createdAtUtc,
    required int sourceGeneration,
    required int revision,
    required VaultRecoveryState state,
    required List<int> encryptedVaultBytes,
  }) async {
    if (revision < 1 || revision > _maximumRevision) {
      throw const VaultStorageException();
    }
    final base = await _fileProvider();
    final target = File(revision.isOdd ? '${base.path}.a' : '${base.path}.b');
    final temporary = File('${target.path}.tmp');
    final record = <String, Object?>{
      'magic': _magic,
      'version': _version,
      'revision': revision,
      'transactionId': transactionId,
      'createdAtUtc': createdAtUtc.toIso8601String(),
      'sourceGeneration': sourceGeneration,
      'state': state.name,
      'encryptedVault': base64Encode(encryptedVaultBytes),
    };
    final digest = await Sha256().hash(utf8.encode(jsonEncode(record)));
    final encoded = jsonEncode(<String, Object?>{
      ...record,
      'sha256': base64UrlEncode(digest.bytes),
    });
    if (utf8.encode(encoded).length > _maximumJournalBytes) {
      throw const VaultStorageException();
    }
    try {
      await base.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(encoded, flush: true);
      if (await temporary.length() != utf8.encode(encoded).length) {
        throw const VaultStorageException();
      }
      final verified = await _readCandidate(
        _CandidateLocation(file: temporary, priority: 4),
      );
      try {
        final verifiedEntry = verified.entry;
        if (verifiedEntry == null ||
            verifiedEntry.revision != revision ||
            verifiedEntry.transactionId != transactionId ||
            verifiedEntry.state != state) {
          throw const VaultStorageException();
        }
      } finally {
        verified.destroy();
      }

      // revision 奇偶槽交替写入。删除目标旧槽时，另一槽（或刚完成并已
      // 验证的 temporary）仍保留完整副本，因此绝不先删除唯一有效 journal。
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultStorageException();
    }
  }

  Future<void> _commitTombstone(int revision) async {
    Object? writeFailure;
    try {
      await _writeTombstone(revision);
    } on Object catch (error) {
      writeFailure = error;
    }

    _JournalCandidate? latest;
    try {
      latest = await _readLatestCandidate();
      if (latest != null && latest.isTombstone && latest.revision >= revision) {
        return;
      }
    } finally {
      latest?.destroy();
    }
    if (writeFailure is VaultException) throw writeFailure;
    throw const VaultStorageException();
  }

  Future<void> _writeTombstone(int revision) async {
    if (revision < 1 || revision > _maximumRevision) {
      throw const VaultStorageException();
    }
    final base = await _fileProvider();
    final target = File(revision.isOdd ? '${base.path}.a' : '${base.path}.b');
    final temporary = File('${target.path}.tmp');
    final record = <String, Object?>{
      'magic': _magic,
      'version': _version,
      'revision': revision,
      'state': _discardedState,
    };
    final digest = await Sha256().hash(utf8.encode(jsonEncode(record)));
    final encoded = jsonEncode(<String, Object?>{
      ...record,
      'sha256': base64UrlEncode(digest.bytes),
    });
    try {
      await base.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(encoded, flush: true);
      if (await temporary.length() != utf8.encode(encoded).length) {
        throw const VaultStorageException();
      }
      final verified = await _readCandidate(
        _CandidateLocation(file: temporary, priority: 4),
      );
      try {
        if (!verified.isTombstone || verified.revision != revision) {
          throw const VaultStorageException();
        }
      } finally {
        verified.destroy();
      }
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultStorageException();
    }
  }

  Future<void> _deleteRetiredCandidatesBestEffort() async {
    File base;
    try {
      base = await _fileProvider();
    } on Object {
      return;
    }
    final locations = <_CandidateLocation>[
      _CandidateLocation(file: base, priority: 1),
      _CandidateLocation(file: File('${base.path}.tmp'), priority: 2),
      _CandidateLocation(file: File('${base.path}.a'), priority: 3),
      _CandidateLocation(file: File('${base.path}.a.tmp'), priority: 4),
      _CandidateLocation(file: File('${base.path}.b'), priority: 3),
      _CandidateLocation(file: File('${base.path}.b.tmp'), priority: 4),
    ];
    for (final location in locations) {
      try {
        if (!await location.file.exists()) continue;
      } on Object {
        continue;
      }
      var keep = false;
      _JournalCandidate? candidate;
      try {
        candidate = await _readCandidate(location);
        keep = candidate.isTombstone;
      } on Object {
        // 损坏、旧版或未完成的非 tombstone 文件均可尽力清理。
      } finally {
        candidate?.destroy();
      }
      if (!keep) {
        try {
          await location.file.delete();
        } on Object {
          // tombstone 已经提交；物理文件清理只能作为第二道防线。
        }
      }
    }
  }

  Future<int> _nextRevision() async {
    final latest = await _readLatestCandidate();
    if (latest == null) return 1;
    try {
      return _incrementRevision(latest.revision);
    } finally {
      latest.destroy();
    }
  }

  static int _incrementRevision(int revision) {
    if (revision < 1 || revision >= _maximumRevision) {
      throw const VaultStorageException();
    }
    return revision + 1;
  }

  Future<_JournalCandidate?> _readLatestCandidate() async {
    final base = await _fileProvider();
    final locations = <_CandidateLocation>[
      // 兼容旧版主文件；旧实现遗留的有效 .tmp 表示一次中断的新写入，
      // 同 revision 下优先于旧主文件。
      _CandidateLocation(file: base, priority: 1),
      _CandidateLocation(file: File('${base.path}.tmp'), priority: 2),
      _CandidateLocation(file: File('${base.path}.a'), priority: 3),
      _CandidateLocation(file: File('${base.path}.a.tmp'), priority: 4),
      _CandidateLocation(file: File('${base.path}.b'), priority: 3),
      _CandidateLocation(file: File('${base.path}.b.tmp'), priority: 4),
    ];
    _JournalCandidate? latest;
    var foundAnyFile = false;
    for (final location in locations) {
      if (!await location.file.exists()) continue;
      foundAnyFile = true;
      _JournalCandidate candidate;
      try {
        candidate = await _readCandidate(location);
      } on Object {
        continue;
      }
      final shouldReplace =
          latest == null ||
          candidate.revision > latest.revision ||
          (candidate.revision == latest.revision &&
              candidate.location.priority > latest.location.priority);
      if (shouldReplace) {
        latest?.destroy();
        latest = candidate;
      } else {
        candidate.destroy();
      }
    }
    if (latest == null && foundAnyFile) {
      throw const VaultStorageException();
    }
    return latest;
  }

  Future<_JournalCandidate> _readCandidate(_CandidateLocation location) async {
    Uint8List? encryptedBytes;
    try {
      final length = await location.file.length();
      if (length < 1 || length > _maximumJournalBytes) {
        throw const VaultStorageException();
      }
      final decoded = jsonDecode(await location.file.readAsString());
      if (decoded is! Map<Object?, Object?> ||
          decoded['magic'] != _magic ||
          (decoded['version'] != _legacyVersion &&
              decoded['version'] != _previousVersion &&
              decoded['version'] != _version) ||
          decoded['state'] is! String ||
          decoded['sha256'] is! String) {
        throw const VaultStorageException();
      }
      final version = decoded['version']! as int;
      final revision = version == _legacyVersion ? 1 : decoded['revision'];
      final stateValue = decoded['state']! as String;
      final expectedHash = decoded['sha256']! as String;
      if (revision is! int ||
          revision < 1 ||
          revision > _maximumRevision ||
          expectedHash.isEmpty ||
          expectedHash.length > 128) {
        throw const VaultStorageException();
      }

      if (version == _version && stateValue == _discardedState) {
        if (decoded.containsKey('encryptedVault')) {
          throw const VaultStorageException();
        }
        final digest = await Sha256().hash(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'magic': _magic,
              'version': _version,
              'revision': revision,
              'state': _discardedState,
            }),
          ),
        );
        if (!_constantTimeEquals(
          utf8.encode(base64UrlEncode(digest.bytes)),
          utf8.encode(expectedHash),
        )) {
          throw const VaultStorageException();
        }
        return _JournalCandidate.tombstone(
          location: location,
          revision: revision,
        );
      }

      if (decoded['transactionId'] is! String ||
          decoded['createdAtUtc'] is! String ||
          decoded['sourceGeneration'] is! int ||
          decoded['encryptedVault'] is! String) {
        throw const VaultStorageException();
      }
      final transactionId = decoded['transactionId']! as String;
      final createdAtValue = decoded['createdAtUtc']! as String;
      final createdAt = DateTime.tryParse(createdAtValue);
      final sourceGeneration = decoded['sourceGeneration']! as int;
      final state = VaultRecoveryState.values
          .where((candidate) => candidate.name == stateValue)
          .firstOrNull;
      final encryptedVaultValue = decoded['encryptedVault']! as String;
      if (transactionId.isEmpty ||
          transactionId.length > 64 ||
          createdAtValue.length > 64 ||
          createdAt == null ||
          !createdAt.isUtc ||
          sourceGeneration < 1 ||
          sourceGeneration > 1000000000 ||
          state == null ||
          expectedHash.isEmpty ||
          expectedHash.length > 128) {
        throw const VaultStorageException();
      }
      encryptedBytes = Uint8List.fromList(base64Decode(encryptedVaultValue));
      if (encryptedBytes.isEmpty ||
          encryptedBytes.length > maximumPortableBackupBytes) {
        throw const VaultStorageException();
      }
      final digest = version == _legacyVersion
          ? await Sha256().hash(encryptedBytes)
          : await Sha256().hash(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'magic': _magic,
                  'version': version,
                  'revision': revision,
                  'transactionId': transactionId,
                  'createdAtUtc': createdAtValue,
                  'sourceGeneration': sourceGeneration,
                  'state': stateValue,
                  'encryptedVault': encryptedVaultValue,
                }),
              ),
            );
      if (!_constantTimeEquals(
        utf8.encode(base64UrlEncode(digest.bytes)),
        utf8.encode(expectedHash),
      )) {
        throw const VaultStorageException();
      }
      final entry = VaultRecoveryEntry(
        transactionId: transactionId,
        createdAtUtc: createdAt,
        sourceGeneration: sourceGeneration,
        revision: revision,
        state: state,
        encryptedVaultBytes: encryptedBytes,
      );
      encryptedBytes.fillRange(0, encryptedBytes.length, 0);
      encryptedBytes = null;
      return _JournalCandidate.entry(location: location, entry: entry);
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultStorageException();
    } finally {
      encryptedBytes?.fillRange(0, encryptedBytes.length, 0);
    }
  }

  static String _newTransactionId() {
    final random = SecretKeyData.random(length: 16);
    try {
      return random.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
    } finally {
      random.destroy();
    }
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index += 1) {
      final leftValue = index < left.length ? left[index] : 0;
      final rightValue = index < right.length ? right[index] : 0;
      difference |= leftValue ^ rightValue;
    }
    return difference == 0;
  }
}

final class _CandidateLocation {
  const _CandidateLocation({required this.file, required this.priority});

  final File file;
  final int priority;
}

final class _JournalCandidate {
  _JournalCandidate.entry({
    required this.location,
    required VaultRecoveryEntry entry,
  }) : entry = entry,
       revision = entry.revision,
       isTombstone = false;

  const _JournalCandidate.tombstone({
    required this.location,
    required this.revision,
  }) : entry = null,
       isTombstone = true;

  final _CandidateLocation location;
  final int revision;
  final VaultRecoveryEntry? entry;
  final bool isTombstone;

  void destroy() => entry?.destroy();
}
