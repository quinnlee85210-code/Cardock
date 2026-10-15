const browserPasswordSourceIds = {
  'chrome_google_csv',
  'chrome_passwords_csv',
  'google_password_manager_csv',
};
bool isBrowserPasswordSourceId(String id) =>
    browserPasswordSourceIds.contains(id);

/// Recognition never rewrites an actual password; only placeholder classification
/// uses a trimmed, case-folded candidate.
bool browserPasswordLooksMasked(String password) {
  final value = password.trim().toLowerCase();
  if (value.isEmpty) return false;
  if ({
    'password hidden',
    'hidden',
    '[hidden]',
    '(hidden)',
    '[redacted]',
    'redacted',
    '<redacted>',
    '已隐藏',
    '已遮挡',
    '非表示',
    '••••',
    '...',
    '…',
  }.contains(value)) {
    return true;
  }
  return value.runes.every(
        (r) => {0x2a, 0x2022, 0x25cf, 0xb7, 0x2e, 0x2026}.contains(r),
      ) ||
      value.length >= 4 && value.runes.every((r) => r == 0x78);
}
