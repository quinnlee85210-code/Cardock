import 'dart:convert';

import 'package:account_subscription_manager/core/storage/data_transfer_file_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('data transfer file routing', () {
    for (final extension in supportedExternalImportExtensions) {
      test('accepts .$extension as external import', () {
        expect(
          classifyDataTransferFile(
            fileName: 'records.${extension.toUpperCase()}',
            bytes: utf8.encode('name,value\nexample,1'),
          ),
          DataTransferFileRole.externalImport,
        );
      });
    }

    test('content signature recognizes portable and legacy backups', () {
      for (final magic in const <String>[
        'ASM_PORTABLE_BACKUP',
        'ASM_LOCAL_VAULT',
      ]) {
        expect(
          classifyDataTransferFile(
            fileName: 'renamed.csv',
            bytes: utf8.encode('{ "magic" : "$magic", "formatVersion" : 99 }'),
          ),
          DataTransferFileRole.encryptedBackup,
        );
      }
    });

    test('content signature recognizes BOM calendar despite renamed file', () {
      expect(
        classifyDataTransferFile(
          fileName: 'renamed.txt',
          bytes: utf8.encode('\ufeff  BEGIN:VCALENDAR\r\nEND:VCALENDAR'),
        ),
        DataTransferFileRole.calendarIcs,
      );
    });

    test('calendar content wins over asmbackup extension', () {
      expect(
        classifyDataTransferFile(
          fileName: 'wrong.asmbackup',
          bytes: utf8.encode('BEGIN:VCALENDAR\r\nEND:VCALENDAR'),
        ),
        DataTransferFileRole.calendarIcs,
      );
    });

    test('asmbackup extension remains eligible for codec validation', () {
      expect(
        classifyDataTransferFile(
          fileName: 'damaged.asmbackup',
          bytes: const <int>[1, 2, 3],
        ),
        DataTransferFileRole.encryptedBackup,
      );
    });

    test('unknown and missing extensions are rejected', () {
      for (final name in const <String>['records.bin', 'records', '.hidden']) {
        expect(
          classifyDataTransferFile(
            fileName: name,
            bytes: utf8.encode('unknown'),
          ),
          DataTransferFileRole.unsupported,
        );
      }
    });
  });
}
