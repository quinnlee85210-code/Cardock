import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/temporary_web/temporary_web_batch_import_port.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_controller.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_models.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_vault_gateway.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeGateway gateway;
  late _FakeTransport transport;
  late _FakeBatchPort port;
  late _MutableClock clock;
  late TemporaryWebSessionController controller;
  var requestSequence = 0;

  Map<String, Object?> command(
    String action,
    Map<String, Object?> body, {
    int expectedRevision = 7,
  }) => <String, Object?>{
    'action': action,
    'requestId': 'batch_flow_request_${requestSequence++}_0000',
    'expectedRevision': expectedRevision,
    'body': body,
  };

  setUp(() async {
    gateway = _FakeGateway();
    transport = _FakeTransport();
    port = _FakeBatchPort();
    clock = _MutableClock(DateTime.utc(2026, 8, 30, 8));
    controller = TemporaryWebSessionController(
      gateway,
      transport,
      const _FakeAddressProvider(),
      now: clock.call,
      monotonicNow: clock.monotonicCall,
      batchImportPort: port,
    );
    await controller.start(
      address: const TemporaryWebAddress(
        address: '192.168.43.1',
        interfaceName: 'wlan0',
      ),
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('配对前拒绝命令；10MiB 上限与完整分块只在认证会话进入预览', () async {
    final beforePair = await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(totalBytes: 1, totalChunks: 1),
      ),
    );
    expect(beforePair['status'], 'sessionEnded');
    transport.pair('192.168.43.2');

    final maximumChunks =
        (temporaryWebMaximumBatchImportBytes +
            temporaryWebBatchImportChunkBytes -
            1) ~/
        temporaryWebBatchImportChunkBytes;
    final maximum = await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(
          sessionId: 'batch_maximum_session_0001',
          totalBytes: temporaryWebMaximumBatchImportBytes,
          totalChunks: maximumChunks,
        ),
      ),
    );
    expect(maximum['status'], 'ok');

    final tooLarge = await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(
          sessionId: 'batch_too_large_session_01',
          totalBytes: temporaryWebMaximumBatchImportBytes + 1,
          totalChunks: maximumChunks,
        ),
      ),
    );
    expect(tooLarge['status'], 'rejected');
    expect(port.previewRequests, isEmpty);

    final bytes = Uint8List.fromList(
      utf8.encode('name,url\nFake,https://example.invalid'),
    );
    final start = await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(totalBytes: bytes.length, totalChunks: 1),
      ),
    );
    expect(start, containsPair('nextSequence', 0));
    final chunk = await transport.command(
      command(
        'batchImportUploadChunk',
        _chunkBody(sequence: 0, totalChunks: 1, bytes: bytes),
      ),
    );
    expect(chunk, containsPair('nextSequence', 1));
    final finish = await transport.command(
      command('batchImportUploadFinish', <String, Object?>{
        'sessionId': 'batch_upload_session_0001',
        'totalChunks': 1,
      }),
    );
    expect(finish['status'], 'ok');
    expect(port.previewRequests, hasLength(1));
    expect(port.capturedPreviewBytes, bytes);
    expect(
      ((finish['data']! as Map<String, Object?>)['rows']! as List<Object?>),
      hasLength(2),
    );
  });

  test('认证分块上传保留手机解析结构化错误码和可行动原因', () async {
    transport.pair('192.168.43.2');
    port.previewFailure = const TemporaryWebBatchImportException(
      code: 'tabular_invalidOfficeDocument',
      message: 'Office 文件结构无法解析；请确认是有效 XLSX/DOCX，并重新导出后再试。',
    );
    final bytes = Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04]);
    expect(
      (await transport.command(
        command(
          'batchImportUploadStart',
          _uploadStartBody(totalBytes: bytes.length, totalChunks: 1),
        ),
      ))['status'],
      'ok',
    );
    expect(
      (await transport.command(
        command(
          'batchImportUploadChunk',
          _chunkBody(sequence: 0, totalChunks: 1, bytes: bytes),
        ),
      ))['status'],
      'ok',
    );

    final finish = await transport.command(
      command('batchImportUploadFinish', <String, Object?>{
        'sessionId': 'batch_upload_session_0001',
        'totalChunks': 1,
      }),
    );

    expect(finish['status'], 'rejected');
    expect(finish['errorCode'], 'tabular_invalidOfficeDocument');
    expect(finish['message'], contains('重新导出后再试'));
  });

  test('乱序、重复、缺块与两分钟上传超时都销毁分块会话', () async {
    transport.pair('192.168.43.2');
    final twoChunkBytes = temporaryWebBatchImportChunkBytes + 1;
    final firstChunk = Uint8List(temporaryWebBatchImportChunkBytes);

    await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(totalBytes: twoChunkBytes, totalChunks: 2),
      ),
    );
    final outOfOrder = await transport.command(
      command(
        'batchImportUploadChunk',
        _chunkBody(sequence: 1, totalChunks: 2, bytes: Uint8List(1)),
      ),
    );
    expect(outOfOrder['status'], 'rejected');

    await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(totalBytes: twoChunkBytes, totalChunks: 2),
      ),
    );
    expect(
      (await transport.command(
        command(
          'batchImportUploadChunk',
          _chunkBody(sequence: 0, totalChunks: 2, bytes: firstChunk),
        ),
      ))['status'],
      'ok',
    );
    final duplicate = await transport.command(
      command(
        'batchImportUploadChunk',
        _chunkBody(sequence: 0, totalChunks: 2, bytes: firstChunk),
      ),
    );
    expect(duplicate['status'], 'rejected');

    await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(totalBytes: twoChunkBytes, totalChunks: 2),
      ),
    );
    await transport.command(
      command(
        'batchImportUploadChunk',
        _chunkBody(sequence: 0, totalChunks: 2, bytes: firstChunk),
      ),
    );
    final missing = await transport.command(
      command('batchImportUploadFinish', <String, Object?>{
        'sessionId': 'batch_upload_session_0001',
        'totalChunks': 2,
      }),
    );
    expect(missing['status'], 'rejected');

    await transport.command(
      command(
        'batchImportUploadStart',
        _uploadStartBody(totalBytes: 1, totalChunks: 1),
      ),
    );
    clock.advance(const Duration(minutes: 2, milliseconds: 1));
    final expired = await transport.command(
      command(
        'batchImportUploadChunk',
        _chunkBody(sequence: 0, totalChunks: 1, bytes: Uint8List(1)),
      ),
    );
    expect(expired['status'], 'rejected');
    expect(port.previewRequests, isEmpty);
  });

  test('同一会话连续加入双文件不清空首份状态，切换与移除决议完整转发', () async {
    transport.pair('192.168.43.2');

    Future<Map<String, Object?>> upload({
      required String sessionId,
      required String fileName,
      required String sourceId,
      required String contents,
    }) async {
      final bytes = Uint8List.fromList(utf8.encode(contents));
      final start = await transport.command(
        command(
          'batchImportUploadStart',
          _uploadStartBody(
            sessionId: sessionId,
            fileName: fileName,
            sourceId: sourceId,
            totalBytes: bytes.length,
            totalChunks: 1,
          ),
        ),
      );
      expect(start['status'], 'ok');
      final chunk = await transport.command(
        command(
          'batchImportUploadChunk',
          _chunkBody(
            sessionId: sessionId,
            sequence: 0,
            totalChunks: 1,
            bytes: bytes,
          ),
        ),
      );
      expect(chunk['status'], 'ok');
      return transport.command(
        command('batchImportUploadFinish', <String, Object?>{
          'sessionId': sessionId,
          'totalChunks': 1,
        }),
      );
    }

    final account = await upload(
      sessionId: 'batch_dual_account_0001',
      fileName: 'accounts.csv',
      sourceId: 'cardock_accounts_template',
      contents:
          'account_key,platform_name,login_account,phone,email,password,url,notes\n'
          'dual-key,Fake Account,user,,,,https://example.invalid,',
    );
    expect(account['status'], 'ok');
    final clearCountAfterAccount = port.clearCalls;

    final subscription = await upload(
      sessionId: 'batch_dual_subscription_01',
      fileName: 'subscriptions.csv',
      sourceId: 'cardock_subscriptions_template',
      contents:
          'account_key,plan_name,amount,currency,billing_cycle,subscription_start_date,next_renewal_date,auto_renew,payment_method,reminder_days,notes\n'
          'dual-key,Fake Plan,1.00,CNY,monthly,2026-08-01,2026-09-01,true,Fake,3,',
    );
    expect(subscription['status'], 'ok');
    expect(port.previewRequests, hasLength(2));
    expect(
      port.clearCalls,
      clearCountAfterAccount,
      reason: '第二份文件上传前不能清除第一份文件的权威内存状态。',
    );

    final activated = await transport.command(
      command('batchImportRevise', <String, Object?>{
        'previewToken': 'preview-uploaded',
        'mappingOverrides': <String, String>{},
        'rowPatches': <String, Map<String, String>>{},
        'defaultValues': <String, String>{},
        'activateDocumentKind': 'account',
      }),
    );
    expect(activated['status'], 'ok');
    expect(port.revisionRequests.last.activateDocumentKind, 'account');
    expect(port.revisionRequests.last.removeDocumentKind, isNull);

    final removed = await transport.command(
      command('batchImportRevise', <String, Object?>{
        'previewToken': 'preview-revised-1',
        'mappingOverrides': <String, String>{},
        'rowPatches': <String, Map<String, String>>{},
        'defaultValues': <String, String>{},
        'removeDocumentKind': 'subscription',
      }),
    );
    expect(removed['status'], 'ok');
    expect(port.revisionRequests.last.removeDocumentKind, 'subscription');
    expect(port.revisionRequests.last.activateDocumentKind, isNull);
  });

  test('修订映射、行编辑和默认值生成新 token，订阅 target 进入权威准备', () async {
    transport.pair('192.168.43.2');
    port.seedPreview('preview-original');

    final revised = await transport.command(
      command('batchImportRevise', <String, Object?>{
        'previewToken': 'preview-original',
        'mappingOverrides': <String, String>{
          '0': 'platformName',
          '1': 'ignore',
        },
        'rowPatches': <String, Map<String, String>>{
          'account-row-2': <String, String>{
            'platformName': 'Edited Fake',
            'url': 'https://edited.example.invalid',
          },
        },
        'defaultValues': <String, String>{'currency': 'USD'},
      }),
    );
    expect(revised['status'], 'ok');
    final revisedData = revised['data']! as Map<String, Object?>;
    expect(revisedData['previewToken'], 'preview-revised-1');
    expect(port.revisionRequests.single.mappingOverrides, <int, String?>{
      0: 'platformName',
      1: null,
    });
    expect(
      port.revisionRequests.single.rowPatches['account-row-2']?['url'],
      'https://edited.example.invalid',
    );
    expect(port.revisionRequests.single.defaultValues['currency'], 'USD');

    final pending = await transport.command(
      command('batchImportCommit', <String, Object?>{
        'previewToken': 'preview-revised-1',
        'selectedRowIds': <String>['account-row-2', 'subscription-row-2'],
        'duplicateResolutions': <String, String>{'account-row-2': 'skip'},
        'subscriptionAccountTargets': <String, String>{
          'subscription-row-2': 'existing-account-1',
        },
      }),
    );
    expect(
      pending['status'],
      'pendingPhoneApproval',
      reason: pending.toString(),
    );
    final preparedRequest = port.prepareRequests.single;
    expect(
      preparedRequest.subscriptionAccountTargets['subscription-row-2'],
      'existing-account-1',
    );
    final approval = controller.snapshot.pendingApprovals.single;
    expect(approval.kind, TemporaryWebApprovalKind.batchImport);
    expect(approval.detail, contains('新增账号 1'));
    expect(approval.detail, contains('更新账号 1'));
    expect(approval.detail, contains('正式订阅 1'));
    expect(approval.detail, contains('待完善草稿 1'));
    expect(approval.detail, contains('额度复核：通过'));
    expect(approval.detail, isNot(contains('TEST-ONLY-PASSWORD')));
  });

  test('手机批准再次核对并返回正式/草稿字段，stale revision 与 token 被拒绝', () async {
    transport.pair('192.168.43.2');
    port.seedPreview('preview-to-approve');
    final staleRevision = await transport.command(
      command(
        'batchImportCommit',
        _commitBody('preview-to-approve'),
        expectedRevision: 8,
      ),
    );
    expect(staleRevision['status'], 'conflict');
    expect(port.prepareRequests, isEmpty);

    final staleToken = await transport.command(
      command('batchImportRevise', <String, Object?>{
        'previewToken': 'stale-preview-token',
        'mappingOverrides': <String, String>{},
        'rowPatches': <String, Map<String, String>>{},
        'defaultValues': <String, String>{},
      }),
    );
    expect(staleToken['status'], 'rejected');

    final pending = await transport.command(
      command('batchImportCommit', _commitBody('preview-to-approve')),
    );
    expect(
      pending['status'],
      'pendingPhoneApproval',
      reason: pending.toString(),
    );
    final approvalId = pending['approvalId']! as String;
    await controller.approve(approvalId);
    expect(port.approveTokens, <String>['approval-token-1']);
    final result = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': approvalId,
    });
    expect(result['status'], 'committed');
    expect(result['formalSubscriptions'], 1);
    expect(result['pendingSubscriptionDrafts'], 1);
    expect(result['importedAccounts'], 1);
    expect(result['rollbackAvailable'], isTrue);
    expect(controller.snapshot.pendingApprovals, isEmpty);
    expect(port.clearCalls, greaterThan(0));
  });

  test('拒绝、审批超时、显式清空和停止会话均同步清敏', () async {
    transport.pair('192.168.43.2');

    port.seedPreview('preview-reject');
    var pending = await transport.command(
      command('batchImportCommit', _commitBody('preview-reject')),
    );
    expect(
      pending['status'],
      'pendingPhoneApproval',
      reason: pending.toString(),
    );
    var approvalId = pending['approvalId']! as String;
    var beforeClear = port.clearCalls;
    await controller.reject(approvalId);
    expect(port.clearCalls, greaterThan(beforeClear));
    var result = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': approvalId,
    });
    expect(result['status'], 'rejected');

    port.seedPreview('preview-expire');
    pending = await transport.command(
      command('batchImportCommit', _commitBody('preview-expire')),
    );
    expect(
      pending['status'],
      'pendingPhoneApproval',
      reason: pending.toString(),
    );
    approvalId = pending['approvalId']! as String;
    beforeClear = port.clearCalls;
    clock.advance(const Duration(minutes: 2, milliseconds: 1));
    await transport.command(<String, Object?>{'action': 'sessionStatus'});
    await controller.enforceTimeoutsAndNetworkState();
    expect(port.clearCalls, greaterThan(beforeClear));
    result = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': approvalId,
    });
    expect(result['status'], 'expired');

    port.seedPreview('preview-clear');
    beforeClear = port.clearCalls;
    final cleared = await transport.command(
      command('batchImportClear', <String, Object?>{}),
    );
    expect(cleared['status'], 'ok');
    expect(port.clearCalls, greaterThan(beforeClear));

    beforeClear = port.clearCalls;
    controller.stop(TemporaryWebStopReason.user);
    expect(port.clearCalls, greaterThan(beforeClear));
    expect(controller.snapshot.phase, TemporaryWebSessionPhase.stopped);
  });
}

