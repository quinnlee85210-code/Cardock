import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'import_models.dart';
import 'tabular_office_document.dart';

enum TabularParseFailureCode {
  fileTooLarge,
  emptyFile,
  unknownEncoding,
  invalidEncoding,
  invalidDelimitedText,
  unsupportedDelimiter,
  tooManyRows,
  tooManyColumns,
  fieldTooLarge,
  missingHeader,
  invalidOfficeDocument,
}

enum TabularParseProgressPhase { queued, parsing, completed, cancelled, failed }

final class TabularParseProgress {
  const TabularParseProgress({required this.phase, this.fraction});

  final TabularParseProgressPhase phase;
  final double? fraction;
}

final class TabularParseCancelledException implements Exception {
  const TabularParseCancelledException();

  @override
  String toString() => 'TabularParseCancelledException';
}

final class TabularParseException implements Exception {
  const TabularParseException(this.code, this.message, {this.offset});

  final TabularParseFailureCode code;
  final String message;
  final int? offset;

  @override
  String toString() => 'TabularParseException(${code.name}): $message';
}

final class TabularParseLimits {
  const TabularParseLimits({
    this.maximumFileBytes = 10 * 1024 * 1024,
    this.maximumDataRows = 5000,
    this.maximumColumns = 200,
    this.maximumFieldBytes = 64 * 1024,
  });

  final int maximumFileBytes;
  final int maximumDataRows;
  final int maximumColumns;
  final int maximumFieldBytes;
}

final class TabularParseOptions {
  const TabularParseOptions({
    this.limits = const TabularParseLimits(),
    this.delimiter,
    this.hasHeader = true,
  });

  final TabularParseLimits limits;
  final String? delimiter;
  final bool hasHeader;
}

final class TabularImportParser {
  const TabularImportParser();

  TabularParseJob parseInBackground(
    Uint8List bytes, {
    TabularParseOptions options = const TabularParseOptions(),
  }) => TabularParseJob._(Uint8List.fromList(bytes), options);

