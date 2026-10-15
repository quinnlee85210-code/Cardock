import 'browser_password_csv.dart';
export 'browser_password_csv.dart';
import 'dart:collection';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'import_models.dart';

String normalizeImportHeader(String input) {
  final value = unorm
      .nfkc(input.replaceFirst('\uFEFF', ''))
      .trim()
      .toLowerCase();
  final output = StringBuffer();
  for (final rune in value.runes) {
    if (_headerWhitespace.contains(rune) ||
        rune == 0x005F ||
        rune == 0x002D ||
        rune == 0x2010 ||
        rune == 0x2011 ||
        rune == 0x2013 ||
        rune == 0x2014) {
      continue;
    }
    output.writeCharCode(rune);
  }
  return output.toString();
}

final class ImportSourceAdapter {
  ImportSourceAdapter({
    required this.id,
    required this.displayName,
    required this.itemKind,
    required this.enabled,
    required this.verified,
    required List<String> exactHeaders,
    List<List<String>> alternativeExactHeaders = const <List<String>>[],
    Map<String, ImportTargetField> defaultMappings =
        const <String, ImportTargetField>{},
    Set<String> ignoredHeaders = const <String>{},
    Set<String> sensitiveHeaders = const <String>{},
    Set<String> optionalExactHeaders = const <String>{},
    this.typeHeader,
    this.acceptedTypeValue,
    this.isGeneric = false,
  }) : exactHeaders = List<String>.unmodifiable(exactHeaders),
       normalizedExactHeaders = List<String>.unmodifiable(
         exactHeaders.map(normalizeImportHeader),
       ),
       normalizedHeaderLayouts = List<List<String>>.unmodifiable(<List<String>>[
         List<String>.unmodifiable(exactHeaders.map(normalizeImportHeader)),
         ...alternativeExactHeaders.map(
           (headers) =>
               List<String>.unmodifiable(headers.map(normalizeImportHeader)),
         ),
       ]),
       defaultMappings = UnmodifiableMapView<String, ImportTargetField>(
         <String, ImportTargetField>{
           for (final entry in defaultMappings.entries)
             normalizeImportHeader(entry.key): entry.value,
         },
       ),
       ignoredHeaders = Set<String>.unmodifiable(
         ignoredHeaders.map(normalizeImportHeader),
       ),
       sensitiveHeaders = Set<String>.unmodifiable(
         sensitiveHeaders.map(normalizeImportHeader),
       ),
       optionalExactHeaders = Set<String>.unmodifiable(
         optionalExactHeaders.map(normalizeImportHeader),
       );

  final String id;
  final String displayName;
  final ImportItemKind itemKind;
  final bool enabled;
  final bool verified;
  final List<String> exactHeaders;
  final List<String> normalizedExactHeaders;
  final List<List<String>> normalizedHeaderLayouts;
  final Map<String, ImportTargetField> defaultMappings;
  final Set<String> ignoredHeaders;
  final Set<String> sensitiveHeaders;
  final Set<String> optionalExactHeaders;
  final String? typeHeader;
  final String? acceptedTypeValue;
  final bool isGeneric;