Map<String, Object?> _uploadStartBody({
  String sessionId = 'batch_upload_session_0001',
  String fileName = 'fake-example.csv',
  String sourceId = 'generic_tabular',
  required int totalBytes,
  required int totalChunks,
}) => <String, Object?>{
  'sessionId': sessionId,
  'fileName': fileName,
  'sourceId': sourceId,
  'totalBytes': totalBytes,
  'totalChunks': totalChunks,
};

Map<String, Object?> _chunkBody({
  String sessionId = 'batch_upload_session_0001',
  required int sequence,
  required int totalChunks,
  required Uint8List bytes,
}) => <String, Object?>{
  'sessionId': sessionId,
  'sequence': sequence,
  'totalChunks': totalChunks,
  'contentBase64': base64Encode(bytes),
};

Map<String, Object?> _commitBody(String previewToken) => <String, Object?>{
  'previewToken': previewToken,
  'selectedRowIds': <String>['account-row-2', 'subscription-row-2'],
  'duplicateResolutions': <String, String>{'account-row-2': 'skip'},
  'subscriptionAccountTargets': <String, String>{
    'subscription-row-2': 'existing-account-1',
  },
};

final class _FakeBatchPort implements TemporaryWebBatchImportPort {
  bool available = true;
  int clearCalls = 0;
  int _revisionNumber = 0;
  String? _previewToken;
  final List<TemporaryWebBatchImportRequest> previewRequests =
      <TemporaryWebBatchImportRequest>[];
  final List<TemporaryWebBatchRevisionRequest> revisionRequests =
      <TemporaryWebBatchRevisionRequest>[];
  final List<TemporaryWebBatchCommitRequest> prepareRequests =
      <TemporaryWebBatchCommitRequest>[];
  final List<String> approveTokens = <String>[];
  Uint8List? capturedPreviewBytes;
  Object? previewFailure;

