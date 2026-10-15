import 'password_change_record.dart';
import 'account_custom_field.dart';

export 'password_change_record.dart';
export 'account_custom_field.dart';
export 'binding_retirement_plan.dart';
export 'password_health_ignore_rule.dart';

const accountCategories = <String>[
  'AI工具',
  '影音娱乐',
  '购物',
  '社交',
  '办公',
  '云服务',
  '金融',
  '保险',
  '其他',
];

/// 返回内置分类与现有账号自定义分类合并后的唯一候选。
///
/// 内置分类保持固定顺序；自定义分类按首次出现在保险库中的顺序追加。
/// 比较时忽略英文大小写，避免同名候选在下拉框中重复出现。
List<String> accountCategoryOptions(Iterable<AccountRecord> accounts) {
  final result = <String>[];
  final normalized = <String>{};

  void add(String? value) {
    final category = value?.trim();
    if (category == null || category.isEmpty) return;
    if (normalized.add(category.toLowerCase())) {
      result.add(category);
    }
  }

  for (final category in accountCategories) {
    add(category);
  }
  for (final account in accounts) {
    add(account.category);
  }
  return List<String>.unmodifiable(result);
}

enum AccountPasswordUpdateMode { preserve, replace, clear }

enum PasswordSyncState {
  unknown,
  needsReview,
  verified,
  externalChangePendingSync,
}

const passwordReviewIntervalOptions = <int>{90, 180, 365};

extension AccountPasswordUpdateModeLabel on AccountPasswordUpdateMode {
  String get label => switch (this) {
    AccountPasswordUpdateMode.preserve => '保留现有密码',
    AccountPasswordUpdateMode.replace => '替换密码',
    AccountPasswordUpdateMode.clear => '清除已保存密码',
  };
}

final class AccountDraft {
  factory AccountDraft({
    required String platformName,
    String? category,
    String? loginAccount,
    String? username,
    String? boundPhone,
    String? boundEmail,
    String? password,
    String? website,
    String? notes,
    List<AccountCustomField> customFields = const [],
  }) {
    final normalizedPlatformName = _requiredPlatformName(platformName);

    return AccountDraft._(
      platformName: normalizedPlatformName,
      category: _trimToNull(category, maxLength: 100, fieldName: '分类'),
      loginAccount: _trimToNull(
        loginAccount,
        maxLength: 512,
        fieldName: '登录账号',
      ),
      username: _trimToNull(username, maxLength: 512, fieldName: '用户名'),
      boundPhone: _trimToNull(boundPhone, maxLength: 100, fieldName: '绑定手机号'),
      boundEmail: _trimToNull(boundEmail, maxLength: 320, fieldName: '绑定邮箱'),
      password: _passwordToNull(password),
      website: _trimToNull(website, maxLength: 2048, fieldName: '网址'),
      notes: _trimToNull(notes, maxLength: 10000, fieldName: '备注'),
      customFields: validateAccountCustomFields(customFields),
    );
  }

  const AccountDraft._({
    required this.platformName,
    this.category,
    this.loginAccount,
    this.username,
    this.boundPhone,
    this.boundEmail,
    this.password,
    this.website,
    this.notes,
    this.customFields = const [],
  });

  final String platformName;
  final String? category;
  final String? loginAccount;
  final String? username;
  final String? boundPhone;
  final String? boundEmail;
  final String? password;
  final String? website;
  final String? notes;
  final List<AccountCustomField> customFields;

  static String _requiredPlatformName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('平台或应用名称不能为空');
    }
    if (normalized.runes.length > 100) {
      throw ArgumentError('平台或应用名称过长');
    }
    return normalized;
  }

  static String? _trimToNull(
    String? value, {
    required int maxLength,
    required String fieldName,
  }) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    if (normalized.runes.length > maxLength) {
      throw ArgumentError('$fieldName内容过长');
    }
    return normalized;
  }

  static String? _passwordToNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.runes.length > 4096) {
      throw ArgumentError('登录密码内容过长');
    }
    return value;
  }
}

