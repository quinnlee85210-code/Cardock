import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class TemporaryWebRuntimeKeeper {
  Future<void> start();

  Future<void> stop();
}

final class NoopTemporaryWebRuntimeKeeper implements TemporaryWebRuntimeKeeper {
  const NoopTemporaryWebRuntimeKeeper();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

final class MethodChannelTemporaryWebRuntimeKeeper
    implements TemporaryWebRuntimeKeeper {
  const MethodChannelTemporaryWebRuntimeKeeper([
    this._channel = const MethodChannel('cardock/temporary_web_runtime'),
  ]);

  final MethodChannel _channel;

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

TemporaryWebRuntimeKeeper createDefaultTemporaryWebRuntimeKeeper() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return const MethodChannelTemporaryWebRuntimeKeeper();
  }
  return const NoopTemporaryWebRuntimeKeeper();
}