  @override
  bool get isAvailable => available;

  void seedPreview(String token) {
    _previewToken = token;
  }

  @override
  Future<TemporaryWebBatchImportPreview> preview(
    TemporaryWebBatchImportRequest request,
  ) async {
    final failure = previewFailure;
    if (failure != null) throw failure;
    previewRequests.add(request);
    capturedPreviewBytes = Uint8List.fromList(request.bytes);
    _previewToken = 'preview-uploaded';
    return _preview(_previewToken!);
  }

  @override
  Future<TemporaryWebBatchImportPreview> revisePreview(
    TemporaryWebBatchRevisionRequest request,
  ) async {
    if (request.previewToken != _previewToken ||
        request.expectedRevision != 7) {
      throw const FormatException('stale preview');
    }
    revisionRequests.add(request);
    _revisionNumber += 1;
    _previewToken = 'preview-revised-$_revisionNumber';
    return _preview(_previewToken!);
  }

  @override
  Future<TemporaryWebBatchPreparedCommit> prepareCommit(
    TemporaryWebBatchCommitRequest request,
  ) async {
    if (request.previewToken != _previewToken ||
        request.expectedRevision != 7) {
      throw const FormatException('stale preview');
    }
    prepareRequests.add(request);
    return TemporaryWebBatchPreparedCommit(
      approvalToken: 'approval-token-${prepareRequests.length}',
      expectedRevision: 7,
      selectedRecordCount: request.selectedRowIds.length,
      newAccountCount: 1,
      updatedAccountCount: 1,
      skippedAccountCount: 0,
      formalSubscriptionCount: 1,
      pendingSubscriptionDraftCount: 1,
      unsupportedItemCount: 0,
      quotaAllowed: true,
      remainingAccounts: 12,
      remainingSubscriptions: 3,
    );
  }

