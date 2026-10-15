import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'temporary_web_controller.dart';
import 'temporary_web_crypto.dart';
import 'temporary_web_pairing.dart';

typedef TemporaryWebAssetLoader = Future<String> Function(String assetKey);

final class IoTemporaryWebTransport implements TemporaryWebTransport {
  IoTemporaryWebTransport({
    TemporaryWebAssetLoader? assetLoader,
    Duration requestReadTimeout = const Duration(seconds: 10),
    int maximumConcurrentHandlers = 8,
    int maximumBufferedRequestBytes = 1024 * 1024,
  }) : assert(requestReadTimeout > Duration.zero),
       assert(maximumConcurrentHandlers > 0),
       assert(maximumBufferedRequestBytes > 0),
       _assetLoader = assetLoader ?? rootBundle.loadString,
       _requestReadTimeout = requestReadTimeout,
       _maximumConcurrentHandlers = maximumConcurrentHandlers,
       _maximumBufferedRequestBytes = maximumBufferedRequestBytes;

  static const int _maximumRequestBytes = 512 * 1024;

  final TemporaryWebAssetLoader _assetLoader;
  final Duration _requestReadTimeout;
  final int _maximumConcurrentHandlers;
  final int _maximumBufferedRequestBytes;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  TrustedLanPhonePairing? _pairing;
  TrustedLanSecureChannel? _channel;
  TemporaryWebCommandHandler? _onCommand;
  void Function(String remoteAddress)? _onPaired;
  void Function(Object error)? _onFatalError;
  Map<String, _StaticAsset> _assets = const <String, _StaticAsset>{};
  String? _expectedHost;
  String? _expectedOrigin;
  String? _pairedRemoteAddress;
  int _epoch = 0;
  bool _accepting = false;
  int _activeRequestHandlers = 0;
  int _bufferedRequestBytes = 0;
  bool _pairingInProgress = false;
  bool _messageInProgress = false;

  @override
  Future<TemporaryWebTransportBinding> start({
    required String address,
    required TemporaryWebCommandHandler onCommand,
    required void Function(String remoteAddress) onPaired,
    required void Function(Object error) onFatalError,
  }) async {
    if (_server != null || _accepting) {
      throw StateError('Temporary web transport is already running.');
    }
    final internetAddress = InternetAddress.tryParse(address);
    if (internetAddress == null ||
        internetAddress.type != InternetAddressType.IPv4) {
      throw ArgumentError('A concrete IPv4 address is required.');
    }

    final epoch = ++_epoch;
    final pairing = await TrustedLanPhonePairing.start();
    HttpServer? server;
    try {
      final loadedAssets =
          await Future.wait(<Future<MapEntry<String, _StaticAsset>>>[
            _loadAsset(
              '/',
              'assets/temporary_web/index.html',
              'text/html; charset=utf-8',
            ),
            _loadAsset(
              '/index.html',
              'assets/temporary_web/index.html',
              'text/html; charset=utf-8',
            ),
            _loadAsset(
              '/app.css',
              'assets/temporary_web/app.css',
              'text/css; charset=utf-8',
            ),
            _loadAsset(
              '/app.js',
              'assets/temporary_web/app.js',
              'text/javascript; charset=utf-8',
            ),
          ]);
      if (epoch != _epoch) {
        pairing.cancel();
        throw StateError('Temporary web transport start was revoked.');
      }
      server = await HttpServer.bind(internetAddress, 0, shared: false);
      server.autoCompress = false;
      if (epoch != _epoch) {
        pairing.cancel();
        await server.close(force: true);
        throw StateError('Temporary web transport start was revoked.');
      }

      _pairing = pairing;
      _server = server;
      _onCommand = onCommand;
      _onPaired = onPaired;
      _onFatalError = onFatalError;
      _assets = Map<String, _StaticAsset>.unmodifiable(<String, _StaticAsset>{
        for (final item in loadedAssets) item.key: item.value,
      });
      _expectedHost = '$address:${server.port}';
      _expectedOrigin = Uri(
        scheme: 'http',
        host: address,
        port: server.port,
      ).origin;
      _pairedRemoteAddress = null;
      _accepting = true;
      _activeRequestHandlers = 0;
      _bufferedRequestBytes = 0;
      _pairingInProgress = false;
      _messageInProgress = false;
      _subscription = server.listen(
        (request) => unawaited(_handleRequest(epoch, request)),
        onError: (Object error, StackTrace stackTrace) {
          if (epoch == _epoch && _accepting) {
            _accepting = false;
            _onFatalError?.call(error);
          }
        },
        cancelOnError: false,
      );
      return TemporaryWebTransportBinding(
        port: server.port,
        formattedConnectionCode: pairing.formattedConnectionCode,
      );
    } catch (_) {
      pairing.cancel();
      if (server != null) await server.close(force: true);
      rethrow;
    }
  }

