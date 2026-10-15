import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

enum OfficeTabularKind { xlsx, docx }

final class OfficeTabularDocument {
  OfficeTabularDocument({required this.kind, required List<List<String>> rows})
    : rows = List<List<String>>.unmodifiable(
        rows.map((row) => List<String>.unmodifiable(row)),
      );

  final OfficeTabularKind kind;
  final List<List<String>> rows;
}

OfficeTabularDocument? decodeOfficeTabularDocument(
  Uint8List bytes, {
  required int maximumColumns,
  required int maximumRows,
  required int maximumFieldBytes,
}) {
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      (bytes[2] != 0x03 && bytes[2] != 0x05 && bytes[2] != 0x07)) {
    return null;
  }

  final archive = _decodeBoundedOfficeArchive(bytes);

  if (archive.findFile('xl/workbook.xml') != null) {
    return OfficeTabularDocument(
      kind: OfficeTabularKind.xlsx,
      rows: _readXlsx(
        archive,
        maximumColumns: maximumColumns,
        maximumRows: maximumRows,
        maximumFieldBytes: maximumFieldBytes,
      ),
    );
  }
  if (archive.findFile('word/document.xml') != null) {
    return OfficeTabularDocument(
      kind: OfficeTabularKind.docx,
      rows: _readDocx(
        archive,
        maximumColumns: maximumColumns,
        maximumRows: maximumRows,
        maximumFieldBytes: maximumFieldBytes,
      ),
    );
  }
  throw const FormatException(
    'Only XLSX workbooks and DOCX documents with a table are supported.',
  );
}

const _maximumOfficeEntries = 200;
const _maximumOfficeEntryBytes = 20 * 1024 * 1024;
const _maximumOfficeExpandedBytes = 40 * 1024 * 1024;

Archive _decodeBoundedOfficeArchive(Uint8List bytes) {
  try {
    return _decodeBoundedOfficeArchiveUnchecked(bytes);
  } on _OfficeArchiveTooManyFiles {
    throw const FormatException('The Office document contains too many files.');
  } on _OfficeArchiveTooLarge {
    throw const FormatException('The Office document is too large to import.');
  } on Object {
    throw const FormatException('The selected Office document is damaged.');
  }
}

