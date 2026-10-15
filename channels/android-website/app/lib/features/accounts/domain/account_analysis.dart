import 'dart:convert';
import 'package:cryptography/dart.dart';

import '../../../core/security/account_comparison.dart';
import '../../../core/security/vault_contract.dart';
import '../../subscriptions/domain/subscription_insights.dart';
import 'account_record.dart';

export 'binding_retirement_plan.dart';
export 'password_health_ignore_rule.dart';

enum PasswordHealthSeverity { priority, optimization, verification }

enum AccountFilter {
  hasPassword,
  noPassword,
  hasPhone,
  hasEmail,
  hasSubscription,
  noSubscription,
  hasPendingDraft,
  hasAttentionSubscription,
  hasDuplicate,
  hasPasswordHealth,
  hasBindingPending,
  crossPlatformLogin;

  String get label => switch (this) {
    hasPassword => '有密码',
    noPassword => '无密码',
    hasPhone => '有绑定手机号',
    hasEmail => '有绑定邮箱',
    hasSubscription => '有关联订阅',
    noSubscription => '无关联订阅',
    hasPendingDraft => '有待完善订阅草稿',
    hasAttentionSubscription => '有待处理订阅',
    hasDuplicate => '存在重复候选',
    hasPasswordHealth => '存在未忽略密码健康提示',
    hasBindingPending => '存在绑定停用待处理',
    crossPlatformLogin => '登录标识跨平台复用',
  };
}

final class PasswordHealthFinding {
  const PasswordHealthFinding({
    required this.accountId,
    required this.issueType,
    required this.severity,
    this.relatedAccountIds = const {},
    this.ignored = false,
    this.passwordValueRevision = 0,
    this.memberRevisions = const {},
    this.basis = '',
  });
  final String accountId, issueType, basis;
  final PasswordHealthSeverity severity;
  final Set<String> relatedAccountIds;
  final bool ignored;
  final int passwordValueRevision;
  final Map<String, int> memberRevisions;
  String get key => '$accountId:$issueType';
  String get title => switch (issueType) {
    'reusedPassword' => '多个活动账号当前使用相同密码',
    'commonPassword' => '命中本机常见弱密码规则',
    'shortPassword' => '密码长度低于8位',
    'repeatedCharacters' => '密码由明显重复字符组成',
    'shortSequence' => '密码是明显短连续序列',
    'keyboardSequence' => '密码是明显短键盘序列',
    'moderateLength' => '密码长度为8至11位',
    'numericPassword' => '密码仅含数字且不超过12位',
    'simplePattern' => '密码由简单短片段重复组成',
    'missingPassword' => '没有保存密码',
    'unknownChangeDate' => '没有可信的Cardock密码变更日期',
    'oldChangeDate' => '超过730天未在Cardock记录密码变化',
    _ => '密码资料需要核对',
  };
  PasswordHealthIgnoreRule toIgnoreRule() => PasswordHealthIgnoreRule(
    accountId: accountId,
    issueType: issueType,
    passwordValueRevision: passwordValueRevision,
    memberRevisions: issueType == 'reusedPassword' ? const {} : memberRevisions,
    basis: basis,
  );
}

final class BindingGroup {
  BindingGroup({
    required this.type,
    required this.targetValue,
    required this.normalizedValue,
    Set<String> activeAccountIds = const {},
    Set<String> trashAccountIds = const {},
  }) : activeAccountIds = Set.unmodifiable(activeAccountIds),
       trashAccountIds = Set.unmodifiable(trashAccountIds);
  final BindingType type;
  final String targetValue, normalizedValue;
  final Set<String> activeAccountIds, trashAccountIds;
  String get key => '${type.name}:$normalizedValue';
}

final class BindingPlanProgress {
  BindingPlanProgress({
    required this.plan,
    required Set<String> pendingAccountIds,
    required Set<String> completedAccountIds,
    required Set<String> trashAccountIds,
  }) : pendingAccountIds = Set.unmodifiable(pendingAccountIds),
       completedAccountIds = Set.unmodifiable(completedAccountIds),
       trashAccountIds = Set.unmodifiable(trashAccountIds);
  final BindingRetirementPlan plan;
  final Set<String> pendingAccountIds, completedAccountIds, trashAccountIds;
}

final class AccountDuplicateCandidate {
  AccountDuplicateCandidate({
    required this.account,
    required this.inTrash,
    required Set<String> matchingFields,
  }) : matchingFields = Set.unmodifiable(matchingFields);
  final AccountRecord account;
  final bool inTrash;
  final Set<String> matchingFields;
}

