/// Only non-secret account revisions describe why a specific issue was hidden.
final class PasswordHealthIgnoreRule {
  PasswordHealthIgnoreRule({
    required this.accountId,
    required this.issueType,
    required this.passwordValueRevision,
    Map<String, int> memberRevisions = const {},
    this.basis = '',
  }) : memberRevisions = Map.unmodifiable(memberRevisions) {
    if (!_validId(accountId) ||
        issueType.isEmpty ||
        issueType.length > 100 ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(issueType) ||
        !_validRevision(passwordValueRevision) ||
        basis.length > 256 ||
        this.memberRevisions.length > 10000 ||
        this.memberRevisions.entries.any(
          (entry) => !_validId(entry.key) || !_validRevision(entry.value),
        )) {
      throw ArgumentError('密码健康忽略规则无效');
    }
  }
  final String accountId, issueType, basis;
  final int passwordValueRevision;
  final Map<String, int> memberRevisions;
  String get key => '$accountId:$issueType';
  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'issueType': issueType,
    'passwordValueRevision': passwordValueRevision,
    'memberRevisions': memberRevisions,
    'basis': basis,
  };
  factory PasswordHealthIgnoreRule.fromJson(Object? value) {
    try {
      if (value is! Map<Object?, Object?> ||
          value['accountId'] is! String ||
          value['issueType'] is! String ||
          value['passwordValueRevision'] is! int ||
          value['memberRevisions'] is! Map ||
          value['basis'] is! String) {
        throw const FormatException('密码健康忽略规则无效');
      }
      final members = value['memberRevisions'] as Map;
      if (members.keys.any((key) => key is! String) ||
          members.values.any((revision) => revision is! int)) {
        throw const FormatException('密码健康忽略规则无效');
      }
      return PasswordHealthIgnoreRule(
        accountId: value['accountId'] as String,
        issueType: value['issueType'] as String,
        passwordValueRevision: value['passwordValueRevision'] as int,
        memberRevisions: members.cast<String, int>(),
        basis: value['basis'] as String,
      );
    } on ArgumentError {
      throw const FormatException('密码健康忽略规则无效');
    }
  }
}

bool _validId(String value) => value.isNotEmpty && value.runes.length <= 128;
bool _validRevision(int value) => value >= 0 && value <= 9007199254740991;
