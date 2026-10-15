import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/temporary_web/temporary_web_batch_import_port.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_controller.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_models.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_vault_gateway.dart';
import 'package:account_subscription_manager/core/platform/temporary_web_runtime_keeper.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeGateway gateway;
  late _FakeTransport transport;
  late _FakeAddressProvider addresses;
  late _MutableClock clock;
  late TemporaryWebSessionController controller;

  setUp(() {
    gateway = _FakeGateway(
      accounts: <AccountRecord>[
        AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(
            platformName: '历史平台',
            category: '币圈',
            loginAccount: 'old@example.com',
            password: 'old-secret',
            notes: '历史备注',
          ),
        ),
      ],
    );
    transport = _FakeTransport();
    addresses = _FakeAddressProvider();
    clock = _MutableClock(DateTime.utc(2026, 8, 1, 8));
    controller = TemporaryWebSessionController(
      gateway,
      transport,
      addresses,
      now: clock.call,
      monotonicNow: clock.monotonicCall,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('自定义敏感字段只手机逐次批准且仅一次消费，消费不续期', () async {
    gateway._accounts[0] = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '历史平台',
        customFields: [
          AccountCustomField(
            id: 'field-1',
            name: '私密备注',
            type: AccountCustomFieldType.sensitiveText,
            value: 'TEST-ONLY-CUSTOM-SECRET',
            order: 0,
          ),
        ],
      ),
    );
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.details,
      ),
    );
    final snapshot = await transport.command({'action': 'snapshot'});
    expect(jsonEncode(snapshot), isNot(contains('TEST-ONLY-CUSTOM-SECRET')));
    final pending = await transport.command({
      'action': 'requestCustomField',
      'requestId': 'request_custom_secret_01',
      'expectedRevision': 7,
      'body': {'id': 'account-1', 'fieldId': 'field-1'},
    });
    expect(jsonEncode(pending), isNot(contains('TEST-ONLY-CUSTOM-SECRET')));
    expect(
      controller.snapshot.pendingApprovals.single.kind,
      TemporaryWebApprovalKind.revealCustomField,
    );
    await controller.approve(pending['approvalId']! as String);
    clock.advance(const Duration(seconds: 29));
    final result = await transport.command({
      'action': 'approvalResult',
      'approvalId': pending['approvalId'],
    });
    expect(result['secret'], 'TEST-ONLY-CUSTOM-SECRET');
    expect(result['visibleForMilliseconds'], 1000);
    expect(
      (await transport.command({
        'action': 'approvalResult',
        'approvalId': pending['approvalId'],
      }))['status'],
      'notFound',
    );
    final again = await transport.command({
      'action': 'requestCustomField',
      'requestId': 'request_custom_secret_02',
      'expectedRevision': 7,
      'body': {'id': 'account-1', 'fieldId': 'field-1'},
    });
    expect(again['status'], 'pendingPhoneApproval');
    await controller.reject(again['approvalId']! as String);
    expect(
      jsonEncode(
        await transport.command({
          'action': 'approvalResult',
          'approvalId': again['approvalId'],
        }),
      ),
      isNot(contains('TEST-ONLY-CUSTOM-SECRET')),
    );
  });

  test('字段保存经手机确认且保留隐藏历史值；显式替换无需先显示', () async {
    gateway._accounts[0] = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '历史平台',
        customFields: [
          AccountCustomField(
            id: 'field-1',
            name: '敏感字段',
            type: AccountCustomFieldType.sensitiveText,
            value: 'TEST-ONLY-OLD',
            order: 0,
          ),
        ],
      ),
    );
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.details,
        allowHistoryEditing: true,
      ),
    );
    final preserve = await transport.command({
      'action': 'updateAccount',
      'requestId': 'request_preserve_field_01',
      'expectedRevision': 7,
      'body': {
        'id': 'account-1',
        'platformName': '历史平台',
        'passwordMode': 'preserve',
        'customFields': [
          {
            'id': 'field-1',
            'name': '新名称',
            'type': 'sensitive_text',
            'value': '',
            'order': 0,
            'revision': 0,
            'valueState': 'redacted',
          },
        ],
      },
    });
    expect(gateway._accounts.single.customFields.single.name, '敏感字段');
    expect(
      (await _approveResult(controller, transport, preserve))['status'],
      'committed',
    );
    expect(gateway._accounts.single.customFields.single.value, 'TEST-ONLY-OLD');
    final replace = await transport.command({
      'action': 'updateAccount',
      'requestId': 'request_replace_field_01',
      'expectedRevision': 8,
      'body': {
        'id': 'account-1',
        'platformName': '历史平台',
        'passwordMode': 'preserve',
        'customFields': [
          {
            'id': 'field-1',
            'name': '新名称',
            'type': 'sensitive_text',
            'value': 'TEST-ONLY-NEW',
            'order': 0,
            'revision': 0,
          },
        ],
      },
    });
    expect(jsonEncode(replace), isNot(contains('TEST-ONLY-OLD')));
    expect(
      (await _approveResult(controller, transport, replace))['status'],
      'committed',
    );
    expect(gateway._accounts.single.customFields.single.value, 'TEST-ONLY-NEW');
  });

  test('字段隐藏值不能借类型降级暴露；保存审批revision变化零写', () async {
    gateway._accounts[0] = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '历史平台',
        customFields: [
          AccountCustomField(
            id: 'field-1',
            name: 'Secret',
            type: AccountCustomFieldType.sensitiveText,
            value: 'TEST-ONLY-OLD',
            order: 0,
          ),
        ],
      ),
    );
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.details,
        allowHistoryEditing: true,
      ),
    );
    final invalid = await transport.command({
      'action': 'updateAccount',
      'requestId': 'request_downgrade_field_01',
      'expectedRevision': 7,
      'body': {
        'id': 'account-1',
        'platformName': '历史平台',
        'passwordMode': 'preserve',
        'customFields': [
          {
            'id': 'field-1',
            'name': 'Secret',
            'type': 'text',
            'value': '',
            'order': 0,
            'revision': 0,
            'valueState': 'redacted',
          },
        ],
      },
    });
    expect(invalid['status'], 'rejected');
    final pending = await transport.command({
      'action': 'addAccount',
      'requestId': 'request_stale_field_01',
      'expectedRevision': 7,
      'body': {
        'platformName': 'New',
        'customFields': [
          {
            'id': 'field-2',
            'name': 'Field',
            'type': 'text',
            'value': 'x',
            'order': 0,
            'revision': 0,
          },
        ],
      },
    });
    expect(gateway.addAccountCalls, 0);
    gateway.advanceRevision();
    expect(
      (await _approveResult(controller, transport, pending))['status'],
      'stale',
    );
    expect(gateway.addAccountCalls, 0);
    expect(gateway._accounts.length, 1);
  });

  test('未授权历史字段无法申请；锁定销毁已批准敏感结果', () async {
    gateway._accounts[0] = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '历史平台',
        customFields: [
          AccountCustomField(
            id: 'field-1',
            name: 'Secret',
            type: AccountCustomFieldType.sensitiveText,
            value: 'TEST-ONLY-SECRET',
            order: 0,
          ),
        ],
      ),
    );
    await _startAndPair(controller, transport);
    final rejected = await transport.command({
      'action': 'requestCustomField',
      'requestId': 'request_hidden_field_01',
      'expectedRevision': 7,
      'body': {'id': 'account-1', 'fieldId': 'field-1'},
    });
    expect(rejected['status'], 'rejected');
    expect(controller.snapshot.pendingApprovals, isEmpty);
    controller.stop(TemporaryWebStopReason.user);
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.details,
      ),
    );
    final pending = await transport.command({
      'action': 'requestCustomField',
      'requestId': 'request_lock_field_01',
      'expectedRevision': 7,
      'body': {'id': 'account-1', 'fieldId': 'field-1'},
    });
    await controller.approve(pending['approvalId']! as String);
    gateway.accessStateValue =
        TemporaryWebVaultAccessState.temporarilyUnavailable;
    controller.handleVaultAccessStateChanged();
    gateway.accessStateValue = TemporaryWebVaultAccessState.ready;
    controller.handleVaultAccessStateChanged();
    final result = await transport.command({
      'action': 'approvalResult',
      'approvalId': pending['approvalId'],
    });
    expect(result['status'], 'notFound');
    expect(jsonEncode(result), isNot(contains('TEST-ONLY-SECRET')));
  });

  test('仅本次模式对空库、GitHub 与其他历史只传相同的空授权投影', () async {
    final variants = <List<AccountRecord>>[
      const <AccountRecord>[],
      <AccountRecord>[
        AccountRecord.fromDraft(
          id: 'github-history',
          draft: AccountDraft(
            platformName: 'GitHub',
            loginAccount: 'hidden-github@example.invalid',
            password: 'TEST-ONLY-HIDDEN-GITHUB',
          ),
        ),
      ],
      <AccountRecord>[
        AccountRecord.fromDraft(
          id: 'other-history',
          draft: AccountDraft(
            platformName: 'Other hidden service',
            loginAccount: 'hidden-other@example.invalid',
            password: 'TEST-ONLY-HIDDEN-OTHER',
          ),
        ),
      ],
    ];
    final projections = <Map<String, Object?>>[];
    for (var index = 0; index < variants.length; index += 1) {
      controller.dispose();
      gateway = _FakeGateway(accounts: variants[index]);
      transport = _FakeTransport();
      final batchPort = _CapturingBatchImportPort();
      controller = TemporaryWebSessionController(
        gateway,
        transport,
        addresses,
        now: clock.call,
        monotonicNow: clock.monotonicCall,
        batchImportPort: batchPort,
      );
      await _startAndPair(controller, transport);
      await _uploadSingleChunkBatch(transport, expectedRevision: 7);
      final request = batchPort.lastRequest!;
      expect(
        request.previewScope,
        TemporaryWebBatchPreviewScope.currentSessionAuthorizedOnly,
      );
      projections.add(<String, Object?>{
        'accounts': request.visibleAccounts.map((item) => item.id).toList(),
        'targets': request.visibleAccountTargets,
      });
    }

    expect(projections[0], projections[1]);
    expect(projections[1], projections[2]);
    expect(projections.first['accounts'], isEmpty);
    expect(projections.first['targets'], isEmpty);
    final serialized = jsonEncode(projections);
    expect(serialized, isNot(contains('GitHub')));
    expect(serialized, isNot(contains('hidden-')));
    expect(serialized, isNot(contains('TEST-ONLY-HIDDEN')));
  });

  test('显式历史摘要模式只给批量目标平台摘要，仍不下发登录名或密码', () async {
    controller.dispose();
    final batchPort = _CapturingBatchImportPort();
    controller = TemporaryWebSessionController(
      gateway,
      transport,
      addresses,
      now: clock.call,
      monotonicNow: clock.monotonicCall,
      batchImportPort: batchPort,
    );
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );

    await _uploadSingleChunkBatch(transport, expectedRevision: 7);

    final targets = batchPort.lastRequest!.visibleAccountTargets;
    expect(targets, <String, String>{'account-1': '历史平台'});
    expect(
      batchPort.lastRequest!.previewScope,
      TemporaryWebBatchPreviewScope.authorizedHistory,
    );
    final visible = batchPort.lastRequest!.visibleAccounts.single;
    expect(visible.id, 'account-1');
    expect(visible.platformName, '历史平台');
    expect(visible.loginAccount, isEmpty);
    expect(visible.phone, isEmpty);
    expect(visible.email, isEmpty);
    expect(visible.url, isEmpty);
    expect(visible.notes, isEmpty);
    final serialized = jsonEncode(targets);
    expect(serialized, isNot(contains('old@example.com')));
    expect(serialized, isNot(contains('old-secret')));
  });

  test('默认 5 分钟且仅本次；新增须手机审批后才可编辑删除', () async {
    await _startAndPair(controller, transport);

    final initial = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    final initialData = initial['data']! as Map<String, Object?>;
    expect(initialData['accounts'], isEmpty);
    expect(initialData['accountCategories'], <String>[
      ...accountCategories,
      '币圈',
    ]);

    final pending = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': 'request_add_account_0001',
      'expectedRevision': 7,
      'body': <String, Object?>{
        'platformName': '本次平台',
        'loginAccount': 'new@example.com',
        'password': 'new-secret',
      },
    });
    expect(pending['status'], 'pendingPhoneApproval');
    expect(gateway.addAccountCalls, 0);
    final added = await _approveResult(controller, transport, pending);
    expect(added['status'], 'committed');
    expect(gateway.addAccountCalls, 1);

    final duplicate = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': 'request_add_account_0001',
      'expectedRevision': 7,
      'body': <String, Object?>{'platformName': '不应再次写入'},
    });
    expect(duplicate, pending);
    expect(gateway.addAccountCalls, 1);

    final snapshot = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    final data = snapshot['data']! as Map<String, Object?>;
    final accounts = data['accounts']! as List<Object?>;
    expect(accounts, hasLength(1));
    expect(
      (accounts.single! as Map<String, Object?>)['password'],
      'new-secret',
    );

    final deleted = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_delete_account_01',
      'expectedRevision': 8,
      'body': <String, Object?>{'id': added['recordId']},
    });
    expect(deleted['status'], 'committed');
    expect(controller.snapshot.pendingApprovals, isEmpty);
  });

  test('仅本次模式无需可见账号也能新增并投影独立订阅', () async {
    await _startAndPair(controller, transport);

    final added = await transport.command(<String, Object?>{
      'action': 'addSubscription',
      'requestId': 'request_add_standalone_01',
      'expectedRevision': 7,
      'body': _subscriptionBody(accountId: null),
    });
    expect(added['status'], 'committed');

    final snapshot = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    final data = snapshot['data']! as Map<String, Object?>;
    expect(data['accounts'], isEmpty);
    final subscription =
        (data['subscriptions']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(subscription['accountId'], isNull);
    expect(subscription['serviceName'], '测试订阅');
  });

  test('历史摘要不泄露详情或密码，历史删除必须手机确认', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );

    final snapshot = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    final data = snapshot['data']! as Map<String, Object?>;
    final account =
        (data['accounts']! as List<Object?>).single! as Map<String, Object?>;
    expect(account['platformName'], '历史平台');
    expect(account, isNot(contains('loginAccount')));
    expect(account, isNot(contains('notes')));
    expect(account, isNot(contains('password')));
    expect(account, isNot(contains('hasPassword')));

    final pending = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_delete_history_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    expect(pending['status'], 'pendingPhoneApproval');
    expect(gateway.deleteAccountCalls, 0);
    expect(controller.snapshot.pendingApprovals, hasLength(1));

    await controller.approve(pending['approvalId']! as String);
    expect(gateway.deleteAccountCalls, 1);
    final result = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': pending['approvalId'],
    });
    expect(result['status'], 'committed');
  });

  test('历史编辑和历史密码显示是两个独立权限', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.details,
        allowHistoryEditing: true,
        allowHistoricalPasswordReveal: false,
      ),
    );

    final edited = await transport.command(<String, Object?>{
      'action': 'updateAccount',
      'requestId': 'request_edit_history_0001',
      'expectedRevision': 7,
      'body': <String, Object?>{
        'id': 'account-1',
        'platformName': '历史平台已改',
        'loginAccount': 'old@example.com',
        'passwordMode': 'preserve',
      },
    });
    expect(edited['status'], 'committed');

    final denied = await transport.command(<String, Object?>{
      'action': 'requestHistoricalPassword',
      'requestId': 'request_password_denied_1',
      'expectedRevision': 8,
      'body': <String, Object?>{'id': 'account-1'},
    });
    expect(denied['status'], 'rejected');
    expect(controller.snapshot.pendingApprovals, isEmpty);
  });

  test('允许历史密码后仍需手机逐次确认，结果只读取一次', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.details,
        allowHistoricalPasswordReveal: true,
      ),
    );

    final pending = await transport.command(<String, Object?>{
      'action': 'requestHistoricalPassword',
      'requestId': 'request_password_reveal_1',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    expect(pending['status'], 'pendingPhoneApproval');
    await controller.approve(pending['approvalId']! as String);

    final approved = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': pending['approvalId'],
    });
    expect(approved['status'], 'approved');
    expect(approved['password'], 'old-secret');
    expect(approved['visibleForMilliseconds'], 30000);
    expect(approved, isNot(contains('visibleUntil')));

    final consumed = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': pending['approvalId'],
    });
    expect(consumed['status'], 'notFound');
  });

  test('所选 1/30 分钟均从服务开启计时且请求不会续期', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        connectionDuration: Duration(minutes: 1),
      ),
    );
    clock.advance(const Duration(seconds: 59));
    expect(
      (await transport.command(<String, Object?>{
        'action': 'sessionStatus',
      }))['status'],
      'ok',
    );
    clock.advance(const Duration(seconds: 1));
    await controller.enforceTimeoutsAndNetworkState();
    expect(
      controller.snapshot.stopReason,
      TemporaryWebStopReason.absoluteTimeout,
    );

    controller.dispose();
    controller = TemporaryWebSessionController(
      gateway,
      transport = _FakeTransport(),
      addresses,
      now: clock.call,
      monotonicNow: clock.monotonicCall,
    );
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        connectionDuration: Duration(minutes: 30),
      ),
    );
    for (var index = 0; index < 3; index += 1) {
      clock.advance(const Duration(minutes: 9));
      await transport.command(<String, Object?>{'action': 'snapshot'});
    }
    clock.advance(const Duration(minutes: 3));
    await controller.enforceTimeoutsAndNetworkState();
    expect(
      controller.snapshot.stopReason,
      TemporaryWebStopReason.absoluteTimeout,
    );
  });

  test('一次性配对拒绝与普通传输故障分开记录', () async {
    await controller.start(
      address: const TemporaryWebAddress(
        address: '192.168.43.1',
        interfaceName: 'wlan0',
      ),
      policy: const TemporaryWebSessionPolicy(),
    );

    transport.fail(const TemporaryWebPairingRejectedException());

    expect(controller.snapshot.isRunning, isFalse);
    expect(
      controller.snapshot.stopReason,
      TemporaryWebStopReason.pairingRejected,
    );
    expect(controller.snapshot.errorMessage, contains('连接码验证失败'));
  });

  test('断开后本次记录立即按历史记录处理', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    final pending = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': 'request_add_then_disconnect',
      'expectedRevision': 7,
      'body': <String, Object?>{
        'platformName': '会话创建',
        'password': 'session-secret',
      },
    });
    final added = await _approveResult(controller, transport, pending);
    expect(added['status'], 'committed');
    controller.stop(TemporaryWebStopReason.user);

    transport = _FakeTransport();
    controller.dispose();
    controller = TemporaryWebSessionController(
      gateway,
      transport,
      addresses,
      now: clock.call,
      monotonicNow: clock.monotonicCall,
    );
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    final snapshot = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    final accounts =
        (snapshot['data']! as Map<String, Object?>)['accounts']!
            as List<Object?>;
    final reconnected = accounts
        .map((item) => item! as Map<String, Object?>)
        .where((item) => item['id'] == added['recordId'])
        .single;
    expect(reconnected['isCurrentSession'], isFalse);
    expect(reconnected, isNot(contains('password')));
    expect(reconnected['deleteNeedsPhoneApproval'], isTrue);
  });

  test('旧会话写入返回后不得污染新会话本次集合或结果缓存', () async {
    await _startAndPair(controller, transport);
    final writeGate = Completer<void>();
    gateway.addAccountGate = writeGate;
    final oldRequest = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': 'request_cross_session_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'platformName': '旧会话延迟写入'},
    });
    final oldWrite = controller.approve(oldRequest['approvalId']! as String);
    await pumpEventQueue();
    expect(gateway.addAccountCalls, 1);
    expect(controller.isPerformingControlledOperation, isTrue);
    clock.advance(const Duration(seconds: 9));
    await controller.enforceTimeoutsAndNetworkState();
    expect(controller.snapshot.phase, TemporaryWebSessionPhase.connected);

    controller.stop(TemporaryWebStopReason.user);
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    gateway.addAccountGate = null;
    writeGate.complete();
    await oldWrite;
    final oldResult = await transport.command({
      'action': 'approvalResult',
      'approvalId': oldRequest['approvalId'],
    });
    expect(oldResult['status'], 'notFound');
    expect(controller.isPerformingControlledOperation, isFalse);

    final snapshot = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    final records =
        (snapshot['data']! as Map<String, Object?>)['accounts']!
            as List<Object?>;
    final delayedRecord = records
        .map((item) => item! as Map<String, Object?>)
        .where((item) => item['platformName'] == '旧会话延迟写入')
        .single;
    expect(delayedRecord['isCurrentSession'], isFalse);

    final retried = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': 'request_cross_session_01',
      'expectedRevision': 8,
      'body': <String, Object?>{'platformName': '新会话重用请求号'},
    });
    expect(
      (await _approveResult(controller, transport, retried))['status'],
      'committed',
    );
    expect(gateway.addAccountCalls, 2);
  });

  test('手机审批与网页命令串行，旧审批不得写入新会话', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    final pending = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_delayed_approval_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    final approvalId = pending['approvalId']! as String;
    final deleteGate = Completer<void>();
    gateway.deleteAccountGate = deleteGate;
    final approval = controller.approve(approvalId);
    await pumpEventQueue();
    expect(gateway.deleteAccountCalls, 1);
    expect(controller.isPerformingControlledOperation, isTrue);

    var queuedCommandCompleted = false;
    final queuedCommand = transport
        .command(<String, Object?>{'action': 'snapshot'})
        .then((value) {
          queuedCommandCompleted = true;
          return value;
        });
    await pumpEventQueue();
    expect(queuedCommandCompleted, isFalse);

    controller.stop(TemporaryWebStopReason.user);
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    gateway.deleteAccountGate = null;
    deleteGate.complete();
    await approval;
    await queuedCommand;
    expect(controller.isPerformingControlledOperation, isFalse);

    final leakedResult = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': approvalId,
    });
    expect(leakedResult['status'], 'notFound');
  });

  test('服务端拒绝被篡改网页越过历史可见范围和详情编辑边界', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.currentSessionOnly,
        allowHistoryEditing: true,
        allowHistoricalPasswordReveal: true,
      ),
    );

    final hiddenEdit = await transport.command(<String, Object?>{
      'action': 'updateAccount',
      'requestId': 'request_hidden_edit_0001',
      'expectedRevision': 7,
      'body': <String, Object?>{
        'id': 'account-1',
        'platformName': '不应修改',
        'passwordMode': 'preserve',
      },
    });
    final hiddenDelete = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_hidden_delete_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    final hiddenPassword = await transport.command(<String, Object?>{
      'action': 'requestHistoricalPassword',
      'requestId': 'request_hidden_password1',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    final hiddenAssociation = await transport.command(<String, Object?>{
      'action': 'addSubscription',
      'requestId': 'request_hidden_account_01',
      'expectedRevision': 7,
      'body': _subscriptionBody(accountId: 'account-1'),
    });

    for (final result in <Map<String, Object?>>[
      hiddenEdit,
      hiddenDelete,
      hiddenPassword,
      hiddenAssociation,
    ]) {
      expect(result['status'], 'rejected');
    }
    expect(gateway.deleteAccountCalls, 0);
    expect(controller.snapshot.pendingApprovals, isEmpty);

    controller.stop(TemporaryWebStopReason.user);
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
        allowHistoryEditing: true,
      ),
    );
    final summaryOverwrite = await transport.command(<String, Object?>{
      'action': 'updateAccount',
      'requestId': 'request_summary_edit_001',
      'expectedRevision': 7,
      'body': <String, Object?>{
        'id': 'account-1',
        'platformName': '不应覆盖详情',
        'passwordMode': 'preserve',
      },
    });
    expect(summaryOverwrite['status'], 'rejected');
    expect(gateway.readRecords().accounts.single.platformName, '历史平台');
  });

  test('状态与活动请求都不续期并返回单调连接时长余量', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        connectionDuration: Duration(minutes: 1),
      ),
    );
    final initial = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    final timeouts =
        (initial['data']! as Map<String, Object?>)['timeouts']!
            as Map<String, Object?>;
    expect(timeouts['connectionDurationMilliseconds'], 60000);
    expect(timeouts['connectionRemainingMilliseconds'], 60000);

    clock.advance(const Duration(seconds: 40));
    final heartbeat = await transport.command(<String, Object?>{
      'action': 'sessionStatus',
    });
    final heartbeatTimeouts = heartbeat['timeouts']! as Map<String, Object?>;
    expect(heartbeatTimeouts['connectionRemainingMilliseconds'], 20000);

    final activity = await transport.command(<String, Object?>{
      'action': 'activity',
    });
    final activityTimeouts = activity['timeouts']! as Map<String, Object?>;
    expect(activityTimeouts['connectionRemainingMilliseconds'], 20000);

    clock.advance(const Duration(seconds: 20));
    final expired = await transport.command(<String, Object?>{
      'action': 'activity',
    });
    expect(expired['status'], 'sessionEnded');
    expect(
      controller.snapshot.stopReason,
      TemporaryWebStopReason.absoluteTimeout,
    );
  });

  test('没有电脑心跳且局域网地址暂不可见时仍保持到所选时长', () async {
    await controller.start(
      address: const TemporaryWebAddress(
        address: '192.168.43.1',
        interfaceName: 'wlan0',
      ),
      policy: const TemporaryWebSessionPolicy(
        connectionDuration: Duration(minutes: 1),
      ),
    );
    clock.advance(const Duration(seconds: 20));
    await controller.enforceTimeoutsAndNetworkState();
    expect(
      controller.snapshot.phase,
      TemporaryWebSessionPhase.waitingForPairing,
    );
    transport.pair('192.168.43.2');

    addresses.available = false;
    clock.advance(const Duration(seconds: 39));
    await controller.enforceTimeoutsAndNetworkState();
    expect(controller.snapshot.phase, TemporaryWebSessionPhase.connected);

    clock.advance(const Duration(seconds: 1));
    await controller.enforceTimeoutsAndNetworkState();

    expect(controller.snapshot.phase, TemporaryWebSessionPhase.stopped);
    expect(
      controller.snapshot.stopReason,
      TemporaryWebStopReason.absoluteTimeout,
    );
  });

  test('长写入及其后无心跳仍只按所选连接时长结束', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        connectionDuration: Duration(minutes: 1),
      ),
    );
    final gate = Completer<void>();
    gateway.addAccountGate = gate;
    final pending = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': 'request_long_write_lease_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'platformName': '长写入'},
    });
    final write = controller.approve(pending['approvalId']! as String);
    await pumpEventQueue();

    clock.advance(const Duration(seconds: 9));
    await controller.enforceTimeoutsAndNetworkState();
    expect(controller.snapshot.phase, TemporaryWebSessionPhase.connected);

    gateway.addAccountGate = null;
    gate.complete();
    await write;
    expect(
      (await transport.command({
        'action': 'approvalResult',
        'approvalId': pending['approvalId'],
      }))['status'],
      'committed',
    );
    clock.advance(const Duration(seconds: 50));
    await controller.enforceTimeoutsAndNetworkState();
    expect(controller.snapshot.phase, TemporaryWebSessionPhase.connected);
    clock.advance(const Duration(seconds: 1));
    await controller.enforceTimeoutsAndNetworkState();
    expect(
      controller.snapshot.stopReason,
      TemporaryWebStopReason.absoluteTimeout,
    );
  });

  test('墙钟回拨不能延长手机审批的两分钟有效期', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    final pending = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_monotonic_delete_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    final approvalId = pending['approvalId']! as String;

    final approval = controller.snapshot.pendingApprovals.single;
    expect(controller.approvalRemaining(approval), const Duration(minutes: 2));
    clock.value = clock.value.add(const Duration(days: 10));
    await controller.enforceTimeoutsAndNetworkState();
    expect(controller.snapshot.pendingApprovals, contains(approval));
    expect(controller.approvalRemaining(approval), const Duration(minutes: 2));
    clock.rewindWall(const Duration(days: 20));
    clock.advance(const Duration(minutes: 2));
    await controller.approve(approvalId);

    expect(gateway.deleteAccountCalls, 0);
    final result = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': approvalId,
    });
    expect(result['status'], 'expired');
  });

  test('墙钟回拨不能延长密码确认结果的三十秒有效期', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.details,
        allowHistoricalPasswordReveal: true,
      ),
    );
    final firstPending = await transport.command(<String, Object?>{
      'action': 'requestHistoricalPassword',
      'requestId': 'request_monotonic_secret_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    final firstApprovalId = firstPending['approvalId']! as String;
    await controller.approve(firstApprovalId);
    final secondPending = await transport.command(<String, Object?>{
      'action': 'requestHistoricalPassword',
      'requestId': 'request_monotonic_secret_02',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    final secondApprovalId = secondPending['approvalId']! as String;
    await controller.approve(secondApprovalId);

    clock.rewindWall(const Duration(days: 1));
    clock.advance(const Duration(milliseconds: 29999));
    final stillAvailable = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': firstApprovalId,
    });
    expect(stillAvailable['status'], 'approved');
    expect(stillAvailable['password'], 'old-secret');
    expect(
      stillAvailable['visibleForMilliseconds'],
      1,
      reason: '消费结果不得重置三十秒显示期限',
    );

    clock.advance(const Duration(milliseconds: 1));
    final expired = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': secondApprovalId,
    });
    expect(expired['status'], 'notFound');
    expect(expired, isNot(contains('password')));
  });

  test('墙钟回拨不能延长 30 分钟上限，截止后命令与审批均被拒绝', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
        connectionDuration: Duration(minutes: 30),
      ),
    );
    final pending = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_deadline_delete1',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    expect(pending['status'], 'pendingPhoneApproval');

    for (var index = 0; index < 3; index += 1) {
      clock.advance(const Duration(minutes: 9));
      expect(
        (await transport.command(<String, Object?>{
          'action': 'snapshot',
        }))['status'],
        'ok',
      );
    }
    clock.rewindWall(const Duration(days: 10));
    clock.advance(const Duration(minutes: 3));
    await controller.approve(pending['approvalId']! as String);

    expect(
      controller.snapshot.stopReason,
      TemporaryWebStopReason.absoluteTimeout,
    );
    expect(gateway.deleteAccountCalls, 0);
    final afterDeadline = await transport.command(<String, Object?>{
      'action': 'snapshot',
    });
    expect(afterDeadline['status'], 'sessionEnded');
  });

  test('批准进行中提交拒绝会排队，不能先伪报拒绝再完成删除', () async {
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    final pending = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_approve_reject_1',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    final approvalId = pending['approvalId']! as String;
    final gate = Completer<void>();
    gateway.deleteAccountGate = gate;
    final approve = controller.approve(approvalId);
    await pumpEventQueue();
    final reject = controller.reject(approvalId);
    await pumpEventQueue();
    expect(gateway.deleteAccountCalls, 1);

    gateway.deleteAccountGate = null;
    gate.complete();
    await Future.wait<void>(<Future<void>>[approve, reject]);
    final result = await transport.command(<String, Object?>{
      'action': 'approvalResult',
      'approvalId': approvalId,
    });
    expect(result['status'], 'committed');
    expect(gateway.readRecords().accounts, isEmpty);
  });

  test('手机锁定立即清服务端敏感内存但保留连接，同保险库解锁后可用同请求写入', () async {
    controller.dispose();
    final batchPort = _CapturingBatchImportPort();
    final runtimeKeeper = _FakeRuntimeKeeper();
    controller = TemporaryWebSessionController(
      gateway,
      transport,
      addresses,
      now: clock.call,
      monotonicNow: clock.monotonicCall,
      batchImportPort: batchPort,
      runtimeKeeper: runtimeKeeper,
    );
    await _startAndPair(
      controller,
      transport,
      policy: const TemporaryWebSessionPolicy(
        historyMode: TemporaryWebHistoryMode.summary,
      ),
    );
    await _uploadSingleChunkBatch(transport, expectedRevision: 7);
    final pending = await transport.command(<String, Object?>{
      'action': 'deleteAccount',
      'requestId': 'request_lock_pending_delete_01',
      'expectedRevision': 7,
      'body': <String, Object?>{'id': 'account-1'},
    });
    expect(pending['status'], 'pendingPhoneApproval');
    final clearsBeforeLock = batchPort.clearCalls;

    gateway.accessStateValue =
        TemporaryWebVaultAccessState.temporarilyUnavailable;
    controller.handleVaultAccessStateChanged();

    expect(controller.snapshot.phase, TemporaryWebSessionPhase.connected);
    expect(controller.snapshot.pendingApprovals, isEmpty);
    expect(transport.revoked, isFalse);
    expect(batchPort.clearCalls, greaterThan(clearsBeforeLock));
    expect(runtimeKeeper.startCalls, 1);
    expect(runtimeKeeper.stopCalls, 0);
    final status = await transport.command(<String, Object?>{
      'action': 'sessionStatus',
    });
    expect(status, containsPair('status', 'ok'));
    expect(status, containsPair('vaultAccess', 'locked'));
    final activity = await transport.command(<String, Object?>{
      'action': 'activity',
    });
    expect(activity, containsPair('status', 'ok'));
    expect(activity, containsPair('vaultAccess', 'locked'));
    expect(
      (await transport.command(<String, Object?>{
        'action': 'snapshot',
      }))['status'],
      'phoneUnlockRequired',
    );

    const requestId = 'request_locked_add_account_01';
    final lockedMutation = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': requestId,
      'expectedRevision': 7,
      'body': <String, Object?>{'platformName': '锁定期间未写入'},
    });
    expect(lockedMutation['status'], 'phoneUnlockRequired');
    expect(gateway.addAccountCalls, 0);

    gateway.accessStateValue = TemporaryWebVaultAccessState.ready;
    controller.handleVaultAccessStateChanged();
    final resumedStatus = await transport.command(<String, Object?>{
      'action': 'sessionStatus',
    });
    expect(resumedStatus, containsPair('vaultAccess', 'ready'));
    final committed = await transport.command(<String, Object?>{
      'action': 'addAccount',
      'requestId': requestId,
      'expectedRevision': 7,
      'body': <String, Object?>{'platformName': '解锁后写入'},
    });
    expect(
      (await _approveResult(controller, transport, committed))['status'],
      'committed',
    );
    expect(gateway.addAccountCalls, 1);

    controller.stop(TemporaryWebStopReason.user);
    expect(runtimeKeeper.stopCalls, 1);
  });

  test('锁定后 revision 或 vaultBindingId 变化都会终止旧连接', () async {
    for (final changeBinding in <bool>[false, true]) {
      controller.dispose();
      gateway = _FakeGateway(accounts: const <AccountRecord>[]);
      transport = _FakeTransport();
      controller = TemporaryWebSessionController(
        gateway,
        transport,
        addresses,
        now: clock.call,
        monotonicNow: clock.monotonicCall,
      );
      await _startAndPair(controller, transport);
      gateway.accessStateValue =
          TemporaryWebVaultAccessState.temporarilyUnavailable;
      controller.handleVaultAccessStateChanged();
      if (changeBinding) {
        gateway.vaultBindingId = 'different-fake-vault';
      } else {
        gateway.advanceRevision();
      }
      gateway.accessStateValue = TemporaryWebVaultAccessState.ready;
      controller.handleVaultAccessStateChanged();

      expect(
        controller.snapshot.stopReason,
        TemporaryWebStopReason.vaultChanged,
      );
      expect(transport.revoked, isTrue);
    }
  });

  test('busy 等 invalid 状态立即终止旧连接，空 binding 不能启动', () async {
    gateway.vaultBindingId = null;
    expect(controller.canStart, isFalse);
    await expectLater(
      controller.start(
        address: const TemporaryWebAddress(
          address: '192.168.43.1',
          interfaceName: 'wlan0',
        ),
        policy: const TemporaryWebSessionPolicy(),
      ),
      throwsStateError,
    );

    gateway.vaultBindingId = 'fake-vault';
    await _startAndPair(controller, transport);
    gateway.accessStateValue = TemporaryWebVaultAccessState.invalid;
    controller.handleVaultAccessStateChanged();
    expect(controller.snapshot.stopReason, TemporaryWebStopReason.vaultChanged);
    expect(transport.revoked, isTrue);
  });
}

