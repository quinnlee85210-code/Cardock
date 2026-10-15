import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/app/temporary_web_app_state_gateway.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_batch_import_port.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_models.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/data_import/infrastructure/app_state_temporary_web_batch_import_port.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

const _masterPassword = 'TEST-ONLY-WEB-DUAL-1234';
const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;
  late AppStateTemporaryWebBatchImportPort port;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-web-dual-document-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    state = AppState(
      vaultStore: EncryptedVaultStore(
        directoryProvider: () async => directory,
        creationKdf: _testKdf,
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_masterPassword), VaultActionResult.success);
    port = AppStateTemporaryWebBatchImportPort(appState: state);
  });

  test('账号后订阅形成同一计划，一个 account_key 可关联多条正式订阅', () async {
    var preview = await _addAccounts(
      port,
      state,
      fileName: 'accounts-first.csv',
      rows: const <String>[
        'shared-key,虚构平台甲,user-a,13000000000,a@example.invalid,TEST-ONLY-WEB-PASSWORD,https://a.example.invalid,虚构账号',
      ],
    );
    expect(preview.activeDocumentKind, 'account');
    expect(preview.documents.map((item) => item.kind), <String>['account']);

    preview = await _addSubscriptions(
      port,
      state,
      fileName: 'subscriptions-second.csv',
      rows: const <String>[
        'shared-key,虚构月度套餐,12.50,CNY,每月,2026-08-01,2026-09-01,是,虚构支付,3,第一条',
        'shared-key,虚构年度套餐,99.00,CNY,每年,2026-01-01,2027-01-01,否,虚构支付,7,第二条',
      ],
    );

    expect(preview.activeDocumentKind, 'subscription');
    expect(preview.documents.map((item) => item.kind), <String>[
      'account',
      'subscription',
    ]);
    expect(preview.rows.where((row) => row.kind == 'account'), hasLength(1));
    final subscriptionRows = preview.rows
        .where((row) => row.kind == 'subscription')
        .toList(growable: false);
    expect(subscriptionRows, hasLength(2));
    expect(
      subscriptionRows.map((row) => row.accountKeyAssociation).toSet(),
      <String?>{'linkedToImportedAccount'},
    );
    expect(
      subscriptionRows.every((row) => !row.subscriptionTargetRequired),
      isTrue,
    );
    expect(subscriptionRows.every((row) => row.canImport), isTrue);

    final prepared = await port.prepareCommit(
      TemporaryWebBatchCommitRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        selectedRowIds: preview.rows.map((row) => row.id).toSet(),
        duplicateResolutions: const <String, String>{},
      ),
    );
    expect(prepared.selectedRecordCount, 3);
    expect(prepared.newAccountCount, 1);
    expect(prepared.formalSubscriptionCount, 2);
    expect(prepared.pendingSubscriptionDraftCount, 0);

    final result = await port.approveCommit(
      prepared.approvalToken,
      expectedRevision: prepared.expectedRevision,
    );
    expect(result.importedAccounts, 1);
    expect(result.formalSubscriptions, 2);
    expect(result.pendingSubscriptionDrafts, 0);
    expect(state.accounts, hasLength(1));
    expect(state.subscriptions, hasLength(2));
    expect(state.subscriptions.map((item) => item.accountId).toSet(), <String?>{
      state.accounts.single.id,
    });
  });

  test('真实端口接收虚构稀疏 XLSX 时保留两条账号行', () async {
    final preview = await port.preview(
      TemporaryWebBatchImportRequest(
        fileName: 'fictional-sparse-accounts.xlsx',
        bytes: _fictionalSparseAccountsXlsx(),
        sourceId: 'auto',
        expectedRevision: state.localWebRevision,
        previewScope:
            TemporaryWebBatchPreviewScope.currentSessionAuthorizedOnly,
      ),
    );

    expect(preview.detectedFormat, contains('xlsx'));
    expect(preview.rows.where((row) => row.kind == 'account'), hasLength(2));
    expect(preview.rows.every((row) => row.canImport), isTrue);
  });

  test('订阅后账号同样合并，缺失关联会由后加入账号转为可导入', () async {
    var preview = await _addSubscriptions(
      port,
      state,
      fileName: 'subscriptions-first.csv',
      rows: const <String>[
        'reverse-key,反向顺序套餐,25.00,USD,每月,2026-08-15,2026-09-15,是,虚构支付,5,反向顺序',
      ],
    );
    var subscription = preview.rows.single;
    expect(subscription.accountKeyAssociation, 'missingImportedAccountKey');
    expect(subscription.subscriptionTargetRequired, isTrue);
    expect(subscription.canImport, isFalse);

    preview = await _addAccounts(
      port,
      state,
      fileName: 'accounts-second.csv',
      rows: const <String>[
        'reverse-key,虚构平台乙,user-b,,,TEST-ONLY-REVERSE-PASSWORD,https://b.example.invalid,反向账号',
      ],
    );
    expect(preview.activeDocumentKind, 'account');
    expect(preview.documents.map((item) => item.kind), <String>[
      'account',
      'subscription',
    ]);
    subscription = preview.rows.singleWhere(
      (row) => row.kind == 'subscription',
    );
    expect(subscription.accountKeyAssociation, 'linkedToImportedAccount');
    expect(subscription.subscriptionTargetRequired, isFalse);
    expect(subscription.canImport, isTrue);

    final prepared = await port.prepareCommit(
      TemporaryWebBatchCommitRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        selectedRowIds: preview.rows.map((row) => row.id).toSet(),
        duplicateResolutions: const <String, String>{},
      ),
    );
    expect(prepared.newAccountCount, 1);
    expect(prepared.formalSubscriptionCount, 1);
    expect(prepared.pendingSubscriptionDraftCount, 0);
  });

  test('同类型上传只替换该文件，两类文件可以分别移除', () async {
    var preview = await _addAccounts(
      port,
      state,
      fileName: 'accounts-old.csv',
      rows: const <String>[
        'replace-key,旧虚构平台,old-user,,,,https://old.example.invalid,旧行',
      ],
    );
    preview = await _addSubscriptions(
      port,
      state,
      fileName: 'subscriptions-kept.csv',
      rows: const <String>[
        'replace-key,保留订阅,8.00,CNY,每月,2026-08-01,2026-09-01,是,虚构支付,3,保留',
      ],
    );
    preview = await _addAccounts(
      port,
      state,
      fileName: 'accounts-replacement.csv',
      rows: const <String>[
        'replace-key,新虚构平台,new-user,,,,https://new.example.invalid,新行',
      ],
    );

    expect(preview.documents, hasLength(2));
    expect(
      preview.documents.singleWhere((item) => item.kind == 'account').fileName,
      'accounts-replacement.csv',
    );
    expect(
      preview.documents
          .singleWhere((item) => item.kind == 'subscription')
          .fileName,
      'subscriptions-kept.csv',
    );
    expect(
      preview.rows.singleWhere((row) => row.kind == 'account').title,
      '新虚构平台',
    );
    expect(preview.rows.where((row) => row.title == '旧虚构平台'), isEmpty);
    expect(
      preview.rows.where((row) => row.kind == 'subscription'),
      hasLength(1),
    );

    preview = await port.revisePreview(
      TemporaryWebBatchRevisionRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        activateDocumentKind: 'subscription',
      ),
    );
    expect(preview.activeDocumentKind, 'subscription');
    expect(
      preview.mappings.any((mapping) => mapping.targetField == 'planName'),
      isTrue,
    );
    preview = await port.revisePreview(
      TemporaryWebBatchRevisionRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        activateDocumentKind: 'account',
      ),
    );
    expect(preview.activeDocumentKind, 'account');
    expect(
      preview.mappings.any((mapping) => mapping.targetField == 'platformName'),
      isTrue,
    );

    preview = await port.revisePreview(
      TemporaryWebBatchRevisionRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        removeDocumentKind: 'subscription',
      ),
    );
    expect(preview.documents.map((item) => item.kind), <String>['account']);
    expect(preview.rows.every((row) => row.kind == 'account'), isTrue);
    expect(preview.activeDocumentKind, 'account');

    preview = await _addSubscriptions(
      port,
      state,
      fileName: 'subscriptions-added-again.csv',
      rows: const <String>[
        'replace-key,再次加入订阅,8.00,CNY,每月,2026-08-01,2026-09-01,是,虚构支付,3,再次加入',
      ],
    );
    preview = await port.revisePreview(
      TemporaryWebBatchRevisionRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        removeDocumentKind: 'account',
      ),
    );
    expect(preview.documents.map((item) => item.kind), <String>[
      'subscription',
    ]);
    expect(preview.rows.every((row) => row.kind == 'subscription'), isTrue);
    expect(preview.activeDocumentKind, 'subscription');
    expect(
      preview.rows.single.accountKeyAssociation,
      'missingImportedAccountKey',
    );
    expect(preview.rows.single.canImport, isFalse);
  });

  test('不存在的 account_key 明确标错并阻止形成可提交计划', () async {
    var preview = await _addAccounts(
      port,
      state,
      fileName: 'accounts.csv',
      rows: const <String>[
        'known-key,已知虚构平台,known-user,,,,https://known.example.invalid,',
      ],
    );
    preview = await _addSubscriptions(
      port,
      state,
      fileName: 'subscriptions.csv',
      rows: const <String>[
        'missing-key,无关联订阅,18.00,CNY,每月,2026-08-01,2026-09-01,是,虚构支付,3,',
      ],
    );
    final row = preview.rows.singleWhere(
      (candidate) => candidate.kind == 'subscription',
    );
    expect(row.accountKeyAssociation, 'missingImportedAccountKey');
    expect(row.subscriptionTargetRequired, isTrue);
    expect(row.canImport, isFalse);
    expect(row.issue, contains('请选择关联账号'));

    await expectLater(
      port.prepareCommit(
        TemporaryWebBatchCommitRequest(
          previewToken: preview.previewToken,
          expectedRevision: preview.revision,
          selectedRowIds: preview.rows.map((item) => item.id).toSet(),
          duplicateResolutions: const <String, String>{},
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
  });

  test('原单条录入与账号单文件批量导入路径继续可用', () async {
    final gateway = AppStateTemporaryWebVaultGateway(state);
    final single = await gateway.addAccountAfterPhoneApproval(
      AccountDraft(platformName: '单条虚构平台', loginAccount: 'single-user'),
      expectedRevision: gateway.revision,
    );
    expect(single.disposition, TemporaryWebMutationDisposition.committed);

    final preview = await _addAccounts(
      port,
      state,
      fileName: 'single-file.csv',
      rows: const <String>[
        'single-file-key,单文件虚构平台,batch-user,,,,https://batch.example.invalid,',
      ],
    );
    expect(preview.documents, hasLength(1));
    expect(preview.documents.single.kind, 'account');
    expect(preview.rows, hasLength(1));

    final prepared = await port.prepareCommit(
      TemporaryWebBatchCommitRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        selectedRowIds: <String>{preview.rows.single.id},
        duplicateResolutions: const <String, String>{},
      ),
    );
    expect(prepared.newAccountCount, 1);
    expect(prepared.formalSubscriptionCount, 0);
    final committed = await port.approveCommit(
      prepared.approvalToken,
      expectedRevision: prepared.expectedRevision,
    );
    expect(committed.importedAccounts, 1);
    expect(state.accounts, hasLength(2));
  });

  test('已应用账号映射在切换和替换订阅文件后保留，同类替换才重置', () async {
    var preview = await _addAccounts(
      port,
      state,
      fileName: 'mapped-accounts.csv',
      rows: const <String>[
        'mapped-key,原平台列,原登录列,,,,https://mapped.example.invalid,',
      ],
    );
    preview = await port.revisePreview(
      TemporaryWebBatchRevisionRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        mappingOverrides: const <int, String?>{
          1: 'loginAccount',
          2: 'platformName',
        },
      ),
    );
    expect(
      preview.rows.singleWhere((row) => row.kind == 'account').title,
      '原登录列',
    );
    expect(preview.mappings[1].targetField, 'loginAccount');
    expect(preview.mappings[2].targetField, 'platformName');

    preview = await _addSubscriptions(
      port,
      state,
      fileName: 'subscriptions-first.csv',
      rows: const <String>[
        'mapped-key,第一订阅,1.00,CNY,每月,2026-08-01,2026-09-01,是,虚构支付,3,',
      ],
    );
    preview = await _addSubscriptions(
      port,
      state,
      fileName: 'subscriptions-replacement.csv',
      rows: const <String>[
        'mapped-key,替换订阅,2.00,CNY,每月,2026-08-01,2026-10-01,是,虚构支付,3,',
      ],
    );
    preview = await port.revisePreview(
      TemporaryWebBatchRevisionRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
        activateDocumentKind: 'account',
      ),
    );
    expect(preview.mappings[1].targetField, 'loginAccount');
    expect(preview.mappings[2].targetField, 'platformName');
    expect(
      preview.rows.singleWhere((row) => row.kind == 'account').title,
      '原登录列',
    );

    preview = await port.revisePreview(
      TemporaryWebBatchRevisionRequest(
        previewToken: preview.previewToken,
        expectedRevision: preview.revision,
      ),
    );
    expect(preview.mappings[1].targetField, 'loginAccount');
    expect(preview.mappings[2].targetField, 'platformName');

    preview = await _addAccounts(
      port,
      state,
      fileName: 'accounts-replacement.csv',
      rows: const <String>[
        'mapped-key,新平台列,新登录列,,,,https://new-mapped.example.invalid,',
      ],
    );
    expect(preview.mappings[1].targetField, 'platformName');
    expect(preview.mappings[2].targetField, 'loginAccount');
    expect(
      preview.rows.singleWhere((row) => row.kind == 'account').title,
      '新平台列',
    );
  });

  test('浏览器源码不持久化业务数据且所有 HTTP 调用保持同源相对路径', () {
    final source = File('tool/temporary_web_client.dart').readAsStringSync();
    final lower = source.toLowerCase();
    for (final forbidden in const <String>[
      'localStorage',
      'sessionStorage',
      'indexedDB',
      'serviceWorker',
      'document.cookie',
      'sendBeacon',
      'WebSocket',
      'EventSource',
    ]) {
      expect(lower, isNot(contains(forbidden.toLowerCase())));
    }
    expect(lower, isNot(contains('http://')));
    expect(lower, isNot(contains('https://')));
    expect(source, isNot(contains('Uri.http(')));
    expect(source, isNot(contains('Uri.https(')));
    expect(source, contains('reconcileTemporaryWebBatchDecisions('));
    expect(
      source,
      contains(
        'resetActiveDocumentIfPreviouslyPresent: documentKindsBeforeUpload',
      ),
    );
    expect(source, contains('resetDocumentKinds: removeDocumentKind == null'));

    final paths = RegExp(
      r"_jsonRequest\(\s*'(?:GET|POST)'\s*,\s*'([^']+)'",
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!).toList();
    expect(
      paths,
      unorderedEquals(<String>[
        '/api/pairing/hello',
        '/api/pairing/finish',
        '/api/message',
      ]),
    );
    expect(paths.every((path) => path.startsWith('/api/')), isTrue);
  });
}

