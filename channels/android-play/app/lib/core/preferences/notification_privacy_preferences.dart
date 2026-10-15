import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Device-only preference, deliberately absent from every vault and backup.
enum NotificationPrivacy { privacy, serviceName, fullSummary }

extension NotificationPrivacyLabel on NotificationPrivacy {
  String get label => switch (this) {
    NotificationPrivacy.privacy => '隐私模式',
    NotificationPrivacy.serviceName => '服务名称模式',
    NotificationPrivacy.fullSummary => '完整订阅摘要模式',
  };
}

abstract interface class NotificationPrivacyStore {
  Future<NotificationPrivacy> read();
  Future<void> write(NotificationPrivacy value);
}

final class MemoryNotificationPrivacyStore implements NotificationPrivacyStore {
  MemoryNotificationPrivacyStore([this.value = NotificationPrivacy.privacy]);
  NotificationPrivacy value;
  @override
  Future<NotificationPrivacy> read() async => value;
  @override
  Future<void> write(NotificationPrivacy value) async {
    this.value = value;
  }
}

final class FileNotificationPrivacyStore implements NotificationPrivacyStore {
  FileNotificationPrivacyStore(this.directory);
  factory FileNotificationPrivacyStore.appSupport() =>
      FileNotificationPrivacyStore(getApplicationSupportDirectory);
  final Future<Directory> Function() directory;
  static const fileName = 'cardock_notification_privacy_v1.json';
  static const formatVersion = 1;
  Future<File> _file() async =>
      File('${(await directory()).path}${Platform.pathSeparator}$fileName');

  static NotificationPrivacy decode(Object? value) {
    if (value is! Map ||
        value['version'] != formatVersion ||
        value.length != 2) {
      return NotificationPrivacy.privacy;
    }
    return NotificationPrivacy.values
            .where((p) => p.name == value['level'])
            .firstOrNull ??
        NotificationPrivacy.privacy;
  }

  @override
  Future<NotificationPrivacy> read() async {
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 256) {
        return NotificationPrivacy.privacy;
      }
      return decode(jsonDecode(await file.readAsString()));
    } on Object {
      return NotificationPrivacy.privacy;
    }
  }

  @override
  Future<void> write(NotificationPrivacy value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.tmp');
    final text = jsonEncode({'version': formatVersion, 'level': value.name});
    await staging.writeAsString(text, flush: true);
    if (await staging.readAsString() != text) {
      throw const FileSystemException('Preference verification failed');
    }
    // Same-directory rename is the atomic commit. An interrupted staging file
    // is never loaded, and a failed write leaves the previous value intact.
    await staging.rename(file.path);
  }
}