final class AccountRecord {
  const AccountRecord._({
    required this.id,
    required this.platformName,
    this.category,
    this.loginAccount,
    this.username,
    this.boundPhone,
    this.boundEmail,
    this.password,
    this.website,
    this.notes,
    this.passwordStoredAtUtc,
    this.passwordSyncState = PasswordSyncState.unknown,
    this.passwordVerifiedAtUtc,
    this.platformPasswordChangedAtUtc,
    this.passwordReviewIntervalDays,
    this.passwordReviewSnoozedUntilUtc,
    this.passwordChangeHistory = const <PasswordChangeRecord>[],
    this.customFields = const [],
    this.passwordValueRevision = 0,
  });

  factory AccountRecord.fromDraft({
    required String id,
    required AccountDraft draft,
    DateTime? passwordStoredAtUtc,
    PasswordSyncState passwordSyncState = PasswordSyncState.unknown,
    DateTime? passwordVerifiedAtUtc,
    DateTime? platformPasswordChangedAtUtc,
    int? passwordReviewIntervalDays,
    DateTime? passwordReviewSnoozedUntilUtc,
    List<PasswordChangeRecord> passwordChangeHistory = const [],
    int? passwordValueRevision,
  }) {
    final record = AccountRecord._(
      id: id,
      platformName: draft.platformName,
      category: draft.category,
      loginAccount: draft.loginAccount,
      username: draft.username,
      boundPhone: draft.boundPhone,
      boundEmail: draft.boundEmail,
      password: draft.password,
      website: draft.website,
      notes: draft.notes,
      passwordStoredAtUtc: passwordStoredAtUtc?.toUtc(),
      passwordSyncState: passwordSyncState,
      passwordVerifiedAtUtc: passwordVerifiedAtUtc?.toUtc(),
      platformPasswordChangedAtUtc: platformPasswordChangedAtUtc?.toUtc(),
      passwordReviewIntervalDays: passwordReviewIntervalDays,
      passwordReviewSnoozedUntilUtc: passwordReviewSnoozedUntilUtc?.toUtc(),
      passwordChangeHistory: List.unmodifiable(passwordChangeHistory),
      customFields: draft.customFields,
      passwordValueRevision:
          passwordValueRevision ?? (draft.password == null ? 0 : 1),
    );
    record._validatePasswordReviewMetadata();
    return record;
  }

