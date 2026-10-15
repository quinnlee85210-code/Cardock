import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('中文用户名规范化后可往返并参与搜索', () {
    final record = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '测试平台',
        loginAccount: '中文登录账号@example.cn',
        username: '  中文昵称_甲🙂  ',
      ),
    );

    expect(record.username, '中文昵称_甲🙂');
    expect(record.matches('昵称_甲'), isTrue);

    final restored = AccountRecord.fromEncryptedPayloadJson(
      record.toEncryptedPayloadJson(),
    );
    expect(restored.username, '中文昵称_甲🙂');
  });

  test('schema v1 账号字段无损读取并写为 schema v5', () {
    final restored = VaultSnapshot.fromEncryptedPayloadJson(<String, Object?>{
      'schemaVersion': 1,
      'nextAccountId': 2,
      'accounts': <Object?>[
        <String, Object?>{
          'id': 'account-1',
          'platformName': '旧版中文平台',
          'category': '云服务',
          'loginAccount': '旧版中文登录账号',
          'boundPhone': '13800000000',
          'boundEmail': 'legacy@example.cn',
          'password': null,
          'website': 'https://中文域名.cn',
          'notes': '旧版中文备注',
        },
      ],
    });

    final account = restored.accounts.single;
    expect(account.platformName, '旧版中文平台');
    expect(account.loginAccount, '旧版中文登录账号');
    expect(account.username, isNull);
    expect(account.website, 'https://中文域名.cn');
    expect(account.notes, '旧版中文备注');
    expect(restored.subscriptions, isEmpty);
    expect(
      restored.toEncryptedPayloadJson()['schemaVersion'],
      VaultSnapshot.currentSchemaVersion,
    );
  });

  test('schema v2 账号与订阅无损读取并写为 schema v5', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: 'v2中文平台',
        loginAccount: 'v2登录账号',
        notes: 'v2备注',
      ),
    );
    final accountJson = account.toEncryptedPayloadJson()..remove('username');
    final restored = VaultSnapshot.fromEncryptedPayloadJson(<String, Object?>{
      'schemaVersion': 2,
      'nextAccountId': 2,
      'nextSubscriptionId': 2,
      'accounts': <Object?>[accountJson],
      'subscriptions': <Object?>[_legacySubscriptionJson()],
    });

    expect(restored.accounts.single.platformName, 'v2中文平台');
    expect(restored.accounts.single.loginAccount, 'v2登录账号');
    expect(restored.accounts.single.username, isNull);
    expect(restored.accounts.single.notes, 'v2备注');
    expect(restored.nextSubscriptionId, 2);
    expect(restored.subscriptions.single.serviceName, 'v2中文订阅');
    expect(restored.subscriptions.single.amount, '19.90');
    expect(restored.subscriptions.single.reminderEnabled, isTrue);
    expect(restored.subscriptions.single.snoozedUntil, isNull);
    expect(restored.subscriptions.single.cancelledOn, isNull);
    expect(restored.subscriptions.single.accessEndsOn, isNull);
    expect(restored.subscriptions.single.renewalHistory, isEmpty);
    expect(
      restored.toEncryptedPayloadJson()['schemaVersion'],
      VaultSnapshot.currentSchemaVersion,
    );
  });

  test('schema v3 用户名与旧订阅迁移为 schema v5 安全默认值', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: 'v3中文平台',
        loginAccount: 'v3登录账号',
        username: 'v3中文用户名',
      ),
    );
    final restored = VaultSnapshot.fromEncryptedPayloadJson(<String, Object?>{
      'schemaVersion': 3,
      'nextAccountId': 2,
      'nextSubscriptionId': 2,
      'accounts': <Object?>[account.toEncryptedPayloadJson()],
      'subscriptions': <Object?>[_legacySubscriptionJson()],
    });

    expect(restored.accounts.single.username, 'v3中文用户名');
    expect(restored.subscriptions.single.reminderEnabled, isTrue);
    expect(restored.subscriptions.single.renewalHistory, isEmpty);
    expect(restored.preferences.autoLockSeconds, 0);
    expect(restored.preferences.defaultReminderTimeMinutes, 12 * 60 + 30);
    expect(restored.recentAccountIds, isEmpty);
    expect(
      restored.toEncryptedPayloadJson()['schemaVersion'],
      VaultSnapshot.currentSchemaVersion,
    );
  });

  test('schema v4 加密保存偏好与最近查看并拒绝无效引用', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '最近查看账号'),
    );
    final snapshot = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      preferences: const VaultPreferences(
        autoLockSeconds: 60,
        defaultReminderDaysBefore: 3,
        defaultReminderTimeMinutes: 14 * 60 + 35,
        defaultCurrency: 'HKD',
        notificationsEnabled: true,
      ),
      recentAccountIds: const <String>['account-1'],
    );

    final restored = VaultSnapshot.fromEncryptedPayloadJson(
      snapshot.toEncryptedPayloadJson(),
    );
    expect(restored.preferences.autoLockSeconds, 60);
    expect(restored.preferences.defaultReminderDaysBefore, 3);
    expect(restored.preferences.defaultReminderTimeMinutes, 14 * 60 + 35);
    expect(restored.preferences.defaultCurrency, 'HKD');
    expect(restored.preferences.notificationsEnabled, isTrue);
    expect(restored.recentAccountIds, const <String>['account-1']);

    expect(
      () => VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[account],
        recentAccountIds: const <String>['account-missing'],
      ),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('拒绝未来 schema 版本', () {
    final futureSchemaVersion = VaultSnapshot.currentSchemaVersion + 1;
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(<String, Object?>{
        'schemaVersion': futureSchemaVersion,
        'nextAccountId': 1,
        'accounts': <Object?>[],
      }),
      throwsA(
        isA<VaultUnsupportedSchemaVersionException>().having(
          (error) => error.version,
          'version',
          futureSchemaVersion,
        ),
      ),
    );
  });
}

Map<String, Object?> _legacySubscriptionJson() => <String, Object?>{
  'id': 'subscription-1',
  'accountId': 'account-1',
  'serviceName': 'v2中文订阅',
  'planName': null,
  'amount': '19.90',
  'currency': 'CNY',
  'firstSubscribedOn': '2026-07-01',
  'nextRenewalOn': '2026-08-01',
  'cycleCount': 1,
  'cycleUnit': 'month',
  'autoRenew': true,
  'paymentMethod': null,
  'reminderDaysBefore': 7,
  'status': 'active',
};
