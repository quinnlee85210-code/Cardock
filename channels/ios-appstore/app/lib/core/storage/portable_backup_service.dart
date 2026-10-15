import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';

import 'portable_backup_codec.dart';

typedef PortableBackupSelection = ({String name, Uint8List bytes});

abstract interface class PortableBackupService {
  Future<bool> saveEncryptedBackup(Uint8List bytes, {String? dialogTitle});

  Future<PortableBackupSelection?> pickEncryptedBackup({String? dialogTitle});
}

final class FilePickerPortableBackupService implements PortableBackupService {
  const FilePickerPortableBackupService({this.platform});
  final TargetPlatform? platform;
  TargetPlatform? get _platform =>
      platform ??
      (Platform.isIOS
          ? TargetPlatform.iOS
          : Platform.isAndroid
          ? TargetPlatform.android
          : null);

  static const maximumBackupBytes = maximumPortableBackupBytes;

  @override
  Future<bool> saveEncryptedBackup(
    Uint8List bytes, {
    String? dialogTitle,
  }) async {
    if (bytes.isEmpty || bytes.length > maximumBackupBytes) {
      throw const FormatException('备份文件大小无效');
    }
    final now = DateTime.now();
    final fileName =
        'AccountBook_${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}.asmbackup';
    if (_platform == TargetPlatform.iOS) {
      final saved = await const MethodChannel(
        'cardock/document_storage_v1',
      ).invokeMethod<bool>('saveBackup', {'name': fileName, 'bytes': bytes});
      if (saved == null) throw const FormatException('Invalid export response');
      return saved;
    }
    final result = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle ?? '保存账号与订阅加密备份',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const <String>['asmbackup'],
      bytes: bytes,
    );
    return result != null;
  }

  @override
  Future<PortableBackupSelection?> pickEncryptedBackup({
    String? dialogTitle,
  }) async {
    if (_platform == TargetPlatform.android ||
        _platform == TargetPlatform.iOS) {
      final result = await const MethodChannel(
        'cardock/document_storage_v1',
      ).invokeMapMethod<String, Object?>('pickBackup');
      if (result == null) return null;
      final bytes = result['bytes'], name = result['name'];
      if (bytes is! Uint8List ||
          name is! String ||
          bytes.isEmpty ||
          bytes.length > maximumBackupBytes) {
        throw const FormatException('无法读取备份文件');
      }
      return (name: name, bytes: bytes);
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle ?? '选择账号与订阅加密备份',
      type: FileType.custom,
      allowedExtensions: const <String>['asmbackup'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null) {
      return null;
    }
    final file = result.files.single;
    if (file.size > maximumBackupBytes) {
      throw const FormatException('备份文件不得超过16 MiB');
    }
    final stream = file.readStream;
    if (stream == null) throw const FormatException('无法读取备份文件');
    return (name: file.name, bytes: await readBoundedBackup(stream));
  }
}

/// Counts actual bytes; provider metadata never replaces this limit.
Future<Uint8List> readBoundedBackup(Stream<List<int>> stream) async {
  final output = BytesBuilder(copy: false);
  try {
    await for (final chunk in stream) {
      if (chunk.length > maximumPortableBackupBytes - output.length) {
        throw const FormatException('备份文件不得超过16 MiB');
      }
      output.add(chunk);
    }
    if (output.isEmpty) throw const FormatException('无法读取备份文件');
    return output.takeBytes();
  } finally {
    output.clear();
  }
}
