/// Only the timing of a saved password change is retained, never the old value.
final class PasswordChangeRecord {
  factory PasswordChangeRecord({
    required DateTime changedAtUtc,
    DateTime? previousStoredAtUtc,
  }) {
    final changed = changedAtUtc.toUtc();
    final previous = previousStoredAtUtc?.toUtc();
    for (final date in [changed, previous]) {
      if (date != null && (date.year < 1970 || date.year > 2300)) {
        throw ArgumentError('密码变更日期无效');
      }
    }
    return PasswordChangeRecord._(changed, previous);
  }

  const PasswordChangeRecord._(this.changedAtUtc, this.previousStoredAtUtc);

  final DateTime changedAtUtc;
  final DateTime? previousStoredAtUtc;

  factory PasswordChangeRecord.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('密码变更记录无效');
    }
    DateTime? date(String key, {bool required = false}) {
      final raw = value[key];
      if (raw == null && !required) return null;
      final parsed = raw is String ? DateTime.tryParse(raw) : null;
      if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != raw) {
        throw const FormatException('密码变更记录无效');
      }
      return parsed;
    }

    return PasswordChangeRecord(
      changedAtUtc: date('changedAtUtc', required: true)!,
      previousStoredAtUtc: date('previousStoredAtUtc'),
    );
  }

  Map<String, Object?> toJson() => {
    'changedAtUtc': changedAtUtc.toIso8601String(),
    'previousStoredAtUtc': previousStoredAtUtc?.toIso8601String(),
  };
}
