import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Android reads the explicitly selected SAF document into bounded memory.
/// file_picker's Android cache-copy path is intentionally not used here.
Future<({String name, Uint8List bytes})?> pickImportDocument() async {
  if (Platform.isAndroid) {
    final value = await const MethodChannel(
      'cardock/document_storage_v1',
    ).invokeMapMethod<String, Object?>('pickImport');
    return decodeImportDocumentResponse(value);
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

/// Platform-channel typed data may be read-only. Import owns a mutable copy so
/// the parser and all exit paths can clear it without throwing during cleanup.
({String name, Uint8List bytes})? decodeImportDocumentResponse(
  Map<String, Object?>? value,
) {
  if (value == null) return null;
  final bytes = value['bytes'], name = value['name'];
  if (bytes is! Uint8List ||
      name is! String ||
      bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Invalid document response');
  }
  return (name: name, bytes: Uint8List.fromList(bytes));
}