  TabularDocument parse(
    Uint8List bytes, {
    TabularParseOptions options = const TabularParseOptions(),
  }) {
    if (bytes.isEmpty) {
      throw const TabularParseException(
        TabularParseFailureCode.emptyFile,
        'The selected file is empty.',
      );
    }
    if (bytes.length > options.limits.maximumFileBytes) {
      throw const TabularParseException(
        TabularParseFailureCode.fileTooLarge,
        'The selected file exceeds the configured import limit.',
      );
    }

    OfficeTabularDocument? office;
    try {
      office = decodeOfficeTabularDocument(
        bytes,
        maximumColumns: options.limits.maximumColumns,
        maximumRows: options.limits.maximumDataRows,
        maximumFieldBytes: options.limits.maximumFieldBytes,
      );
    } on FormatException catch (error) {
      throw TabularParseException(
        TabularParseFailureCode.invalidOfficeDocument,
        error.message,
      );
    }

    late final TabularSourceEncoding sourceEncoding;
    late final String delimiter;
    late final List<_ParsedRecord> records;
    if (office != null) {
      sourceEncoding = office.kind == OfficeTabularKind.xlsx
          ? TabularSourceEncoding.xlsx
          : TabularSourceEncoding.docx;
      delimiter = '\t';
      records = <_ParsedRecord>[
        for (var index = 0; index < office.rows.length; index += 1)
          _ParsedRecord(
            values: office.rows[index],
            originalRowNumber: index + 1,
          ),
      ];
    } else {
      final decoded = _decode(bytes);
      _rejectIllegalControls(decoded.text);
      sourceEncoding = decoded.encoding;
      delimiter = options.delimiter ?? _detectDelimiter(decoded.text);
      if (!_supportedDelimiters.contains(delimiter)) {
        throw const TabularParseException(
          TabularParseFailureCode.unsupportedDelimiter,
          'Only comma, tab, and semicolon delimiters are supported.',
        );
      }
      records = _parseRecords(decoded.text, delimiter, options.limits);
    }
    if (records.isEmpty) {
      throw const TabularParseException(
        TabularParseFailureCode.emptyFile,
        'The selected file does not contain any records.',
      );
    }

    final documentIssues = <ImportIssue>[];
    late final List<String> headers;
    late List<_ParsedRecord> dataRecords;
    if (options.hasHeader) {
      headers = records.first.values;
      dataRecords = records.skip(1).toList(growable: false);
      if (office != null) {
        dataRecords = _padSparseOfficeRecords(dataRecords, headers.length);
      }
      if (headers.every((value) => value.trim().isEmpty)) {
        throw const TabularParseException(
          TabularParseFailureCode.missingHeader,
          'The selected file does not contain a usable header row.',
        );
      }
    } else {
      final maximumColumns = records
          .map((record) => record.values.length)
          .fold<int>(0, (current, value) => value > current ? value : current);
      headers = List<String>.generate(
        maximumColumns,
        (index) => 'column_${index + 1}',
        growable: false,
      );
      dataRecords = office == null
          ? records
          : _padSparseOfficeRecords(records, maximumColumns);
      documentIssues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'missing_header',
          message:
              'Generated column names are being used for a headerless file.',
        ),
      );
    }

    if (headers.length > options.limits.maximumColumns) {
      throw const TabularParseException(
        TabularParseFailureCode.tooManyColumns,
        'The selected file contains too many columns.',
      );
    }
    if (dataRecords.length > options.limits.maximumDataRows) {
      throw const TabularParseException(
        TabularParseFailureCode.tooManyRows,
        'The selected file contains too many data rows.',
      );
    }

    final duplicateHeaders = <String, int>{};
    for (var index = 0; index < headers.length; index += 1) {
      final normalized = headers[index].trim().toLowerCase();
      if (normalized.isEmpty) continue;
      final previous = duplicateHeaders[normalized];
      if (previous != null) {
        documentIssues.add(
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: 'duplicate_header',
            message: 'The file contains a duplicate header.',
            rowNumber: records.first.originalRowNumber,
            columnNumber: index + 1,
          ),
        );
      } else {
        duplicateHeaders[normalized] = index;
      }
    }

    final rows = <TabularRow>[];
    for (final record in dataRecords) {
      if (record.values.every((value) => value.isEmpty)) {
        documentIssues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'empty_row_skipped',
            message: 'An empty row was skipped.',
            rowNumber: record.originalRowNumber,
          ),
        );
        continue;
      }
      final rowIssues = <ImportIssue>[];
      if (record.values.length != headers.length) {
        final issue = ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'column_count_mismatch',
          message: 'The row has a different number of columns than the header.',
          rowNumber: record.originalRowNumber,
        );
        rowIssues.add(issue);
        documentIssues.add(issue);
      }
      rows.add(
        TabularRow(
          values: record.values,
          originalRowNumber: record.originalRowNumber,
          issues: rowIssues,
        ),
      );
    }

    return TabularDocument(
      headers: headers,
      rows: rows,
      encoding: sourceEncoding,
      delimiter: delimiter,
      hasHeader: options.hasHeader,
      originalByteLength: bytes.length,
      issues: documentIssues,
    );
  }

  _DecodedDocument _decode(Uint8List bytes) {
    if (_startsWith(bytes, const <int>[0xEF, 0xBB, 0xBF])) {
      return _DecodedDocument(
        text: _decodeUtf8(bytes.sublist(3), hasBom: true),
        encoding: TabularSourceEncoding.utf8Bom,
      );
    }
    if (_startsWith(bytes, const <int>[0xFF, 0xFE])) {
      return _DecodedDocument(
        text: _decodeUtf16(bytes.sublist(2), littleEndian: true),
        encoding: TabularSourceEncoding.utf16LeBom,
      );
    }
    if (_startsWith(bytes, const <int>[0xFE, 0xFF])) {
      return _DecodedDocument(
        text: _decodeUtf16(bytes.sublist(2), littleEndian: false),
        encoding: TabularSourceEncoding.utf16BeBom,
      );
    }
    return _DecodedDocument(
      text: _decodeUtf8(bytes, hasBom: false),
      encoding: TabularSourceEncoding.utf8,
    );
  }

  String _decodeUtf8(List<int> bytes, {required bool hasBom}) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw TabularParseException(
        hasBom
            ? TabularParseFailureCode.invalidEncoding
            : TabularParseFailureCode.unknownEncoding,
        hasBom
            ? 'The UTF-8 file is malformed.'
            : 'The file encoding is not recognized as UTF-8.',
      );
    }
  }

  String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    if (bytes.length.isOdd) {
      throw const TabularParseException(
        TabularParseFailureCode.invalidEncoding,
        'The UTF-16 file has an incomplete code unit.',
      );
    }
    final codeUnits = <int>[];
    for (var index = 0; index < bytes.length; index += 2) {
      final first = bytes[index];
      final second = bytes[index + 1];
      codeUnits.add(
        littleEndian ? first | (second << 8) : (first << 8) | second,
      );
    }
    for (var index = 0; index < codeUnits.length; index += 1) {
      final unit = codeUnits[index];
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (index + 1 >= codeUnits.length ||
            codeUnits[index + 1] < 0xDC00 ||
            codeUnits[index + 1] > 0xDFFF) {
          throw const TabularParseException(
            TabularParseFailureCode.invalidEncoding,
            'The UTF-16 file contains an invalid surrogate pair.',
          );
        }
        index += 1;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw const TabularParseException(
          TabularParseFailureCode.invalidEncoding,
          'The UTF-16 file contains an unexpected low surrogate.',
        );
      }
    }
    return String.fromCharCodes(codeUnits);
  }

  void _rejectIllegalControls(String text) {
    for (var index = 0; index < text.length; index += 1) {
      final unit = text.codeUnitAt(index);
      final illegal =
          unit == 0 ||
          (unit < 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) ||
          unit == 0x7F;
      if (illegal) {
        throw TabularParseException(
          TabularParseFailureCode.unknownEncoding,
          'The file contains NUL or unsupported control characters.',
          offset: index,
        );
      }
    }
  }

  String _detectDelimiter(String text) {
    final counts = <String, int>{
      for (final value in _supportedDelimiters) value: 0,
    };
    var inQuotes = false;
    for (var index = 0; index < text.length; index += 1) {
      final char = text[index];
      if (char == '"') {
        if (inQuotes && index + 1 < text.length && text[index + 1] == '"') {
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }
      if (!inQuotes && (char == '\r' || char == '\n')) break;
      if (!inQuotes && counts.containsKey(char)) {
        counts[char] = counts[char]! + 1;
      }
    }
    final maximum = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    if (maximum == 0) return ',';
    final winners = counts.entries
        .where((entry) => entry.value == maximum)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (winners.length != 1) {
      throw const TabularParseException(
        TabularParseFailureCode.invalidDelimitedText,
        'The delimiter cannot be determined reliably.',
      );
    }
    return winners.single;
  }

  List<_ParsedRecord> _parseRecords(
    String text,
    String delimiter,
    TabularParseLimits limits,
  ) {
    final records = <_ParsedRecord>[];
    final fields = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var justClosedQuote = false;
    var fieldStarted = false;
    var recordStarted = false;
    var physicalLine = 1;
    var recordStartLine = 1;
    var lastWasRecordTerminator = false;

    void finishField() {
      final value = field.toString();
      if (utf8.encode(value).length > limits.maximumFieldBytes) {
        throw const TabularParseException(
          TabularParseFailureCode.fieldTooLarge,
          'A field exceeds the configured import limit.',
        );
      }
      fields.add(value);
      field.clear();
      fieldStarted = false;
      justClosedQuote = false;
      if (fields.length > limits.maximumColumns) {
        throw const TabularParseException(
          TabularParseFailureCode.tooManyColumns,
          'A row contains too many columns.',
        );
      }
    }

    void finishRecord() {
      finishField();
      records.add(
        _ParsedRecord(
          values: List<String>.of(fields),
          originalRowNumber: recordStartLine,
        ),
      );
      fields.clear();
      recordStarted = false;
      lastWasRecordTerminator = true;
    }

    for (var index = 0; index < text.length; index += 1) {
      final char = text[index];
      if (inQuotes) {
        if (char == '"') {
          if (index + 1 < text.length && text[index + 1] == '"') {
            field.write('"');
            index += 1;
          } else {
            inQuotes = false;
            justClosedQuote = true;
          }
          continue;
        }
        if (char == '\r') {
          field.write('\r');
          if (index + 1 < text.length && text[index + 1] == '\n') {
            field.write('\n');
            index += 1;
          }
          physicalLine += 1;
          continue;
        }
        if (char == '\n') {
          field.write('\n');
          physicalLine += 1;
          continue;
        }
        field.write(char);
        continue;
      }

      if (justClosedQuote) {
        if (char == delimiter) {
          finishField();
          recordStarted = true;
          lastWasRecordTerminator = false;
          continue;
        }
        if (char == '\r' || char == '\n') {
          finishRecord();
          if (char == '\r' &&
              index + 1 < text.length &&
              text[index + 1] == '\n') {
            index += 1;
          }
          physicalLine += 1;
          recordStartLine = physicalLine;
          continue;
        }
        throw TabularParseException(
          TabularParseFailureCode.invalidDelimitedText,
          'Unexpected content appears after a closing quote.',
          offset: index,
        );
      }

      if (char == '"') {
        if (fieldStarted || field.length != 0) {
          throw TabularParseException(
            TabularParseFailureCode.invalidDelimitedText,
            'A quote appears inside an unquoted field.',
            offset: index,
          );
        }
        inQuotes = true;
        fieldStarted = true;
        recordStarted = true;
        lastWasRecordTerminator = false;
        continue;
      }
      if (char == delimiter) {
        finishField();
        recordStarted = true;
        lastWasRecordTerminator = false;
        continue;
      }
      if (char == '\r' || char == '\n') {
        finishRecord();
        if (char == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index += 1;
        }
        physicalLine += 1;
        recordStartLine = physicalLine;
        continue;
      }
      field.write(char);
      fieldStarted = true;
      recordStarted = true;
      lastWasRecordTerminator = false;
    }

    if (inQuotes) {
      throw const TabularParseException(
        TabularParseFailureCode.invalidDelimitedText,
        'The file ends inside a quoted field.',
      );
    }
    if (recordStarted || fields.isNotEmpty || !lastWasRecordTerminator) {
      finishRecord();
    }
    return records;
  }

  bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index += 1) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }
}

