import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

final class UnlockClockReading {
  const UnlockClockReading({
    required this.bootCount,
    required this.elapsedRealtimeMilliseconds,
  });

  final int bootCount;
  final int elapsedRealtimeMilliseconds;
}

abstract interface class UnlockThrottleClock {
  Future<UnlockClockReading> read();
}

final class MethodChannelUnlockThrottleClock implements UnlockThrottleClock {
  const MethodChannelUnlockThrottleClock([
    this._channel = const MethodChannel(channelName),
  ]);

  static const String channelName =
      'account_subscription_manager/unlock_clock_v1';
  static const String readMethod = 'read';

  final MethodChannel _channel;

  @override
  Future<UnlockClockReading> read() async {
    final value = await _channel.invokeMethod<Object?>(readMethod);
    if (value is! Map<Object?, Object?>) {
      throw const UnlockThrottleClockException(
        'unlock clock returned an invalid payload',
      );
    }
    final bootCount = value['bootCount'];
    final elapsedRealtimeMilliseconds =
        value['elapsedRealtimeMilliseconds'] ?? value['elapsedRealtimeMs'];
    if (bootCount is! int ||
        bootCount < 0 ||
        elapsedRealtimeMilliseconds is! int ||
        elapsedRealtimeMilliseconds < 0) {
      throw const UnlockThrottleClockException(
        'unlock clock returned invalid values',
      );
    }
    return UnlockClockReading(
      bootCount: bootCount,
      elapsedRealtimeMilliseconds: elapsedRealtimeMilliseconds,
    );
  }
}

final class MemoryUnlockThrottleClock implements UnlockThrottleClock {
  MemoryUnlockThrottleClock({
    this.bootCount = 1,
    int elapsedRealtimeMilliseconds = 0,
  }) : elapsedRealtimeMilliseconds = elapsedRealtimeMilliseconds {
    if (bootCount < 0 || elapsedRealtimeMilliseconds < 0) {
      throw ArgumentError('clock values must not be negative');
    }
  }

  int bootCount;
  int elapsedRealtimeMilliseconds;

  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration');
    }
    elapsedRealtimeMilliseconds += duration.inMilliseconds;
  }

  void reboot({int? nextBootCount}) {
    final next = nextBootCount ?? bootCount + 1;
    if (next < 0 || next == bootCount) {
      throw ArgumentError.value(next, 'nextBootCount');
    }
    bootCount = next;
    elapsedRealtimeMilliseconds = 0;
  }

  @override
  Future<UnlockClockReading> read() async => UnlockClockReading(
    bootCount: bootCount,
    elapsedRealtimeMilliseconds: elapsedRealtimeMilliseconds,
  );
}

final class UnlockThrottleClockException implements Exception {
  const UnlockThrottleClockException(this.message);

  final String message;

  @override
  String toString() => 'UnlockThrottleClockException: $message';
}

final class UnlockThrottlePolicy {
  const UnlockThrottlePolicy._();

  static const int maximumFailedAttempts = 10;
  static const Duration maximumCooldown = Duration(minutes: 30);

  static Duration cooldownFor(int failedAttempts) {
    if (failedAttempts < 5) return Duration.zero;
    if (failedAttempts < 7) return const Duration(seconds: 30);
    if (failedAttempts < 9) return const Duration(minutes: 2);
    if (failedAttempts < 10) return const Duration(minutes: 10);
    return maximumCooldown;
  }
}

enum UnlockThrottleRecordState { active, cleared }

final class UnlockThrottleRecord {
  const UnlockThrottleRecord({
    required this.revision,
    required this.state,
    required this.failedAttempts,
    required this.bootCount,
    required this.cooldownDurationMilliseconds,
    required this.elapsedDeadlineMilliseconds,
  });

  final int revision;
  final UnlockThrottleRecordState state;
  final int failedAttempts;
  final int bootCount;
  final int cooldownDurationMilliseconds;
  final int elapsedDeadlineMilliseconds;
}