  @override
  Future<TemporaryWebBatchCommitResult> approveCommit(
    String approvalToken, {
    required int expectedRevision,
  }) async {
    if (expectedRevision != 7 || !approvalToken.startsWith('approval-token-')) {
      throw const FormatException('stale approval');
    }
    approveTokens.add(approvalToken);
    return const TemporaryWebBatchCommitResult(
      importedAccounts: 1,
      formalSubscriptions: 1,
      pendingSubscriptionDrafts: 1,
      mergedRecords: 1,
      skippedRecords: 0,
      unsupportedRecords: 0,
      rollbackAvailable: true,
    );
  }

  @override
  void clearSensitiveMemory() {
    clearCalls += 1;
    _previewToken = null;
    capturedPreviewBytes = null;
  }

  TemporaryWebBatchImportPreview _preview(String token) =>
      TemporaryWebBatchImportPreview(
        previewToken: token,
        revision: 7,
        sourceLabel: 'Fake source',
        detectedFormat: 'UTF-8 CSV',
        mappings: const <TemporaryWebBatchImportMapping>[
          TemporaryWebBatchImportMapping(
            columnIndex: 0,
            sourceLabel: 'name',
            targetField: 'platformName',
            availableTargets: <String>['platformName', 'url'],
          ),
        ],
        rows: const <TemporaryWebBatchImportRow>[
          TemporaryWebBatchImportRow(
            id: 'account-row-2',
            kind: 'account',
            title: 'Fake Account',
            subtitle: 'fake@example.invalid',
            passwordStatus: 'encryptedForImport',
            defaultResolution: 'skip',
            originalRowNumber: 2,
            fields: <String, String>{
              'platformName': 'Fake Account',
              'url': 'https://example.invalid',
            },
          ),
          TemporaryWebBatchImportRow(
            id: 'subscription-row-2',
            kind: 'subscription',
            title: 'Fake Pro',
            subtitle: 'USD',
            passwordStatus: 'absent',
            defaultResolution: 'skip',
            originalRowNumber: 2,
            subscriptionTargetRequired: true,
            subscriptionTargetOptions: <String, String>{
              'existing-account-1': 'Existing Fake',
            },
            fields: <String, String>{'currency': 'USD'},
          ),
        ],
      );
}