Map<String, Object?> _subscriptionBody({required String? accountId}) =>
    <String, Object?>{
      'accountId': accountId,
      'serviceName': '测试订阅',
      'planName': null,
      'amount': null,
      'currency': 'CNY',
      'firstSubscribedOn': '2026-08-01',
      'nextRenewalOn': '2026-09-01',
      'cycleCount': 1,
      'cycleUnit': 'month',
      'autoRenew': true,
      'paymentMethod': null,
      'reminderDaysBefore': 7,
      'reminderEnabled': true,
      'status': 'active',
    };

Future<void> _startAndPair(
  TemporaryWebSessionController controller,
  _FakeTransport transport, {
  TemporaryWebSessionPolicy policy = const TemporaryWebSessionPolicy(),
}) async {
  await controller.start(
    address: const TemporaryWebAddress(
      address: '192.168.43.1',
      interfaceName: 'wlan0',
    ),
    policy: policy,
  );
  transport.pair('192.168.43.2');
}

Future<void> _uploadSingleChunkBatch(
  _FakeTransport transport, {
  required int expectedRevision,
}) async {
  final bytes = Uint8List.fromList(utf8.encode('platform_name\nExample'));
  const sessionId = 'request_batch_visibility_session_01';
  final start = await transport.command(<String, Object?>{
    'action': 'batchImportUploadStart',
    'requestId': 'request_batch_visibility_start_01',
    'expectedRevision': expectedRevision,
    'body': <String, Object?>{
      'sessionId': sessionId,
      'fileName': 'accounts.csv',
      'sourceId': 'auto',
      'totalBytes': bytes.length,
      'totalChunks': 1,
    },
  });
  expect(start['status'], 'ok');
  final chunk = await transport.command(<String, Object?>{
    'action': 'batchImportUploadChunk',
    'requestId': 'request_batch_visibility_chunk_01',
    'expectedRevision': expectedRevision,
    'body': <String, Object?>{
      'sessionId': sessionId,
      'sequence': 0,
      'totalChunks': 1,
      'contentBase64': base64Encode(bytes),
    },
  });
  expect(chunk['status'], 'ok');
  final finish = await transport.command(<String, Object?>{
    'action': 'batchImportUploadFinish',
    'requestId': 'request_batch_visibility_finish_01',
    'expectedRevision': expectedRevision,
    'body': <String, Object?>{'sessionId': sessionId, 'totalChunks': 1},
  });
  expect(finish['status'], 'ok');
  bytes.fillRange(0, bytes.length, 0);
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

  void rewindWall(Duration duration) {
    value = value.subtract(duration);
  }
}