  factory AccountRecord.fromEncryptedPayloadJson(
    Object? value, {
    bool allowPasswordReviewMetadata = true,
    bool allowPasswordChangeHistory = true,
    bool allowStage3Metadata = true,
  }) {
    try {
      if (value is! Map<Object?, Object?>) {
        throw const FormatException('账号记录格式无效');
      }
      final id = value['id'];
      if (id is! String || id.isEmpty || id.runes.length > 128) {
        throw const FormatException('账号记录格式无效');
      }

      String? optionalString(String name) {
        final field = value[name];
        if (field == null) {
          return null;
        }
        if (field is! String) {
          throw const FormatException('账号记录格式无效');
        }
        return field;
      }

      DateTime? optionalUtc(String name) {
        final field = value[name];
        if (field == null) return null;
        if (!allowPasswordReviewMetadata) return null;
        if (field is! String) {
          throw const FormatException('账号记录格式无效');
        }
        final parsed = DateTime.tryParse(field);
        if (parsed == null ||
            !parsed.isUtc ||
            parsed.toIso8601String() != field) {
          throw const FormatException('账号记录格式无效');
        }
        return parsed;
      }

      final rawSyncState = value['passwordSyncState'];
      if (allowPasswordReviewMetadata && rawSyncState is! String) {
        throw const FormatException('账号记录格式无效');
      }
      final syncState = allowPasswordReviewMetadata
          ? PasswordSyncState.values
                .where((candidate) => candidate.name == rawSyncState)
                .firstOrNull
          : PasswordSyncState.unknown;
      if (syncState == null) {
        throw const FormatException('账号记录格式无效');
      }
      final rawReviewInterval = value['passwordReviewIntervalDays'];
      if (rawReviewInterval != null &&
          allowPasswordReviewMetadata &&
          rawReviewInterval is! int) {
        throw const FormatException('账号记录格式无效');
      }

      final platformName = value['platformName'];
      if (platformName is! String) {
        throw const FormatException('账号记录格式无效');
      }

      final rawHistory = allowPasswordChangeHistory
          ? value['passwordChangeHistory'] ?? const <Object?>[]
          : const <Object?>[];
      if (rawHistory is! List<Object?> || rawHistory.length > 10000) {
        throw const FormatException('密码变更记录无效');
      }
      final rawFields = allowStage3Metadata
          ? value['customFields'] ?? const <Object?>[]
          : const <Object?>[];
      final rawRevision = allowStage3Metadata
          ? value['passwordValueRevision']
          : null;
      if (rawFields is! List<Object?> ||
          rawFields.length > 10 ||
          rawRevision != null && rawRevision is! int) {
        throw const FormatException('账号扩展记录格式无效');
      }
      return AccountRecord.fromDraft(
        id: id,
        draft: AccountDraft(
          platformName: platformName,
          category: optionalString('category'),
          loginAccount: optionalString('loginAccount'),
          username: optionalString('username'),
          boundPhone: optionalString('boundPhone'),
          boundEmail: optionalString('boundEmail'),
          password: optionalString('password'),
          website: optionalString('website'),
          notes: optionalString('notes'),
          customFields: rawFields.map(AccountCustomField.fromJson).toList(),
        ),
        passwordValueRevision: rawRevision as int?,
        passwordStoredAtUtc: optionalUtc('passwordStoredAtUtc'),
        passwordChangeHistory: rawHistory
            .map(PasswordChangeRecord.fromJson)
            .toList(),
        passwordSyncState: syncState,
        passwordVerifiedAtUtc: optionalUtc('passwordVerifiedAtUtc'),
        platformPasswordChangedAtUtc: optionalUtc(
          'platformPasswordChangedAtUtc',
        ),
        passwordReviewIntervalDays: allowPasswordReviewMetadata
            ? rawReviewInterval as int?
            : null,
        passwordReviewSnoozedUntilUtc: optionalUtc(
          'passwordReviewSnoozedUntilUtc',
        ),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError {
      throw const FormatException('账号记录格式无效');
    }
  }

  final String id;
  final String platformName;
  final String? category;
  final String? loginAccount;
  final String? username;
  final String? boundPhone;
  final String? boundEmail;
  final String? password;
  final String? website;
  final String? notes;
  final DateTime? passwordStoredAtUtc;
  final PasswordSyncState passwordSyncState;
  final DateTime? passwordVerifiedAtUtc;
  final DateTime? platformPasswordChangedAtUtc;
  final int? passwordReviewIntervalDays;
  final DateTime? passwordReviewSnoozedUntilUtc;
  final List<PasswordChangeRecord> passwordChangeHistory;
  final List<AccountCustomField> customFields;
  final int passwordValueRevision;

  /// Value changes include clearing and first setting; history stays separate.
  int revisionAfterPasswordSave(String? next) {
    final normalized = next == null || next.isEmpty ? null : next;
    if (password == normalized) return passwordValueRevision;
    if (passwordValueRevision >= 9007199254740991) {
      throw StateError('密码值修订已达到本机安全上限');
    }
    return passwordValueRevision + 1;
  }

  /// Initial entry, unchanged saves and removing a saved value are not changes.
  List<PasswordChangeRecord> historyAfterPasswordSave(
    String? next,
    DateTime now,
  ) => password != null && next != null && password != next
      ? <PasswordChangeRecord>[
          ...passwordChangeHistory,
          PasswordChangeRecord(
            changedAtUtc: now,
            previousStoredAtUtc: passwordStoredAtUtc,
          ),
        ]
      : passwordChangeHistory;

  DateTime? passwordReviewDueAtUtc({DateTime? nowUtc}) {
    if (password == null || passwordReviewIntervalDays == null) return null;
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final snoozed = passwordReviewSnoozedUntilUtc;
    if (snoozed != null && snoozed.isAfter(now)) return snoozed;
    if (passwordSyncState != PasswordSyncState.verified ||
        passwordVerifiedAtUtc == null) {
      return now;
    }
    return passwordVerifiedAtUtc!.add(
      Duration(days: passwordReviewIntervalDays!),
    );
  }

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'id': id,
    'platformName': platformName,
    'category': category,
    'loginAccount': loginAccount,
    'username': username,
    'boundPhone': boundPhone,
    'boundEmail': boundEmail,
    'password': password,
    'website': website,
    'notes': notes,
    'customFields': customFields.map((field) => field.toJson()).toList(),
    'passwordValueRevision': passwordValueRevision,
    'passwordStoredAtUtc': passwordStoredAtUtc?.toIso8601String(),
    'passwordChangeHistory': passwordChangeHistory
        .map((event) => event.toJson())
        .toList(),
    'passwordSyncState': passwordSyncState.name,
    'passwordVerifiedAtUtc': passwordVerifiedAtUtc?.toIso8601String(),
    'platformPasswordChangedAtUtc': platformPasswordChangedAtUtc
        ?.toIso8601String(),
    'passwordReviewIntervalDays': passwordReviewIntervalDays,
    'passwordReviewSnoozedUntilUtc': passwordReviewSnoozedUntilUtc
        ?.toIso8601String(),
  };

  bool matches(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    return <String?>[
      platformName,
      category,
      loginAccount,
      username,
      boundPhone,
      boundEmail,
      website,
      notes,
      ...customFields.map((field) => field.name),
      ...customFields
          .where((field) => !field.isSensitive)
          .map((field) => field.value),
    ].whereType<String>().any(
      (value) => value.toLowerCase().contains(normalizedQuery),
    );
  }

  void _validatePasswordReviewMetadata() {
    if (passwordValueRevision < 0 ||
        passwordValueRevision > 9007199254740991 ||
        password != null && passwordValueRevision == 0) {
      throw ArgumentError('密码值修订无效');
    }
    if (passwordChangeHistory.length > 10000) {
      throw ArgumentError('密码变更记录已达到本机安全上限');
    }
    void validateUtc(DateTime? value) {
      if (value != null &&
          (!value.isUtc || value.year < 1970 || value.year > 2300)) {
        throw ArgumentError('密码复核时间无效');
      }
    }

    validateUtc(passwordStoredAtUtc);
    validateUtc(passwordVerifiedAtUtc);
    validateUtc(platformPasswordChangedAtUtc);
    validateUtc(passwordReviewSnoozedUntilUtc);
    if (passwordReviewIntervalDays != null &&
        !passwordReviewIntervalOptions.contains(passwordReviewIntervalDays)) {
      throw ArgumentError('密码复核周期无效');
    }
    if (passwordReviewSnoozedUntilUtc != null &&
        passwordReviewIntervalDays == null) {
      throw ArgumentError('稍后提醒必须先开启密码复核周期');
    }
    if (password == null &&
        (passwordStoredAtUtc != null ||
            passwordSyncState != PasswordSyncState.unknown ||
            passwordVerifiedAtUtc != null ||
            platformPasswordChangedAtUtc != null ||
            passwordReviewIntervalDays != null ||
            passwordReviewSnoozedUntilUtc != null)) {
      throw ArgumentError('未保存密码时不能保留密码复核状态');
    }
    if (passwordSyncState == PasswordSyncState.verified &&
        passwordVerifiedAtUtc == null) {
      throw ArgumentError('已核对状态必须保存用户确认时间');
    }
    if (passwordSyncState == PasswordSyncState.externalChangePendingSync &&
        platformPasswordChangedAtUtc == null) {
      throw ArgumentError('平台改密待同步状态必须保存用户标记时间');
    }
  }
}