/// Linear grouping and indexed lookup. The owner discards this object on every
/// committed revision, lock, vault switch, or dispose. Nothing is persisted.
final class AccountAnalysisSnapshot {
  AccountAnalysisSnapshot._();
  factory AccountAnalysisSnapshot.empty() => AccountAnalysisSnapshot._();
  factory AccountAnalysisSnapshot.fromSnapshot(
    VaultSnapshot source, {
    DateTime? now,
  }) {
    final result = AccountAnalysisSnapshot._();
    final localCurrent = now ?? DateTime.now();
    final current = localCurrent.toUtc();
    result.computedAtUtc = current;
    result.nextRefreshAtUtc =
        (localCurrent.isUtc
                ? DateTime.utc(
                    localCurrent.year,
                    localCurrent.month,
                    localCurrent.day + 1,
                  )
                : DateTime(
                    localCurrent.year,
                    localCurrent.month,
                    localCurrent.day + 1,
                  ))
            .toUtc();
    void expiresAt(DateTime instant) {
      if (instant.isAfter(current) &&
          instant.isBefore(result.nextRefreshAtUtc!)) {
        result.nextRefreshAtUtc = instant;
      }
    }

    final active = {for (final a in source.accounts) a.id: a};
    final trashed = {
      for (final a in source.trashAccounts) a.record.id: a.record,
    };
    result._all.addAll(active);
    result._all.addAll(trashed);
    result._trashIds.addAll(trashed.keys);
    final passwords = <String, List<AccountRecord>>{};
    final logins = <String, List<AccountRecord>>{};
    final bindingBuilders = <String, _BindingBuilder>{};
    void index(AccountRecord a, bool trash) {
      final keys = AccountComparison.duplicateKeys(
        platformName: a.platformName,
        loginAccount: a.loginAccount,
        username: a.username,
        emailValue: a.boundEmail,
        phoneValue: a.boundPhone,
        website: a.website,
      );
      for (final key in keys.entries) {
        result._duplicateIndex.putIfAbsent(key.key, () => {}).add(a.id);
        result._keyFields[key.key] = key.value;
      }
      for (final type in BindingType.values) {
        final original = type == BindingType.phone
            ? a.boundPhone
            : a.boundEmail;
        final normalized = type == BindingType.phone
            ? AccountComparison.phone(original)
            : AccountComparison.email(original);
        if (normalized.isEmpty) continue;
        final group = bindingBuilders.putIfAbsent(
          '${type.name}:$normalized',
          () => _BindingBuilder(type, original!, normalized),
        );
        (trash ? group.trash : group.active).add(a.id);
      }
      if (trash) return;
      if (a.password != null && a.password!.isNotEmpty) {
        passwords.putIfAbsent(a.password!, () => []).add(a);
      }
      final login = AccountComparison.login(a.loginAccount);
      if (login.isNotEmpty) logins.putIfAbsent(login, () => []).add(a);
    }

    for (final a in source.accounts) {
      index(a, false);
    }
    for (final a in source.trashAccounts) {
      index(a.record, true);
    }
    final duplicateIds = <String>{};
    for (final group in result._duplicateIndex.values) {
      if (group.length > 1) {
        duplicateIds.addAll(group.where(active.containsKey));
      }
    }
    result.duplicateAccountIds = Set.unmodifiable(duplicateIds);
    final crossLogin = <String>{};
    for (final group in logins.values) {
      if (group
              .map((a) => AccountComparison.platform(a.platformName))
              .toSet()
              .length >
          1) {
        crossLogin.addAll(group.map((a) => a.id));
      }
    }
    result.crossPlatformLoginAccountIds = Set.unmodifiable(crossLogin);
    result.subscriptionAccountIds = Set.unmodifiable(
      source.subscriptions.map((s) => s.accountId).whereType<String>(),
    );
    result.pendingDraftAccountIds = Set.unmodifiable(
      source.pendingSubscriptionDrafts
          .map((d) => d.accountId)
          .whereType<String>(),
    );
    result.attentionSubscriptionAccountIds = Set.unmodifiable(
      subscriptionAttention(
        source.subscriptions,
        localCurrent,
      ).map((a) => a.subscription.accountId).whereType<String>(),
    );
    final bindingGroups = bindingBuilders.values.map((g) => g.build()).toList();
    result.bindingGroups = List.unmodifiable(bindingGroups);
    final byBinding = {for (final g in bindingGroups) g.key: g};
    final pendingBindings = <String>{};
    result.bindingPlans = List.unmodifiable(
      source.bindingRetirementPlans.map((plan) {
        final group = byBinding['${plan.type.name}:${plan.normalizedValue}'];
        final pending = group?.activeAccountIds ?? <String>{};
        if (!plan.isClosed) pendingBindings.addAll(pending);
        return BindingPlanProgress(
          plan: plan,
          pendingAccountIds: pending,
          completedAccountIds: plan.accountIds
              .where((id) => active.containsKey(id) && !pending.contains(id))
              .toSet(),
          trashAccountIds: group?.trashAccountIds ?? {},
        );
      }),
    );
    result.bindingPendingAccountIds = Set.unmodifiable(pendingBindings);
    final ignores = {
      for (final rule in source.passwordHealthIgnoreRules) rule.key: rule,
    };
    final findings = <PasswordHealthFinding>[];
    final reuseMetadata =
        <
          String,
          ({Set<String> ids, Map<String, int> revisions, String basis})
        >{};
    for (final group in passwords.entries) {
      if (group.value.length < 2) continue;
      final revisions = Map<String, int>.unmodifiable({
        for (final a in group.value) a.id: a.passwordValueRevision,
      });
      reuseMetadata[group.key] = (
        ids: Set.unmodifiable(group.value.map((a) => a.id)),
        revisions: revisions,
        basis: passwordReuseMembershipBasis(revisions),
      );
    }
    for (final a in source.accounts) {
      final reuse = reuseMetadata[a.password];
      final lastChange = a.passwordChangeHistory.isEmpty
          ? null
          : a.passwordChangeHistory.last.changedAtUtc;
      if (a.password != null && a.password!.isNotEmpty && lastChange != null) {
        if (lastChange.isAfter(current)) {
          expiresAt(lastChange);
        } else {
          // The rule says strictly more than 730 days, including sub-day instants.
          expiresAt(lastChange.add(const Duration(days: 730, microseconds: 1)));
        }
      }
      void add(
        String type,
        PasswordHealthSeverity severity, {
        bool reused = false,
        bool dateBased = false,
      }) {
        final basis = reused
            ? reuse!.basis
            : dateBased
            ? '${a.passwordChangeHistory.length}:${lastChange?.toIso8601String() ?? "none"}'
            : '';
        final revisions = reused ? reuse!.revisions : const <String, int>{};
        final ignore = ignores['${a.id}:$type'];
        final ignored =
            ignore != null &&
            ignore.passwordValueRevision == a.passwordValueRevision &&
            (reused && ignore.memberRevisions.isNotEmpty
                ? ignore.basis.isEmpty &&
                      ignore.memberRevisions.length == revisions.length &&
                      ignore.memberRevisions.entries.every(
                        (e) => revisions[e.key] == e.value,
                      )
                : ignore.basis == basis && ignore.memberRevisions.isEmpty);
        findings.add(
          PasswordHealthFinding(
            accountId: a.id,
            issueType: type,
            severity: severity,
            relatedAccountIds: reused ? reuse!.ids : const {},
            ignored: ignored,
            passwordValueRevision: a.passwordValueRevision,
            memberRevisions: revisions,
            basis: basis,
          ),
        );
      }

      final password = a.password;
      if (password == null || password.isEmpty) {
        add('missingPassword', PasswordHealthSeverity.verification);
      } else {
        if (reuse != null) {
          add('reusedPassword', PasswordHealthSeverity.priority, reused: true);
        }
        for (final issue in passwordPatternIssues(password).entries) {
          add(issue.key, issue.value);
        }
        if (lastChange == null || lastChange.isAfter(current)) {
          add(
            'unknownChangeDate',
            PasswordHealthSeverity.verification,
            dateBased: true,
          );
        } else if (current.difference(lastChange) > const Duration(days: 730)) {
          add(
            'oldChangeDate',
            PasswordHealthSeverity.verification,
            dateBased: true,
          );
        }
      }
    }
    result.healthFindings = List.unmodifiable(findings);
    result.unignoredHealthAccountIds = Set.unmodifiable(
      findings.where((f) => !f.ignored).map((f) => f.accountId),
    );
    return result;
  }

