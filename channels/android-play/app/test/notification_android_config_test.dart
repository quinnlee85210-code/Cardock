import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release资源优化保留Cardock通知小图标和既有资源名', () async {
    final icon = File('android/app/src/main/res/drawable/ic_notification.xml');
    final keepRule = File('android/app/src/main/res/raw/keep.xml');
    final scheduler = File('lib/core/notifications/reminder_scheduler.dart');

    expect(await icon.exists(), isTrue);
    expect(await keepRule.exists(), isTrue);
    expect(await scheduler.exists(), isTrue);

    final iconContents = await icon.readAsString();
    expect(iconContents, contains('android:width="24dp"'));
    expect(iconContents, contains('android:height="24dp"'));
    expect(iconContents, contains('android:viewportWidth="24"'));
    expect(iconContents, contains('android:viewportHeight="24"'));
    expect(iconContents, contains('android:fillColor="#FFFFFFFF"'));
    expect(iconContents, contains('M4.2,7.2 V13.3'));
    expect(iconContents, contains('M9.4,4.2 H14.2 L16.4,6.4'));
    expect(iconContents, contains('M10,8.2 L12.2,9.3 L14.4,8.2'));
    expect(iconContents, contains('M10,10.3 L12.2,11.4 L14.4,10.3'));
    expect(iconContents, isNot(contains('M8.1,3.4')));
    expect(iconContents, isNot(contains('M4,7.6')));
    expect(iconContents, isNot(contains('gradient')));

    final keepRuleContents = await keepRule.readAsString();
    expect(keepRuleContents, contains('xmlns:tools='));
    expect(
      keepRuleContents,
      contains('tools:keep="@drawable/ic_notification"'),
    );

    final schedulerContents = await scheduler.readAsString();
    expect(
      schedulerContents,
      contains("AndroidInitializationSettings('ic_notification')"),
    );
    expect(
      schedulerContents,
      isNot(contains("AndroidInitializationSettings('ic_stat_cardock')")),
    );
  });

  test('Android通知PNG密度回退尺寸完整且沿用ic_notification名称', () async {
    const expected = <String, ({int size, String sha256})>{
      'mdpi': (
        size: 24,
        sha256:
            'B73DAF2C96A31314903792560CEDAD54DDFE844E3529FE2C3C2EEA85498D1E22',
      ),
      'hdpi': (
        size: 36,
        sha256:
            '6A8549ED9294AE6339831580C8F330CD749D80E5D98B830F4BD04D0AD94FD0D7',
      ),
      'xhdpi': (
        size: 48,
        sha256:
            '4D82CD9B423A4CE1663000BD5BA12B582D50BFE4BBA0A1A5CC3F58D8090CBB15',
      ),
      'xxhdpi': (
        size: 72,
        sha256:
            '6572DCA31FCB609BFD90A6B62DBA7D1E1E59CB1FB988E9B50B0730C8651CA025',
      ),
      'xxxhdpi': (
        size: 96,
        sha256:
            '69BFEE6D88C7EFB9FA9DB6A030610C58FE4123537A8987A6C1B8C6E9D566AC1E',
      ),
    };

    for (final entry in expected.entries) {
      final file = File(
        'android/app/src/main/res/drawable-${entry.key}/'
        'ic_notification.png',
      );
      expect(await file.exists(), isTrue, reason: file.path);
      final dimensions = await _readPngDimensions(file);
      expect(dimensions.width, entry.value.size, reason: file.path);
      expect(dimensions.height, entry.value.size, reason: file.path);
      expect(await _sha256Hex(file), entry.value.sha256, reason: file.path);
    }
  });

  test('Android提醒精确优先非精确降级且保留重启恢复配置', () async {
    final scheduler = await File(
      'lib/core/notifications/reminder_scheduler.dart',
    ).readAsString();
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(scheduler, contains('AndroidScheduleMode.inexactAllowWhileIdle'));
    expect(scheduler, contains('AndroidScheduleMode.exactAllowWhileIdle'));
    expect(scheduler, contains('canScheduleExactNotifications()'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ReminderRecoveryReceiver'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, isNot(contains('USE_EXACT_ALARM')));
  });
}

Future<String> _sha256Hex(File file) async {
  final digest = await Sha256().hash(await file.readAsBytes());
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

Future<({int width, int height})> _readPngDimensions(File file) async {
  final bytes = await file.readAsBytes();
  expect(bytes.sublist(0, 8), <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ], reason: file.path);
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}
