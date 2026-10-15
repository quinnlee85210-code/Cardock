import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../security/vault_contract.dart';

final class BackupHealthRecord {
  const BackupHealthRecord({
    this.lastExportedAtUtc,
    this.lastVerifiedAtUtc,
    this.lastVerifiedFormatVersion,
  });

  final DateTime? lastExportedAtUtc;
  final DateTime? lastVerifiedAtUtc;
  final int? lastVerifiedFormatVersion;

  BackupHealthRecord copyWith({
    DateTime? lastExportedAtUtc,
    DateTime? lastVerifiedAtUtc,
    int? lastVerifiedFormatVersion,
  }) => BackupHealthRecord(
    lastExportedAtUtc: lastExportedAtUtc ?? this.lastExportedAtUtc,
    lastVerifiedAtUtc: lastVerifiedAtUtc ?? this.lastVerifiedAtUtc,
    lastVerifiedFormatVersion:
        lastVerifiedFormatVersion ?? this.lastVerifiedFormatVersion,
  );
}

abstract interface class BackupHealthStore {
  Future<BackupHealthRecord> read();

  Future<void> write(BackupHealthRecord record);
}

final class NoopBackupHealthStore implements BackupHealthStore {
  const NoopBackupHealthStore();

  @override
  Future<BackupHealthRecord> read() async => const BackupHealthRecord();

  @override
  Future<void> write(BackupHealthRecord record) async {}
}

final class FileBackupHealthStore implements BackupHealthStore {
  FileBackupHealthStore({required this._fileProvider});

  factory FileBackupHealthStore.appSupport() => FileBackupHealthStore(
    fileProvider: () async {
      final support = await getApplicationSupportDirectory();
      return File(
        '${support.path}${Platform.pathSeparator}backup_health_v1.json',
      );
    },
  );

  static const _magic = 'ASM_BACKUP_HEALTH';
  static const _version = 1;
  final Future<File> Function() _fileProvider;

  @override
  Future<BackupHealthRecord> read() async {
    final file = await _fileProvider();
    if (!await file.exists()) return const BackupHealthRecord();
    try {
      if (await file.length() > 4096) throw const FormatException();
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<Object?, Object?> ||
          value['magic'] != _magic ||
          value['version'] != _version) {
        throw const FormatException();
      }
      DateTime? date(String key) {
        final raw = value[key];
        if (raw == null) return null;
        if (raw is! String || raw.length > 64) throw const FormatException();
        final parsed = DateTime.tryParse(raw);
        if (parsed == null || !parsed.isUtc) throw const FormatException();
        return parsed;
      }

      final format = value['lastVerifiedFormatVersion'];
      if (format != null && (format is! int || format < 1 || format > 2)) {
        throw const FormatException();
      }
      return BackupHealthRecord(
        lastExportedAtUtc: date('lastExportedAtUtc'),
        lastVerifiedAtUtc: date('lastVerifiedAtUtc'),
        lastVerifiedFormatVersion: format as int?,
      );
    } on Object {
      throw const VaultStorageException();
    }
  }

  @override
  Future<void> write(BackupHealthRecord record) async {
    final file = await _fileProvider();
    final temporary = File('${file.path}.tmp');
    final encoded = jsonEncode(<String, Object?>{
      'magic': _magic,
      'version': _version,
      'lastExportedAtUtc': record.lastExportedAtUtc?.toIso8601String(),
      'lastVerifiedAtUtc': record.lastVerifiedAtUtc?.toIso8601String(),
      'lastVerifiedFormatVersion': record.lastVerifiedFormatVersion,
    });
    try {
      await file.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(encoded, flush: true);
      if (await temporary.readAsString() != encoded) {
        throw const VaultStorageException();
      }
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultStorageException();
    }
  }
}
