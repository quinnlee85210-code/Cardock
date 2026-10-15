import 'dart:math';

enum NewPasswordStrength { rejected, acceptable, strong }

enum NewPasswordPurpose { critical, master, decoy }

final class PasswordAssessment {
  const PasswordAssessment({required this.strength, required this.message});

  final NewPasswordStrength strength;
  final String message;

  bool get accepted => strength != NewPasswordStrength.rejected;
}

/// 完全离线的新密码向导。
///
/// 这里只对“新建”主密码、诱饵密码和独立备份密码执行较强策略；
/// 已有保险库仍按原格式精确匹配，避免升级后把真实用户锁在库外。
final class OfflinePasswordAdvisor {
  OfflinePasswordAdvisor._();

  static const _alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _blockedFragments = <String>{
    '123456',
    '654321',
    'password',
    'qwerty',
    'admin',
    'letmein',
    'iloveyou',
    'masterpassword',
  };

  /// 生成 28 个不易混淆的随机字符，约 140 bit 随机空间。
  /// 连字符只用于人工抄录和核对，也属于密码本身。
  static String generate({Random? random}) {
    final source = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 28; index += 1) {
      if (index > 0 && index % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(_alphabet[source.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  static PasswordAssessment assess(
    String password, {
    NewPasswordPurpose purpose = NewPasswordPurpose.critical,
  }) {
    if (purpose == NewPasswordPurpose.decoy) {
      return _assessDecoy(password);
    }
    return _assessCritical(
      password,
      master: purpose == NewPasswordPurpose.master,
    );
  }

  static PasswordAssessment _assessCritical(
    String password, {
    required bool master,
  }) {
    final runes = password.runes.toList(growable: false);
    if (runes.length < (master ? 8 : 16)) {
      return PasswordAssessment(
        strength: NewPasswordStrength.rejected,
        message: master
            ? '主密码至少需要8个字符，最多128个字符。'
            : '新密码至少需要16个字符；更推荐使用离线生成的随机密码。',
      );
    }
    if (runes.length > 128) {
      return const PasswordAssessment(
        strength: NewPasswordStrength.rejected,
        message: '密码不能超过128个字符。',
      );
    }

    final normalized = password.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (_blockedFragments.any(normalized.contains)) {
      return const PasswordAssessment(
        strength: NewPasswordStrength.rejected,
        message: '密码包含常见弱口令或连续数字，请换一组完全不同的内容。',
      );
    }
    if (runes.toSet().length < (master ? min(8, runes.length ~/ 2) : 8) ||
        _hasLongRepeatedRun(runes) ||
        _hasRepeatedShortBlock(runes)) {
      return const PasswordAssessment(
        strength: NewPasswordStrength.rejected,
        message: '密码重复规律过强，请增加互不相关的字符或使用离线生成。',
      );
    }

    final categories = <int>{for (final rune in runes) _categoryOf(rune)};
    final requiredCategories = runes.length >= 24 ? 2 : 3;
    if (categories.length < requiredCategories) {
      return PasswordAssessment(
        strength: NewPasswordStrength.rejected,
        message: runes.length >= 24
            ? '长密码仍需至少包含两类不同字符，避免使用单一重复模式。'
            : master
            ? '8到23字符的主密码至少需要三类字符；建议组合大小写字母、数字和符号。'
            : '16到23字符的密码至少需要三类字符；也可改用更长的离线随机密码。',
      );
    }

    if (runes.length >= 28 && categories.length >= 3) {
      return const PasswordAssessment(
        strength: NewPasswordStrength.strong,
        message: '满足本机强密码建议；请离线妥善保管，遗失后无法找回。',
      );
    }
    return const PasswordAssessment(
      strength: NewPasswordStrength.acceptable,
      message: '可以使用；若用于长期保存重要账号，仍推荐离线生成的随机密码。',
    );
  }

  static PasswordAssessment _assessDecoy(String password) {
    final length = password.runes.length;
    if (length < 6) {
      return const PasswordAssessment(
        strength: NewPasswordStrength.rejected,
        message: '诱饵密码至少需要6个字符。',
      );
    }
    if (length > 32) {
      return const PasswordAssessment(
        strength: NewPasswordStrength.rejected,
        message: '新诱饵密码不能超过32个字符；已有较长诱饵密码仍可照常解锁。',
      );
    }

    final normalized = password.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (_blockedFragments.any(normalized.contains) ||
        password.runes.toSet().length < 4 ||
        _hasLongRepeatedRun(password.runes.toList(growable: false))) {
      return const PasswordAssessment(
        strength: NewPasswordStrength.acceptable,
        message: '长度可用，但容易被猜到；它只适合作为诱饵密码，且不能与真实主密码相同或相近。',
      );
    }
    return const PasswordAssessment(
      strength: NewPasswordStrength.acceptable,
      message: '诱饵密码长度可用；请确保容易记住，并与真实主密码完全不同。',
    );
  }

  static bool _hasLongRepeatedRun(List<int> runes) {
    var runLength = 1;
    for (var index = 1; index < runes.length; index += 1) {
      if (runes[index] == runes[index - 1]) {
        runLength += 1;
        if (runLength >= 4) {
          return true;
        }
      } else {
        runLength = 1;
      }
    }
    return false;
  }

  // Advisory only; the bytes used for unlock and restore are unchanged.
  static bool _hasRepeatedShortBlock(List<int> runes) {
    for (var size = 1; size <= 12 && size * 2 <= runes.length; size++) {
      var repeated = true;
      for (var index = size; index < runes.length; index++) {
        if (runes[index] != runes[index % size]) {
          repeated = false;
          break;
        }
      }
      if (repeated) return true;
    }
    return false;
  }

  static int _categoryOf(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return 0;
    if (rune >= 0x41 && rune <= 0x5a) return 1;
    if (rune >= 0x61 && rune <= 0x7a) return 2;
    if (rune <= 0x7f) return 3;
    return 4;
  }
}