  double confidenceFor(TabularDocument document) {
    if (!enabled || !verified) return 0;
    if (isGeneric) return 0.05;
    if (isBrowserPasswordSourceId(id)) {
      if (document.delimiter != ',' ||
          {
            TabularSourceEncoding.xlsx,
            TabularSourceEncoding.docx,
          }.contains(document.encoding)) {
        return 0;
      }
      final headers = document.headers
          .map((h) => h.trim().toLowerCase())
          .toList();
      final expected = [
        'name',
        'url',
        'username',
        'password',
        if (headers.length == 5) 'note',
      ];
      return headers.length == expected.length &&
              List.generate(
                headers.length,
                (i) => headers[i] == expected[i],
              ).every((v) => v)
          ? 1
          : 0;
    }
    final actual = document.headers.map(normalizeImportHeader).toList();
    final acceptedHeaders = <List<String>>[
      for (final layout in normalizedHeaderLayouts) ...<List<String>>[
        layout,
        if (optionalExactHeaders.isNotEmpty)
          layout
              .where((header) => !optionalExactHeaders.contains(header))
              .toList(growable: false),
      ],
    ];
    for (final expected in acceptedHeaders) {
      if (actual.length != expected.length) continue;
      var matches = true;
      for (var index = 0; index < actual.length; index += 1) {
        if (actual[index] != expected[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return 1;
    }
    return 0;
  }

  Map<String, Object?> toMetadataJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'itemKind': itemKind.name,
    'enabled': enabled,
    'verified': verified,
    'isGeneric': isGeneric,
  };
}

final class ImportSourceMatch {
  const ImportSourceMatch({required this.adapter, required this.confidence});

  final ImportSourceAdapter adapter;
  final double confidence;

  Map<String, Object?> toJson() => <String, Object?>{
    ...adapter.toMetadataJson(),
    'confidence': confidence,
  };
}

final class ImportSourceDetection {
  ImportSourceDetection({
    required this.selectedAdapter,
    required List<ImportSourceMatch> matches,
    required this.usedGenericFallback,
    required this.requiresUserConfirmation,
  }) : matches = List<ImportSourceMatch>.unmodifiable(matches);

  final ImportSourceAdapter selectedAdapter;
  final List<ImportSourceMatch> matches;
  final bool usedGenericFallback;
  final bool requiresUserConfirmation;

  Map<String, Object?> toJson() => <String, Object?>{
    'selectedAdapter': selectedAdapter.toMetadataJson(),
    'matches': matches.map((match) => match.toJson()).toList(growable: false),
    'usedGenericFallback': usedGenericFallback,
    'requiresUserConfirmation': requiresUserConfirmation,
  };
}

final class ImportSourceRegistry {
  ImportSourceRegistry(List<ImportSourceAdapter> adapters)
    : adapters = List<ImportSourceAdapter>.unmodifiable(adapters),
      _byId = UnmodifiableMapView<String, ImportSourceAdapter>(
        <String, ImportSourceAdapter>{
          for (final adapter in adapters) adapter.id: adapter,
        },
      ) {
    if (_byId.length != adapters.length) {
      throw ArgumentError('Import source adapter IDs must be unique.');
    }
    if (!_byId.containsKey('generic_tabular')) {
      throw ArgumentError('The generic_tabular adapter is required.');
    }
  }

  factory ImportSourceRegistry.standard() =>
      ImportSourceRegistry(<ImportSourceAdapter>[
        _browserAdapter(
          'chrome_google_csv',
          'Chrome / Google Password Manager compatible CSV',
        ),
        _browserAdapter('chrome_passwords_csv', 'Chrome 密码 CSV'),
        _browserAdapter(
          'google_password_manager_csv',
          'Google Password Manager CSV',
        ),
        _disabledAdapter(
          id: 'chrome_edge_google_csv',
          displayName: 'Legacy browser CSV alias',
        ),
        _disabledAdapter(id: 'firefox_csv', displayName: 'Firefox CSV'),
        _disabledAdapter(
          id: 'apple_passwords_csv',
          displayName: 'Apple Passwords compatible CSV',
        ),
        _bitwardenAdapter,
        _onePasswordAdapter,
        _keepassXcAdapter,
        _cardockAccountsAdapter,
        _cardockSubscriptionsAdapter,
        _genericAdapter,
      ]);

  final List<ImportSourceAdapter> adapters;
  final Map<String, ImportSourceAdapter> _byId;

  ImportSourceAdapter adapterById(String id) {
    final adapter = _byId[id];
    if (adapter == null) {
      throw ArgumentError.value(id, 'id', 'Unknown adapter.');
    }
    return adapter;
  }

  ImportSourceDetection detect(TabularDocument document) {
    final matches = <ImportSourceMatch>[];
    for (final adapter in adapters) {
      if (isBrowserPasswordSourceId(adapter.id) &&
          adapter.id != 'chrome_google_csv') {
        continue;
      }
      final confidence = adapter.confidenceFor(document);
      if (confidence > 0) {
        matches.add(
          ImportSourceMatch(adapter: adapter, confidence: confidence),
        );
      }
    }
    matches.sort((a, b) => b.confidence.compareTo(a.confidence));
    final dedicated = matches
        .where((match) => !match.adapter.isGeneric)
        .toList(growable: false);
    if (dedicated.isEmpty) {
      final generic = adapterById('generic_tabular');
      return ImportSourceDetection(
        selectedAdapter: generic,
        matches: matches,
        usedGenericFallback: true,
        requiresUserConfirmation: false,
      );
    }
    final best = dedicated.first;
    final closeMatches = dedicated
        .where((match) => (best.confidence - match.confidence).abs() < 0.1)
        .toList(growable: false);
    return ImportSourceDetection(
      selectedAdapter: best.adapter,
      matches: matches,
      usedGenericFallback: false,
      requiresUserConfirmation: closeMatches.length > 1,
    );
  }
}

ImportSourceAdapter _browserAdapter(String id, String name) =>
    ImportSourceAdapter(
      id: id,
      displayName: name,
      itemKind: ImportItemKind.account,
      enabled: true,
      verified: true,
      exactHeaders: const ['name', 'url', 'username', 'password', 'note'],
      optionalExactHeaders: const {'note'},
      defaultMappings: const {
        'name': ImportTargetField.platformName,
        'url': ImportTargetField.url,
        'username': ImportTargetField.loginAccount,
        'password': ImportTargetField.password,
        'note': ImportTargetField.notes,
      },
    );

ImportSourceAdapter _disabledAdapter({
  required String id,
  required String displayName,
}) => ImportSourceAdapter(
  id: id,
  displayName: displayName,
  itemKind: ImportItemKind.account,
  enabled: false,
  verified: false,
  exactHeaders: const <String>[],
);

final _bitwardenAdapter = ImportSourceAdapter(
  id: 'bitwarden_csv',
  displayName: 'Bitwarden CSV',
  itemKind: ImportItemKind.account,
  enabled: true,
  verified: true,
  exactHeaders: const <String>[
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
  defaultMappings: const <String, ImportTargetField>{
    'name': ImportTargetField.platformName,
    'notes': ImportTargetField.notes,
    'login_uri': ImportTargetField.url,
    'login_username': ImportTargetField.loginAccount,
    'login_password': ImportTargetField.password,
  },
  ignoredHeaders: const <String>{'folder', 'favorite', 'type', 'reprompt'},
  sensitiveHeaders: const <String>{'fields', 'login_totp'},
  typeHeader: 'type',
  acceptedTypeValue: 'login',
);

final _keepassXcAdapter = ImportSourceAdapter(
  id: 'keepassxc_csv',
  displayName: 'KeePassXC CSV',
  itemKind: ImportItemKind.account,
  enabled: true,
  verified: true,
  exactHeaders: const <String>[
    'Group',
    'Title',
    'Username',
    'Password',
    'URL',
    'Notes',
  ],
  defaultMappings: const <String, ImportTargetField>{
    'Title': ImportTargetField.platformName,
    'Username': ImportTargetField.loginAccount,
    'Password': ImportTargetField.password,
    'URL': ImportTargetField.url,
    'Notes': ImportTargetField.notes,
  },
  ignoredHeaders: const <String>{'Group'},
);

final _onePasswordAdapter = ImportSourceAdapter(
  id: 'onepassword_csv',
  displayName: '1Password CSV',
  itemKind: ImportItemKind.account,
  enabled: true,
  verified: true,
  exactHeaders: const <String>[
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
  defaultMappings: const <String, ImportTargetField>{
    'Title': ImportTargetField.platformName,
    'Website': ImportTargetField.url,
    'Username': ImportTargetField.loginAccount,
    'Password': ImportTargetField.password,
    'Notes': ImportTargetField.notes,
  },
  ignoredHeaders: const <String>{'Favorite status', 'Archived status', 'Tags'},
  sensitiveHeaders: const <String>{'One-time password'},
);

final _cardockAccountsAdapter = ImportSourceAdapter(
  id: 'cardock_accounts_template',
  displayName: 'Cardock accounts template',
  itemKind: ImportItemKind.account,
  enabled: true,
  verified: true,
  exactHeaders: const <String>[
    'account_key',
    'platform_name',
    'login_account',
    'phone',
    'email',
    'password',
    'url',
    'notes',
  ],
  alternativeExactHeaders: const <List<String>>[
    <String>['账号关联标识', '平台名称', '登录账号', '手机号', '邮箱', '密码', '网址', '备注'],
    <String>[
      'Account Link Key',
      'Platform Name',
      'Login Username',
      'Phone',
      'Email',
      'Password',
      'Website',
      'Notes',
    ],
    <String>[
      'アカウント連携キー',
      'サービス名',
      'ログイン名',
      '電話番号',
      'メールアドレス',
      'パスワード',
      'ウェブサイト',
      'メモ',
    ],
  ],
  defaultMappings: const <String, ImportTargetField>{
    'account_key': ImportTargetField.accountKey,
    'platform_name': ImportTargetField.platformName,
    'login_account': ImportTargetField.loginAccount,
    'phone': ImportTargetField.phone,
    'email': ImportTargetField.email,
    'password': ImportTargetField.password,
    'url': ImportTargetField.url,
    'notes': ImportTargetField.notes,
    '账号关联标识': ImportTargetField.accountKey,
    '平台名称': ImportTargetField.platformName,
    '登录账号': ImportTargetField.loginAccount,
    '手机号': ImportTargetField.phone,
    '邮箱': ImportTargetField.email,
    '密码': ImportTargetField.password,
    '网址': ImportTargetField.url,
    '备注': ImportTargetField.notes,
    'Account Link Key': ImportTargetField.accountKey,
    'Platform Name': ImportTargetField.platformName,
    'Login Username': ImportTargetField.loginAccount,
    'Phone': ImportTargetField.phone,
    'Email': ImportTargetField.email,
    'Password': ImportTargetField.password,
    'Website': ImportTargetField.url,
    'Notes': ImportTargetField.notes,
    'アカウント連携キー': ImportTargetField.accountKey,
    'サービス名': ImportTargetField.platformName,
    'ログイン名': ImportTargetField.loginAccount,
    '電話番号': ImportTargetField.phone,
    'メールアドレス': ImportTargetField.email,
    'パスワード': ImportTargetField.password,
    'ウェブサイト': ImportTargetField.url,
    'メモ': ImportTargetField.notes,
  },
);

final _cardockSubscriptionsAdapter = ImportSourceAdapter(
  id: 'cardock_subscriptions_template',
  displayName: 'Cardock subscriptions template',
  itemKind: ImportItemKind.subscription,
  enabled: true,
  verified: true,
  exactHeaders: const <String>[
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
  alternativeExactHeaders: const <List<String>>[
    <String>[
      '账号关联标识',
      '方案名称',
      '金额',
      '币种',
      '计费周期',
      '首次订阅日期',
      '下次续费日期',
      '自动续费',
      '支付方式',
      '提前提醒天数',
      '备注',
    ],
    <String>[
      'Account Link Key',
      'Plan Name',
      'Amount',
      'Currency',
      'Billing Cycle',
      'Subscription Start Date',
      'Next Renewal Date',
      'Auto Renew',
      'Payment Method',
      'Reminder Days',
      'Notes',
    ],
    <String>[
      'アカウント連携キー',
      'プラン名',
      '金額',
      '通貨',
      '請求周期',
      '初回購読日',
      '次回更新日',
      '自動更新',
      '支払方法',
      '事前通知日数',
      'メモ',
    ],
  ],
  defaultMappings: const <String, ImportTargetField>{
    'account_key': ImportTargetField.accountKey,
    'plan_name': ImportTargetField.planName,
    'amount': ImportTargetField.amount,
    'currency': ImportTargetField.currency,
    'billing_cycle': ImportTargetField.billingCycle,
    'subscription_start_date': ImportTargetField.subscriptionStartDate,
    'next_renewal_date': ImportTargetField.nextRenewalDate,
    'auto_renew': ImportTargetField.autoRenew,
    'payment_method': ImportTargetField.paymentMethod,
    'reminder_days': ImportTargetField.reminderDays,
    'notes': ImportTargetField.notes,
    '账号关联标识': ImportTargetField.accountKey,
    '方案名称': ImportTargetField.planName,
    '金额': ImportTargetField.amount,
    '币种': ImportTargetField.currency,
    '计费周期': ImportTargetField.billingCycle,
    '首次订阅日期': ImportTargetField.subscriptionStartDate,
    '下次续费日期': ImportTargetField.nextRenewalDate,
    '自动续费': ImportTargetField.autoRenew,
    '支付方式': ImportTargetField.paymentMethod,
    '提前提醒天数': ImportTargetField.reminderDays,
    '备注': ImportTargetField.notes,
    'Account Link Key': ImportTargetField.accountKey,
    'Plan Name': ImportTargetField.planName,
    'Amount': ImportTargetField.amount,
    'Currency': ImportTargetField.currency,
    'Billing Cycle': ImportTargetField.billingCycle,
    'Subscription Start Date': ImportTargetField.subscriptionStartDate,
    'Next Renewal Date': ImportTargetField.nextRenewalDate,
    'Auto Renew': ImportTargetField.autoRenew,
    'Payment Method': ImportTargetField.paymentMethod,
    'Reminder Days': ImportTargetField.reminderDays,
    'Notes': ImportTargetField.notes,
    'アカウント連携キー': ImportTargetField.accountKey,
    'プラン名': ImportTargetField.planName,
    '金額': ImportTargetField.amount,
    '通貨': ImportTargetField.currency,
    '請求周期': ImportTargetField.billingCycle,
    '初回購読日': ImportTargetField.subscriptionStartDate,
    '次回更新日': ImportTargetField.nextRenewalDate,
    '自動更新': ImportTargetField.autoRenew,
    '支払方法': ImportTargetField.paymentMethod,
    '事前通知日数': ImportTargetField.reminderDays,
    'メモ': ImportTargetField.notes,
  },
  optionalExactHeaders: const <String>{
    'subscription_start_date',
    '首次订阅日期',
    'Subscription Start Date',
    '初回購読日',
  },
);

final _genericAdapter = ImportSourceAdapter(
  id: 'generic_tabular',
  displayName: 'Generic CSV / TSV',
  itemKind: ImportItemKind.account,
  enabled: true,
  verified: true,
  exactHeaders: const <String>[],
  isGeneric: true,
  defaultMappings: _genericMappings,
  sensitiveHeaders: _genericSensitiveHeaders,
);

const _genericMappings = <String, ImportTargetField>{
  'name': ImportTargetField.platformName,
  'title': ImportTargetField.platformName,
  'service': ImportTargetField.platformName,
  'site': ImportTargetField.platformName,
  'platform': ImportTargetField.platformName,
  'website_name': ImportTargetField.platformName,
  '平台': ImportTargetField.platformName,
  '平台名称': ImportTargetField.platformName,
  '名称': ImportTargetField.platformName,
  '服务': ImportTargetField.platformName,
  '标题': ImportTargetField.platformName,
  'タイトル': ImportTargetField.platformName,
  'サービス': ImportTargetField.platformName,
  'サービス名': ImportTargetField.platformName,
  'サイト名': ImportTargetField.platformName,
  'url': ImportTargetField.url,
  'uri': ImportTargetField.url,
  'website': ImportTargetField.url,
  'site_url': ImportTargetField.url,
  'login_uri': ImportTargetField.url,
  '网址': ImportTargetField.url,
  '网站': ImportTargetField.url,
  '网站地址': ImportTargetField.url,
  'ウェブサイト': ImportTargetField.url,
  'サイトURL': ImportTargetField.url,
  'username': ImportTargetField.loginAccount,
  'user': ImportTargetField.loginAccount,
  'login': ImportTargetField.loginAccount,
  'login_username': ImportTargetField.loginAccount,
  'account': ImportTargetField.loginAccount,
  'account_name': ImportTargetField.loginAccount,
  '登录账号': ImportTargetField.loginAccount,
  '用户名': ImportTargetField.loginAccount,
  '账号': ImportTargetField.loginAccount,
  '帐号': ImportTargetField.loginAccount,
  'ユーザー名': ImportTargetField.loginAccount,
  'ログイン名': ImportTargetField.loginAccount,
  'アカウント': ImportTargetField.loginAccount,
  'password': ImportTargetField.password,
  'pass': ImportTargetField.password,
  'login_password': ImportTargetField.password,
  '密码': ImportTargetField.password,
  'パスワード': ImportTargetField.password,
  'email': ImportTargetField.email,
  'e-mail': ImportTargetField.email,
  'mail': ImportTargetField.email,
  'email_address': ImportTargetField.email,
  '邮箱': ImportTargetField.email,
  '电子邮箱': ImportTargetField.email,
  'メール': ImportTargetField.email,
  'メールアドレス': ImportTargetField.email,
  'phone': ImportTargetField.phone,
  'mobile': ImportTargetField.phone,
  'telephone': ImportTargetField.phone,
  'tel': ImportTargetField.phone,
  '手机号': ImportTargetField.phone,
  '手机': ImportTargetField.phone,
  '电话': ImportTargetField.phone,
  '電話番号': ImportTargetField.phone,
  '携帯番号': ImportTargetField.phone,
  'note': ImportTargetField.notes,
  'notes': ImportTargetField.notes,
  'memo': ImportTargetField.notes,
  'comment': ImportTargetField.notes,
  'comments': ImportTargetField.notes,
  '备注': ImportTargetField.notes,
  '说明': ImportTargetField.notes,
  'メモ': ImportTargetField.notes,
  '備考': ImportTargetField.notes,
  'コメント': ImportTargetField.notes,
};

const _genericSensitiveHeaders = <String>{
  'fields',
  'totp',
  'login_totp',
  'otpauth',
  'otp_auth',
  'passkey',
  'webauthn',
  'recovery_code',
  'recovery_codes',
  'private_key',
  'ssh_private_key',
  'api_private_key',
  'credit_card',
  'card_number',
  'secret_answer',
  'one-time password',
  '动态验证码',
  '恢复码',
  '私钥',
  '秘密问题答案',
};

const _headerWhitespace = <int>{
  0x0009,
  0x000A,
  0x000B,
  0x000C,
  0x000D,
  0x0020,
  0x0085,
  0x00A0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200A,
  0x2028,
  0x2029,
  0x202F,
  0x205F,
  0x3000,
};