Archive _decodeBoundedOfficeArchiveUnchecked(Uint8List bytes) {
  final preflight = _preflightOfficeCentralDirectory(bytes);
  final directory = ZipDirectory.read(InputStream(bytes));
  final headers = directory.fileHeaders;
  if (directory.numberOfThisDisk != 0 ||
      directory.diskWithTheStartOfTheCentralDirectory != 0 ||
      directory.totalCentralDirectoryEntriesOnThisDisk != headers.length ||
      directory.totalCentralDirectoryEntries != headers.length ||
      preflight.entryCount != headers.length) {
    throw const _OfficeArchiveDamaged();
  }

  final entries = <_BoundedOfficeEntry>[];
  final names = <String>{};
  var compressedBytes = 0;
  var expandedBytes = 0;
  for (final header in headers) {
    if (header.diskNumberStart != 0) {
      throw const _OfficeArchiveDamaged();
    }
    final local = header.file;
    final compressedSize = header.compressedSize;
    final uncompressedSize = header.uncompressedSize;
    final expectedCrc32 = header.crc32;
    if (local == null ||
        compressedSize == null ||
        uncompressedSize == null ||
        expectedCrc32 == null ||
        compressedSize < 0 ||
        uncompressedSize < 0 ||
        local.flags != header.generalPurposeBitFlag ||
        local.compressionMethod != header.compressionMethod ||
        local.compressedSize != compressedSize ||
        local.uncompressedSize != uncompressedSize ||
        local.crc32 != expectedCrc32) {
      throw const _OfficeArchiveDamaged();
    }

    final flags = header.generalPurposeBitFlag;
    final compressionMethod = header.compressionMethod;
    if ((flags & 0x01) != 0 ||
        (flags & 0x40) != 0 ||
        (compressionMethod != ArchiveFile.STORE &&
            compressionMethod != ArchiveFile.DEFLATE)) {
      throw const _OfficeArchiveDamaged();
    }
    compressedBytes += compressedSize;
    if (compressedBytes > bytes.length) {
      throw const _OfficeArchiveDamaged();
    }

    final name = header.filename.replaceAll('\\', '/');
    if (name.isEmpty || name.contains('\u0000') || !names.add(name)) {
      throw const _OfficeArchiveDamaged();
    }
    final madeByUnix = header.versionMadeBy >> 8 == 3;
    final fileType = ((header.externalFileAttributes ?? 0) >> 16) & 0xF000;
    final isDirectory =
        name.endsWith('/') || (madeByUnix && fileType == 0x4000);
    final isRegularFile =
        !isDirectory && (!madeByUnix || fileType == 0 || fileType == 0x8000);
    if (!isDirectory && !isRegularFile) {
      throw const _OfficeArchiveDamaged();
    }
    if (isDirectory) {
      if (uncompressedSize != 0) {
        throw const _OfficeArchiveDamaged();
      }
    } else {
      expandedBytes += uncompressedSize;
      if (uncompressedSize > _maximumOfficeEntryBytes ||
          expandedBytes > _maximumOfficeExpandedBytes) {
        throw const _OfficeArchiveTooLarge();
      }
    }
    if (compressionMethod == ArchiveFile.STORE &&
        compressedSize != uncompressedSize) {
      throw const _OfficeArchiveDamaged();
    }
    final raw = local.rawContent?.toUint8List();
    if (raw == null || raw.length != compressedSize) {
      throw const _OfficeArchiveDamaged();
    }
    entries.add(
      _BoundedOfficeEntry(
        name: name,
        isDirectory: isDirectory,
        uncompressedSize: uncompressedSize,
        crc32: expectedCrc32,
        compressionMethod: compressionMethod,
        rawBytes: raw,
      ),
    );
  }

  final verified = Archive();
  for (final entry in entries) {
    final output = _FixedCapacityOutput(entry.uncompressedSize);
    final compressed = ArchiveFile(
      entry.name,
      entry.uncompressedSize,
      InputStream(entry.rawBytes),
      entry.compressionMethod,
    );
    final compressedInput = compressed.rawContent;
    compressed.decompress(output);
    final content = output.bytes;
    if (content.length != entry.uncompressedSize ||
        getCrc32(content) != entry.crc32 ||
        (entry.compressionMethod == ArchiveFile.DEFLATE &&
            (compressedInput == null || !compressedInput.isEOS))) {
      throw const _OfficeArchiveDamaged();
    }
    if (!entry.isDirectory) {
      verified.addFile(ArchiveFile(entry.name, content.length, content));
    }
  }
  return verified;
}

