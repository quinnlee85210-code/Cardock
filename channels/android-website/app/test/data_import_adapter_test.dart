import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:flutter_test/flutter_test.dart';

TabularDocument _parseRows(List<List<String>> rows) =>
    const TabularImportParser().parse(
      Uint8List.fromList(
        utf8.encode(rows.map((row) => row.join(',')).join('\n')),
      ),
    );

TabularDocument _parseSource(String source) =>
    const TabularImportParser().parse(Uint8List.fromList(utf8.encode(source)));

void main() {
  final registry = ImportSourceRegistry.standard();

  test('适配器注册表仅启用已有精确证据的官方格式', () {
    for (final id in <String>[
      'chrome_edge_google_csv',
      'firefox_csv',
      'apple_passwords_csv',
    ]) {
      final adapter = registry.adapterById(id);
      expect(adapter.enabled, isFalse, reason: id);
      expect(adapter.verified, isFalse, reason: id);
    }
    for (final id in <String>[
      'chrome_google_csv',
      'chrome_passwords_csv',
      'google_password_manager_csv',
      'bitwarden_csv',
      'keepassxc_csv',
      'onepassword_csv',
      'cardock_accounts_template',
      'cardock_subscriptions_template',
      'generic_tabular',
    ]) {
      final adapter = registry.adapterById(id);
      expect(adapter.enabled, isTrue, reason: id);
      expect(adapter.verified, isTrue, reason: id);
    }
  });

  test('13 类虚构 fixture 按证据精确识别或低置信回退', () {
    final fixtures = <({String label, String source, String adapterId, bool fallback})>[
      (
        label: 'Chrome Google confirmed compatible',
        source: 'name,url,username,password,note',
        adapterId: 'chrome_google_csv',
        fallback: false,
      ),
      (
        label: 'Firefox unverified',
        source:
            'url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged',
        adapterId: 'generic_tabular',
        fallback: true,
      ),
      (
        label: 'Apple unverified',
        source: 'Title,URL,Username,Password,Notes',
        adapterId: 'generic_tabular',
        fallback: true,
      ),
      (
        label: 'Bitwarden',
        source:
            'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp',
        adapterId: 'bitwarden_csv',
        fallback: false,
      ),
      (
        label: '1Password',
        source:
            'Title,Website,Username,Password,One-time password,Favorite status,Archived status,Tags,Notes',
        adapterId: 'onepassword_csv',
        fallback: false,
      ),
      (
        label: 'KeePassXC',
        source: 'Group,Title,Username,Password,URL,Notes',
        adapterId: 'keepassxc_csv',
        fallback: false,
      ),
      (
        label: 'Chinese generic',
        source: '平台,网址,用户名,密码,备注',
        adapterId: 'generic_tabular',
        fallback: true,
      ),
      (
        label: 'English generic',
        source: 'service,website,login,password,notes',
        adapterId: 'generic_tabular',
        fallback: true,
      ),
      (
        label: 'Japanese generic',
        source: 'サービス名,サイトURL,ユーザー名,パスワード,メモ',
        adapterId: 'generic_tabular',
        fallback: true,
      ),
      (
        label: 'TSV generic',
        source: 'name\turl\tusername\tpassword\tnote',
        adapterId: 'generic_tabular',
        fallback: true,
      ),
      (
        label: 'semicolon generic',
        source: 'name;url;username;password;note',
        adapterId: 'generic_tabular',
        fallback: true,
      ),
      (
        label: 'Cardock accounts',
        source:
            'account_key,platform_name,login_account,phone,email,password,url,notes',
        adapterId: 'cardock_accounts_template',
        fallback: false,
      ),
      (
        label: 'Cardock subscriptions',
        source:
            'account_key,plan_name,amount,currency,billing_cycle,subscription_start_date,next_renewal_date,auto_renew,payment_method,reminder_days,notes',
        adapterId: 'cardock_subscriptions_template',
        fallback: false,
      ),
    ];

    expect(fixtures, hasLength(13));
    for (final fixture in fixtures) {
      final detection = registry.detect(_parseSource(fixture.source));
      expect(
        detection.selectedAdapter.id,
        fixture.adapterId,
        reason: fixture.label,
      );
      expect(
        detection.usedGenericFallback,
        fixture.fallback,
        reason: fixture.label,
      );
      if (fixture.fallback) {
        expect(
          detection.matches.single.confidence,
          lessThan(0.1),
          reason: fixture.label,
        );
      }
    }
  });

  test('已确认浏览器表头启用，未知列名仍回退 generic', () {
    final chromeLike = _parseRows(<List<String>>[
      <String>['name', 'url', 'username', 'password', 'note'],
      <String>[
        'Fake Service',
        'https://example.invalid',
        'fake-user',
        'fake-password',
        'fake-note',
      ],
    ]);

    final detection = registry.detect(chromeLike);

    expect(detection.selectedAdapter.id, 'chrome_google_csv');
    expect(detection.usedGenericFallback, isFalse);
    expect(detection.requiresUserConfirmation, isFalse);
    final unknown = registry.detect(
      _parseSource('name,username,password,note'),
    );
    expect(unknown.selectedAdapter.id, 'generic_tabular');
    expect(unknown.usedGenericFallback, isTrue);
  });

  test('Cardock 中英日模板表头均精确识别并自动映射', () {
    const accountHeaders = <String>[
      '账号关联标识,平台名称,登录账号,手机号,邮箱,密码,网址,备注',
      'Account Link Key,Platform Name,Login Username,Phone,Email,Password,Website,Notes',
      'アカウント連携キー,サービス名,ログイン名,電話番号,メールアドレス,パスワード,ウェブサイト,メモ',
    ];
    const subscriptionHeaders = <String>[
      '账号关联标识,方案名称,金额,币种,计费周期,首次订阅日期,下次续费日期,自动续费,支付方式,提前提醒天数,备注',
      'Account Link Key,Plan Name,Amount,Currency,Billing Cycle,Subscription Start Date,Next Renewal Date,Auto Renew,Payment Method,Reminder Days,Notes',
      'アカウント連携キー,プラン名,金額,通貨,請求周期,初回購読日,次回更新日,自動更新,支払方法,事前通知日数,メモ',
    ];

    for (final headers in accountHeaders) {
      final document = _parseSource('$headers\nkey-1,Fake,user,,,,,note');
      final adapter = registry.detect(document).selectedAdapter;
      expect(adapter.id, 'cardock_accounts_template', reason: headers);
      final mapping = const ImportFieldMapper().mapAccounts(
        document,
        adapter: adapter,
      );
      expect(mapping.drafts.single.loginAccount, 'user');
      expect(mapping.drafts.single.notes, 'note');
    }
    for (final headers in subscriptionHeaders) {
      final adapter = registry.detect(_parseSource(headers)).selectedAdapter;
      expect(adapter.id, 'cardock_subscriptions_template', reason: headers);
    }
  });

  test('Bitwarden 精确格式仅导入 login 并排除敏感扩展字段', () {
    final document = _parseRows(<List<String>>[
      <String>[
        'folder',
        'favorite',
        'type',
        'name',
        'notes',
        'fields',
        'reprompt',
        'login_uri',
        'login_username',
        'login_password',
        'login_totp',
      ],
      <String>[
        '',
        'false',
        'login',
        'Fake Vault Service',
        'safe note',
        'fake custom field',
        'false',
        'https://example.invalid/login',
        'fake-user',
        '  fake-password  ',
        'fake-otp-value',
      ],
      <String>[
        '',
        'false',
        'secure_note',
        'Ignored Item',
        'safe note',
        '',
        'false',
        '',
        '',
        '',
        '',
      ],
    ]);
    final detection = registry.detect(document);
    final result = const ImportFieldMapper().mapAccounts(
      document,
      adapter: detection.selectedAdapter,
    );

    expect(detection.selectedAdapter.id, 'bitwarden_csv');
    expect(detection.usedGenericFallback, isFalse);
    expect(result.drafts, hasLength(1));
    expect(result.unsupportedRowCount, 1);
    expect(result.drafts.single.platformName, 'Fake Vault Service');
    expect(result.drafts.single.password, '  fake-password  ');
    expect(
      result.excludedSensitiveColumns.map((column) => column.header),
      containsAll(<String>['fields', 'login_totp']),
    );
    expect(
      result.unmappedColumns.map((column) => column.header),
      containsAll(<String>['folder', 'favorite', 'type', 'reprompt']),
    );
  });

  test('KeePassXC 与 1Password 精确表头映射且 OTP 不进入备注', () {
    final keepass = _parseRows(<List<String>>[
      <String>['Group', 'Title', 'Username', 'Password', 'URL', 'Notes'],
      <String>[
        'Fake Group',
        'Fake KeePass Service',
        'fake-user',
        'fake-pass',
        'https://keepass.example.invalid',
        'safe note',
      ],
    ]);
    final onePassword = _parseRows(<List<String>>[
      <String>[
        'Title',
        'Website',
        'Username',
        'Password',
        'One-time password',
        'Favorite status',
        'Archived status',
        'Tags',
        'Notes',
      ],
      <String>[
        'Fake 1Password Service',
        'https://onepassword.example.invalid',
        'fake-user',
        'fake-pass',
        'fake-otp',
        'false',
        'false',
        'fake-tag',
        'safe note',
      ],
    ]);

    final keepassDetection = registry.detect(keepass);
    final onePasswordDetection = registry.detect(onePassword);
    final keepassResult = const ImportFieldMapper().mapAccounts(
      keepass,
      adapter: keepassDetection.selectedAdapter,
    );
    final onePasswordResult = const ImportFieldMapper().mapAccounts(
      onePassword,
      adapter: onePasswordDetection.selectedAdapter,
    );

    expect(keepassDetection.selectedAdapter.id, 'keepassxc_csv');
    expect(keepassResult.drafts.single.password, 'fake-pass');
    expect(onePasswordDetection.selectedAdapter.id, 'onepassword_csv');
    expect(onePasswordResult.drafts.single.notes, 'safe note');
    expect(
      onePasswordResult.excludedSensitiveColumns.single.header,
      'One-time password',
    );
    expect(
      onePasswordResult.unmappedColumns.map((column) => column.header),
      containsAll(<String>['Favorite status', 'Archived status', 'Tags']),
    );
  });

  test('generic 可手动映射，但敏感列即使覆盖也被阻止', () {
    final document = _parseRows(<List<String>>[
      <String>['服务', '密码', '动态验证码', '额外列'],
      <String>['虚构服务', '  fake-pass  ', 'fake-otp', 'extra'],
    ]);
    final adapter = registry.detect(document).selectedAdapter;
    final result = const ImportFieldMapper().mapAccounts(
      document,
      adapter: adapter,
      overrides: const <int, ImportTargetField>{2: ImportTargetField.notes},
    );

    expect(adapter.id, 'generic_tabular');
    expect(result.drafts.single.password, '  fake-pass  ');
    expect(result.drafts.single.notes, isEmpty);
    expect(result.excludedSensitiveColumns.single.header, '动态验证码');
    expect(result.unmappedColumns.single.header, '额外列');
    expect(
      result.issues.map((issue) => issue.code),
      contains('sensitive_column_mapping_blocked'),
    );
  });

  test('TOTP、Passkey、信用卡、恢复码和私钥列全部敏感排除', () {
    final document = _parseRows(<List<String>>[
      <String>[
        'name',
        'password',
        'TOTP',
        'Passkey',
        'credit_card',
        'recovery_codes',
        'private_key',
        'unknown',
      ],
      <String>[
        'Fake Service',
        'fake-pass',
        'fake-totp',
        'fake-passkey',
        'fake-card',
        'fake-recovery',
        'fake-private-key',
        'extra',
      ],
    ]);
    final result = const ImportFieldMapper().mapAccounts(
      document,
      adapter: registry.detect(document).selectedAdapter,
      overrides: const <int, ImportTargetField>{
        2: ImportTargetField.notes,
        3: ImportTargetField.notes,
        4: ImportTargetField.notes,
        5: ImportTargetField.notes,
        6: ImportTargetField.notes,
      },
    );

    expect(result.excludedSensitiveColumns, hasLength(5));
    expect(result.drafts.single.notes, isEmpty);
    expect(result.unmappedColumns.single.header, 'unknown');
    expect(
      result.issues.where(
        (issue) => issue.code == 'sensitive_column_mapping_blocked',
      ),
      hasLength(5),
    );
  });

  test('品牌回调只产生建议，不改平台名、网址或密码原值', () {
    final document = _parseRows(<List<String>>[
      <String>[
        'account_key',
        'platform_name',
        'login_account',
        'phone',
        'email',
        'password',
        'url',
        'notes',
      ],
      <String>[
        'fake-account-1',
        '  Fake Service  ',
        'fake-user',
        '',
        '',
        '  fake-password  ',
        'example.invalid/raw-path',
        'safe note',
      ],
    ]);
    String? callbackPlatform;
    String? callbackUrl;
    final mapper = ImportFieldMapper(
      brandSuggestionResolver: (platformName, url) {
        callbackPlatform = platformName;
        callbackUrl = url;
        return ImportBrandSuggestionResult.exactUnique(
          'existing-catalog-brand-id',
        );
      },
    );
    final result = mapper.mapAccounts(
      document,
      adapter: registry.detect(document).selectedAdapter,
    );
    final draft = result.drafts.single;

    expect(callbackPlatform, '  Fake Service  ');
    expect(callbackUrl, 'example.invalid/raw-path');
    expect(draft.platformName, '  Fake Service  ');
    expect(draft.url, 'example.invalid/raw-path');
    expect(draft.password, '  fake-password  ');
    expect(draft.brandSuggestion, 'existing-catalog-brand-id');
  });

  test('品牌匹配 exact 唯一建议，多候选和无匹配均不猜第一项', () {
    final document = _parseRows(<List<String>>[
      <String>['name', 'url'],
      <String>['Fake Service', 'https://example.invalid'],
    ]);
    final adapter = registry.detect(document).selectedAdapter;

    AccountImportDraft mapWith(ImportBrandSuggestionResult result) =>
        ImportFieldMapper(
          brandSuggestionResolver: (platformName, url) => result,
        ).mapAccounts(document, adapter: adapter).drafts.single;

    final exact = mapWith(
      ImportBrandSuggestionResult.exactUnique('brand-exact'),
    );
    final multiple = mapWith(
      ImportBrandSuggestionResult.multipleCandidates(<String>[
        'brand-a',
        'brand-b',
      ]),
    );
    final none = mapWith(ImportBrandSuggestionResult.none());

    expect(exact.brandSuggestion, 'brand-exact');
    expect(exact.brandSuggestionCandidates, <String>['brand-exact']);
    expect(multiple.brandSuggestion, isNull);
    expect(multiple.brandSuggestionCandidates, <String>['brand-a', 'brand-b']);
    expect(none.brandSuggestion, isNull);
    expect(none.brandSuggestionCandidates, isEmpty);
  });

  test('Cardock 两模板精确检测，订阅字段按原值进入完整或待完善草稿', () {
    final accounts = _parseRows(<List<String>>[
      <String>[
        'account_key',
        'platform_name',
        'login_account',
        'phone',
        'email',
        'password',
        'url',
        'notes',
      ],
      <String>['fake-1', 'Fake', '', '', '', 'fake-pass', '', ''],
    ]);
    final subscriptions = _parseRows(<List<String>>[
      <String>[
        'account_key',
        'plan_name',
        'amount',
        'currency',
        'billing_cycle',
        'subscription_start_date',
        'next_renewal_date',
        'auto_renew',
        'payment_method',
        'reminder_days',
        'notes',
      ],
      <String>[
        'fake-1',
        'Fake Pro',
        '12.50',
        'USD',
        '每月',
        '2026-08-30',
        '2026-09-30',
        '是',
        'Fake Card',
        '3',
        'safe note',
      ],
      <String>[
        '',
        'Incomplete',
        '-1',
        'US',
        'weekly',
        '',
        '2026-02-30',
        'maybe',
        '',
        '-1',
        'safe note',
      ],
    ]);

    expect(
      registry.detect(accounts).selectedAdapter.id,
      'cardock_accounts_template',
    );
    final subscriptionDetection = registry.detect(subscriptions);
    expect(
      subscriptionDetection.selectedAdapter.id,
      'cardock_subscriptions_template',
    );
    final result = const ImportFieldMapper().mapSubscriptions(
      subscriptions,
      adapter: subscriptionDetection.selectedAdapter,
    );

    expect(result.drafts, hasLength(2));
    expect(result.drafts.first.isSyntacticallyComplete, isTrue);
    expect(result.drafts.first.amount, '12.50');
    expect(result.drafts.first.subscriptionStartDate, '2026-08-30');
    expect(normalizeSubscriptionBillingCycle('每月'), 'monthly');
    expect(parseSubscriptionAutoRenew('是'), isTrue);
    expect(parseSubscriptionDate('2026-09-30'), DateTime(2026, 9, 30));
    expect(result.drafts.last.accountKeyWasGenerated, isTrue);
    expect(result.drafts.last.isSyntacticallyComplete, isFalse);
    expect(
      result.drafts.last.missingOrInvalidFields,
      containsAll(<String>[
        'amount',
        'currency',
        'billing_cycle',
        'subscription_start_date',
        'next_renewal_date',
        'auto_renew',
        'payment_method',
        'reminder_days',
      ]),
    );
  });

  test('旧订阅模板仍精确识别但未知开始日期只能进入待完善路径', () {
    final document = _parseRows(<List<String>>[
      <String>[
        'account_key',
        'plan_name',
        'amount',
        'currency',
        'billing_cycle',
        'next_renewal_date',
        'auto_renew',
        'payment_method',
        'reminder_days',
        'notes',
      ],
      <String>[
        'legacy-account',
        'Legacy Plan',
        '10',
        'CNY',
        'monthly',
        '2026-10-01',
        'true',
        'Fake Card',
        '2',
        '',
      ],
    ]);
    final detection = registry.detect(document);
    expect(detection.selectedAdapter.id, 'cardock_subscriptions_template');
    expect(detection.usedGenericFallback, isFalse);

    final result = const ImportFieldMapper().mapSubscriptions(
      document,
      adapter: detection.selectedAdapter,
    );
    expect(result.drafts.single.subscriptionStartDate, isEmpty);
    expect(result.drafts.single.nextRenewalDate, '2026-10-01');
    expect(
      result.drafts.single.missingOrInvalidFields,
      contains('subscription_start_date'),
    );
    expect(result.drafts.single.isSyntacticallyComplete, isFalse);
  });

  test('固定周期和布尔中英日别名稳定，custom 缺周期细节保持待完善', () {
    const cycleAliases = <String, String>{
      'monthly': 'monthly',
      '每月': 'monthly',
      '毎月': 'monthly',
      'quarterly': 'quarterly',
      '每季度': 'quarterly',
      '四半期': 'quarterly',
      'semiannual': 'semiannual',
      '每半年': 'semiannual',
      '半年ごと': 'semiannual',
      'annual': 'annual',
      '每年': 'annual',
      '毎年': 'annual',
    };
    const trueAliases = <String>['true', 'yes', '1', '是', 'はい'];
    const falseAliases = <String>['false', 'no', '0', '否', 'いいえ'];
    final headers = <String>[
      'account_key',
      'plan_name',
      'amount',
      'currency',
      'billing_cycle',
      'subscription_start_date',
      'next_renewal_date',
      'auto_renew',
      'payment_method',
      'reminder_days',
      'notes',
    ];
    final rows = <List<String>>[headers];
    var index = 0;
    for (final cycle in cycleAliases.keys) {
      rows.add(<String>[
        'fake-$index',
        'Fake Plan',
        '10',
        'USD',
        cycle,
        '2026-09-01',
        '2026-10-01',
        [...trueAliases, ...falseAliases][index % 10],
        'Fake Card',
        '2',
        '',
      ]);
      index += 1;
    }
    for (final custom in <String>['custom', '自定义', 'カスタム']) {
      rows.add(<String>[
        'fake-custom-$custom',
        'Custom Plan',
        '10',
        'USD',
        custom,
        '2026-09-01',
        '2026-10-01',
        'true',
        'Fake Card',
        '2',
        '',
      ]);
    }
    final document = _parseRows(rows);
    final result = const ImportFieldMapper().mapSubscriptions(
      document,
      adapter: registry.detect(document).selectedAdapter,
    );

    for (final entry in cycleAliases.entries) {
      expect(normalizeSubscriptionBillingCycle(entry.key), entry.value);
    }
    for (final value in trueAliases) {
      expect(parseSubscriptionAutoRenew(value), isTrue, reason: value);
    }
    for (final value in falseAliases) {
      expect(parseSubscriptionAutoRenew(value), isFalse, reason: value);
    }
    expect(
      result.drafts
          .take(cycleAliases.length)
          .every((draft) => draft.isSyntacticallyComplete),
      isTrue,
    );
    for (final draft in result.drafts.skip(cycleAliases.length)) {
      expect(draft.isSyntacticallyComplete, isFalse);
      expect(draft.missingOrInvalidFields, contains('billing_cycle'));
      expect(normalizeSubscriptionBillingCycle(draft.billingCycle), 'custom');
    }
  });
}
