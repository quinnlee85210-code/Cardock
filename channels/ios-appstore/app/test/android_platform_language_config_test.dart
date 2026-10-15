import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android native prompts follow the Cardock language bridge', () {
    final activity = File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsStringSync();
    final bridge = File(
      'lib/core/platform/app_language_bridge.dart',
    ).readAsStringSync();

    expect(activity, contains('"cardock/platform_language"'));
    expect(activity, contains('"setLanguage"'));
    expect(activity, contains('LANGUAGE_SIMPLIFIED_CHINESE = "zh_CN"'));
    expect(activity, contains('LANGUAGE_ENGLISH = "en"'));
    expect(activity, contains('LANGUAGE_JAPANESE = "ja"'));
    expect(activity, contains('.setTitle(localizedString('));
    expect(activity, contains('.setSubtitle(localizedString('));
    expect(activity, contains('.setNegativeButtonText(localizedString('));
    expect(
      activity,
      contains('localizedString(R.string.sensitive_clipboard_label)'),
    );
    expect(activity, isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
    expect(bridge, contains("MethodChannel("));
    expect(bridge, contains("'cardock/platform_language'"));
    expect(bridge, contains("'language': language.storageCode"));
    expect(
      activity,
      contains(
        '.setTitle(localizedString(R.string.quick_unlock_prompt_title))',
      ),
    );
    expect(
      activity,
      contains(
        '.setSubtitle(localizedString(R.string.biometric_prompt_subtitle))',
      ),
    );
    expect(
      activity,
      contains(
        '.setNegativeButtonText(localizedString(R.string.use_master_password))',
      ),
    );
    expect(
      activity,
      contains('.setTitle(localizedString(R.string.recovery_prompt_title))'),
    );
    expect(
      activity,
      contains('.setNegativeButtonText(localizedString(R.string.cancel))'),
    );
  });

  test(
    'Chinese fallback, English, and Japanese resource keys stay in parity',
    () {
      final files = <File>[
        File('android/app/src/main/res/values/strings.xml'),
        File('android/app/src/main/res/values-en/strings.xml'),
        File('android/app/src/main/res/values-ja/strings.xml'),
      ];
      final keyPattern = RegExp(r'<string name="([^"]+)">');
      final keySets = <Set<String>>[
        for (final file in files)
          {
            for (final match in keyPattern.allMatches(file.readAsStringSync()))
              match.group(1)!,
          },
      ];

      expect(keySets[0], contains('quick_unlock_prompt_title'));
      expect(keySets[0], contains('recovery_prompt_title'));
      expect(keySets[0], contains('sensitive_clipboard_label'));
      expect(keySets[1], keySets[0]);
      expect(keySets[2], keySets[0]);
    },
  );

  test('quick unlock 与 recovery 两处原生 prompt 的英日资源语义稳定', () {
    final english = _readAndroidStrings(
      'android/app/src/main/res/values-en/strings.xml',
    );
    final japanese = _readAndroidStrings(
      'android/app/src/main/res/values-ja/strings.xml',
    );

    expect(
      english['quick_unlock_prompt_title'],
      'Unlock accounts and subscriptions',
    );
    expect(
      english['biometric_prompt_subtitle'],
      'Verify with strong biometrics on this device',
    );
    expect(english['use_master_password'], 'Use master password');
    expect(
      english['recovery_prompt_title'],
      'Authenticate for password recovery',
    );
    expect(english['cancel'], 'Cancel');

    expect(japanese['quick_unlock_prompt_title'], 'アカウントとサブスクリプションのロックを解除');
    expect(japanese['biometric_prompt_subtitle'], 'この端末の強力な生体認証を行ってください');
    expect(japanese['use_master_password'], 'マスターパスワードを使用');
    expect(japanese['recovery_prompt_title'], 'パスワード復旧のために認証');
    expect(japanese['cancel'], 'キャンセル');
  });
}

Map<String, String> _readAndroidStrings(String path) {
  final source = File(path).readAsStringSync();
  return <String, String>{
    for (final match in RegExp(
      r'<string name="([^"]+)">([^<]*)</string>',
    ).allMatches(source))
      match.group(1)!: match.group(2)!,
  };
}