final class _FakeAddressProvider implements TemporaryWebAddressProvider {
  bool available = true;

  @override
  Future<bool> isStillAvailable(String address) async =>
      available && address == '192.168.43.1';

  @override
  Future<List<TemporaryWebAddress>> listPrivateIpv4Addresses() async =>
      const <TemporaryWebAddress>[
        TemporaryWebAddress(address: '192.168.43.1', interfaceName: 'wlan0'),
      ];
}

final class _CapturingBatchImportPort implements TemporaryWebBatchImportPort {
  TemporaryWebBatchImportRequest? lastRequest;
  int clearCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<TemporaryWebBatchImportPreview> preview(
    TemporaryWebBatchImportRequest request,
  ) async {
    lastRequest = request;
    return TemporaryWebBatchImportPreview(
      previewToken: 'preview-token',
      revision: request.expectedRevision,
      sourceLabel: 'test',
      detectedFormat: 'CSV',
      mappings: const <TemporaryWebBatchImportMapping>[],
      rows: const <TemporaryWebBatchImportRow>[],
      warnings: const <String>[],
    );
  }

  @override
  Future<TemporaryWebBatchImportPreview> revisePreview(
    TemporaryWebBatchRevisionRequest request,
  ) => throw UnsupportedError('not used');

  @override
  Future<TemporaryWebBatchPreparedCommit> prepareCommit(
    TemporaryWebBatchCommitRequest request,
  ) => throw UnsupportedError('not used');

