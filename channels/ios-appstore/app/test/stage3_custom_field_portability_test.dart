import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/data_import/custom_field_companion.dart';
import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/storage/readable_export.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_models.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_projector.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_vault_gateway.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';

AccountImportDraft account({
  String key = 'a',
  String adapter = 'cardock_accounts_template',
}) => AccountImportDraft(
  originalRowNumber: 2,
  sourceId: 'fixture',
  adapterId: adapter,
  accountKey: key,
  platformName: 'Fictional service',
);
AccountCustomField field(
  String id,
  String name,
  String value, {
  bool secret = false,
  int order = 0,
}) => AccountCustomField(
  id: id,
  name: name,
  type: secret
      ? AccountCustomFieldType.sensitiveText
      : AccountCustomFieldType.text,
  value: value,
  order: order,
);
TabularDocument table(List<List<String>> rows, {List<String>? headers}) =>
    TabularDocument(
      headers: headers ?? CustomFieldCompanion.headers,
      rows: [
        for (var i = 0; i < rows.length; i++)
          TabularRow(values: rows[i], originalRowNumber: i + 2),
      ],
      encoding: TabularSourceEncoding.utf8,
      delimiter: ',',
      hasHeader: true,
      originalByteLength: 100,
    );
Future<List<int>> collect(Stream<List<int>> stream) =>
    stream.fold(<int>[], (out, bytes) => out..addAll(bytes));