abstract interface class UnlockThrottleStore {
  Future<UnlockThrottleRecord?> read();

  Future<void> write(UnlockThrottleRecord record);
}

final class MemoryUnlockThrottleStore implements UnlockThrottleStore {
  MemoryUnlockThrottleStore([this.value]);

  UnlockThrottleRecord? value;
  int readCalls = 0;
  int writeCalls = 0;

  @override
  Future<UnlockThrottleRecord?> read() async {
    readCalls += 1;
    return value;
  }

  @override
  Future<void> write(UnlockThrottleRecord record) async {
    writeCalls += 1;
    value = record;
  }
}

final class FileUnlockThrottleStore implements UnlockThrottleStore {
  FileUnlockThrottleStore(this._fileProvider);

  factory FileUnlockThrottleStore.appSupport() =>
      FileUnlockThrottleStore(() async {
        final support = await getApplicationSupportDirectory();
        return File(
          '${support.path}${Platform.pathSeparator}unlock_throttle_v1.json',
        );
      });

  static const String _magic = 'ASM_UNLOCK_THROTTLE';
  static const int _version = 1;
  static const int _maximumFileBytes = 8192;
  static const int _maximumRevision = 0x7fffffff;

  final Future<File> Function() _fileProvider;

  @override
  Future<UnlockThrottleRecord?> read() async {
    final file = await _fileProvider();
    final candidates = <File>[
      file,
      File('${file.path}.bak'),
      File('${file.path}.tmp'),
      File('${file.path}.tmp.0'),
      File('${file.path}.tmp.1'),
    ];
    var foundFile = false;
    final valid = <UnlockThrottleRecord>[];
    for (final candidate in candidates) {
      try {
        if (!await candidate.exists()) continue;
        foundFile = true;
        if (await candidate.length() > _maximumFileBytes) continue;
        valid.add(_decode(await candidate.readAsString()));
      } on Object {
        // A valid sibling generation still permits crash recovery.
      }
    }
    if (valid.isEmpty) {
      if (!foundFile) return null;
      throw const UnlockThrottleStorageException(
        'no valid unlock throttle generation',
      );
    }
    valid.sort((left, right) => right.revision.compareTo(left.revision));
    return valid.first;
  }