_OfficeCentralDirectoryPreflight _preflightOfficeCentralDirectory(
  Uint8List bytes,
) {
  const eocdLength = 22;
  // archive 3.6.1 selects the first raw EOCD signature encountered while
  // scanning backward from bytes.length - 5. Mirror that exact selection so
  // a later signature embedded in the ZIP comment cannot make ZipDirectory
  // parse a different, unbounded central directory after this preflight.
  for (var offset = bytes.length - 5; offset >= 0; offset -= 1) {
    if (_officeUint32(bytes, offset) != ZipDirectory.eocdLocatorSignature) {
      continue;
    }
    if (offset + eocdLength > bytes.length) {
      throw const _OfficeArchiveDamaged();
    }
    final commentLength = _officeUint16(bytes, offset + 20);
    if (offset + eocdLength + commentLength != bytes.length) {
      throw const _OfficeArchiveDamaged();
    }
    final diskNumber = _officeUint16(bytes, offset + 4);
    final centralDirectoryDisk = _officeUint16(bytes, offset + 6);
    final entriesOnDisk = _officeUint16(bytes, offset + 8);
    final totalEntries = _officeUint16(bytes, offset + 10);
    final eocdCentralSize = _officeUint32(bytes, offset + 12);
    final eocdCentralOffset = _officeUint32(bytes, offset + 16);
    final needsZip64 =
        diskNumber == 0xffff ||
        centralDirectoryDisk == 0xffff ||
        entriesOnDisk == 0xffff ||
        totalEntries == 0xffff ||
        eocdCentralSize == 0xffffffff ||
        eocdCentralOffset == 0xffffffff;

    late final int declaredEntries;
    late final int centralSize;
    late final int centralOffset;
    late final int expectedCentralEnd;
    if (!needsZip64) {
      if (diskNumber != 0 ||
          centralDirectoryDisk != 0 ||
          entriesOnDisk != totalEntries) {
        throw const _OfficeArchiveDamaged();
      }
      declaredEntries = totalEntries;
      centralSize = eocdCentralSize;
      centralOffset = eocdCentralOffset;
      expectedCentralEnd = offset;
    } else {
      final locatorOffset = offset - ZipDirectory.zip64EocdLocatorSize;
      if (locatorOffset < 0 ||
          _officeUint32(bytes, locatorOffset) !=
              ZipDirectory.zip64EocdLocatorSignature ||
          _officeUint32(bytes, locatorOffset + 4) != 0 ||
          _officeUint32(bytes, locatorOffset + 16) != 1) {
        throw const _OfficeArchiveDamaged();
      }
      final zip64Offset = _officeUint64(bytes, locatorOffset + 8);
      if (zip64Offset < 0 ||
          zip64Offset + ZipDirectory.zip64EocdSize > locatorOffset ||
          _officeUint32(bytes, zip64Offset) !=
              ZipDirectory.zip64EocdSignature) {
        throw const _OfficeArchiveDamaged();
      }
      final zip64RecordSize = _officeUint64(bytes, zip64Offset + 4);
      if (zip64RecordSize < 44 ||
          zip64Offset + 12 + zip64RecordSize != locatorOffset ||
          _officeUint32(bytes, zip64Offset + 16) != 0 ||
          _officeUint32(bytes, zip64Offset + 20) != 0) {
        throw const _OfficeArchiveDamaged();
      }
      final zip64EntriesOnDisk = _officeUint64(bytes, zip64Offset + 24);
      declaredEntries = _officeUint64(bytes, zip64Offset + 32);
      centralSize = _officeUint64(bytes, zip64Offset + 40);
      centralOffset = _officeUint64(bytes, zip64Offset + 48);
      expectedCentralEnd = zip64Offset;
      if (zip64EntriesOnDisk != declaredEntries ||
          (diskNumber != 0xffff && diskNumber != 0) ||
          (centralDirectoryDisk != 0xffff && centralDirectoryDisk != 0) ||
          (entriesOnDisk != 0xffff && entriesOnDisk != declaredEntries) ||
          (totalEntries != 0xffff && totalEntries != declaredEntries) ||
          (eocdCentralSize != 0xffffffff && eocdCentralSize != centralSize) ||
          (eocdCentralOffset != 0xffffffff &&
              eocdCentralOffset != centralOffset)) {
        throw const _OfficeArchiveDamaged();
      }
    }

    if (declaredEntries > _maximumOfficeEntries) {
      throw const _OfficeArchiveTooManyFiles();
    }
    final centralEnd = centralOffset + centralSize;
    if (centralOffset < 0 ||
        centralSize < 0 ||
        centralEnd < centralOffset ||
        centralEnd != expectedCentralEnd) {
      throw const _OfficeArchiveDamaged();
    }

    var cursor = centralOffset;
    var actualEntries = 0;
    while (cursor < centralEnd) {
      if (cursor + 46 > centralEnd ||
          _officeUint32(bytes, cursor) != ZipFileHeader.SIGNATURE) {
        throw const _OfficeArchiveDamaged();
      }
      actualEntries += 1;
      if (actualEntries > _maximumOfficeEntries) {
        throw const _OfficeArchiveTooManyFiles();
      }
      final filenameLength = _officeUint16(bytes, cursor + 28);
      final extraLength = _officeUint16(bytes, cursor + 30);
      final commentLength = _officeUint16(bytes, cursor + 32);
      final next = cursor + 46 + filenameLength + extraLength + commentLength;
      if (next <= cursor || next > centralEnd) {
        throw const _OfficeArchiveDamaged();
      }
      cursor = next;
    }
    if (cursor != centralEnd || actualEntries != declaredEntries) {
      throw const _OfficeArchiveDamaged();
    }
    return _OfficeCentralDirectoryPreflight(entryCount: actualEntries);
  }
  throw const _OfficeArchiveDamaged();
}

int _officeUint16(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 2 > bytes.length) {
    throw const _OfficeArchiveDamaged();
  }
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _officeUint32(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw const _OfficeArchiveDamaged();
  }
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