  @override
  Future<TemporaryWebBatchCommitResult> approveCommit(
    String approvalToken, {
    required int expectedRevision,
  }) => throw UnsupportedError('not used');

  @override
  void clearSensitiveMemory() {
    clearCalls += 1;
  }
}

final class _FakeRuntimeKeeper implements TemporaryWebRuntimeKeeper {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

final class _FakeTransport implements TemporaryWebTransport {
  TemporaryWebCommandHandler? _handler;
  void Function(String)? _onPaired;
  void Function(Object)? _onFatalError;
  bool revoked = false;

  @override
  void revoke() {
    revoked = true;
  }

  @override
  Future<TemporaryWebTransportBinding> start({
    required String address,
    required TemporaryWebCommandHandler onCommand,
    required void Function(String remoteAddress) onPaired,
    required void Function(Object error) onFatalError,
  }) async {
    revoked = false;
    _handler = onCommand;
    _onPaired = onPaired;
    _onFatalError = onFatalError;
    return const TemporaryWebTransportBinding(
      port: 43123,
      formattedConnectionCode: 'ABCDEFGH',
    );
  }

  void pair(String address) => _onPaired!(address);

  void fail(Object error) => _onFatalError!(error);

  Future<Map<String, Object?>> command(Map<String, Object?> value) =>
      _handler!(value, '192.168.43.2');

