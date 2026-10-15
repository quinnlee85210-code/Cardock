import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List _officeZip(Map<String, String> files, {bool compress = true}) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = _utf8Bytes(entry.value);
    final file = ArchiveFile(entry.key, bytes.length, bytes)
      ..compress = compress;
    archive.addFile(file);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

int _readUint16LittleEndian(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _readUint32LittleEndian(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void _writeUint16LittleEndian(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _writeUint32LittleEndian(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}

int _endOfCentralDirectoryOffset(Uint8List bytes) {
  for (var offset = bytes.length - 22; offset >= 0; offset -= 1) {
    if (_readUint32LittleEndian(bytes, offset) ==
            ZipDirectory.eocdLocatorSignature &&
        offset + 22 + _readUint16LittleEndian(bytes, offset + 20) ==
            bytes.length) {
      return offset;
    }
  }
  throw StateError('TEST-ONLY ZIP end record not found.');
}

Uint8List _withDeclaredEntryCount(Uint8List source, int value) {
  final bytes = Uint8List.fromList(source);
  final offset = _endOfCentralDirectoryOffset(bytes);
  bytes[offset + 8] = value & 0xff;
  bytes[offset + 9] = (value >> 8) & 0xff;
  bytes[offset + 10] = value & 0xff;
  bytes[offset + 11] = (value >> 8) & 0xff;
  return bytes;
}

Uint8List _withCommentContainingFalseEocd(Uint8List source) {
  const appendedCommentLength = 40;
  final originalDirectory = ZipDirectory.read(InputStream(source));
  final realEocdOffset = _endOfCentralDirectoryOffset(source);
  final bytes = Uint8List(source.length + appendedCommentLength);
  bytes.setRange(0, source.length, source);
  _writeUint16LittleEndian(bytes, realEocdOffset + 20, appendedCommentLength);

  // This later raw signature deliberately has an invalid comment boundary,
  // but otherwise points at the real central directory. archive 3.6.1 selects
  // it unless production preflight mirrors the dependency's backward scan.
  final falseEocdOffset = source.length + 4;
  _writeUint32LittleEndian(
    bytes,
    falseEocdOffset,
    ZipDirectory.eocdLocatorSignature,
  );
  _writeUint16LittleEndian(
    bytes,
    falseEocdOffset + 8,
    originalDirectory.fileHeaders.length,
  );
  _writeUint16LittleEndian(
    bytes,
    falseEocdOffset + 10,
    originalDirectory.fileHeaders.length,
  );
  _writeUint32LittleEndian(
    bytes,
    falseEocdOffset + 12,
    originalDirectory.centralDirectorySize,
  );
  _writeUint32LittleEndian(
    bytes,
    falseEocdOffset + 16,
    originalDirectory.centralDirectoryOffset,
  );
  return bytes;
}

Uint8List _withLocalAndCentralCrc(
  Uint8List source,
  String filename,
  int value,
) {
  final bytes = Uint8List.fromList(source);
  final directory = ZipDirectory.read(InputStream(bytes));
  final header = directory.fileHeaders.singleWhere(
    (candidate) => candidate.filename == filename,
  );
  _writeUint32LittleEndian(bytes, header.localHeaderOffset! + 14, value);
  _writeUint32LittleEndian(
    bytes,
    _centralHeaderOffset(bytes, filename) + 16,
    value,
  );
  return bytes;
}

Uint8List _officeZipWithCompressedEmptyDirectory() {
  const document =
      '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>标题</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>';
  final documentBytes = _utf8Bytes(document);
  final rawDirectory = Deflate(const <int>[]).getBytes();
  final archive = Archive()
    ..addFile(
      ArchiveFile('word/document.xml', documentBytes.length, documentBytes),
    )
    ..addFile(
      ArchiveFile(
          'empty/',
          rawDirectory.length,
          InputStream(rawDirectory),
          ArchiveFile.DEFLATE,
        )
        ..size = 0
        ..crc32 = 0
        ..isFile = false,
    );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Uint8List _officeZipWithEntryCount(int count) {
  const document =
      '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>标题</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>';
  final archive = Archive();
  final documentBytes = _utf8Bytes(document);
  archive.addFile(
    ArchiveFile('word/document.xml', documentBytes.length, documentBytes),
  );
  for (var index = 1; index < count; index += 1) {
    archive.addFile(
      ArchiveFile('custom/filler-$index', 0, Uint8List(0))..compress = false,
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Uint8List _officeZipWithReusedLargeDeflateStream() {
  const document =
      '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>标题</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>';
  const emptyBlockCount = 4096;
  const aliasCount = 12;
  final rawDirectory = Uint8List(emptyBlockCount * 5);
  for (var index = 0; index < emptyBlockCount; index += 1) {
    final offset = index * 5;
    rawDirectory[offset] = index == emptyBlockCount - 1 ? 0x01 : 0x00;
    rawDirectory[offset + 3] = 0xff;
    rawDirectory[offset + 4] = 0xff;
  }

  final documentBytes = _utf8Bytes(document);
  final archive = Archive()
    ..addFile(
      ArchiveFile('word/document.xml', documentBytes.length, documentBytes),
    )
    ..addFile(
      ArchiveFile(
          'shared-large-empty/',
          rawDirectory.length,
          InputStream(rawDirectory),
          ArchiveFile.DEFLATE,
        )
        ..size = 0
        ..crc32 = 0
        ..isFile = false,
    );
  for (var index = 0; index < aliasCount; index += 1) {
    archive.addFile(
      ArchiveFile('alias-$index/', 0, Uint8List(0))
        ..compress = false
        ..isFile = false,
    );
  }

  final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
  final directory = ZipDirectory.read(InputStream(bytes));
  final shared = directory.fileHeaders.singleWhere(
    (header) => header.filename == 'shared-large-empty/',
  );
  for (var index = 0; index < aliasCount; index += 1) {
    final offset = _centralHeaderOffset(bytes, 'alias-$index/');
    _writeUint16LittleEndian(bytes, offset + 8, shared.generalPurposeBitFlag);
    _writeUint16LittleEndian(bytes, offset + 10, shared.compressionMethod);
    _writeUint32LittleEndian(bytes, offset + 16, shared.crc32!);
    _writeUint32LittleEndian(bytes, offset + 20, shared.compressedSize!);
    _writeUint32LittleEndian(bytes, offset + 24, shared.uncompressedSize!);
    _writeUint32LittleEndian(bytes, offset + 42, shared.localHeaderOffset!);
  }
  return bytes;
}

Uint8List _withUnixSymlinkType(Uint8List source, String filename) {
  final bytes = Uint8List.fromList(source);
  final offset = _centralHeaderOffset(bytes, filename);
  bytes[offset + 5] = 3;
  _writeUint32LittleEndian(bytes, offset + 38, 0xA000 << 16);
  return bytes;
}

int _centralHeaderOffset(Uint8List bytes, String filename) {
  final directory = ZipDirectory.read(InputStream(bytes));
  var offset = directory.centralDirectoryOffset;
  final end = offset + directory.centralDirectorySize;
  while (offset + 46 <= end) {
    if (_readUint32LittleEndian(bytes, offset) != ZipFileHeader.SIGNATURE) {
      break;
    }
    final filenameLength = _readUint16LittleEndian(bytes, offset + 28);
    final extraLength = _readUint16LittleEndian(bytes, offset + 30);
    final commentLength = _readUint16LittleEndian(bytes, offset + 32);
    final entryName = utf8.decode(
      bytes.sublist(offset + 46, offset + 46 + filenameLength),
    );
    if (entryName == filename) return offset;
    offset += 46 + filenameLength + extraLength + commentLength;
  }
  throw StateError('TEST-ONLY ZIP entry not found: $filename');
}

Uint8List _withCentralUint32(
  Uint8List source,
  String filename,
  int fieldOffset,
  int value,
) {
  final bytes = Uint8List.fromList(source);
  _writeUint32LittleEndian(
    bytes,
    _centralHeaderOffset(bytes, filename) + fieldOffset,
    value,
  );
  return bytes;
}

void _corruptFirstPayloadByte(Uint8List bytes, String filename) {
  final directory = ZipDirectory.read(InputStream(bytes));
  final header = directory.fileHeaders.singleWhere(
    (candidate) => candidate.filename == filename,
  );
  final localOffset = header.localHeaderOffset!;
  final filenameLength = _readUint16LittleEndian(bytes, localOffset + 26);
  final extraLength = _readUint16LittleEndian(bytes, localOffset + 28);
  final payloadOffset = localOffset + 30 + filenameLength + extraLength;
  bytes[payloadOffset] ^= 0xff;
}

Uint8List _utf16Bytes(String value, {required bool littleEndian}) {
  final bytes = <int>[
    if (littleEndian) ...<int>[0xFF, 0xFE] else ...<int>[0xFE, 0xFF],
  ];
  for (final unit in value.codeUnits) {
    if (littleEndian) {
      bytes
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    } else {
      bytes
        ..add(unit >> 8)
        ..add(unit & 0xFF);
    }
  }
  return Uint8List.fromList(bytes);
}

Matcher _failsWith(TabularParseFailureCode code) =>
    isA<TabularParseException>().having((error) => error.code, 'code', code);

void main() {
  const parser = TabularImportParser();

  test('CSV 状态机保留引号换行、双引号、空尾字段及密码原值', () {
    const source =
        'platform,password,notes,empty\r\n'
        'Fake Service,"  fake,pass\nline ""quoted""  ",safe note,\r\n';

    final document = parser.parse(_utf8Bytes(source));

    expect(document.encoding, TabularSourceEncoding.utf8);
    expect(document.delimiter, ',');
    expect(document.headers, <String>[
      'platform',
      'password',
      'notes',
      'empty',
    ]);
    expect(document.rows, hasLength(1));
    expect(document.rows.single.originalRowNumber, 2);
    expect(document.rows.single.values, <String>[
      'Fake Service',
      '  fake,pass\nline "quoted"  ',
      'safe note',
      '',
    ]);
  });

  test('支持 UTF-8 BOM、UTF-16 LE/BE BOM 与 Tab/分号/逗号', () {
    final utf8Bom = parser.parse(
      Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('name\tpassword\r\nFake\tvalue'),
      ]),
    );
    final utf16Le = parser.parse(
      _utf16Bytes('名称;密码\r\n虚构服务;虚构值', littleEndian: true),
    );
    final utf16Be = parser.parse(
      _utf16Bytes('タイトル,password\n架空🙂,value', littleEndian: false),
    );

    expect(utf8Bom.encoding, TabularSourceEncoding.utf8Bom);
    expect(utf8Bom.delimiter, '\t');
    expect(utf8Bom.rows.single.values, <String>['Fake', 'value']);
    expect(utf16Le.encoding, TabularSourceEncoding.utf16LeBom);
    expect(utf16Le.delimiter, ';');
    expect(utf16Le.rows.single.values, <String>['虚构服务', '虚构值']);
    expect(utf16Be.encoding, TabularSourceEncoding.utf16BeBom);
    expect(utf16Be.delimiter, ',');
    expect(utf16Be.rows.single.values.first, '架空🙂');
  });

  test('读取 XLSX 首个工作表和 DOCX 首个表格', () {
    final xlsx = _officeZip(<String, String>{
      'xl/workbook.xml':
          '<workbook xmlns:r="urn:r"><sheets><sheet r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':
          '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml':
          '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>平台名称</t></is></c><c r="B1" t="inlineStr"><is><t>密码</t></is></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>Fake</t></is></c><c r="B2" t="inlineStr"><is><t>fake-pass</t></is></c></row></sheetData></worksheet>',
    });
    final docx = _officeZip(<String, String>{
      'word/document.xml':
          '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>平台名称</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>备注</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Fake</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>safe note</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>',
    });

    final xlsxDocument = parser.parse(xlsx);
    final docxDocument = parser.parse(docx);

    expect(xlsxDocument.encoding, TabularSourceEncoding.xlsx);
    expect(xlsxDocument.headers, <String>['平台名称', '密码']);
    expect(xlsxDocument.rows.single.values, <String>['Fake', 'fake-pass']);
    expect(docxDocument.encoding, TabularSourceEncoding.docx);
    expect(docxDocument.headers, <String>['平台名称', '备注']);
    expect(docxDocument.rows.single.values, <String>['Fake', 'safe note']);
  });

  test('Office 有界解压兼容 STORE 与带回引用的 DEFLATE', () {
    const prefix =
        '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>平台名称</w:t></w:r></w:p></w:tc></w:tr>';
    const suffix = '</w:tbl></w:body></w:document>';
    final stored = _officeZip(<String, String>{
      'word/document.xml':
          '$prefix<w:tr><w:tc><w:p><w:r><w:t>STORE</w:t></w:r></w:p></w:tc></w:tr>$suffix',
    }, compress: false);
    final repeated = List<String>.filled(4096, 'A').join();
    final deflated = _officeZip(<String, String>{
      'word/document.xml':
          '$prefix<w:tr><w:tc><w:p><w:r><w:t>$repeated</w:t></w:r></w:p></w:tc></w:tr>$suffix',
    });

    expect(parser.parse(stored).rows.single.values, <String>['STORE']);
    expect(parser.parse(deflated).rows.single.values.single, repeated);
  });

  test('Office 有界解压兼容合法的 DEFLATE 空目录', () {
    final source = _officeZipWithCompressedEmptyDirectory();
    final directory = ZipDirectory.read(InputStream(source));
    final emptyDirectory = directory.fileHeaders.singleWhere(
      (header) => header.filename == 'empty/',
    );

    expect(emptyDirectory.compressionMethod, ArchiveFile.DEFLATE);
    expect(emptyDirectory.uncompressedSize, 0);
    expect(emptyDirectory.compressedSize, greaterThan(0));
    expect(parser.parse(source).headers, <String>['标题']);
  });

  test('Office 在解析中央目录前拒绝超过 200 个条目', () {
    final source = _officeZipWithEntryCount(201);

    expect(
      () => decodeOfficeTabularDocument(
        source,
        maximumColumns: 64,
        maximumRows: 100,
        maximumFieldBytes: 64 * 1024,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The Office document contains too many files.',
        ),
      ),
    );
  });

  test('Office 不信任伪报为 1 的 EOCD 条目数并在第 201 项拒绝', () {
    final source = _withDeclaredEntryCount(_officeZipWithEntryCount(201), 1);

    expect(
      () => decodeOfficeTabularDocument(
        source,
        maximumColumns: 64,
        maximumRows: 100,
        maximumFieldBytes: 64 * 1024,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The Office document contains too many files.',
        ),
      ),
    );
  });

  test('Office 拒绝 comment 内会被 archive 先选中的伪 EOCD', () {
    final source = _withCommentContainingFalseEocd(
      _officeZip(<String, String>{
        'word/document.xml':
            '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>标题</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>',
      }),
    );
    final validEocdOffset = _endOfCentralDirectoryOffset(source);
    final dependencySelection = ZipDirectory.read(InputStream(source));

    expect(dependencySelection.filePosition, greaterThan(validEocdOffset));
    expect(dependencySelection.fileHeaders, hasLength(1));
    expect(
      () => decodeOfficeTabularDocument(
        source,
        maximumColumns: 64,
        maximumRows: 100,
        maximumFieldBytes: 64 * 1024,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The selected Office document is damaged.',
        ),
      ),
    );
  });

  test('Office 在解压前拒绝多个中央目录项复用同一大 DEFLATE 流', () {
    final source = _officeZipWithReusedLargeDeflateStream();
    final directory = ZipDirectory.read(InputStream(source));
    final shared = directory.fileHeaders.singleWhere(
      (header) => header.filename == 'shared-large-empty/',
    );
    final aliases = directory.fileHeaders.where(
      (header) => header.filename.startsWith('alias-'),
    );
    final totalCompressedBytes = directory.fileHeaders.fold<int>(
      0,
      (total, header) => total + header.compressedSize!,
    );

    expect(shared.compressionMethod, ArchiveFile.DEFLATE);
    expect(shared.uncompressedSize, 0);
    expect(shared.compressedSize, greaterThan(16 * 1024));
    expect(shared.file!.content, isEmpty);
    expect(aliases, hasLength(12));
    expect(
      aliases.every(
        (header) => header.localHeaderOffset == shared.localHeaderOffset,
      ),
      isTrue,
    );
    expect(totalCompressedBytes, greaterThan(source.length));
    expect(
      () => decodeOfficeTabularDocument(
        source,
        maximumColumns: 64,
        maximumRows: 100,
        maximumFieldBytes: 64 * 1024,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The selected Office document is damaged.',
        ),
      ),
    );
  });

  test('Office 在损坏载荷解压前拒绝单项与声明总量超限', () {
    const document =
        '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>标题</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>';
    final source = _officeZip(<String, String>{
      'word/document.xml': document,
      'custom/filler-a.xml': '<root>alpha</root>',
      'custom/filler-b.xml': '<root>beta</root>',
    });
    final perEntry = _withCentralUint32(
      source,
      'word/document.xml',
      24,
      20 * 1024 * 1024 + 1,
    );
    _corruptFirstPayloadByte(perEntry, 'word/document.xml');

    expect(
      () => decodeOfficeTabularDocument(
        perEntry,
        maximumColumns: 64,
        maximumRows: 100,
        maximumFieldBytes: 64 * 1024,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The Office document is too large to import.',
        ),
      ),
    );

    var total = Uint8List.fromList(source);
    for (final name in <String>[
      'word/document.xml',
      'custom/filler-a.xml',
      'custom/filler-b.xml',
    ]) {
      total = _withCentralUint32(total, name, 24, 14 * 1024 * 1024);
    }
    _corruptFirstPayloadByte(total, 'word/document.xml');
    expect(
      () => decodeOfficeTabularDocument(
        total,
        maximumColumns: 64,
        maximumRows: 100,
        maximumFieldBytes: 64 * 1024,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The Office document is too large to import.',
        ),
      ),
    );
  });

  test('Office 固定容量与 CRC 校验拒绝伪造声明且同步后台口径一致', () async {
    final source = _officeZip(<String, String>{
      'word/document.xml':
          '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>标题</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>',
    });
    final declaredTooSmall = _withCentralUint32(
      source,
      'word/document.xml',
      24,
      1,
    );
    final headerOffset = _centralHeaderOffset(source, 'word/document.xml');
    final originalCrc = _readUint32LittleEndian(source, headerOffset + 16);
    final wrongCrc = _withLocalAndCentralCrc(
      source,
      'word/document.xml',
      originalCrc ^ 0x01000000,
    );

    for (final damaged in <Uint8List>[declaredTooSmall, wrongCrc]) {
      expect(
        () => parser.parse(damaged),
        throwsA(_failsWith(TabularParseFailureCode.invalidOfficeDocument)),
      );
    }
    await expectLater(
      parser.parseInBackground(declaredTooSmall).result,
      throwsA(_failsWith(TabularParseFailureCode.invalidOfficeDocument)),
    );
  });

  test('Office 拒绝 Unix 符号链接条目', () {
    final source = _officeZip(<String, String>{
      'word/document.xml':
          '<w:document xmlns:w="urn:w"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>标题</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>',
      'custom/link': 'word/document.xml',
    });
    final damaged = _withUnixSymlinkType(source, 'custom/link');

    expect(
      () => parser.parse(damaged),
      throwsA(_failsWith(TabularParseFailureCode.invalidOfficeDocument)),
    );
  });

  test('XLSX 稀疏尾部空单元格按空值补齐，同步与后台解析均保留全部行', () async {
    final xlsx = _officeZip(<String, String>{
      'xl/workbook.xml': '''
<workbook xmlns:r='urn:r'><sheets><sheet r:id='rId1'/></sheets></workbook>''',
      'xl/_rels/workbook.xml.rels': '''
<Relationships><Relationship Id='rId1' Target='worksheets/sheet1.xml'/></Relationships>''',
      'xl/worksheets/sheet1.xml': '''
<worksheet><dimension ref='A1:H3'/><sheetData>
<row r='1'><c r='A1' t='inlineStr'><is><t>账号关联标识</t></is></c><c r='B1' t='inlineStr'><is><t>平台名称</t></is></c><c r='C1' t='inlineStr'><is><t>登录账号</t></is></c><c r='D1' t='inlineStr'><is><t>手机号</t></is></c><c r='E1' t='inlineStr'><is><t>邮箱</t></is></c><c r='F1' t='inlineStr'><is><t>密码</t></is></c><c r='G1' t='inlineStr'><is><t>网址</t></is></c><c r='H1' t='inlineStr'><is><t>备注</t></is></c></row>
<row r='2'><c r='A2' t='inlineStr'><is><t>fake-key-a</t></is></c><c r='B2' t='inlineStr'><is><t>虚构平台甲</t></is></c><c r='C2' t='inlineStr'><is><t>fake-user-a</t></is></c><c r='D2' t='inlineStr'><is><t></t></is></c><c r='E2' t='inlineStr'><is><t>a@example.invalid</t></is></c><c r='F2' t='inlineStr'><is><t>TEST-ONLY-PASSWORD-A</t></is></c><c r='G2' t='inlineStr'><is><t>https://a.example.invalid</t></is></c><c r='H2' t='inlineStr'><is><t>虚构备注</t></is></c></row>
<row r='3'><c r='A3' t='inlineStr'><is><t>fake-key-b</t></is></c><c r='B3' t='inlineStr'><is><t>虚构平台乙</t></is></c><c r='C3' t='inlineStr'><is><t>fake-user-b</t></is></c><c r='D3' t='inlineStr'><is><t></t></is></c><c r='E3' t='inlineStr'><is><t>b@example.invalid</t></is></c><c r='F3' t='inlineStr'><is><t>TEST-ONLY-PASSWORD-B</t></is></c><c r='G3' t='inlineStr'><is><t>https://b.example.invalid</t></is></c></row>
</sheetData></worksheet>''',
    });

    final synchronous = parser.parse(xlsx);
    final background = await parser.parseInBackground(xlsx).result;
    for (final document in <TabularDocument>[synchronous, background]) {
      expect(document.rows, hasLength(2));
      expect(document.rows.every((row) => row.values.length == 8), isTrue);
      expect(document.rows.every((row) => row.isValid), isTrue);
      expect(document.rows.last.values.last, isEmpty);
      expect(
        document.issues.map((issue) => issue.code),
        isNot(contains('column_count_mismatch')),
      );
    }
  });

  test('无表头模式生成稳定列名并保留全部行', () {
    final document = parser.parse(
      _utf8Bytes('one;two\nthree;four'),
      options: const TabularParseOptions(hasHeader: false),
    );

    expect(document.hasHeader, isFalse);
    expect(document.headers, <String>['column_1', 'column_2']);
    expect(document.rows, hasLength(2));
    expect(
      document.issues.map((issue) => issue.code),
      contains('missing_header'),
    );
  });

  test('列数错误按行报告且不截断原始列', () {
    final document = parser.parse(_utf8Bytes('a,b\n1\n2,3,4'));

    expect(document.rows, hasLength(2));
    expect(document.rows.first.isValid, isFalse);
    expect(document.rows.first.values, <String>['1']);
    expect(document.rows.last.isValid, isFalse);
    expect(document.rows.last.values, <String>['2', '3', '4']);
    expect(
      document.issues.where((issue) => issue.code == 'column_count_mismatch'),
      hasLength(2),
    );
  });

  test('拒绝未知编码、损坏 BOM 编码、NUL 与不完整引号', () {
    expect(
      () => parser.parse(Uint8List.fromList(<int>[0xC3, 0x28])),
      throwsA(_failsWith(TabularParseFailureCode.unknownEncoding)),
    );
    expect(
      () =>
          parser.parse(Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, 0xC3, 0x28])),
      throwsA(_failsWith(TabularParseFailureCode.invalidEncoding)),
    );
    expect(
      () => parser.parse(Uint8List.fromList(<int>[0xFF, 0xFE, 0x61])),
      throwsA(_failsWith(TabularParseFailureCode.invalidEncoding)),
    );
    expect(
      () => parser.parse(_utf8Bytes('a,b\nx,\u0000')),
      throwsA(_failsWith(TabularParseFailureCode.unknownEncoding)),
    );
    expect(
      () => parser.parse(_utf8Bytes('a,b\n"unfinished,value')),
      throwsA(_failsWith(TabularParseFailureCode.invalidDelimitedText)),
    );
  });

  test('解析上限分别拒绝过大文件、过多行列及超长字段', () {
    expect(
      () => parser.parse(
        _utf8Bytes('a,b\n1,2'),
        options: const TabularParseOptions(
          limits: TabularParseLimits(maximumFileBytes: 3),
        ),
      ),
      throwsA(_failsWith(TabularParseFailureCode.fileTooLarge)),
    );
    expect(
      () => parser.parse(
        _utf8Bytes('a\n1\n2'),
        options: const TabularParseOptions(
          limits: TabularParseLimits(maximumDataRows: 1),
        ),
      ),
      throwsA(_failsWith(TabularParseFailureCode.tooManyRows)),
    );
    expect(
      () => parser.parse(
        _utf8Bytes('a,b,c\n1,2,3'),
        options: const TabularParseOptions(
          limits: TabularParseLimits(maximumColumns: 2),
        ),
      ),
      throwsA(_failsWith(TabularParseFailureCode.tooManyColumns)),
    );
    expect(
      () => parser.parse(
        _utf8Bytes('a\nabcd'),
        options: const TabularParseOptions(
          limits: TabularParseLimits(maximumFieldBytes: 3),
        ),
      ),
      throwsA(_failsWith(TabularParseFailureCode.fieldTooLarge)),
    );
  });

  test('仅接受三种分隔符且歧义时安全拒绝', () {
    expect(
      () => parser.parse(
        _utf8Bytes('a|b\n1|2'),
        options: const TabularParseOptions(delimiter: '|'),
      ),
      throwsA(_failsWith(TabularParseFailureCode.unsupportedDelimiter)),
    );
    expect(
      () => parser.parse(_utf8Bytes('a,b;c\n1,2;3')),
      throwsA(_failsWith(TabularParseFailureCode.invalidDelimitedText)),
    );
  });

  test('重复表头报告警告，中文英日文、Emoji 与非 BMP 原样保留', () {
    final document = parser.parse(_utf8Bytes('名称,名称,说明\n虚构服务,Fake,日本語🙂𠀀'));

    expect(
      document.issues.map((issue) => issue.code),
      contains('duplicate_header'),
    );
    expect(document.rows.single.values, <String>['虚构服务', 'Fake', '日本語🙂𠀀']);
  });

  test('HTML、脚本及公式字符串仅作为普通文本返回', () {
    const source =
        'kind,value\n'
        'html,"<img src=x onerror=alert(1)>"\n'
        'script,"<script>alert(1)</script>"\n'
        'formula,"=HYPERLINK(""https://example.invalid"",""fake"")"';
    final document = parser.parse(_utf8Bytes(source));

    expect(document.rows[0].values[1], '<img src=x onerror=alert(1)>');
    expect(document.rows[1].values[1], '<script>alert(1)</script>');
    expect(
      document.rows[2].values[1],
      '=HYPERLINK("https://example.invalid","fake")',
    );
  });

  test('空文件安全拒绝', () {
    expect(
      () => parser.parse(Uint8List(0)),
      throwsA(_failsWith(TabularParseFailureCode.emptyFile)),
    );
  });

  test('后台解析在 isolate 完成并暴露完成状态', () async {
    final job = parser.parseInBackground(_utf8Bytes('a,b\n1,2'));

    final document = await job.result;

    expect(document.rows.single.values, <String>['1', '2']);
    expect(job.isCompleted, isTrue);
    expect(job.isCancelled, isFalse);
    expect(job.currentProgress.phase, TabularParseProgressPhase.completed);
    expect(job.currentProgress.fraction, 1);
  });

  test('后台解析 5000 行不越界且在宽松上限内完成', () async {
    final source = StringBuffer('name,password\n');
    for (var index = 0; index < 5000; index += 1) {
      source.writeln('Fake $index,fake-pass-$index');
    }
    final stopwatch = Stopwatch()..start();

    final job = parser.parseInBackground(_utf8Bytes(source.toString()));
    final document = await job.result;
    stopwatch.stop();

    expect(document.rows, hasLength(5000));
    expect(job.currentProgress.phase, TabularParseProgressPhase.completed);
    expect(stopwatch.elapsed.inSeconds, lessThan(30));
  });

  test('后台解析可取消且取消后不向会话写入暂存', () async {
    final controller = ImportSessionController();
    final job = parser.parseInBackground(_utf8Bytes('a,b\n1,2'));
    final cancelled = expectLater(
      job.result,
      throwsA(isA<TabularParseCancelledException>()),
    );

    expect(job.cancel(), isTrue);
    await cancelled;

    expect(job.isCancelled, isTrue);
    expect(job.currentProgress.phase, TabularParseProgressPhase.cancelled);
    expect(controller.snapshot.phase, ImportSessionPhase.idle);
    expect(controller.snapshot.document, isNull);
    expect(controller.snapshot.plan, isNull);
  });

  test('同步解析失败不会替换已加载会话或 revision', () {
    final controller = ImportSessionController();
    final before = controller.loadDocument(
      _utf8Bytes('name,password\nFake,fake-pass'),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 7,
    );

    expect(
      () => controller.loadDocument(
        _utf8Bytes('name,password\n"broken,fake-pass'),
        vaultScopeId: 'decoy-vault',
        expectedVaultRevision: 99,
      ),
      throwsA(_failsWith(TabularParseFailureCode.invalidDelimitedText)),
    );

    expect(controller.snapshot.document, same(before.document));
    expect(controller.snapshot.vaultScopeId, 'real-vault');
    expect(controller.snapshot.expectedVaultRevision, 7);
    expect(controller.snapshot.plan, isNull);
  });
}