final class _FakeGateway implements TemporaryWebVaultGateway {
  final AccountRecord _existingAccount = AccountRecord.fromDraft(
    id: 'existing-account-1',
    draft: AccountDraft(
      platformName: 'Existing Fake',
      loginAccount: 'existing@example.invalid',
    ),
  );

  @override
  bool get isEligibleForTemporaryWebSession => true;

  @override
  String? get vaultBindingId => 'fake-vault';

  @override
  int get revision => 7;

  @override
  TemporaryWebVaultRecords readRecords() => TemporaryWebVaultRecords(
    revision: 7,
    accounts: <AccountRecord>[_existingAccount],
    subscriptions: const <SubscriptionRecord>[],
  );

  @override
  Future<TemporaryWebMutationResult> addAccount(AccountDraft draft) async =>
      TemporaryWebMutationResult.rejected(revision: 7, message: 'unused');

  @override
  Future<TemporaryWebMutationResult> updateAccount({
    required String accountId,
    required AccountDraft draft,
    required AccountPasswordUpdateMode passwordMode,
  }) async =>
      TemporaryWebMutationResult.rejected(revision: 7, message: 'unused');

  @override
  Future<TemporaryWebMutationResult> deleteAccount(String accountId) async =>
      TemporaryWebMutationResult.rejected(revision: 7, message: 'unused');