  @override
  void revoke() {
    ++_epoch;
    _accepting = false;
    _activeRequestHandlers = 0;
    _bufferedRequestBytes = 0;
    _pairingInProgress = false;
    _messageInProgress = false;
    _pairing?.cancel();
    _pairing = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.destroy());
    _onCommand = null;
    _onPaired = null;
    _pairedRemoteAddress = null;
  }

  @override
  Future<void> stop() async {
    revoke();
    final subscription = _subscription;
    final server = _server;
    _subscription = null;
    _server = null;
    _expectedHost = null;
    _expectedOrigin = null;
    _assets = const <String, _StaticAsset>{};
    await subscription?.cancel();
    await server?.close(force: true);
  }

  Future<MapEntry<String, _StaticAsset>> _loadAsset(
    String requestPath,
    String assetKey,
    String contentType,
  ) async {
    final text = await _assetLoader(assetKey);
    return MapEntry<String, _StaticAsset>(
      requestPath,
      _StaticAsset(
        bytes: Uint8List.fromList(utf8.encode(text)),
        contentType: contentType,
      ),
    );
  }

  Future<void> _handleRequest(int epoch, HttpRequest request) async {
    var handlerAdmitted = false;
    try {
      _setSecurityHeaders(request.response);
      if (!_accepting || epoch != _epoch) {
        await _sendJsonAndCancelUnreadRequest(
          request,
          HttpStatus.gone,
          const <String, Object?>{'status': 'sessionEnded'},
        );
        return;
      }
      if (_activeRequestHandlers >= _maximumConcurrentHandlers) {
        await _sendJsonAndCancelUnreadRequest(
          request,
          HttpStatus.serviceUnavailable,
          const <String, Object?>{'status': 'serverBusy'},
        );
        return;
      }
      _activeRequestHandlers += 1;
      handlerAdmitted = true;
      if (!_validHost(request)) {
        await _sendJsonAndCancelUnreadRequest(
          request,
          HttpStatus.badRequest,
          const <String, Object?>{'status': 'invalidHost'},
        );
        return;
      }
      if (request.method == 'GET' &&
          (request.contentLength > 0 ||
              request.headers.chunkedTransferEncoding)) {
        await _sendJsonAndCancelUnreadRequest(
          request,
          HttpStatus.badRequest,
          const <String, Object?>{'status': 'invalidRequest'},
        );
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && _assets.containsKey(path)) {
        await _sendAsset(request.response, _assets[path]!);
        return;
      }
      if (request.method == 'GET' && path == '/api/pairing/hello') {
        await _sendPairingHello(request);
        return;
      }
      if (request.method == 'POST' && path == '/api/pairing/finish') {
        await _finishPairing(epoch, request);
        return;
      }
      if (request.method == 'POST' && path == '/api/message') {
        await _handleEncryptedMessage(epoch, request);
        return;
      }
      await _sendJsonAndCancelUnreadRequest(
        request,
        HttpStatus.notFound,
        const <String, Object?>{'status': 'notFound'},
      );
    } on _RequestResponseSentException {
      // The body reader completed a bounded rejection while cancelling its
      // request subscription.
    } on _RequestTimeoutException {
      await _sendJsonIfPossible(
        request.response,
        HttpStatus.requestTimeout,
        const <String, Object?>{'status': 'requestTimeout'},
      );
    } on _RequestTooLargeException {
      await _sendJsonIfPossible(
        request.response,
        HttpStatus.requestEntityTooLarge,
        const <String, Object?>{'status': 'requestTooLarge'},
      );
    } on _ServerBusyException {
      await _sendJsonIfPossible(
        request.response,
        HttpStatus.serviceUnavailable,
        const <String, Object?>{'status': 'serverBusy'},
      );
    } on Object {
      await _sendJsonIfPossible(
        request.response,
        HttpStatus.badRequest,
        const <String, Object?>{'status': 'invalidRequest'},
      );
    } finally {
      if (handlerAdmitted && epoch == _epoch) {
        _activeRequestHandlers -= 1;
      }
    }
  }

  Future<void> _sendPairingHello(HttpRequest request) async {
    if (_pairedRemoteAddress != null || _pairing == null) {
      await _sendJson(
        request.response,
        HttpStatus.conflict,
        const <String, Object?>{'status': 'alreadyPaired'},
      );
      return;
    }
    await _sendJson(request.response, HttpStatus.ok, <String, Object?>{
      'hello': _pairing!.hello.toJson(),
    });
  }

  Future<void> _finishPairing(int epoch, HttpRequest request) async {
    if (!_validPostRequest(request)) {
      await _sendJsonAndCancelUnreadRequest(
        request,
        HttpStatus.forbidden,
        const <String, Object?>{'status': 'rejected'},
      );
      return;
    }
    if (_pairingInProgress) {
      await _sendJsonAndCancelUnreadRequest(
        request,
        HttpStatus.tooManyRequests,
        const <String, Object?>{'status': 'requestInProgress'},
      );
      return;
    }
    final remoteAddress = request.connectionInfo?.remoteAddress.address;
    final pairing = _pairing;
    if (remoteAddress == null || pairing == null || _channel != null) {
      await _sendJsonAndCancelUnreadRequest(
        request,
        HttpStatus.conflict,
        const <String, Object?>{'status': 'alreadyPaired'},
      );
      return;
    }

    _pairingInProgress = true;
    try {
      final body = await _readJsonObject(epoch, request);
      final helloJson = _requiredJsonObject(body, 'hello');
      final result = await pairing.finish(
        TrustedLanBrowserHello.fromJson(helloJson),
      );
      if (!_accepting || epoch != _epoch) {
        await result.channel.destroy();
        return;
      }
      _pairing = null;
      _channel = result.channel;
      _pairedRemoteAddress = remoteAddress;
      await _sendJson(request.response, HttpStatus.ok, <String, Object?>{
        'confirmation': result.confirmation.toJson(),
      });
      _onPaired?.call(remoteAddress);
    } on _RequestReadException {
      rethrow;
    } on Object {
      _pairing = null;
      _accepting = false;
      await _sendJsonIfPossible(
        request.response,
        HttpStatus.unauthorized,
        const <String, Object?>{
          'status': 'pairingFailed',
          'message': '连接码无效或配对已失效，请在手机端重新开启。',
        },
      );
      if (epoch == _epoch) {
        _onFatalError?.call(const TemporaryWebPairingRejectedException());
      }
    } finally {
      if (epoch == _epoch) _pairingInProgress = false;
    }
  }

  Future<void> _handleEncryptedMessage(int epoch, HttpRequest request) async {
    if (!_validPostRequest(request)) {
      await _sendJsonAndCancelUnreadRequest(
        request,
        HttpStatus.forbidden,
        const <String, Object?>{'status': 'rejected'},
      );
      return;
    }
    final remoteAddress = request.connectionInfo?.remoteAddress.address;
    final channel = _channel;
    if (remoteAddress == null ||
        remoteAddress != _pairedRemoteAddress ||
        channel == null) {
      await _sendJsonAndCancelUnreadRequest(
        request,
        HttpStatus.unauthorized,
        const <String, Object?>{'status': 'notPaired'},
      );
      return;
    }
    if (_messageInProgress) {
      await _sendJsonAndCancelUnreadRequest(
        request,
        HttpStatus.tooManyRequests,
        const <String, Object?>{'status': 'requestInProgress'},
      );
      return;
    }

    _messageInProgress = true;
    Uint8List? plaintext;
    Uint8List? responsePlaintext;
    try {
      final body = await _readJsonObject(epoch, request);
      final frame = TrustedLanEncryptedFrame.fromJson(
        _requiredJsonObject(body, 'frame'),
      );
      plaintext = await channel.decrypt(frame);
      final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      final command = _stringKeyedObject(decoded);
      final handler = _onCommand;
      if (handler == null || epoch != _epoch || !_accepting) {
        throw StateError('Temporary web session ended.');
      }
      final result = await handler(command, remoteAddress);
      responsePlaintext = Uint8List.fromList(utf8.encode(jsonEncode(result)));
      final responseFrame = await channel.encrypt(responsePlaintext);
      await _sendJson(request.response, HttpStatus.ok, <String, Object?>{
        'frame': responseFrame.toJson(),
      });
    } on TrustedLanRecordException catch (error) {
      _accepting = false;
      await _sendJsonIfPossible(
        request.response,
        HttpStatus.unauthorized,
        const <String, Object?>{'status': 'encryptedRecordRejected'},
      );
      if (epoch == _epoch) _onFatalError?.call(error);
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      responsePlaintext?.fillRange(0, responsePlaintext.length, 0);
      _messageInProgress = false;
    }
  }

  bool _validHost(HttpRequest request) =>
      request.headers.value(HttpHeaders.hostHeader) == _expectedHost;

  bool _validPostRequest(HttpRequest request) {
    final contentType = request.headers.contentType;
    return contentType?.mimeType == ContentType.json.mimeType &&
        request.headers.value('origin') == _expectedOrigin;
  }

  Future<Map<String, Object?>> _readJsonObject(
    int epoch,
    HttpRequest request,
  ) async {
    final declaredLength = request.contentLength;
    var reservedBytes = 0;
    final builder = BytesBuilder(copy: false);
    final iterator = StreamIterator<List<int>>(request);
    final stopwatch = Stopwatch()..start();
    var length = 0;
    Map<String, Object?>? result;
    _RequestReadException? rejection;
    try {
      if (declaredLength > _maximumRequestBytes) {
        throw const _RequestTooLargeException();
      }
      if (declaredLength > 0) {
        _reserveBufferedBytes(epoch, declaredLength);
        reservedBytes = declaredLength;
      }
      while (true) {
        final remaining = _requestReadTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          throw const _RequestTimeoutException();
        }
        final hasNext = await iterator.moveNext().timeout(remaining);
        if (!hasNext) break;
        final chunk = iterator.current;
        length += chunk.length;
        if (length > _maximumRequestBytes) {
          throw const _RequestTooLargeException();
        }
        if (declaredLength < 0) {
          _reserveBufferedBytes(epoch, chunk.length);
          reservedBytes += chunk.length;
        }
        builder.add(chunk);
      }
      final decoded = jsonDecode(
        utf8.decode(builder.takeBytes(), allowMalformed: false),
      );
      result = _stringKeyedObject(decoded);
    } on TimeoutException {
      rejection = const _RequestTimeoutException();
    } on _RequestReadException catch (error) {
      rejection = error;
    } finally {
      stopwatch.stop();
      final detachedResponse = rejection == null
          ? null
          : _beginDetachedRequestReadRejection(request.response, rejection);
      try {
        await iterator.cancel();
      } on Object {
        // The request may already have been closed by the peer or server.
      }
      if (detachedResponse != null) {
        await _completeDetachedJsonResponse(detachedResponse);
      }
      if (reservedBytes > 0 && epoch == _epoch) {
        _bufferedRequestBytes -= reservedBytes;
        assert(_bufferedRequestBytes >= 0);
      }
    }
    if (rejection != null) {
      throw const _RequestResponseSentException();
    }
    return result!;
  }

  ({Future<Socket> socket, List<int> body}) _beginDetachedRequestReadRejection(
    HttpResponse response,
    _RequestReadException rejection,
  ) {
    final (statusCode, status) = switch (rejection) {
      _RequestTimeoutException() => (
        HttpStatus.requestTimeout,
        'requestTimeout',
      ),
      _RequestTooLargeException() => (
        HttpStatus.requestEntityTooLarge,
        'requestTooLarge',
      ),
      _ServerBusyException() => (HttpStatus.serviceUnavailable, 'serverBusy'),
      _RequestResponseSentException() => throw StateError(
        'A sent response cannot be sent again.',
      ),
    };
    return _beginDetachedJsonResponse(response, statusCode, <String, Object?>{
      'status': status,
    });
  }

  Future<void> _sendJsonAndCancelUnreadRequest(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    final subscription = request.listen((_) {});
    final detachedResponse = _beginDetachedJsonResponse(
      request.response,
      statusCode,
      body,
    );
    try {
      await subscription.cancel();
    } on Object {
      // The peer may have already closed its request stream.
    }
    await _completeDetachedJsonResponse(detachedResponse);
  }

  ({Future<Socket> socket, List<int> body}) _beginDetachedJsonResponse(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> value,
  ) {
    final body = utf8.encode(jsonEncode(value));
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.headers.contentLength = body.length;
    return (socket: response.detachSocket(), body: body);
  }

  Future<void> _completeDetachedJsonResponse(
    ({Future<Socket> socket, List<int> body}) response,
  ) async {
    Socket? socket;
    try {
      socket = await response.socket;
      socket.add(response.body);
      await socket.flush();
      await socket.close();
    } on Object {
      socket?.destroy();
    }
  }

  void _reserveBufferedBytes(int epoch, int byteCount) {
    if (!_accepting || epoch != _epoch) {
      throw const _ServerBusyException();
    }
    if (_bufferedRequestBytes + byteCount > _maximumBufferedRequestBytes) {
      throw const _ServerBusyException();
    }
    _bufferedRequestBytes += byteCount;
  }

  Map<String, Object?> _stringKeyedObject(Object? value) {
    if (value is! Map<Object?, Object?> || value.length > 128) {
      throw const FormatException('JSON object required.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('JSON keys must be strings.');
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  Map<String, Object?> _requiredJsonObject(
    Map<String, Object?> value,
    String key,
  ) => _stringKeyedObject(value[key]);

  void _setSecurityHeaders(HttpResponse response) {
    response.headers
      ..set(
        HttpHeaders.cacheControlHeader,
        'no-store, no-cache, must-revalidate, private',
      )
      ..set(HttpHeaders.pragmaHeader, 'no-cache')
      ..set(HttpHeaders.expiresHeader, '0')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('X-Frame-Options', 'DENY')
      ..set(
        'Permissions-Policy',
        'camera=(), microphone=(), geolocation=(), payment=(), usb=(), '
            'bluetooth=(), clipboard-read=(), clipboard-write=()',
      )
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'self'; style-src 'self'; "
            "connect-src 'self'; img-src 'self' data:; base-uri 'none'; "
            "form-action 'none'; frame-ancestors 'none'; object-src 'none'",
      );
  }

  Future<void> _sendAsset(HttpResponse response, _StaticAsset asset) async {
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, asset.contentType);
    response.headers.contentLength = asset.bytes.length;
    response.add(asset.bytes);
    await response.close();
  }

  Future<void> _sendJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    final bytes = utf8.encode(jsonEncode(body));
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.headers.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

  Future<void> _sendJsonIfPossible(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    try {
      await _sendJson(response, statusCode, body);
    } on Object {
      response.close();
    }
  }
}

final class _StaticAsset {
  const _StaticAsset({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

sealed class _RequestReadException implements Exception {
  const _RequestReadException();
}

final class _RequestTimeoutException extends _RequestReadException {
  const _RequestTimeoutException();
}

final class _RequestTooLargeException extends _RequestReadException {
  const _RequestTooLargeException();
}

final class _ServerBusyException extends _RequestReadException {
  const _ServerBusyException();
}

final class _RequestResponseSentException extends _RequestReadException {
  const _RequestResponseSentException();
}
