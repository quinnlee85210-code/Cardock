import 'package:account_subscription_manager/core/storage/portable_backup_service.dart';
import 'dart:typed_data';
import 'package:account_subscription_manager/core/platform/import_document_picker.dart';
import 'package:account_subscription_manager/core/data_import/tabular_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'backup cleanup owns its buffer even when Android returns read-only bytes',
    () {
      final source = Uint8List.fromList([1, 2, 3]).asUnmodifiableView();
      final selection = decodeBackupDocumentResponse({
        'name': 'fictional.asmbackup',
        'bytes': source,
      })!;
      selection.bytes.fillRange(0, selection.bytes.length, 0);
      expect(selection.bytes, [0, 0, 0]);
      expect(source, [1, 2, 3]);
      expect(decodeBackupDocumentResponse(null), isNull);
      expect(
        () => decodeBackupDocumentResponse({
          'name': 'empty.asmbackup',
          'bytes': Uint8List(0),
        }),
        throwsFormatException,
      );
      expect(
        () => decodeBackupDocumentResponse({
          'name': 'large.asmbackup',
          'bytes': Uint8List(16 * 1024 * 1024 + 1),
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'read-only Android document bytes can be parsed and cleared safely',
    () async {
      final source = Uint8List.fromList(
        'name,login\nFictional,review\n'.codeUnits,
      ).asUnmodifiableView();
      final file = decodeImportDocumentResponse({
        'name': 'review.csv',
        'bytes': source,
      })!;
      expect(identical(file.bytes, source), isFalse);
      final parsed = await const TabularImportParser()
          .parseInBackground(file.bytes)
          .result;
      expect(parsed.headers, ['name', 'login']);
      file.bytes.fillRange(0, file.bytes.length, 0);
      expect(file.bytes.every((byte) => byte == 0), isTrue);
      expect(String.fromCharCodes(source), contains('Fictional'));
    },
  );
  test(
    'cancel and malformed native document responses fail without copying',
    () {
      expect(decodeImportDocumentResponse(null), isNull);
      for (final value in <Map<String, Object?>>[
        {
          'name': 'wrong.csv',
          'bytes': [1, 2],
        },
        {'name': 42, 'bytes': Uint8List(2)},
        {'name': 'large.csv', 'bytes': Uint8List(10 * 1024 * 1024 + 1)},
      ]) {
        expect(
          () => decodeImportDocumentResponse(value),
          throwsFormatException,
        );
      }
    },
  );
}