Future<TemporaryWebBatchImportPreview> _addAccounts(
  AppStateTemporaryWebBatchImportPort port,
  AppState state, {
  required String fileName,
  required List<String> rows,
}) => port.preview(
  _request(
    state,
    fileName: fileName,
    sourceId: 'cardock_accounts_template',
    contents: <String>[
      'account_key,platform_name,login_account,phone,email,password,url,notes',
      ...rows,
    ].join('\n'),
  ),
);

Future<TemporaryWebBatchImportPreview> _addSubscriptions(
  AppStateTemporaryWebBatchImportPort port,
  AppState state, {
  required String fileName,
  required List<String> rows,
}) => port.preview(
  _request(
    state,
    fileName: fileName,
    sourceId: 'cardock_subscriptions_template',
    contents: <String>[
      'account_key,plan_name,amount,currency,billing_cycle,subscription_start_date,next_renewal_date,auto_renew,payment_method,reminder_days,notes',
      ...rows,
    ].join('\n'),
  ),
);

TemporaryWebBatchImportRequest _request(
  AppState state, {
  required String fileName,
  required String sourceId,
  required String contents,
}) => TemporaryWebBatchImportRequest(
  fileName: fileName,
  bytes: Uint8List.fromList(utf8.encode(contents)),
  sourceId: sourceId,
  expectedRevision: state.localWebRevision,
  previewScope: TemporaryWebBatchPreviewScope.authorizedHistory,
);

