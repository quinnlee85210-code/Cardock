import 'dart:math';

import 'package:account_subscription_manager/core/security/offline_password_advisor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('离线生成器输出可抄录且通过强密码策略', () {
    final generated = OfflinePasswordAdvisor.generate(random: Random(7));

    expect(
      generated,
      matches(RegExp(r'^[2-9A-HJ-NP-Z]{4}(-[2-9A-HJ-NP-Z]{4}){6}$')),
    );
    expect(generated.runes.length, 34);
    expect(
      OfflinePasswordAdvisor.assess(generated).strength,
      NewPasswordStrength.strong,
    );
  });

  test('拒绝过短、常见片段和长重复模式', () {
    expect(OfflinePasswordAdvisor.assess('Short-Password1').accepted, isFalse);
    expect(
      OfflinePasswordAdvisor.assess('My-password-123456-Long!').accepted,
      isFalse,
    );
    expect(
      OfflinePasswordAdvisor.assess('AAAA-very-long-password-2026!').accepted,
      isFalse,
    );
  });

  test('允许足够长且类别充足的用户自定密码', () {
    final result = OfflinePasswordAdvisor.assess('River-Cobalt-Window-74!Safe');

    expect(result.accepted, isTrue);
  });

  test('真实主密码与备份密码继续执行16到128位强策略', () {
    expect(OfflinePasswordAdvisor.assess('Abcdef1!Abcdefg').accepted, isFalse);
    expect(OfflinePasswordAdvisor.assess('Abcdef1!Abcdefgh').accepted, isTrue);
  });

  test('新诱饵密码单独允许6到32位且不放宽关键密码策略', () {
    expect(
      OfflinePasswordAdvisor.assess(
        '故事密码12',
        purpose: NewPasswordPurpose.decoy,
      ).accepted,
      isTrue,
    );
    expect(
      OfflinePasswordAdvisor.assess(
        '五个字',
        purpose: NewPasswordPurpose.decoy,
      ).accepted,
      isFalse,
    );
    expect(
      OfflinePasswordAdvisor.assess(
        '123456789012345678901234567890123',
        purpose: NewPasswordPurpose.decoy,
      ).accepted,
      isFalse,
    );
    expect(OfflinePasswordAdvisor.assess('故事123').accepted, isFalse);
  });
}
