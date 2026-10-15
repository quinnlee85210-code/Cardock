import 'dart:convert';

enum DataTransferFileRole {
  externalImport,
  encryptedBackup,
  calendarIcs,
  unsupported,
}

const supportedExternalImportExtensions = <String>{
  'xlsx',
  'docx',
  'csv',
  'tsv',
  'txt',
};

DataTransferFileRole classifyDataTransferFile({
  required String fileName,
  required List<int> bytes,
}) {
  final prefixLength = bytes.length < 2048 ? bytes.length : 2048;
  final prefix = utf8
      .decode(bytes.sublist(0, prefixLength), allowMalformed: true)
      .replaceFirst('\ufeff', '')
      .trimLeft();
  final compactJsonPrefix = prefix.replaceAll(RegExp(r'\s+'), '');

  if (compactJsonPrefix.startsWith('{') &&
      (compactJsonPrefix.contains('"magic":"ASM_PORTABLE_BACKUP"') ||
          compactJsonPrefix.contains('"magic":"ASM_LOCAL_VAULT"'))) {
    return DataTransferFileRole.encryptedBackup;
  }
  if (prefix.toUpperCase().startsWith('BEGIN:VCALENDAR')) {
    return DataTransferFileRole.calendarIcs;
  }

  final normalizedName = fileName.trim().toLowerCase();
  final dot = normalizedName.lastIndexOf('.');
  final extension = dot < 0 ? '' : normalizedName.substring(dot + 1);
  if (extension == 'asmbackup') {
    return DataTransferFileRole.encryptedBackup;
  }
  if (extension == 'ics') {
    return DataTransferFileRole.calendarIcs;
  }
  if (supportedExternalImportExtensions.contains(extension)) {
    return DataTransferFileRole.externalImport;
  }
  return DataTransferFileRole.unsupported;
}