List<_ParsedRecord> _padSparseOfficeRecords(
  List<_ParsedRecord> records,
  int expectedColumns,
) => <_ParsedRecord>[
  for (final record in records)
    if (record.values.length >= expectedColumns)
      record
    else
      _ParsedRecord(
        values: <String>[
          ...record.values,
          ...List<String>.filled(
            expectedColumns - record.values.length,
            '',
            growable: false,
          ),
        ],
        originalRowNumber: record.originalRowNumber,
      ),
];

final class TabularParseJob {
  TabularParseJob._(Uint8List bytes, TabularParseOptions options) {
    result = _completer.future;
    unawaited(_start(bytes, options));
  }

  final Completer<TabularDocument> _completer = Completer<TabularDocument>();
  final StreamController<TabularParseProgress> _progressController =
      StreamController<TabularParseProgress>.broadcast(sync: true);
  late final Future<TabularDocument> result;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription<Object?>? _subscription;
  bool _cancelRequested = false;
  TabularParseProgress _currentProgress = const TabularParseProgress(
    phase: TabularParseProgressPhase.queued,
    fraction: 0,
  );

  Stream<TabularParseProgress> get progress => _progressController.stream;
  TabularParseProgress get currentProgress => _currentProgress;
  bool get isCompleted => _completer.isCompleted;
  bool get isCancelled => _cancelRequested;