  @override
  Future<TemporaryWebMutationResult> addSubscription(
    SubscriptionDraft draft,
  ) async =>
      TemporaryWebMutationResult.rejected(revision: 7, message: 'unused');

  @override
  Future<TemporaryWebMutationResult> updateSubscription({
    required String subscriptionId,
    required SubscriptionDraft draft,
  }) async =>
      TemporaryWebMutationResult.rejected(revision: 7, message: 'unused');

  @override
  Future<TemporaryWebMutationResult> deleteSubscription(
    String subscriptionId,
  ) async =>
      TemporaryWebMutationResult.rejected(revision: 7, message: 'unused');
}

final class _FakeAddressProvider implements TemporaryWebAddressProvider {
  const _FakeAddressProvider();

  @override
  Future<bool> isStillAvailable(String address) async =>
      address == '192.168.43.1';

  @override
  Future<List<TemporaryWebAddress>> listPrivateIpv4Addresses() async =>
      const <TemporaryWebAddress>[
        TemporaryWebAddress(address: '192.168.43.1', interfaceName: 'wlan0'),
      ];
}

final class _FakeTransport implements TemporaryWebTransport {
  TemporaryWebCommandHandler? _handler;
  void Function(String)? _onPaired;

  @override
  void revoke() {}

  @override
  Future<TemporaryWebTransportBinding> start({
    required String address,
    required TemporaryWebCommandHandler onCommand,
    required void Function(String remoteAddress) onPaired,
    required void Function(Object error) onFatalError,
  }) async {
    _handler = onCommand;
    _onPaired = onPaired;
    return const TemporaryWebTransportBinding(
      port: 43123,
      formattedConnectionCode: 'ABCDEFGH',
    );
  }

  void pair(String address) => _onPaired!(address);

  Future<Map<String, Object?>> command(Map<String, Object?> value) =>
      _handler!(value, '192.168.43.2');

  @override
  Future<void> stop() async {}
}

final class _MutableClock {
  _MutableClock(this.value);

  DateTime value;
  Duration monotonicValue = Duration.zero;

  DateTime call() => value;
  Duration monotonicCall() => monotonicValue;

  void advance(Duration duration) {
    value = value.add(duration);
    monotonicValue += duration;
  }
}