  @override
  Future<void> write(UnlockThrottleRecord record) async {
    _validateRecord(record);
    final file = await _fileProvider();
    final temporary = File('${file.path}.tmp.${record.revision & 1}');
    final backup = File('${file.path}.bak');
    final encoded = _encode(record);
    try {
      await file.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(encoded, flush: true);
      final verified = _decode(await temporary.readAsString());
      if (!_sameRecord(verified, record)) {
        throw const UnlockThrottleStorageException(
          'unlock throttle write verification failed',
        );
      }
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) await file.rename(backup.path);
      await temporary.rename(file.path);
    } on UnlockThrottleStorageException {
      rethrow;
    } on Object catch (error) {
      throw UnlockThrottleStorageException(
        'unable to persist unlock throttle state: $error',
      );
    }
  }

  static String _encode(UnlockThrottleRecord record) =>
      jsonEncode(<String, Object>{
        'magic': _magic,
        'version': _version,
        'revision': record.revision,
        'state': record.state.name,
        'failedAttempts': record.failedAttempts,
        'bootCount': record.bootCount,
        'cooldownDurationMilliseconds': record.cooldownDurationMilliseconds,
        'elapsedDeadlineMilliseconds': record.elapsedDeadlineMilliseconds,
      });

  static UnlockThrottleRecord _decode(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map<Object?, Object?> ||
        value['magic'] != _magic ||
        value['version'] != _version ||
        value['revision'] is! int ||
        value['state'] is! String ||
        value['failedAttempts'] is! int ||
        value['bootCount'] is! int ||
        value['cooldownDurationMilliseconds'] is! int ||
        value['elapsedDeadlineMilliseconds'] is! int) {
      throw const FormatException('invalid unlock throttle document');
    }
    final state = switch (value['state']) {
      'active' => UnlockThrottleRecordState.active,
      'cleared' => UnlockThrottleRecordState.cleared,
      _ => throw const FormatException('invalid unlock throttle state'),
    };
    final record = UnlockThrottleRecord(
      revision: value['revision']! as int,
      state: state,
      failedAttempts: value['failedAttempts']! as int,
      bootCount: value['bootCount']! as int,
      cooldownDurationMilliseconds:
          value['cooldownDurationMilliseconds']! as int,
      elapsedDeadlineMilliseconds: value['elapsedDeadlineMilliseconds']! as int,
    );
    _validateRecord(record);
    return record;
  }

  static void _validateRecord(UnlockThrottleRecord record) {
    if (record.revision < 1 || record.revision > _maximumRevision) {
      throw const FormatException('invalid unlock throttle revision');
    }
    if (record.bootCount < 0 ||
        record.elapsedDeadlineMilliseconds < 0 ||
        record.cooldownDurationMilliseconds < 0) {
      throw const FormatException('negative unlock throttle value');
    }
    if (record.state == UnlockThrottleRecordState.cleared) {
      if (record.failedAttempts != 0 ||
          record.cooldownDurationMilliseconds != 0 ||
          record.elapsedDeadlineMilliseconds != 0) {
        throw const FormatException('invalid cleared unlock throttle state');
      }
      return;
    }
    if (record.failedAttempts < 1 ||
        record.failedAttempts > UnlockThrottlePolicy.maximumFailedAttempts) {
      throw const FormatException('invalid unlock throttle attempt count');
    }
    final expected = UnlockThrottlePolicy.cooldownFor(
      record.failedAttempts,
    ).inMilliseconds;
    final cooldownCleared =
        record.cooldownDurationMilliseconds == 0 &&
        record.elapsedDeadlineMilliseconds == 0;
    if (expected == 0) {
      if (!cooldownCleared) {
        throw const FormatException('unexpected unlock throttle cooldown');
      }
      return;
    }
    if (cooldownCleared) {
      if (record.failedAttempts >= UnlockThrottlePolicy.maximumFailedAttempts) {
        throw const FormatException('maximum cooldown cannot be cleared');
      }
      return;
    }
    if (record.cooldownDurationMilliseconds != expected ||
        record.elapsedDeadlineMilliseconds == 0) {
      throw const FormatException('invalid unlock throttle cooldown');
    }
  }

  static bool _sameRecord(
    UnlockThrottleRecord left,
    UnlockThrottleRecord right,
  ) =>
      left.revision == right.revision &&
      left.state == right.state &&
      left.failedAttempts == right.failedAttempts &&
      left.bootCount == right.bootCount &&
      left.cooldownDurationMilliseconds == right.cooldownDurationMilliseconds &&
      left.elapsedDeadlineMilliseconds == right.elapsedDeadlineMilliseconds;
}

final class UnlockThrottleStorageException implements Exception {
  const UnlockThrottleStorageException(this.message);

  final String message;

  @override
  String toString() => 'UnlockThrottleStorageException: $message';
}

final class UnlockThrottleSnapshot {
  const UnlockThrottleSnapshot({
    required this.failedAttempts,
    required this.cooldownRemaining,
  });

  const UnlockThrottleSnapshot.clear()
    : failedAttempts = 0,
      cooldownRemaining = Duration.zero;

  final int failedAttempts;
  final Duration cooldownRemaining;

  bool get isBlocked => cooldownRemaining > Duration.zero;

  int get attemptsRemaining =>
      (UnlockThrottlePolicy.maximumFailedAttempts - failedAttempts).clamp(
        0,
        UnlockThrottlePolicy.maximumFailedAttempts,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnlockThrottleSnapshot &&
          failedAttempts == other.failedAttempts &&
          cooldownRemaining == other.cooldownRemaining;

  @override
  int get hashCode => Object.hash(failedAttempts, cooldownRemaining);
}

final class UnlockThrottleController {
  UnlockThrottleController(this._store, this._clock);