int _officeUint64(Uint8List bytes, int offset) {
  final low = _officeUint32(bytes, offset);
  final high = _officeUint32(bytes, offset + 4);
  return low | (high << 32);
}

final class _OfficeCentralDirectoryPreflight {
  const _OfficeCentralDirectoryPreflight({required this.entryCount});

  final int entryCount;
}

final class _BoundedOfficeEntry {
  const _BoundedOfficeEntry({
    required this.name,
    required this.isDirectory,
    required this.uncompressedSize,
    required this.crc32,
    required this.compressionMethod,
    required this.rawBytes,
  });

  final String name;
  final bool isDirectory;
  final int uncompressedSize;
  final int crc32;
  final int compressionMethod;
  final Uint8List rawBytes;
}

final class _FixedCapacityOutput extends OutputStreamBase {
  _FixedCapacityOutput(int capacity) : _buffer = Uint8List(capacity);

  final Uint8List _buffer;

  @override
  int length = 0;

  Uint8List get bytes => Uint8List.sublistView(_buffer, 0, length);

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _reserve(1);
    _buffer[length] = value & 0xff;
    length += 1;
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    final count = len ?? bytes.length;
    if (count < 0 || count > bytes.length) {
      throw const _OfficeArchiveDamaged();
    }
    _reserve(count);
    _buffer.setRange(length, length + count, bytes);
    length += count;
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    final source = stream.toUint8List();
    writeBytes(source);
  }

  @override
  void writeUint16(int value) {
    writeByte(value);
    writeByte(value >> 8);
  }

  @override
  void writeUint32(int value) {
    writeUint16(value);
    writeUint16(value >> 16);
  }

  @override
  void writeUint64(int value) {
    writeUint32(value);
    writeUint32(value >> 32);
  }

  List<int> subset(int start, [int? end]) {
    final resolvedStart = start < 0 ? length + start : start;
    final resolvedEnd = end == null
        ? length
        : end < 0
        ? length + end
        : end;
    if (resolvedStart < 0 ||
        resolvedEnd < resolvedStart ||
        resolvedEnd > length) {
      throw const _OfficeArchiveDamaged();
    }
    return Uint8List.sublistView(_buffer, resolvedStart, resolvedEnd);
  }

  void _reserve(int count) {
    if (count < 0 || length + count > _buffer.length) {
      throw const _OfficeArchiveDamaged();
    }
  }
}

final class _OfficeArchiveDamaged implements Exception {
  const _OfficeArchiveDamaged();
}

final class _OfficeArchiveTooManyFiles implements Exception {
  const _OfficeArchiveTooManyFiles();
}

final class _OfficeArchiveTooLarge implements Exception {
  const _OfficeArchiveTooLarge();
}

List<List<String>> _readXlsx(
  Archive archive, {
  required int maximumColumns,
  required int maximumRows,
  required int maximumFieldBytes,
}) {
  final workbook = _xmlFile(archive, 'xl/workbook.xml');
  final firstSheet = workbook.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'sheet')
      .firstOrNull;
  if (firstSheet == null) {
    throw const FormatException('The XLSX workbook does not contain a sheet.');
  }
  final relationId = firstSheet.attributes
      .where((attribute) => attribute.name.local == 'id')
      .map((attribute) => attribute.value)
      .firstOrNull;
  final relationships = _xmlFile(archive, 'xl/_rels/workbook.xml.rels');
  final relation = relationships.descendants
      .whereType<XmlElement>()
      .where(
        (element) =>
            element.name.local == 'Relationship' &&
            element.getAttribute('Id') == relationId,
      )
      .firstOrNull;
  final target = relation?.getAttribute('Target');
  if (target == null || target.isEmpty || target.contains('..')) {
    throw const FormatException('The XLSX sheet reference is invalid.');
  }
  final sheetPath = target.startsWith('/')
      ? target.substring(1)
      : target.startsWith('xl/')
      ? target
      : 'xl/$target';
  final sheet = _xmlFile(archive, sheetPath.replaceAll('\\', '/'));
  final sharedStrings = _readSharedStrings(archive);
  final output = <List<String>>[];
  for (final row in sheet.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'row',
  )) {
    final values = <String>[];
    for (final cell in row.childElements.where(
      (element) => element.name.local == 'c',
    )) {
      final column = _xlsxColumnIndex(cell.getAttribute('r'));
      if (column >= maximumColumns) {
        throw const FormatException('The Office table has too many columns.');
      }
      while (values.length <= column) {
        values.add('');
      }
      final type = cell.getAttribute('t');
      final rawValue = _firstChildText(cell, 'v');
      final value = switch (type) {
        'inlineStr' =>
          cell.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 't')
              .map((element) => element.innerText)
              .join(),
        's' => _sharedStringValue(rawValue, sharedStrings),
        _ => rawValue,
      };
      _checkField(value, maximumFieldBytes);
      values[column] = value;
    }
    output.add(values);
    if (output.length > maximumRows + 1) {
      throw const FormatException('The Office table has too many rows.');
    }
  }
  if (output.isEmpty) {
    throw const FormatException('The XLSX sheet is empty.');
  }
  return output;
}