Uint8List office(Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    final b = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  test(
    'five stable field types preserve exact text, date and decimal values',
    () {
      final companion = CustomFieldCompanion.parse(
        table([
          ['a', '0', 'Text', 'text', '  original\ntext  '],
          ['a', '1', 'Sensitive', 'sensitive_text', 'TEST-ONLY-SECRET'],
          ['a', '2', 'Site', 'url', 'https://example.invalid'],
          ['a', '3', 'Date', 'date', '2024-02-29'],
          ['a', '4', 'Number', 'number', '12345678901234567890.012300'],
        ]),
        [account()],
      );
      expect(companion.rows[1].useImportedValue, false);
      final draft = companion.apply(account());
      expect(draft.customFields.length, 4);
      expect(draft.customFields.first.value, '  original\ntext  ');
      expect(draft.customFields.last.value, '12345678901234567890.012300');
      companion.rows[1]
        ..useImportedValue = true
        ..sensitiveConfirmed = true;
      expect(
        mergeImportedCustomFields([], companion.apply(account())).length,
        5,
      );
    },
  );
  for (final invalid in ['missing', 'A', '']) {
    test('account_key is exact and never guessed: $invalid', () {
      expect(
        () => CustomFieldCompanion.parse(
          table([
            [invalid, '0', 'Name', 'text', 'value'],
          ]),
          [account()],
        ),
        throwsFormatException,
      );
    });
  }
  test('ambiguous key and generated association rejected', () {
    final data = table([
      ['a', '0', 'Name', 'text', 'value'],
    ]);
    expect(
      () => CustomFieldCompanion.parse(data, [account(), account()]),
      throwsFormatException,
    );
    expect(
      () => CustomFieldCompanion.parse(data, [
        AccountImportDraft(
          originalRowNumber: 2,
          sourceId: 'fixture',
          adapterId: 'cardock_accounts_template',
          accountKey: 'a',
          accountKeyWasGenerated: true,
          platformName: 'Fictional',
        ),
      ]),
      throwsFormatException,
    );
  });
  test('third party companion and manual plan injection rejected', () {
    expect(
      () => CustomFieldCompanion.parse(
        table([
          ['a', '0', 'Name', 'text', 'value'],
        ]),
        [account(adapter: 'bitwarden_csv')],
      ),
      throwsFormatException,
    );
    expect(
      () => mergeImportedCustomFields(
        [],
        account(
          adapter: 'bitwarden_csv',
        ).copyWith(customFields: [field('x', 'Name', 'value')]),
      ),
      throwsFormatException,
    );
  });
  test(
    'ten fields including empty allowed; eleven and normalized duplicates reject',
    () {
      final rows = [
        for (var i = 0; i < 10; i++) ['a', '$i', 'Field$i', 'text', ''],
      ];
      expect(
        CustomFieldCompanion.parse(table(rows), [account()]).rows.length,
        10,
      );
      expect(
        () => CustomFieldCompanion.parse(
          table([
            ...rows,
            ['a', '10', 'Eleven', 'text', ''],
          ]),
          [account()],
        ),
        throwsArgumentError,
      );
      expect(
        () => CustomFieldCompanion.parse(
          table([
            ['a', '0', 'Ｎame', 'text', '1'],
            ['a', '1', ' name ', 'text', '2'],
          ]),
          [account()],
        ),
        throwsArgumentError,
      );
    },
  );
  test('sensitive confirmation cannot be substituted by password presence', () {
    final draft = account().copyWith(
      password: 'TEST-ONLY-PASSWORD',
      customFields: [
        field('secret', 'Label', 'TEST-ONLY-SECRET', secret: true),
      ],
    );
    expect(() => mergeImportedCustomFields([], draft), throwsFormatException);
    expect(
      mergeImportedCustomFields(
        [],
        draft.copyWith(confirmedSensitiveCustomFieldIds: {'secret'}),
      ).single.value,
      'TEST-ONLY-SECRET',
    );
  });
  test(
    'same name preserves existing unless individually selected; IDs retained',
    () {
      final old = field('stable', 'Name', 'old');
      final draft = account().copyWith(
        customFields: [field('incoming', 'ＮAME', 'new')],
      );
      expect(mergeImportedCustomFields([old], draft).single.value, 'old');
      final replaced = mergeImportedCustomFields([
        old,
      ], draft.copyWith(replaceCustomFieldNames: {'name'})).single;
      expect(replaced.value, 'new');
      expect(replaced.id, 'stable');
      expect(replaced.revision, 1);
    },
  );
  test(
    'merged fields keep existing positions then companion order with unique ordinals',
    () {
      final merged = mergeImportedCustomFields(
        [field('old', 'Old', 'x')],
        account().copyWith(
          customFields: [
            field('b', 'B', 'b', order: 1),
            field('a', 'A', 'a', order: 0),
          ],
        ),
      );
      expect(merged.map((f) => f.name), ['Old', 'A', 'B']);
      expect(merged.map((f) => f.order), [0, 1, 2]);
    },
  );
  test('combined eleventh field rejects with original list unchanged', () {
    final old = [
      for (var i = 0; i < 10; i++) field('old$i', 'Old$i', 'x', order: i),
    ];
    expect(
      () => mergeImportedCustomFields(
        old,
        account().copyWith(customFields: [field('new', 'New', 'x')]),
      ),
      throwsArgumentError,
    );
    expect(old.length, 10);
    expect(old.first.value, 'x');
  });
  for (final separator in [',', '\t']) {
    test(
      'CSV/TSV/TXT companion reuses bounded parser: ${separator.codeUnitAt(0)}',
      () {
        final bytes = Uint8List.fromList(
          utf8.encode(
            '${CustomFieldCompanion.headers.join(separator)}\r\na${separator}0${separator}Label${separator}text${separator}value\r\n',
          ),
        );
        expect(
          CustomFieldCompanion.parse(const TabularImportParser().parse(bytes), [
            account(),
          ]).rows.single.field.value,
          'value',
        );
      },
    );
  }
  for (final kind in ['xlsx', 'docx']) {
    test('$kind companion uses existing first table reader', () {
      final rows = [
        CustomFieldCompanion.headers,
        ['a', '0', 'Label', 'text', 'value'],
      ];
      final files = kind == 'xlsx'
          ? <String, String>{
              'xl/workbook.xml':
                  '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Fields" sheetId="1" r:id="rId1"/></sheets></workbook>',
              'xl/_rels/workbook.xml.rels':
                  '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"/></Relationships>',
              'xl/worksheets/sheet1.xml':
                  '<worksheet><sheetData>${[
                    for (var r = 0; r < rows.length; r++) '<row r="${r + 1}">${[for (var c = 0; c < rows[r].length; c++) '<c r="${String.fromCharCode(65 + c)}${r + 1}" t="inlineStr"><is><t>${rows[r][c]}</t></is></c>'].join()}</row>',
                  ].join()}</sheetData></worksheet>',
            }
          : <String, String>{
              'word/document.xml':
                  '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:tbl>${[
                    for (final row in rows) '<w:tr>${[for (final value in row) '<w:tc><w:p><w:r><w:t>$value</w:t></w:r></w:p></w:tc>'].join()}</w:tr>',
                  ].join()}</w:tbl></w:body></w:document>',
            };
      expect(
        CustomFieldCompanion.parse(
          const TabularImportParser().parse(office(files)),
          [account()],
        ).rows.single.field.value,
        'value',
      );
    });
  }
  test(
    'ordinary export and password/sensitive switches are independent in JSON and ZIP',
    () async {
      final snapshot = VaultSnapshot(
        nextAccountId: 2,
        accounts: [
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(
              platformName: 'Fictional',
              password: 'TEST-ONLY-PASSWORD',
              customFields: [
                field('plain', 'Ordinary', '=FORMULA(),\n"quoted"'),
                field(
                  'secret',
                  'Secret',
                  'TEST-ONLY-SENSITIVE',
                  secret: true,
                  order: 1,
                ),
              ],
            ),
          ),
        ],
      );
      for (final format in ReadableExportFormat.values) {
        for (final passwords in [false, true]) {
          for (final sensitive in [false, true]) {
            final bytes = await collect(
              ReadableExport(
                snapshot,
                ReadableExportOptions(
                  format: format,
                  includePasswords: passwords,
                  includeSensitiveCustomFields: sensitive,
                ),
              ).bytes(),
            );
            late final String output;
            if (format == ReadableExportFormat.json) {
              output = utf8.decode(bytes);
              final value = jsonDecode(output) as Map;
              final fields = value['account_custom_fields'] as List;
              expect(
                fields[1]['value_state'],
                sensitive ? 'present' : 'redacted',
              );
              expect(fields[0]['field_id'], 'plain');
            } else {
              final zip = ZipDecoder().decodeBytes(bytes, verify: true);
              final custom = zip.findFile('account_custom_fields.csv')!;
              final content = custom.content as List<int>;
              expect(content.take(3), [0xef, 0xbb, 0xbf]);
              expect(utf8.decode(content), contains("'=FORMULA()"));
              output = zip.files
                  .where((f) => f.isFile)
                  .map((f) => utf8.decode(f.content as List<int>))
                  .join();
            }
            expect(output.contains('TEST-ONLY-PASSWORD'), passwords);
            expect(output.contains('TEST-ONLY-SENSITIVE'), sensitive);
          }
        }
      }
    },
  );
  test(
    'authorized history projection never includes sensitive values or names in summary',
    () {
      final record = AccountRecord.fromDraft(
        id: 'a',
        draft: AccountDraft(
          platformName: 'Fictional',
          customFields: [
            field('x', 'Private label', 'TEST-ONLY-SENSITIVE', secret: true),
          ],
        ),
      );
      for (final mode in TemporaryWebHistoryMode.values) {
        final projected = const TemporaryWebRecordProjector().project(
          records: TemporaryWebVaultRecords(
            revision: 1,
            accounts: [record],
            subscriptions: [],
          ),
          policy: TemporaryWebSessionPolicy(historyMode: mode),
          sessionAccountIds: {},
          sessionSubscriptionIds: {},
        );
        final text = jsonEncode(projected);
        expect(text, isNot(contains('TEST-ONLY-SENSITIVE')));
        expect(
          text.contains('Private label'),
          mode == TemporaryWebHistoryMode.details,
        );
      }
    },
  );
  test(
    'import draft decisions are immutable and safe preview excludes field values',
    () {
      final fields = [field('x', 'Label', 'TEST-ONLY-SENSITIVE', secret: true)];
      final confirmed = {'x'};
      final draft = account().copyWith(
        customFields: fields,
        confirmedSensitiveCustomFieldIds: confirmed,
      );
      fields.clear();
      confirmed.clear();
      expect(draft.customFields.length, 1);
      expect(draft.confirmedSensitiveCustomFieldIds, {'x'});
      expect(
        jsonEncode(draft.toSafePreviewJson()),
        isNot(contains('TEST-ONLY-SENSITIVE')),
      );
    },
  );
}