  factory UnlockThrottleController.appSupport() => UnlockThrottleController(
    FileUnlockThrottleStore.appSupport(),
    const MethodChannelUnlockThrottleClock(),
  );

  factory UnlockThrottleController.memory({
    MemoryUnlockThrottleStore? store,
    MemoryUnlockThrottleClock? clock,
  }) => UnlockThrottleController(
    store ?? MemoryUnlockThrottleStore(),
    clock ?? MemoryUnlockThrottleClock(),
  );

  static const int _maximumRevision = 0x7fffffff;

  final UnlockThrottleStore _store;
  final UnlockThrottleClock _clock;
  Future<void> _operationTail = Future<void>.value();
  UnlockThrottleRecord? _record;
  UnlockThrottleSnapshot _snapshot = const UnlockThrottleSnapshot.clear();
  bool _initialized = false;

  UnlockThrottleSnapshot get snapshot => _snapshot;

  Future<UnlockThrottleSnapshot> initialize() => _runExclusive(() async {
    _record = await _store.read();
    _initialized = true;
    return _refreshAt(await _clock.read());
  });

  Future<UnlockThrottleSnapshot> refresh() => _runExclusive(() async {
    _requireInitialized();
    return _refreshAt(await _clock.read());
  });

  Future<UnlockThrottleSnapshot> recordCredentialFailure() =>
      _runExclusive(() async {
        _requireInitialized();
        final reading = await _clock.read();
        await _refreshAt(reading);
        if (_snapshot.isBlocked) {
          return _snapshot;
        }
        final failedAttempts = (_snapshot.failedAttempts + 1).clamp(
          1,
          UnlockThrottlePolicy.maximumFailedAttempts,
        );
        final cooldown = UnlockThrottlePolicy.cooldownFor(failedAttempts);
        final next = UnlockThrottleRecord(
          revision: _nextRevision(),
          state: UnlockThrottleRecordState.active,
          failedAttempts: failedAttempts,
          bootCount: reading.bootCount,
          cooldownDurationMilliseconds: cooldown.inMilliseconds,
          elapsedDeadlineMilliseconds: cooldown == Duration.zero
              ? 0
              : reading.elapsedRealtimeMilliseconds + cooldown.inMilliseconds,
        );
        await _write(next);
        _snapshot = UnlockThrottleSnapshot(
          failedAttempts: failedAttempts,
          cooldownRemaining: cooldown,
        );
        return _snapshot;
      });

  Future<UnlockThrottleSnapshot> clearAfterPrimaryAuthentication() =>
      _runExclusive(() async {
        _requireInitialized();
        final reading = await _clock.read();
        await _refreshAt(reading);
        if ((_record?.failedAttempts ?? 0) == 0) {
          _snapshot = const UnlockThrottleSnapshot.clear();
          return _snapshot;
        }
        final cleared = UnlockThrottleRecord(
          revision: _nextRevision(),
          state: UnlockThrottleRecordState.cleared,
          failedAttempts: 0,
          bootCount: reading.bootCount,
          cooldownDurationMilliseconds: 0,
          elapsedDeadlineMilliseconds: 0,
        );
        await _write(cleared);
        _snapshot = const UnlockThrottleSnapshot.clear();
        return _snapshot;
      });

