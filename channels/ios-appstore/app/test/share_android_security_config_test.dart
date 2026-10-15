import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 分享入口只有一个精确 ACTION_SEND text/plain 导出 Activity', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final shareActivities = RegExp(
      r'<activity\s+[^>]*android:name="\.ShareReceiverActivity"[\s\S]*?</activity>',
    ).allMatches(manifest).map((match) => match.group(0)!).toList();
    expect(shareActivities, hasLength(1));
    final block = shareActivities.single;
    expect(block, contains('android:exported="true"'));
    expect(block, contains('android:noHistory="true"'));
    expect(block, contains('android:excludeFromRecents="true"'));
    expect(block, contains('android:taskAffinity=""'));
    expect(block, contains('android.intent.action.SEND'));
    expect(block, contains('android.intent.category.DEFAULT'));
    expect(block, contains('android:mimeType="text/plain"'));
    expect(block, isNot(contains('SEND_MULTIPLE')));
    expect(block, isNot(contains('text/*')));
    expect(block, isNot(contains('text/html')));

    expect(RegExp('android.intent.action.SEND').allMatches(manifest).length, 1);
    final mainActivity = RegExp(
      r'<activity\s+[^>]*android:name="\.MainActivity"[\s\S]*?</activity>',
    ).firstMatch(manifest)!.group(0)!;
    expect(mainActivity, isNot(contains('android.intent.action.SEND')));
  });

  test('分享功能没有新增权限，原生策略拒绝流、URI、HTML、嵌套和可执行方案', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final permissions = RegExp(
      r'<uses-permission android:name="([^"]+)"\s*/>',
    ).allMatches(manifest).map((match) => match.group(1)).toSet();
    expect(permissions, <String>{
      'android.permission.USE_BIOMETRIC',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.SCHEDULE_EXACT_ALARM',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
      'android.permission.WAKE_LOCK',
      'android.permission.INTERNET',
    });

    final policy = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/ShareIntentPolicy.kt',
    ).readAsString();
    final receiver = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/ShareReceiverActivity.kt',
    ).readAsString();
    for (final expected in <String>[
      'ACTION_SEND',
      'MIME_TEXT_PLAIN',
      'hasStreamExtra',
      'hasHtmlExtra',
      'hasNestedIntent',
      'hasUnsupportedExtras',
      'hasGrantUriPermission',
      'UNSUPPORTED_EXECUTABLE_CONTENT',
      'content|file|intent|javascript|android-app',
      'data:',
      'MAX_TEXT_LENGTH = 20_000',
    ]) {
      expect(policy, contains(expected), reason: expected);
    }
    expect(receiver, contains('Intent.EXTRA_STREAM'));
    expect(receiver, contains('Intent.EXTRA_HTML_TEXT'));
    expect(receiver, contains('URI_GRANT_FLAGS'));
    expect(receiver, contains('source.selector != null'));
    expect(receiver, contains('source.component?.className'));
    expect(receiver, isNot(contains('Log.')));
  });

  test('原文只存在进程内单槽，消费即移除并以单调时钟限制五分钟', () async {
    final store = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/ShareIntakeStore.kt',
    ).readAsString();
    expect(store, contains('private var pending: StoredItem? = null'));
    expect(store, contains('pending = null'));
    expect(store, contains('5 * 60 * 1000L'));
    expect(store, contains('System.nanoTime()'));
    expect(store, contains('@Synchronized'));
    expect(store, isNot(contains('SharedPreferences')));
    expect(store, isNot(contains('File(')));
    expect(store, isNot(contains('database')));
    expect(store, isNot(contains('Log.')));

    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();
    expect(activity, contains('ShareIntakeStore.clear()'));
    expect(activity, contains('override fun onDestroy()'));
    expect(activity, contains('"consumePending"'));
    expect(activity, contains('"clearPending"'));
  });

  test('Android 分享目标及错误文案提供中英日资源', () async {
    for (final directory in <String>['values', 'values-en', 'values-ja']) {
      final strings = await File(
        'android/app/src/main/res/$directory/strings.xml',
      ).readAsString();
      for (final name in <String>[
        'share_target_label',
        'share_error_expired',
        'share_error_text_too_long',
        'share_error_unsupported',
      ]) {
        expect(strings, contains('name="$name"'), reason: '$directory/$name');
      }
    }
  });
}
