import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../notifications/reminder_scheduler.dart';

final class RebuildAuthorization {
  const RebuildAuthorization(this.token, {required this.unsecured});
  final String token;
  final bool unsecured;
}

abstract interface class RebuildPlatform {
  Future<RebuildAuthorization?> authorize(String title, String message);
  Future<void> beginHold(String token);
  Future<void> cancelHold(String token);
  Future<bool> consume(
    RebuildAuthorization authorization,
    String phrase,
    String secondPhrase,
  );
  Future<void> clearForCommittedRebuild();
}

final class MethodChannelRebuildPlatform implements RebuildPlatform {
  const MethodChannelRebuildPlatform();
  static const _channel = MethodChannel('cardock/vault_rebuild_v1');
  @override
  Future<RebuildAuthorization?> authorize(String title, String message) async {
    final value = await _channel.invokeMapMethod<String, Object?>('authorize', {
      'title': title,
      'message': message,
    });
    return value == null
        ? null
        : RebuildAuthorization(
            value['token'] as String,
            unsecured: value['unsecured'] == true,
          );
  }

  @override
  Future<void> beginHold(String token) =>
      _channel.invokeMethod('beginHold', {'token': token});
  @override
  Future<void> cancelHold(String token) =>
      _channel.invokeMethod('cancelHold', {'token': token});
  @override
  Future<bool> consume(
    RebuildAuthorization authorization,
    String phrase,
    String secondPhrase,
  ) async =>
      await _channel.invokeMethod<bool>('consume', {
        'token': authorization.token,
        'phrase': phrase,
        'secondPhrase': secondPhrase,
      }) ??
      false;
  @override
  Future<void> clearForCommittedRebuild() =>
      _channel.invokeMethod('clearCommitted');
}

/// A durable intent is the irreversible commit point. Before it, cancellation
/// writes nothing. After it, startup MUST finish the exact allowlist cleanup
/// before opening or creating a vault. External SAF documents are never touched.
final class VaultRebuildService {
  VaultRebuildService({
    required this.directory,
    required this.platform,
    required this.reminders,
    this.requiresTypedConfirmation = true,
    this.afterStep,
  });
  factory VaultRebuildService.appSupport(ReminderScheduler reminders) =>
      VaultRebuildService(
        directory: getApplicationSupportDirectory,
        platform: const MethodChannelRebuildPlatform(),
        reminders: reminders,
        requiresTypedConfirmation: !Platform.isIOS,
      );
  final Future<Directory> Function() directory;
  final RebuildPlatform platform;
  final ReminderScheduler reminders;
  final bool requiresTypedConfirmation;
  final Future<void> Function(String step)? afterStep;
  static const journalName = 'cardock_rebuild_v1.json';
  static const _vaultDirectories = {
    'encrypted_vault_v1',
    'encrypted_subscription_view_v1',
    'encrypted_vault_secondary_v1',
  };
  static const _files = {
    'vault_access_state_v1.json',
    'backup_health_v1.json',
    'last_restore_rollback_v1.json',
    'unlock_throttle_v1.json',
    'cardock_notification_privacy_v1.json',
  };
  static const _suffixes = [
    '',
    '.bak',
    '.tmp',
    '.tmp.0',
    '.tmp.1',
    '.a',
    '.b',
    '.a.tmp',
    '.b.tmp',
  ];
  static bool removableName(String name) {
    for (final base in _vaultDirectories) {
      if (name == base ||
          RegExp(
            '^${RegExp.escape(base)}\\.(rebuild|retired)\\.[A-Za-z0-9_-]{16}'
            r'$',
          ).hasMatch(name)) {
        return true;
      }
    }
    return _files.any(
      (base) => _suffixes.any((suffix) => name == '$base$suffix'),
    );
  }

  Future<bool> commit({
    required RebuildAuthorization authorization,
    required String phrase,
    String secondPhrase = '',
  }) async {
    if (requiresTypedConfirmation
        ? phrase != '删除本机 Cardock 数据' ||
              (authorization.unsecured && secondPhrase != '我理解没有备份将无法恢复')
        : authorization.unsecured) {
      return false;
    }
    if (!await platform.consume(authorization, phrase, secondPhrase)) {
      return false;
    }
    final root = await directory();
    final journal = File('${root.path}${Platform.pathSeparator}$journalName');
    if (await journal.exists()) {
      throw const FileSystemException('Rebuild already committed');
    }
    final staging = File('${journal.path}.prepared');
    final text = jsonEncode({'version': 1, 'phase': 'committed'});
    await staging.writeAsString(text, flush: true);
    if (await staging.readAsString() != text) {
      throw const FileSystemException('Rebuild intent verification failed');
    }
    await staging.rename(journal.path);
    await afterStep?.call('committed');
    await resumeIfNeeded();
    return true;
  }

  Future<void> resumeIfNeeded() async {
    final root = await directory();
    final journal = File('${root.path}${Platform.pathSeparator}$journalName');
    if (!await journal.exists()) return;
    if (await journal.length() > 256) {
      throw const FormatException('Invalid rebuild intent');
    }
    final intent = jsonDecode(await journal.readAsString());
    if (intent is! Map ||
        intent['version'] != 1 ||
        intent['phase'] != 'committed') {
      throw const FormatException('Unsupported rebuild intent');
    }
    await reminders.cancelAll();
    if (await reminders.pendingReminderCount() != 0) {
      throw StateError('Reminder cancellation incomplete');
    }
    await platform.clearForCommittedRebuild();
    await afterStep?.call('native');
    final resolved = await root.resolveSymbolicLinks();
    await for (final item in root.list(followLinks: false)) {
      final name = item.uri.pathSegments.where((e) => e.isNotEmpty).last;
      if (!removableName(name)) continue;
      final type = await FileSystemEntity.type(item.path, followLinks: false);
      // Refuse links instead of following them outside the app support root.
      if (type == FileSystemEntityType.link ||
          await item.parent.resolveSymbolicLinks() != resolved) {
        throw const FileSystemException('Unexpected rebuild path');
      }
      if (type == FileSystemEntityType.directory) {
        await Directory(item.path).delete(recursive: true);
      } else {
        await File(item.path).delete();
      }
      await afterStep?.call('file');
    }
    await for (final item in root.list(followLinks: false)) {
      if (removableName(
        item.uri.pathSegments.where((e) => e.isNotEmpty).last,
      )) {
        throw StateError('Rebuild cleanup incomplete');
      }
    }
    await afterStep?.call('clean');
    await journal.delete();
  }
}
