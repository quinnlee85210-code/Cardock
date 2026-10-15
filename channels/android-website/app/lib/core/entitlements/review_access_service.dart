import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'review_access_codec.dart';

abstract interface class ReviewAccessStore {
  Future<String?> read();
  Future<void> write(String credential);
  Future<void> remove();
}

/// Native methods require the actual Release signer and Play channel, use a
/// separate AES-GCM slot bound to the installation, and never access vault keys.
final class MethodChannelReviewAccessStore implements ReviewAccessStore {
  const MethodChannelReviewAccessStore();
  static const _channel = MethodChannel('cardock/commercial_license');
  @override
  Future<String?> read() => _channel
      .invokeMethod<String>('readReviewAccess')
      .timeout(const Duration(seconds: 20));
  @override
  Future<void> write(String credential) => _channel
      .invokeMethod<void>('saveReviewAccess', {'credential': credential})
      .timeout(const Duration(seconds: 20));
  @override
  Future<void> remove() => _channel
      .invokeMethod<void>('removeReviewAccess')
      .timeout(const Duration(seconds: 20));
}

enum ReviewAccessResult { activated, removed, invalid, unavailable }

final class ReviewAccessController extends ChangeNotifier
    implements ValueListenable<bool> {
  ReviewAccessController({required this.verifier, required this.store});
  final ReviewAccessVerifier verifier;
  final ReviewAccessStore store;
  bool _active = false;
  bool _busy = false;
  bool _disposed = false;
  Future<void> _tail = Future<void>.value();
  @override
  bool get value => _active;
  bool get isBusy => _busy;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      _busy = true;
      _notify();
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _busy = false;
        _notify();
      }
    });
    return result.future;
  }

  Future<void> initialize() => _exclusive(() async {
    try {
      final credential = await store.read();
      _active = credential != null && await verifier.verify(credential);
    } on Object {
      _active = false;
    }
  });
  Future<ReviewAccessResult> activate(String input) => _exclusive(() async {
    // Bound raw input before normalization or allocation. Only outer whitespace
    // is accepted; encoded fields and signatures are strictly canonical.
    if (input.length > 256) return ReviewAccessResult.invalid;
    final credential = input.trim();
    if (!await verifier.verify(credential)) return ReviewAccessResult.invalid;
    try {
      await store.write(credential);
      final persisted = await store.read();
      if (persisted != credential || !await verifier.verify(persisted!)) {
        return ReviewAccessResult.unavailable;
      }
      _active = true;
      return ReviewAccessResult.activated;
    } on Object {
      return ReviewAccessResult.unavailable;
    }
  });
  Future<ReviewAccessResult> remove() => _exclusive(() async {
    try {
      await store.remove();
      if (await store.read() != null) return ReviewAccessResult.unavailable;
      _active = false;
      return ReviewAccessResult.removed;
    } on Object {
      return ReviewAccessResult.unavailable;
    }
  });
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