  @override
  Future<void> stop() async {}
}

final class _FakeGateway
    implements
        TemporaryWebVaultGateway,
        TemporaryWebVaultAccessStateProvider,
        TemporaryWebPhoneApprovedAccountGateway {
  _FakeGateway({
    required List<AccountRecord> accounts,
    List<SubscriptionRecord> subscriptions = const <SubscriptionRecord>[],
  }) : _accounts = List<AccountRecord>.of(accounts),
       _subscriptions = List<SubscriptionRecord>.of(subscriptions);

  final List<AccountRecord> _accounts;
  final List<SubscriptionRecord> _subscriptions;
  int _revision = 7;
  int _nextAccount = 2;
  int _nextSubscription = 1;
  bool eligible = true;
  TemporaryWebVaultAccessState accessStateValue =
      TemporaryWebVaultAccessState.ready;
  @override
  String? vaultBindingId = 'fake-vault';
  int addAccountCalls = 0;
  int deleteAccountCalls = 0;
  Completer<void>? addAccountGate;
  Completer<void>? deleteAccountGate;

  @override
  bool get isEligibleForTemporaryWebSession => eligible;

  @override
  TemporaryWebVaultAccessState get accessState =>
      eligible ? accessStateValue : TemporaryWebVaultAccessState.invalid;

  @override
  int get revision => _revision;

  void advanceRevision() {
    _revision += 1;
  }

  @override
  TemporaryWebVaultRecords readRecords() => TemporaryWebVaultRecords(
    revision: _revision,
    accounts: List<AccountRecord>.unmodifiable(_accounts),
    subscriptions: List<SubscriptionRecord>.unmodifiable(_subscriptions),
  );

  @override
  List<String> duplicateAccountLabels(AccountDraft draft) => const [];
  @override
  Future<TemporaryWebMutationResult> addAccountAfterPhoneApproval(
    AccountDraft draft, {
    required int expectedRevision,
  }) async {
    if (revision != expectedRevision) {
      return TemporaryWebMutationResult.rejected(
        revision: revision,
        message: 'stale',
      );
    }
    return addAccount(draft);
  }

  @override
  Future<TemporaryWebMutationResult> addAccount(AccountDraft draft) async {
    addAccountCalls += 1;
    await addAccountGate?.future;
    final record = AccountRecord.fromDraft(
      id: 'account-${_nextAccount++}',
      draft: draft,
    );
    _accounts.add(record);
    _revision += 1;
    return TemporaryWebMutationResult.committed(
      revision: _revision,
      recordId: record.id,
    );
  }

  @override
  Future<TemporaryWebMutationResult> addSubscription(
    SubscriptionDraft draft,
  ) async {
    final record = SubscriptionRecord.fromDraft(
      id: 'subscription-${_nextSubscription++}',
      draft: draft,
    );
    _subscriptions.add(record);
    _revision += 1;
    return TemporaryWebMutationResult.committed(
      revision: _revision,
      recordId: record.id,
    );
  }

  @override
  Future<TemporaryWebMutationResult> deleteAccount(String accountId) async {
    deleteAccountCalls += 1;
    await deleteAccountGate?.future;
    _accounts.removeWhere((item) => item.id == accountId);
    _subscriptions.removeWhere((item) => item.accountId == accountId);
    _revision += 1;
    return TemporaryWebMutationResult.committed(revision: _revision);
  }

  @override
  Future<TemporaryWebMutationResult> deleteSubscription(
    String subscriptionId,
  ) async {
    _subscriptions.removeWhere((item) => item.id == subscriptionId);
    _revision += 1;
    return TemporaryWebMutationResult.committed(revision: _revision);
  }

  @override
  Future<TemporaryWebMutationResult> updateAccount({
    required String accountId,
    required AccountDraft draft,
    required AccountPasswordUpdateMode passwordMode,
  }) async {
    final index = _accounts.indexWhere((item) => item.id == accountId);
    final existing = _accounts[index];
    final password = switch (passwordMode) {
      AccountPasswordUpdateMode.preserve => existing.password,
      AccountPasswordUpdateMode.replace => draft.password,
      AccountPasswordUpdateMode.clear => null,
    };
    _accounts[index] = AccountRecord.fromDraft(
      id: accountId,
      draft: AccountDraft(
        platformName: draft.platformName,
        category: draft.category,
        loginAccount: draft.loginAccount,
        username: draft.username,
        boundPhone: draft.boundPhone,
        boundEmail: draft.boundEmail,
        password: password,
        website: draft.website,
        notes: draft.notes,
        customFields: draft.customFields,
      ),
    );
    _revision += 1;
    return TemporaryWebMutationResult.committed(
      revision: _revision,
      recordId: accountId,
    );
  }

  @override
  Future<TemporaryWebMutationResult> updateSubscription({
    required String subscriptionId,
    required SubscriptionDraft draft,
  }) async {
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    _subscriptions[index] = _subscriptions[index].applyDraft(draft);
    _revision += 1;
    return TemporaryWebMutationResult.committed(
      revision: _revision,
      recordId: subscriptionId,
    );
  }
}

Future<Map<String, Object?>> _approveResult(
  TemporaryWebSessionController controller,
  _FakeTransport transport,
  Map<String, Object?> pending,
) async {
  expect(pending['status'], 'pendingPhoneApproval');
  await controller.approve(pending['approvalId']! as String);
  return transport.command({
    'action': 'approvalResult',
    'approvalId': pending['approvalId'],
  });
}