List<String> _readSharedStrings(Archive archive) {
  if (archive.findFile('xl/sharedStrings.xml') == null) return const <String>[];
  final document = _xmlFile(archive, 'xl/sharedStrings.xml');
  return document.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'si')
      .map(
        (element) => element.descendants
            .whereType<XmlElement>()
            .where((child) => child.name.local == 't')
            .map((child) => child.innerText)
            .join(),
      )
      .toList(growable: false);
}

String _sharedStringValue(String raw, List<String> sharedStrings) {
  final index = int.tryParse(raw);
  if (index == null || index < 0 || index >= sharedStrings.length) {
    throw const FormatException('The XLSX shared string index is invalid.');
  }
  return sharedStrings[index];
}

int _xlsxColumnIndex(String? reference) {
  if (reference == null || reference.isEmpty) return 0;
  var value = 0;
  var found = false;
  for (final code in reference.codeUnits) {
    final upper = code >= 0x61 && code <= 0x7A ? code - 0x20 : code;
    if (upper < 0x41 || upper > 0x5A) break;
    found = true;
    value = value * 26 + upper - 0x40;
  }
  return found ? value - 1 : 0;
}

List<List<String>> _readDocx(
  Archive archive, {
  required int maximumColumns,
  required int maximumRows,
  required int maximumFieldBytes,
}) {
  final document = _xmlFile(archive, 'word/document.xml');
  final table = document.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'tbl')
      .firstOrNull;
  if (table == null) {
    throw const FormatException('The DOCX document does not contain a table.');
  }
  final output = <List<String>>[];
  for (final row in table.childElements.where(
    (element) => element.name.local == 'tr',
  )) {
    final values = row.childElements
        .where((element) => element.name.local == 'tc')
        .map((cell) {
          final paragraphs = cell.childElements
              .where((element) => element.name.local == 'p')
              .map(
                (paragraph) => paragraph.descendants
                    .whereType<XmlElement>()
                    .where((element) => element.name.local == 't')
                    .map((element) => element.innerText)
                    .join(),
              )
              .toList(growable: false);
          final value = paragraphs.join('\n');
          _checkField(value, maximumFieldBytes);
          return value;
        })
        .toList(growable: false);
    if (values.length > maximumColumns) {
      throw const FormatException('The Office table has too many columns.');
    }
    output.add(values);
    if (output.length > maximumRows + 1) {
      throw const FormatException('The Office table has too many rows.');
    }
  }
  if (output.isEmpty) {
    throw const FormatException('The DOCX table is empty.');
  }
  return output;
}

XmlDocument _xmlFile(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null || !file.isFile) {
    throw FormatException('The Office document is missing $name.');
  }
  final content = file.content;
  final bytes = switch (content) {
    Uint8List value => value,
    List<int> value => Uint8List.fromList(value),
    _ => throw FormatException('The Office document entry $name is invalid.'),
  };
  try {
    return XmlDocument.parse(utf8.decode(bytes, allowMalformed: false));
  } on Object {
    throw FormatException('The Office document entry $name is malformed.');
  }
}

String _firstChildText(XmlElement element, String localName) =>
    element.childElements
        .where((child) => child.name.local == localName)
        .map((child) => child.innerText)
        .firstOrNull ??
    '';

void _checkField(String value, int maximumFieldBytes) {
  if (utf8.encode(value).length > maximumFieldBytes) {
    throw const FormatException('An Office table field is too large.');
  }
}
