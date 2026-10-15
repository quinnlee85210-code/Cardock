import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Android reads the explicitly selected SAF document into bounded memory.
/// file_picker's Android cache-copy path is intentionally not used here.
Future<({String name, Uint8List bytes})?> pickImportDocument({
  TargetPlatform? platform,
}) async {
  final target =
      platform ??
      (Platform.isIOS
          ? TargetPlatform.iOS
          : Platform.isAndroid
          ? TargetPlatform.android
          : null);
  if (target == TargetPlatform.android || target == TargetPlatform.iOS) {
    final value = await const MethodChannel(
      'cardock/document_storage_v1',
    ).invokeMapMethod<String, Object?>('pickImport');
    if (value == null) return null;
    final bytes = value['bytes'], name = value['name'];
    if (bytes is! Uint8List ||
        name is! String ||
        bytes.isEmpty ||
        bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Invalid document response');
    }
    return (name: name, bytes: bytes);
  }
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    withData: true,
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'docx', 'csv', 'tsv', 'txt'],
  );
  if (result == null ||
      result.files.length != 1 ||
      result.files.single.bytes == null) {
    return null;
  }
  return (name: result.files.single.name, bytes: result.files.single.bytes!);
}
