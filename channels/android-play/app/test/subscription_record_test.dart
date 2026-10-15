import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/pending_subscription_draft.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('订阅记录支持中文字段并严格往返日期与周期', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '中文平台'),
    );
    final subscription = _subscription(
      id: 'subscription-1',
      accountId: account.id,
      serviceName: '云存储高级版🙂',
    );

    final restored = SubscriptionRecord.fromEncryptedPayloadJson(
      subscription.toEncryptedPayloadJson(),
    );
    expect(restored.serviceName, '云存储高级版🙂');
    expect(restored.planName, '家庭年度版');
    expect(restored.amount, '19.9001');
    expect(restored.notes, '正式订阅备注\n第二行');
    expect(restored.cycleLabel, '每3个月');
    expect(formatSubscriptionDate(restored.firstSubscribedOn), '2026-08-01');
    expect(formatSubscriptionDate(restored.nextRenewalOn), '2026-11-01');
  });

  test('订阅拒绝倒置日期、非法金额和非法周期', () {
    expect(
      () => SubscriptionDetailsDraft(
        serviceName: '测试订阅',
        firstSubscribedOn: DateTime(2026, 9, 1),
        nextRenewalOn: DateTime(2026, 8, 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => SubscriptionDetailsDraft(
        serviceName: '测试订阅',
        firstSubscribedOn: DateTime(2026, 8, 1),
        nextRenewalOn: DateTime(2026, 9, 1),
        amount: '19.99999',
      ),
      throwsArgumentError,
    );
    expect(
      () => SubscriptionDetailsDraft(
        serviceName: '测试订阅',
        firstSubscribedOn: DateTime(2026, 8, 1),
        nextRenewalOn: DateTime(2026, 9, 1),
        cycleCount: 0,
      ),
      throwsArgumentError,
    );
  });

  test('正式订阅备注在编辑、续费、延期、取消恢复与密文往返中保留', () {
    final original = _subscription(
      id: 'subscription-notes',
      accountId: null,
      serviceName: '备注保留订阅',
    );
    final editedWithoutNotes = original.applyDraft(
      SubscriptionDraft(
        accountId: null,
        details: SubscriptionDetailsDraft(
          serviceName: '备注保留订阅-已编辑',
          firstSubscribedOn: original.firstSubscribedOn,
          nextRenewalOn: original.nextRenewalOn,
        ),
      ),
    );
    final variants = <SubscriptionRecord>[
      SubscriptionRecord.fromEncryptedPayloadJson(
        original.toEncryptedPayloadJson(),
        allowStandalone: true,
      ),
      editedWithoutNotes,
      original.markRenewed(recordedOn: DateTime(2026, 8, 2)),
      original.snoozeReminderUntil(DateTime(2026, 8, 20)),
      original.snoozeReminder(
        SubscriptionSnoozeTarget.exactInstant(DateTime.utc(2026, 8, 20, 3)),
      ),
      original.cancel(cancelledOn: DateTime(2026, 8, 2)).restore(),
    ];

    for (final variant in variants) {
      expect(variant.notes, '正式订阅备注\n第二行');
      expect(variant.details.notes, '正式订阅备注\n第二行');
    }
  });

  test('schemaVersion 2到6缺失正式订阅 notes 时兼容读取为空', () {
    final account = AccountRecord.fromDraft(
      id: 'account-notes-legacy',
      draft: AccountDraft(platformName: '旧备注平台'),
    );
    final subscription = _subscription(
      id: 'subscription-notes-legacy',
      accountId: account.id,
      serviceName: '旧备注订阅',
    );
    final base = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      nextSubscriptionId: 2,
      subscriptions: <SubscriptionRecord>[subscription],
    ).toEncryptedPayloadJson();

    for (var schemaVersion = 2; schemaVersion <= 6; schemaVersion += 1) {
      final rawSubscription = Map<String, Object?>.from(
        (base['subscriptions']! as List<Object?>).single!
            as Map<String, Object?>,
      )..remove('notes');
      final legacy = Map<String, Object?>.from(base)
        ..['schemaVersion'] = schemaVersion
        ..['subscriptions'] = <Object?>[rawSubscription];
      final restored = VaultSnapshot.fromEncryptedPayloadJson(legacy);
      expect(
        restored.subscriptions.single.notes,
        isNull,
        reason: 'schema $schemaVersion 缺失字段只能读取为空',
      );
    }
  });

  test('schemaVersion 1账号数据无损迁移为空订阅和空草稿的当前schema', () {
    final legacy = <String, Object?>{
      'schemaVersion': 1,
      'nextAccountId': 2,
      'accounts': <Object?>[
        AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(
            platformName: '旧版中文平台',
            loginAccount: '中文账号_一号🙂',
            notes: '旧版中文备注\n第二行，。！',
          ),
        ).toEncryptedPayloadJson(),
      ],
    };

    final migrated = VaultSnapshot.fromEncryptedPayloadJson(legacy);
    expect(migrated.accounts.single.platformName, '旧版中文平台');
    expect(migrated.accounts.single.loginAccount, '中文账号_一号🙂');
    expect(migrated.accounts.single.notes, '旧版中文备注\n第二行，。！');
    expect(migrated.subscriptions, isEmpty);
    expect(migrated.pendingSubscriptionDrafts, isEmpty);
    expect(migrated.nextSubscriptionId, 1);

    final upgraded = migrated.toEncryptedPayloadJson();
    expect(upgraded['schemaVersion'], VaultSnapshot.currentSchemaVersion);
    expect(upgraded['nextSubscriptionId'], 1);
    expect(upgraded['subscriptions'], isEmpty);
  });

  test('快照允许一个账号多条订阅并拒绝孤儿外键', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '多订阅平台'),
    );
    final first = _subscription(
      id: 'subscription-1',
      accountId: account.id,
      serviceName: '云存储',
    );
    final second = _subscription(
      id: 'subscription-2',
      accountId: account.id,
      serviceName: '音乐会员',
    );

    final snapshot = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      nextSubscriptionId: 3,
      subscriptions: <SubscriptionRecord>[first, second],
    );
    expect(snapshot.subscriptions, hasLength(2));

    expect(
      () => VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[account],
        nextSubscriptionId: 2,
        subscriptions: <SubscriptionRecord>[
          _subscription(
            id: 'subscription-orphan',
            accountId: 'account-missing',
            serviceName: '孤儿订阅',
          ),
        ],
      ),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('schemaVersion 8允许独立订阅严格往返且不创建伪账号', () {
    final standalone = _subscription(
      id: 'subscription-standalone',
      accountId: null,
      serviceName: '独立视频会员',
    );
    final snapshot = VaultSnapshot(
      nextAccountId: 1,
      accounts: const <AccountRecord>[],
      nextSubscriptionId: 2,
      subscriptions: <SubscriptionRecord>[standalone],
    );

    final payload = snapshot.toEncryptedPayloadJson();
    expect(payload['schemaVersion'], VaultSnapshot.currentSchemaVersion);
    expect(payload['accounts'], isEmpty);
    expect(
      ((payload['subscriptions']! as List<Object?>).single!
          as Map<String, Object?>)['accountId'],
      isNull,
    );

    final restored = VaultSnapshot.fromEncryptedPayloadJson(payload);
    expect(restored.accounts, isEmpty);
    expect(restored.subscriptions.single.accountId, isNull);
    expect(restored.subscriptions.single.serviceName, '独立视频会员');
  });

  test('schemaVersion 5独立订阅所有业务字段无损迁移为当前schema', () {
    final standalone =
        _subscription(
              id: 'subscription-schema5-standalone',
              accountId: null,
              serviceName: '旧版独立会员',
            )
            .markRenewed(recordedOn: DateTime(2026, 8, 15))
            .snoozeReminderUntil(DateTime(2026, 12, 20));
    final expectedRecordJson = standalone.toEncryptedPayloadJson();
    final legacyRecordJson = Map<String, Object?>.from(expectedRecordJson)
      ..remove('snoozedUntilUtc');
    final legacyPayload =
        VaultSnapshot(
            nextAccountId: 1,
            accounts: const <AccountRecord>[],
            nextSubscriptionId: 2,
            subscriptions: <SubscriptionRecord>[standalone],
          ).toEncryptedPayloadJson()
          ..['schemaVersion'] = 5
          ..['subscriptions'] = <Object?>[legacyRecordJson];

    final restored = VaultSnapshot.fromEncryptedPayloadJson(legacyPayload);
    expect(restored.accounts, isEmpty);
    expect(restored.subscriptions.single.accountId, isNull);
    expect(
      {...restored.subscriptions.single.toEncryptedPayloadJson()}
        ..remove('management'),
      {...expectedRecordJson}..remove('management'),
    );

    expect(restored.subscriptions.single.management!.historyIncomplete, isTrue);
    expect(restored.subscriptions.single.management!.priceHistory, isEmpty);
    expect(
      restored.subscriptions.single.effectiveReminderRules.single.daysBefore,
      [standalone.reminderDaysBefore],
    );
    final upgradedPayload = restored.toEncryptedPayloadJson();
    expect(
      upgradedPayload['schemaVersion'],
      VaultSnapshot.currentSchemaVersion,
    );
    expect(upgradedPayload['accounts'], isEmpty);
    expect(
      ((upgradedPayload['subscriptions']! as List<Object?>).single!
          as Map<String, Object?>)['accountId'],
      isNull,
    );

    final futurePayload = Map<String, Object?>.from(upgradedPayload)
      ..['schemaVersion'] = VaultSnapshot.currentSchemaVersion + 1;
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(futurePayload),
      throwsA(isA<VaultUnsupportedSchemaVersionException>()),
    );
  });

  test('schemaVersion 4仍要求关联账号，旧关联数据升级写为当前schema', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '旧版平台'),
    );
    final linked = _subscription(
      id: 'subscription-1',
      accountId: account.id,
      serviceName: '旧版关联订阅',
    );
    final legacy = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      nextSubscriptionId: 2,
      subscriptions: <SubscriptionRecord>[linked],
    ).toEncryptedPayloadJson()..['schemaVersion'] = 4;

    final restored = VaultSnapshot.fromEncryptedPayloadJson(legacy);
    expect(restored.subscriptions.single.accountId, account.id);
    expect(
      restored.toEncryptedPayloadJson()['schemaVersion'],
      VaultSnapshot.currentSchemaVersion,
    );

    final rawSubscription = Map<String, Object?>.from(
      (legacy['subscriptions']! as List<Object?>).single!
          as Map<String, Object?>,
    )..['accountId'] = null;
    legacy['subscriptions'] = <Object?>[rawSubscription];
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(legacy),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('schemaVersion 8精确小时延后以UTC瞬时严格往返且schemaVersion 5拒绝偷渡', () {
    final snoozed =
        _subscription(
          id: 'subscription-hour-snooze',
          accountId: null,
          serviceName: '跨午夜延后',
        ).snoozeReminder(
          SubscriptionSnoozeTarget.after(
            const Duration(hours: 5),
            now: DateTime.utc(2026, 8, 29, 23, 30),
          ),
        );
    final payload = VaultSnapshot(
      nextAccountId: 1,
      accounts: const <AccountRecord>[],
      nextSubscriptionId: 2,
      subscriptions: <SubscriptionRecord>[snoozed],
    ).toEncryptedPayloadJson();

    final restored = VaultSnapshot.fromEncryptedPayloadJson(payload);
    expect(restored.subscriptions.single.snoozedUntil, isNull);
    expect(
      restored.subscriptions.single.snoozedUntilUtc,
      DateTime.utc(2026, 8, 30, 4, 30),
    );

    final downgraded = Map<String, Object?>.from(payload)
      ..['schemaVersion'] = 5;
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(downgraded),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('未来schemaVersion继续安全拒绝', () {
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(<String, Object?>{
        'schemaVersion': VaultSnapshot.currentSchemaVersion + 1,
      }),
      throwsA(isA<VaultUnsupportedSchemaVersionException>()),
    );
  });

  test('schemaVersion 2到6读取后待完善草稿始终为空', () {
    for (var schemaVersion = 2; schemaVersion <= 6; schemaVersion += 1) {
      final legacy = <String, Object?>{
        'schemaVersion': schemaVersion,
        'nextAccountId': 1,
        'accounts': <Object?>[],
        'nextSubscriptionId': 1,
        'subscriptions': <Object?>[],
        if (schemaVersion >= 4)
          'preferences': const VaultPreferences().toEncryptedPayloadJson(),
        if (schemaVersion >= 4) 'recentAccountIds': <Object?>[],
      };
      final restored = VaultSnapshot.fromEncryptedPayloadJson(legacy);
      expect(
        restored.pendingSubscriptionDrafts,
        isEmpty,
        reason: 'schema $schemaVersion 不得生成草稿',
      );
    }
  });

  test('schemaVersion 8待完善订阅草稿严格往返并拒绝孤儿账号', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '草稿平台'),
    );
    final draft = PendingSubscriptionDraft(
      draftId: 'pending-1',
      accountId: account.id,
      planName: '待确认套餐',
      currency: 'cny',
      billingCycle: const PendingSubscriptionBillingCycle(
        count: 1,
        unit: SubscriptionCycleUnit.month,
      ),
      subscriptionStartDate: DateTime(2026, 8, 1),
      createdAt: DateTime.utc(2026, 8, 30, 1),
      updatedAt: DateTime.utc(2026, 8, 30, 2),
    );
    final payload = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      pendingSubscriptionDrafts: <PendingSubscriptionDraft>[draft],
    ).toEncryptedPayloadJson();

    final restored = VaultSnapshot.fromEncryptedPayloadJson(payload);
    expect(restored.pendingSubscriptionDrafts.single.draftId, 'pending-1');
    expect(restored.pendingSubscriptionDrafts.single.currency, 'CNY');
    expect(
      restored.pendingSubscriptionDrafts.single.subscriptionStartDate,
      DateTime(2026, 8, 1),
    );
    expect(
      restored.pendingSubscriptionDrafts.single.missingFormalFields,
      containsAll(<String>[
        'amount',
        'nextRenewalDate',
        'autoRenew',
        'reminderDays',
      ]),
    );

    expect(
      () => VaultSnapshot(
        nextAccountId: 1,
        accounts: const <AccountRecord>[],
        pendingSubscriptionDrafts: <PendingSubscriptionDraft>[draft],
      ),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('schemaVersion 7草稿迁移时未知首次订阅日期保持为空并升级写为当前schema', () {
    final account = AccountRecord.fromDraft(
      id: 'account-schema7-draft',
      draft: AccountDraft(platformName: '旧模板平台'),
    );
    final draft = PendingSubscriptionDraft(
      draftId: 'pending-schema7',
      accountId: account.id,
      planName: '旧模板套餐',
      amount: '9.90',
      currency: 'CNY',
      billingCycle: const PendingSubscriptionBillingCycle(
        count: 1,
        unit: SubscriptionCycleUnit.month,
      ),
      nextRenewalDate: DateTime(2026, 10, 1),
      autoRenew: true,
      paymentMethod: '测试卡',
      reminderDays: 3,
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 30),
    );
    final legacy = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      pendingSubscriptionDrafts: <PendingSubscriptionDraft>[draft],
    ).toEncryptedPayloadJson()..['schemaVersion'] = 7;
    final rawDraft = Map<String, Object?>.from(
      (legacy['pendingSubscriptionDrafts']! as List<Object?>).single!
          as Map<String, Object?>,
    )..remove('subscriptionStartDate');
    legacy['pendingSubscriptionDrafts'] = <Object?>[rawDraft];

    final restored = VaultSnapshot.fromEncryptedPayloadJson(legacy);
    expect(
      restored.pendingSubscriptionDrafts.single.subscriptionStartDate,
      isNull,
    );
    expect(
      restored.pendingSubscriptionDrafts.single.missingFormalFields,
      contains('subscriptionStartDate'),
    );
    expect(
      restored.toEncryptedPayloadJson()['schemaVersion'],
      VaultSnapshot.currentSchemaVersion,
    );
  });

  test('待完善草稿保留相互独立日期并明确标记错误先后顺序', () {
    final draft = PendingSubscriptionDraft(
      draftId: 'pending-date-order',
      accountId: 'account-1',
      planName: '日期待核对',
      amount: '1.00',
      currency: 'CNY',
      billingCycle: const PendingSubscriptionBillingCycle(
        count: 1,
        unit: SubscriptionCycleUnit.month,
      ),
      subscriptionStartDate: DateTime(2026, 10, 2),
      nextRenewalDate: DateTime(2026, 10, 1),
      autoRenew: true,
      paymentMethod: '测试卡',
      reminderDays: 1,
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 30),
    );

    expect(draft.subscriptionStartDate, DateTime(2026, 10, 2));
    expect(draft.nextRenewalDate, DateTime(2026, 10, 1));
    expect(draft.missingFormalFields, contains('subscriptionDateOrder'));
    expect(draft.isCompleteForFormalValidation, isFalse);
  });

  test('草稿缺失清单同时标记非法金额与缺少套餐和提醒天数', () {
    final draft = PendingSubscriptionDraft(
      draftId: 'pending-invalid',
      accountId: 'account-1',
      amount: '-1',
      currency: 'CNY',
      billingCycle: const PendingSubscriptionBillingCycle(
        count: 1,
        unit: SubscriptionCycleUnit.month,
      ),
      nextRenewalDate: DateTime(2026, 9, 30),
      autoRenew: true,
      paymentMethod: '支付宝',
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 30),
    );
    expect(
      draft.missingFormalFields,
      containsAll(<String>['planName', 'amount', 'reminderDays']),
    );
    expect(draft.isCompleteForFormalValidation, isFalse);
  });
}

SubscriptionRecord _subscription({
  required String id,
  required String? accountId,
  required String serviceName,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: accountId,
    details: SubscriptionDetailsDraft(
      serviceName: serviceName,
      planName: '家庭年度版',
      amount: '19.9001',
      currency: 'CNY',
      firstSubscribedOn: DateTime(2026, 8, 1),
      nextRenewalOn: DateTime(2026, 11, 1),
      cycleCount: 3,
      cycleUnit: SubscriptionCycleUnit.month,
      autoRenew: true,
      paymentMethod: '支付宝',
      notes: '正式订阅备注\n第二行',
      reminderDaysBefore: 7,
    ),
  ),
);