Uint8List _fictionalSparseAccountsXlsx() {
  final files = <String, String>{
    'xl/workbook.xml': '''
<workbook xmlns:r='urn:r'><sheets><sheet r:id='rId1'/></sheets></workbook>''',
    'xl/_rels/workbook.xml.rels': '''
<Relationships><Relationship Id='rId1' Target='worksheets/sheet1.xml'/></Relationships>''',
    'xl/worksheets/sheet1.xml': '''
<worksheet><dimension ref='A1:H3'/><sheetData>
<row r='1'><c r='A1' t='inlineStr'><is><t>账号关联标识</t></is></c><c r='B1' t='inlineStr'><is><t>平台名称</t></is></c><c r='C1' t='inlineStr'><is><t>登录账号</t></is></c><c r='D1' t='inlineStr'><is><t>手机号</t></is></c><c r='E1' t='inlineStr'><is><t>邮箱</t></is></c><c r='F1' t='inlineStr'><is><t>密码</t></is></c><c r='G1' t='inlineStr'><is><t>网址</t></is></c><c r='H1' t='inlineStr'><is><t>备注</t></is></c></row>
<row r='2'><c r='A2' t='inlineStr'><is><t>fake-key-a</t></is></c><c r='B2' t='inlineStr'><is><t>虚构平台甲</t></is></c><c r='C2' t='inlineStr'><is><t>fake-user-a</t></is></c><c r='D2' t='inlineStr'><is><t></t></is></c><c r='E2' t='inlineStr'><is><t>a@example.invalid</t></is></c><c r='F2' t='inlineStr'><is><t>TEST-ONLY-WEB-A</t></is></c><c r='G2' t='inlineStr'><is><t>https://a.example.invalid</t></is></c><c r='H2' t='inlineStr'><is><t>虚构备注</t></is></c></row>
<row r='3'><c r='A3' t='inlineStr'><is><t>fake-key-b</t></is></c><c r='B3' t='inlineStr'><is><t>虚构平台乙</t></is></c><c r='C3' t='inlineStr'><is><t>fake-user-b</t></is></c><c r='D3' t='inlineStr'><is><t></t></is></c><c r='E3' t='inlineStr'><is><t>b@example.invalid</t></is></c><c r='F3' t='inlineStr'><is><t>TEST-ONLY-WEB-B</t></is></c><c r='G3' t='inlineStr'><is><t>https://b.example.invalid</t></is></c></row>
</sheetData></worksheet>''',
  };
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = Uint8List.fromList(utf8.encode(entry.value));
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