  DateTime? computedAtUtc;
  DateTime? nextRefreshAtUtc;
  final Map<String, AccountRecord> _all = {};
  final Set<String> _trashIds = {};
  final Map<String, Set<String>> _duplicateIndex = {};
  final Map<String, String> _keyFields = {};
  List<PasswordHealthFinding> healthFindings = const [];
  List<BindingGroup> bindingGroups = const [];
  List<BindingPlanProgress> bindingPlans = const [];
  Set<String> duplicateAccountIds = const {},
      crossPlatformLoginAccountIds = const {},
      subscriptionAccountIds = const {},
      pendingDraftAccountIds = const {},
      attentionSubscriptionAccountIds = const {},
      unignoredHealthAccountIds = const {},
      bindingPendingAccountIds = const {};

  List<AccountDuplicateCandidate> duplicatesFor(
    AccountDraft draft, {
    String? excludeAccountId,
  }) {
    final keys = AccountComparison.duplicateKeys(
      platformName: draft.platformName,
      loginAccount: draft.loginAccount,
      username: draft.username,
      emailValue: draft.boundEmail,
      phoneValue: draft.boundPhone,
      website: draft.website,
    );
    final matches = <String, Set<String>>{};
    for (final entry in keys.entries) {
      for (final id in _duplicateIndex[entry.key] ?? const <String>{}) {
        if (id != excludeAccountId) {
          matches.putIfAbsent(id, () => {}).add(entry.value);
        }
      }
    }
    return List.unmodifiable(
      matches.entries.map(
        (m) => AccountDuplicateCandidate(
          account: _all[m.key]!,
          inTrash: _trashIds.contains(m.key),
          matchingFields: m.value,
        ),
      ),
    );
  }

