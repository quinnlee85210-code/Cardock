import 'package:flutter/services.dart';

abstract interface class DocumentStorage {
  Future<String?> pickDirectory();
  Future<bool> hasPermission(String tree);
  Future<String> createBackup(String tree, String name);
  Future<void> write(String uri, Uint8List bytes);
  Future<Uint8List> read(String uri);
  Future<void> deleteOwned(String tree, String uri);
  Future<String?> beginExport(String name, String mime);
  Future<void> appendExport(String handle, List<int> bytes);
  Future<void> finishExport(String handle);
  Future<void> abortExport(String handle);
}

final class AndroidDocumentStorage implements DocumentStorage {
  const AndroidDocumentStorage();
  static const _channel = MethodChannel('cardock/document_storage_v1');
  @override
  Future<String?> pickDirectory() =>
      _channel.invokeMethod<String>('pickDirectory');
  @override
  Future<bool> hasPermission(String tree) async =>
      await _channel.invokeMethod<bool>('hasPermission', {'tree': tree}) ??
      false;
  @override
  Future<String> createBackup(String tree, String name) async => (await _channel
      .invokeMethod<String>('createBackup', {'tree': tree, 'name': name}))!;
  @override
  Future<void> write(String uri, Uint8List bytes) =>
      _channel.invokeMethod('write', {'uri': uri, 'bytes': bytes});
  @override
  Future<Uint8List> read(String uri) async =>
      (await _channel.invokeMethod<Uint8List>('read', {'uri': uri}))!;
  @override
  Future<void> deleteOwned(String tree, String uri) =>
      _channel.invokeMethod('deleteOwned', {'tree': tree, 'uri': uri});
  @override
  Future<String?> beginExport(String name, String mime) => _channel
      .invokeMethod<String>('beginExport', {'name': name, 'mime': mime});
  @override
  Future<void> appendExport(String handle, List<int> bytes) =>
      _channel.invokeMethod('appendExport', {
        'handle': handle,
        'bytes': Uint8List.fromList(bytes),
      });
  @override
  Future<void> finishExport(String handle) =>
      _channel.invokeMethod('finishExport', {'handle': handle});
  @override
  Future<void> abortExport(String handle) =>
      _channel.invokeMethod('abortExport', {'handle': handle});
}

String documentFailureCode(Object error) => switch (error) {
  PlatformException(:final code) => switch (code) {
    'permission_revoked' ||
    'directory_missing' ||
    'storage_full' ||
    'provider_refused' ||
    'interrupted' ||
    'read_failed' => code,
    _ => 'storage_failed',
  },
  _ => 'verification_failed',
};
