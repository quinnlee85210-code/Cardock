// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

@TestOn('browser')
library;

import 'dart:html';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chrome FileReader 把虚构 XLSX File 读回原始 ArrayBuffer 字节', () async {
    final original = Uint8List.fromList(<int>[
      0x50,
      0x4B,
      0x03,
      0x04,
      0x46,
      0x41,
      0x4B,
      0x45,
    ]);
    final file = File(
      <Object>[original],
      'fictional-browser.xlsx',
      <String, String>{
        'type':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      },
    );
    final reader = FileReader()..readAsArrayBuffer(file);

    await Future.any<void>(<Future<void>>[
      reader.onLoad.first.then((_) {}),
      reader.onError.first.then(
        (_) => throw const FormatException('file_read_failed'),
      ),
      reader.onAbort.first.then(
        (_) => throw const FormatException('file_read_aborted'),
      ),
    ]).timeout(const Duration(seconds: 5));

    final result = reader.result;
    final bytes = switch (result) {
      ByteBuffer buffer => Uint8List.view(buffer),
      Uint8List values => values,
      _ => throw StateError('unsupported_file_reader_result_type'),
    };
    expect(bytes, original);
  });
}