  bool matches(
    AccountRecord account,
    String query,
    Set<AccountFilter> filters,
  ) {
    if (!account.matches(query) &&
        !AccountComparison.domain(
          account.website,
        ).contains(query.trim().toLowerCase())) {
      return false;
    }
    for (final filter in filters) {
      final match = switch (filter) {
        AccountFilter.hasPassword =>
          account.password != null && account.password!.isNotEmpty,
        AccountFilter.noPassword =>
          account.password == null || account.password!.isEmpty,
        AccountFilter.hasPhone => AccountComparison.phone(
          account.boundPhone,
        ).isNotEmpty,
        AccountFilter.hasEmail => AccountComparison.email(
          account.boundEmail,
        ).isNotEmpty,
        AccountFilter.hasSubscription => subscriptionAccountIds.contains(
          account.id,
        ),
        AccountFilter.noSubscription => !subscriptionAccountIds.contains(
          account.id,
        ),
        AccountFilter.hasPendingDraft => pendingDraftAccountIds.contains(
          account.id,
        ),
        AccountFilter.hasAttentionSubscription =>
          attentionSubscriptionAccountIds.contains(account.id),
        AccountFilter.hasDuplicate => duplicateAccountIds.contains(account.id),
        AccountFilter.hasPasswordHealth => unignoredHealthAccountIds.contains(
          account.id,
        ),
        AccountFilter.hasBindingPending => bindingPendingAccountIds.contains(
          account.id,
        ),
        AccountFilter.crossPlatformLogin =>
          crossPlatformLoginAccountIds.contains(account.id),
      };
      if (!match) return false;
    }
    return true;
  }

  void dispose() {
    computedAtUtc = null;
    nextRefreshAtUtc = null;
    _all.clear();
    _trashIds.clear();
    _duplicateIndex.clear();
    _keyFields.clear();
    healthFindings = const [];
    bindingGroups = const [];
    bindingPlans = const [];
    duplicateAccountIds = const {};
    crossPlatformLoginAccountIds = const {};
    subscriptionAccountIds = const {};
    pendingDraftAccountIds = const {};
    attentionSubscriptionAccountIds = const {};
    unignoredHealthAccountIds = const {};
    bindingPendingAccountIds = const {};
  }
}

final class _BindingBuilder {
  _BindingBuilder(this.type, this.original, this.normalized);
  final BindingType type;
  final String original, normalized;
  final Set<String> active = {}, trash = {};
  BindingGroup build() => BindingGroup(
    type: type,
    targetValue: original,
    normalizedValue: normalized,
    activeAccountIds: active,
    trashAccountIds: trash,
  );
}