  bool cancel() {
    if (_completer.isCompleted) return false;
    _cancelRequested = true;
    _isolate?.kill(priority: Isolate.immediate);
    _emit(
      const TabularParseProgress(
        phase: TabularParseProgressPhase.cancelled,
        fraction: 0,
      ),
    );
    _completer.completeError(const TabularParseCancelledException());
    _release();
    return true;
  }

  Future<void> _start(Uint8List bytes, TabularParseOptions options) async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _subscription = receivePort.listen(_handleMessage);
    try {
      _isolate =
          await Isolate.spawn<List<Object?>>(_parseInBackgroundEntry, <Object?>[
            receivePort.sendPort,
            bytes,
            options.limits.maximumFileBytes,
            options.limits.maximumDataRows,
            options.limits.maximumColumns,
            options.limits.maximumFieldBytes,
            options.delimiter,
            options.hasHeader,
          ]);
      if (_cancelRequested) {
        _isolate?.kill(priority: Isolate.immediate);
        _release();
      }
    } on Object {
      if (_cancelRequested || _completer.isCompleted) return;
      _emit(
        const TabularParseProgress(phase: TabularParseProgressPhase.failed),
      );
      _completer.completeError(
        StateError('The background parser could not be started.'),
      );
      _release();
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  void _handleMessage(Object? message) {
    if (_cancelRequested || _completer.isCompleted) return;
    if (message is! List<Object?> || message.isEmpty) {
      _completeUnexpectedFailure();
      return;
    }
    switch (message.first) {
      case 'parsing':
        _emit(
          const TabularParseProgress(phase: TabularParseProgressPhase.parsing),
        );
      case 'success':
        if (message.length != 2 || message[1] is! TabularDocument) {
          _completeUnexpectedFailure();
          return;
        }
        _emit(
          const TabularParseProgress(
            phase: TabularParseProgressPhase.completed,
            fraction: 1,
          ),
        );
        _completer.complete(message[1]! as TabularDocument);
        _release();
      case 'parse_error':
        if (message.length != 4 || message[1] is! int) {
          _completeUnexpectedFailure();
          return;
        }
        final codeIndex = message[1]! as int;
        if (codeIndex < 0 ||
            codeIndex >= TabularParseFailureCode.values.length) {
          _completeUnexpectedFailure();
          return;
        }
        _emit(
          const TabularParseProgress(phase: TabularParseProgressPhase.failed),
        );
        _completer.completeError(
          TabularParseException(
            TabularParseFailureCode.values[codeIndex],
            message[2]! as String,
            offset: message[3] as int?,
          ),
        );
        _release();
      case 'unexpected_error':
        _completeUnexpectedFailure();
      default:
        _completeUnexpectedFailure();
    }
  }

  void _completeUnexpectedFailure() {
    if (_completer.isCompleted) return;
    _emit(const TabularParseProgress(phase: TabularParseProgressPhase.failed));
    _completer.completeError(
      StateError('The background parser failed unexpectedly.'),
    );
    _release();
  }

  void _emit(TabularParseProgress value) {
    _currentProgress = value;
    if (!_progressController.isClosed) _progressController.add(value);
  }

  void _release() {
    _isolate = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
    if (!_progressController.isClosed) {
      unawaited(_progressController.close());
    }
  }
}

void _parseInBackgroundEntry(List<Object?> message) {
  final sendPort = message[0]! as SendPort;
  sendPort.send(<Object?>['parsing']);
  try {
    final limits = TabularParseLimits(
      maximumFileBytes: message[2]! as int,
      maximumDataRows: message[3]! as int,
      maximumColumns: message[4]! as int,
      maximumFieldBytes: message[5]! as int,
    );
    final options = TabularParseOptions(
      limits: limits,
      delimiter: message[6] as String?,
      hasHeader: message[7]! as bool,
    );
    final document = const TabularImportParser().parse(
      message[1]! as Uint8List,
      options: options,
    );
    sendPort.send(<Object?>['success', document]);
  } on TabularParseException catch (error) {
    sendPort.send(<Object?>[
      'parse_error',
      error.code.index,
      error.message,
      error.offset,
    ]);
  } on Object {
    sendPort.send(<Object?>['unexpected_error']);
  } finally {
    final bytes = message[1]! as Uint8List;
    bytes.fillRange(0, bytes.length, 0);
    message.clear();
  }
}

const _supportedDelimiters = <String>{',', '\t', ';'};

final class _DecodedDocument {
  const _DecodedDocument({required this.text, required this.encoding});

  final String text;
  final TabularSourceEncoding encoding;
}

final class _ParsedRecord {
  const _ParsedRecord({required this.values, required this.originalRowNumber});

  final List<String> values;
  final int originalRowNumber;
}
