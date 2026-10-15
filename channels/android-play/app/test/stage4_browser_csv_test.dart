import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/data_import/data_import.dart';

Uint8List csv(List<String> row, {bool note = true, List<String>? headers}) {
  String field(String v) => '"${v.replaceAll('"', '""')}"';
  return Uint8List.fromList(
    utf8.encode(
      '${(headers ?? ['name', 'url', 'username', 'password', if (note) 'note']).join(',')}\r\n${row.map(field).join(',')}\r\n',
    ),
  );
}

TabularDocument parse(Uint8List bytes) =>
    const TabularImportParser().parse(bytes);
void main() {
  final registry = ImportSourceRegistry.standard();
  for (final note in [false, true]) {
    for (final encoding in ['utf8', 'utf8bom', 'utf16le', 'utf16be']) {
      test('confirmed browser headers and encoding $note/$encoding', () {
        final base = csv([
          'Fixture',
          'https://example.invalid',
          'login',
          'TEST-ONLY',
          if (note) 'note',
        ], note: note);
        Uint8List bytes = base;
        if (encoding == 'utf8bom') {
          bytes = Uint8List.fromList([0xef, 0xbb, 0xbf, ...base]);
        }
        if (encoding.startsWith('utf16')) {
          final little = encoding == 'utf16le';
          bytes = Uint8List.fromList([
            if (little) ...[0xff, 0xfe] else ...[0xfe, 0xff],
            for (final unit in utf8.decode(base).codeUnits)
              ...(little ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255]),
          ]);
        }
        final doc = parse(bytes);
        final detection = registry.detect(doc);
        expect(detection.selectedAdapter.id, 'chrome_google_csv');
        expect(detection.requiresUserConfirmation, false);
        for (final id in [
          'chrome_passwords_csv',
          'google_password_manager_csv',
        ]) {
          final mapped = const ImportFieldMapper().mapAccounts(
            doc,
            adapter: registry.adapterById(id),
          );
          expect(mapped.drafts.single.loginAccount, 'login');
          expect(mapped.drafts.single.hasImportablePassword, true);
          expect(mapped.drafts.single.notes, note ? 'note' : '');
        }
      });
    }
  }
  for (final raw in [
    '  TEST-ONLY  ',
    'TEST,ONLY',
    'TEST"ONLY',
    'TEST\r\nONLY',
    'TEST\nONLY',
    'TEST\rONLY',
    'TEST-e\u0301',
    'TEST-é',
    'TEST-日本😀',
  ]) {
    test('password bytes remain unchanged fixture ${raw.codeUnits}', () {
      final doc = parse(
        csv(['Fixture', 'https://example.invalid', 'login', raw, 'note']),
      );
      final draft = const ImportFieldMapper()
          .mapAccounts(doc, adapter: registry.detect(doc).selectedAdapter)
          .drafts
          .single;
      expect(utf8.encode(draft.password), utf8.encode(raw));
      expect(draft.toSafePreviewJson().containsKey('password'), false);
    });
  }
  for (final value in [
    '*',
    '***',
    '.....',
    '••••',
    '●●●',
    '····',
    '…',
    'xxxx',
    '[hidden]',
    'hidden',
    '[redacted]',
    '<redacted>',
    '已隐藏',
    '非表示',
  ]) {
    test('browser placeholders never import ${value.runes}', () {
      final session = ImportSessionController();
      session.loadDocument(
        csv(['Fixture', 'https://example.invalid', 'login', value, 'note']),
        vaultScopeId: 'fixture',
        expectedVaultRevision: 1,
      );
      session.mapAccounts();
      expect(
        session.snapshot.accountMapping!.drafts.single.passwordLooksMasked,
        true,
      );
      expect(
        () => session.setMaskedPasswordConfirmed(2, confirmed: true),
        throwsStateError,
      );
      session.buildPlan();
      expect(session.snapshot.plan!.newAccounts.single.password, '');
    });
  }
  for (final headers in [
    ['username', 'password'],
    ['name', 'url', 'username', 'password', 'notes'],
    ['url', 'name', 'username', 'password'],
    ['name', 'url', 'username', 'password', 'note', 'extra'],
    ['user-name', 'password'],
    ['name', 'URL', 'login', 'password'],
    ['Title', 'Url', 'Username', 'Password'],
    ['name', 'url', 'username', 'password', 'timeCreated'],
    ['title', 'url', 'username', 'password', 'otpAuth'],
  ]) {
    test('unknown lookalike headers use generic ${headers.join('/')}', () {
      expect(
        registry
            .detect(
              parse(
                csv(List.filled(headers.length, 'TEST-ONLY'), headers: headers),
              ),
            )
            .selectedAdapter
            .id,
        'generic_tabular',
      );
    });
  }
  for (final id in [
    'bitwarden_csv',
    'onepassword_csv',
    'keepassxc_csv',
    'cardock_accounts_template',
    'cardock_subscriptions_template',
  ]) {
    test('known format $id is not browser', () {
      final adapter = registry.adapterById(id);
      final doc = parse(
        csv(
          List.filled(adapter.exactHeaders.length, ''),
          headers: adapter.exactHeaders,
        ),
      );
      expect(registry.detect(doc).selectedAdapter.id, id);
    });
  }
  test(
    'manual browser mismatch rejected by session and mapper, explicit generic remains available',
    () {
      final doc = parse(
        csv(['login', 'TEST-ONLY'], headers: ['username', 'password']),
      );
      final session = ImportSessionController()
        ..loadParsedDocument(
          doc,
          vaultScopeId: 'fixture',
          expectedVaultRevision: 1,
        );
      expect(
        () => session.selectAdapter('chrome_passwords_csv'),
        throwsFormatException,
      );
      expect(
        () => const ImportFieldMapper().mapAccounts(
          doc,
          adapter: registry.adapterById('chrome_passwords_csv'),
        ),
        throwsFormatException,
      );
      session.selectAdapter('generic_tabular');
      session.mapAccounts();
      expect(session.snapshot.accountMapping!.drafts.length, 1);
    },
  );
  test('empty name falls back to safe URL host, never login', () {
    final doc = parse(
      csv([
        '',
        'https://service.example.invalid/path',
        'some-login',
        'TEST-ONLY',
        '',
      ]),
    );
    final draft = const ImportFieldMapper()
        .mapAccounts(doc, adapter: registry.detect(doc).selectedAdapter)
        .drafts
        .single;
    expect(draft.platformName, 'service.example.invalid');
    expect(draft.loginAccount, 'some-login');
  });
  for (final url in [
    'javascript:alert(1)',
    'file:///private',
    'content://provider/a',
    'android://hash@com.example',
    'https://user:pass@example.invalid',
  ]) {
    test('browser rejects unsafe URL scheme ${url.split(':').first}', () {
      final doc = parse(csv(['Fixture', url, 'login', 'TEST-ONLY', '']));
      final draft = const ImportFieldMapper()
          .mapAccounts(doc, adapter: registry.detect(doc).selectedAdapter)
          .drafts
          .single;
      expect(draft.validationState, ImportValidationState.invalid);
    });
  }
  test(
    'different logins on same domain remain independent; same login is candidate',
    () {
      AccountImportDraft draft(int row, String login) => AccountImportDraft(
        originalRowNumber: row,
        sourceId: 'fixture-$row',
        adapterId: 'chrome_google_csv',
        platformName: 'Fixture',
        loginAccount: login,
        url: 'https://example.invalid',
      );
      final duplicates = const ImportDuplicateDetector().detect(
        imported: [draft(2, 'alpha'), draft(3, 'beta'), draft(4, 'alpha')],
        existing: [],
      );
      expect(duplicates.where((d) => d.importRowNumber == 3), isEmpty);
      expect(duplicates.where((d) => d.importRowNumber == 4), hasLength(1));
    },
  );
  test('dedicated mapping cannot redirect password into notes', () {
    final doc = parse(
      csv(['Fixture', 'https://example.invalid', 'login', 'TEST-ONLY', '']),
    );
    expect(
      () => const ImportFieldMapper().mapAccounts(
        doc,
        adapter: registry.detect(doc).selectedAdapter,
        overrides: {3: ImportTargetField.notes},
      ),
      throwsFormatException,
    );
  });
  test(
    '5000 synthetic rows background parse, detection, mapping and duplicate index',
    () async {
      final body = StringBuffer('name,url,username,password,note\r\n');
      for (var i = 0; i < 5000; i++) {
        body.writeln(
          'Fixture,https://example.invalid,fixture-$i,TEST-ONLY-$i,',
        );
      }
      final bytes = Uint8List.fromList(utf8.encode(body.toString()));
      final watch = Stopwatch()..start();
      final document = await const TabularImportParser()
          .parseInBackground(bytes)
          .result;
      final draft = const ImportFieldMapper().mapAccounts(
        document,
        adapter: registry.detect(document).selectedAdapter,
      );
      expect(draft.drafts.length, 5000);
      expect(
        const ImportDuplicateDetector().detect(
          imported: draft.drafts,
          existing: [],
        ),
        isEmpty,
      );
      watch.stop();
      expect(watch.elapsed.inSeconds, lessThan(30));
      // Synthetic fixture only; this is a Windows measurement, not device acceptance.
      // ignore: avoid_print
      print('Stage4 Windows 5000 rows: ${watch.elapsedMilliseconds} ms');
    },
  );
  test('5001 rows rejected and cancel has no parsed authority', () async {
    final text =
        'name,url,username,password\n${List.filled(5001, 'Fixture,https://example.invalid,login,TEST-ONLY').join('\n')}';
    expect(
      () => parse(Uint8List.fromList(utf8.encode(text))),
      throwsA(isA<TabularParseException>()),
    );
    final job = const TabularImportParser().parseInBackground(
      csv(['Fixture', 'https://example.invalid', 'login', 'TEST-ONLY', '']),
    );
    job.cancel();
    await expectLater(
      job.result,
      throwsA(isA<TabularParseCancelledException>()),
    );
  });

  test('same login on unrelated platforms and domains is not merged', () {
    final drafts = [
      for (var n = 0; n < 2; n++)
        AccountImportDraft(
          originalRowNumber: n + 2,
          sourceId: 'test-$n',
          adapterId: 'chrome_google_csv',
          platformName: 'Service $n',
          loginAccount: 'same-login',
          url: 'https://service$n.example.invalid',
        ),
    ];
    expect(
      const ImportDuplicateDetector().detect(imported: drafts, existing: []),
      isEmpty,
    );
  });
}