/// Deliberately small and explainable. This does not query a breach database,
/// assign an overall score, or infer the password used on an external platform.
Map<String, PasswordHealthSeverity> passwordPatternIssues(String password) {
  final result = <String, PasswordHealthSeverity>{};
  if (password.isEmpty) return result;
  final runes = password.runes.toList(), length = password.runes.length;
  final lower = password.toLowerCase();
  const common = {
    'password',
    'admin',
    'welcome',
    'letmein',
    'iloveyou',
    'qwerty',
    'abc123',
    '123456',
    '12345678',
    '123456789',
    '1234567890',
    '111111',
    '000000',
    '123123',
    '888888',
    '666666',
  };
  final base = lower
      .replaceAll(RegExp(r'[0-9!@#$%^&*._-]{1,4}$'), '')
      .replaceAll('@', 'a')
      .replaceAll('0', 'o')
      .replaceAll('3', 'e')
      .replaceAll('1', 'i')
      .replaceAll(r'$', 's');
  if (common.contains(lower) || common.contains(base)) {
    result['commonPassword'] = PasswordHealthSeverity.priority;
  }
  if (length < 8) result['shortPassword'] = PasswordHealthSeverity.priority;
  if (length >= 3 && runes.toSet().length == 1) {
    result['repeatedCharacters'] = PasswordHealthSeverity.priority;
  }
  if (length >= 4 && length <= 12) {
    const sequences = [
      '0123456789',
      '9876543210',
      'abcdefghijklmnopqrstuvwxyz',
      'zyxwvutsrqponmlkjihgfedcba',
    ];
    if (sequences.any((s) => s.contains(lower))) {
      result['shortSequence'] = PasswordHealthSeverity.priority;
    }
    const keyboards = [
      'qwertyuiop',
      'poiuytrewq',
      'asdfghjkl',
      'lkjhgfdsa',
      'zxcvbnm',
      'mnbvcxz',
      'qwerty123',
    ];
    if (keyboards.any((s) => s.contains(lower))) {
      result['keyboardSequence'] = PasswordHealthSeverity.priority;
    }
  }
  if (length >= 8 && length <= 11) {
    result['moderateLength'] = PasswordHealthSeverity.optimization;
  }
  if (length <= 12 && RegExp(r'^[0-9]+$').hasMatch(password)) {
    result['numericPassword'] = PasswordHealthSeverity.optimization;
  }
  if (length >= 8 && length <= 16) {
    for (var width = 2; width <= 4; width++) {
      if (length % width != 0) continue;
      if (List.generate(length, (i) => runes[i % width]).join(',') ==
          runes.join(',')) {
        result['simplePattern'] = PasswordHealthSeverity.optimization;
        break;
      }
    }
  }
  return result;
}

/// Run only inside an already-authorized business transaction. Querying the
/// analysis never writes, advances a generation, or queues a backup.
VaultSnapshot normalizeAccountSecurityMetadata(
  VaultSnapshot source,
  DateTime now,
) {
  final allIds = {
    ...source.accounts.map((a) => a.id),
    ...source.trashAccounts.map((a) => a.record.id),
  };
  final grouped = <String, Set<String>>{};
  for (final a in [
    ...source.accounts,
    ...source.trashAccounts.map((a) => a.record),
  ]) {
    for (final type in BindingType.values) {
      final value = type == BindingType.phone
          ? AccountComparison.phone(a.boundPhone)
          : AccountComparison.email(a.boundEmail);
      if (value.isNotEmpty) {
        grouped.putIfAbsent('${type.name}:$value', () => {}).add(a.id);
      }
    }
  }
  final plans = <BindingRetirementPlan>[];
  for (final plan in source.bindingRetirementPlans) {
    final scope = plan.accountIds.where(allIds.contains).toSet();
    if (!plan.isClosed) {
      scope.addAll(
        grouped['${plan.type.name}:${plan.normalizedValue}'] ?? const {},
      );
    }
    if (scope.isNotEmpty) plans.add(plan.copyWith(accountIds: scope));
  }
  final normalized = source.copyWith(bindingRetirementPlans: plans);
  final analysis = AccountAnalysisSnapshot.fromSnapshot(normalized, now: now);
  final valid = analysis.healthFindings
      .where((f) => f.ignored)
      .map((f) => f.key)
      .toSet();
  final trash = {for (final a in source.trashAccounts) a.record.id: a.record};
  final rules = source.passwordHealthIgnoreRules.where((rule) {
    if (valid.contains(rule.key)) return true;
    final record = trash[rule.accountId];
    return record != null &&
        rule.issueType != 'reusedPassword' &&
        rule.memberRevisions.isEmpty &&
        rule.passwordValueRevision == record.passwordValueRevision;
  }).toList();
  analysis.dispose();
  return normalized.copyWith(passwordHealthIgnoreRules: rules);
}

/// A domain-separated marker of NON-SECRET account IDs and numeric revisions.
/// No password, password character, password hash, or password-derived digest
/// is accepted here. One marker is computed per group and reused by all rows.
String passwordReuseMembershipBasis(Map<String, int> memberRevisions) {
  final ids = memberRevisions.keys.toList()..sort();
  final bytes = utf8.encode(
    jsonEncode([
      'cardock-account-revisions-v1',
      for (final id in ids) [id, memberRevisions[id]],
    ]),
  );
  return 'reuse_members_v1:${base64UrlEncode(const DartSha256().hashSync(bytes).bytes)}';
}