  Future<UnlockThrottleSnapshot> _refreshAt(UnlockClockReading reading) async {
    final record = _record;
    if (record == null ||
        record.state == UnlockThrottleRecordState.cleared ||
        record.failedAttempts == 0) {
      _snapshot = const UnlockThrottleSnapshot.clear();
      return _snapshot;
    }
    if (record.cooldownDurationMilliseconds == 0) {
      _snapshot = UnlockThrottleSnapshot(
        failedAttempts: record.failedAttempts,
        cooldownRemaining: Duration.zero,
      );
      return _snapshot;
    }
    if (record.bootCount != reading.bootCount) {
      final rearmed = UnlockThrottleRecord(
        revision: _nextRevision(),
        state: UnlockThrottleRecordState.active,
        failedAttempts: record.failedAttempts,
        bootCount: reading.bootCount,
        cooldownDurationMilliseconds: record.cooldownDurationMilliseconds,
        elapsedDeadlineMilliseconds:
            reading.elapsedRealtimeMilliseconds +
            record.cooldownDurationMilliseconds,
      );
      await _write(rearmed);
      _snapshot = UnlockThrottleSnapshot(
        failedAttempts: rearmed.failedAttempts,
        cooldownRemaining: Duration(
          milliseconds: rearmed.cooldownDurationMilliseconds,
        ),
      );
      return _snapshot;
    }
    final remainingMilliseconds =
        record.elapsedDeadlineMilliseconds -
        reading.elapsedRealtimeMilliseconds;
    if (remainingMilliseconds > record.cooldownDurationMilliseconds) {
      // elapsedRealtime must not move backwards within one boot. If the native
      // boot identifier was unavailable or the payload was rolled back, re-arm
      // one bounded stage instead of accepting the anomalous deadline.
      final rearmed = UnlockThrottleRecord(
        revision: _nextRevision(),
        state: UnlockThrottleRecordState.active,
        failedAttempts: record.failedAttempts,
        bootCount: reading.bootCount,
        cooldownDurationMilliseconds: record.cooldownDurationMilliseconds,
        elapsedDeadlineMilliseconds:
            reading.elapsedRealtimeMilliseconds +
            record.cooldownDurationMilliseconds,
      );
      await _write(rearmed);
      _snapshot = UnlockThrottleSnapshot(
        failedAttempts: rearmed.failedAttempts,
        cooldownRemaining: Duration(
          milliseconds: rearmed.cooldownDurationMilliseconds,
        ),
      );
      return _snapshot;
    }
    if (remainingMilliseconds > 0) {
      _snapshot = UnlockThrottleSnapshot(
        failedAttempts: record.failedAttempts,
        cooldownRemaining: Duration(milliseconds: remainingMilliseconds),
      );
      return _snapshot;
    }
    if (record.failedAttempts >= UnlockThrottlePolicy.maximumFailedAttempts) {
      final cleared = UnlockThrottleRecord(
        revision: _nextRevision(),
        state: UnlockThrottleRecordState.cleared,
        failedAttempts: 0,
        bootCount: reading.bootCount,
        cooldownDurationMilliseconds: 0,
        elapsedDeadlineMilliseconds: 0,
      );
      await _write(cleared);
      _snapshot = const UnlockThrottleSnapshot.clear();
      return _snapshot;
    }
    final cooldownCleared = UnlockThrottleRecord(
      revision: _nextRevision(),
      state: UnlockThrottleRecordState.active,
      failedAttempts: record.failedAttempts,
      bootCount: reading.bootCount,
      cooldownDurationMilliseconds: 0,
      elapsedDeadlineMilliseconds: 0,
    );
    await _write(cooldownCleared);
    _snapshot = UnlockThrottleSnapshot(
      failedAttempts: cooldownCleared.failedAttempts,
      cooldownRemaining: Duration.zero,
    );
    return _snapshot;
  }

  int _nextRevision() {
    final next = (_record?.revision ?? 0) + 1;
    if (next > _maximumRevision) {
      throw const UnlockThrottleStorageException(
        'unlock throttle revision exhausted',
      );
    }
    return next;
  }

  Future<void> _write(UnlockThrottleRecord record) async {
    await _store.write(record);
    _record = record;
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw StateError('unlock throttle controller is not initialized');
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    return (() async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    })();
  }
}
