import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const List<String> _cardockAccountHeaders = <String>[
  '账号关联标识',
  '平台名称',
  '登录账号',
  '手机号',
  '邮箱',
  '密码',
  '网址',
  '备注',
];

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('DIAGNOSTIC_CODE=INVALID_ARGUMENT_COUNT');
    exitCode = 64;
    return;
  }

  final bytes = await File(arguments.single).readAsBytes();
  _reportWorkbookStructure(bytes);
  var failed = false;
  final parser = const TabularImportParser();
  TabularDocument? synchronousDocument;

  try {
    synchronousDocument = parser.parse(bytes);
    _report('SYNC', synchronousDocument);
  } on TabularParseException catch (error) {
    failed = true;
    _reportParseError('SYNC', error.code.name);
  } on Object catch (error) {
    failed = true;
    _reportUnexpectedError('SYNC', error);
  }

  try {
    final job = parser.parseInBackground(bytes);
    _report('BACKGROUND', await job.result);
  } on TabularParseException catch (error) {
    failed = true;
    _reportParseError('BACKGROUND', error.code.name);
  } on TabularParseCancelledException {
    failed = true;
    _reportParseError('BACKGROUND', 'cancelled');
  } on Object catch (error) {
    failed = true;
    _reportUnexpectedError('BACKGROUND', error);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }

  if (synchronousDocument != null) {
    _reportMapping(synchronousDocument);
  }

  if (failed) exitCode = 2;
}

void _reportWorkbookStructure(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final workbookEntry = archive.findFile('xl/workbook.xml');
    if (workbookEntry == null || !workbookEntry.isFile) {
      stdout
        ..writeln('WORKBOOK_STRUCTURE_STATUS=ERROR')
        ..writeln('WORKBOOK_STRUCTURE_ERROR_CODE=workbook_xml_missing');
      return;
    }
    final workbookBytes = switch (workbookEntry.content) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => throw const FormatException('workbook_xml_invalid'),
    };
    final workbook = XmlDocument.parse(
      utf8.decode(workbookBytes, allowMalformed: false),
    );
    final sheets = workbook.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'sheet')
        .toList(growable: false);
    stdout
      ..writeln('WORKBOOK_STRUCTURE_STATUS=OK')
      ..writeln('WORKBOOK_SHEET_COUNT=${sheets.length}')
      ..writeln(
        'WORKBOOK_FIRST_SHEET_NAME=${sheets.firstOrNull?.getAttribute('name') ?? ''}',
      );
  } on Object catch (error) {
    stdout
      ..writeln('WORKBOOK_STRUCTURE_STATUS=ERROR')
      ..writeln(
        'WORKBOOK_STRUCTURE_ERROR_CODE=unexpected_${error.runtimeType}',
      );
  }
}

void _reportMapping(TabularDocument document) {
  final session = ImportSessionController();
  try {
    session.loadParsedDocument(
      document,
      vaultScopeId: 'diagnostic-vault',
      expectedVaultRevision: 1,
    );
    final adapter = session.snapshot.selectedAdapter;
    stdout
      ..writeln(
        'MAPPING_SOURCE_MATCH=${adapter?.id == 'cardock_accounts_template'}',
      )
      ..writeln('MAPPING_SOURCE_ENABLED=${adapter?.enabled == true}')
      ..writeln('MAPPING_SOURCE_VERIFIED=${adapter?.verified == true}');
    if (adapter?.itemKind == ImportItemKind.account) {
      session.mapAccounts();
      stdout
        ..writeln(
          'MAPPING_VALID_SOURCE_ROWS=${document.rows.where((row) => row.isValid).length}',
        )
        ..writeln(
          'MAPPING_DRAFT_COUNT=${session.snapshot.accountMapping?.drafts.length ?? 0}',
        );
    } else {
      stdout.writeln('MAPPING_ERROR_CODE=unexpected_source_kind');
    }
  } on Object catch (error) {
    stdout.writeln('MAPPING_ERROR_CODE=unexpected_${error.runtimeType}');
  } finally {
    session.clear();
  }
}

void _report(String mode, TabularDocument document) {
  final issueCodes = document.issues.map((issue) => issue.code).toSet().toList()
    ..sort();
  var maximumRowColumns = 0;
  for (final row in document.rows) {
    if (row.values.length > maximumRowColumns) {
      maximumRowColumns = row.values.length;
    }
  }
  stdout
    ..writeln('${mode}_STATUS=OK')
    ..writeln('${mode}_ENCODING=${document.encoding.name}')
    ..writeln('${mode}_HEADER_COUNT=${document.headers.length}')
    ..writeln(
      '${mode}_HEADER_MATCH=${_listEquals(document.headers, _cardockAccountHeaders)}',
    )
    ..writeln('${mode}_DATA_ROW_COUNT=${document.rows.length}')
    ..writeln('${mode}_COLUMN_COUNT=${document.columnCount}')
    ..writeln('${mode}_MAX_ROW_COLUMN_COUNT=$maximumRowColumns')
    ..writeln('${mode}_ISSUE_CODES=${issueCodes.join(',')}');
}

void _reportParseError(String mode, String code) {
  stdout
    ..writeln('${mode}_STATUS=ERROR')
    ..writeln('${mode}_ERROR_CODE=$code');
}

void _reportUnexpectedError(String mode, Object error) {
  stdout
    ..writeln('${mode}_STATUS=ERROR')
    ..writeln('${mode}_ERROR_CODE=unexpected_${error.runtimeType}');
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
