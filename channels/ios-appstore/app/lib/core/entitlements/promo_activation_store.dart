import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'promo_activation_codec.dart';

final class PromoActivationRecord {
  PromoActivationRecord({
    required List<int> installationId,
    this.activationCode,
  }) : installationId = Uint8List.fromList(installationId);

  final Uint8List installationId;
  final String? activationCode;

  PromoActivationRecord copyWith({String? activationCode}) =>
      PromoActivationRecord(
        installationId: installationId,
        activationCode: activationCode ?? this.activationCode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'installationId': base64Encode(installationId),
    'activationCode': activationCode,
  };

  static PromoActivationRecord? tryParse(Object? value) {
    if (value is! Map<Object?, Object?> || value['version'] != 1) return null;
    final encodedInstallationId = value['installationId'];
    final activationCode = value['activationCode'];
    if (encodedInstallationId is! String ||
        (activationCode != null && activationCode is! String)) {
      return null;
    }
    try {
      final installationId = base64Decode(encodedInstallationId);
      if (installationId.length != promoInstallationIdLength ||
          (activationCode is String && activationCode.length > 512)) {
        return null;
      }
      return PromoActivationRecord(
        installationId: installationId,
        activationCode: activationCode as String?,
      );
    } on Object {
      return null;
    }
  }
}

abstract interface class PromoActivationStore {
  Future<PromoActivationRecord?> read();

  Future<void> write(PromoActivationRecord record);
}

/// Fails closed when the platform cannot provide persistent app storage.
///
/// A temporary in-memory installation ID would change after process restart
/// and therefore must never be exposed as a device-bound request code.
final class UnavailablePromoActivationStore implements PromoActivationStore {
  const UnavailablePromoActivationStore();

  @override
  Future<PromoActivationRecord?> read() => Future<PromoActivationRecord?>.error(
    StateError('Promo activation storage is unavailable'),
  );

  @override
  Future<void> write(PromoActivationRecord record) =>
      Future<void>.error(StateError('Promo activation storage is unavailable'));
}

final class MemoryPromoActivationStore implements PromoActivationStore {
  MemoryPromoActivationStore([this.value]);

  PromoActivationRecord? value;

  @override
  Future<PromoActivationRecord?> read() async => value;

  @override
  Future<void> write(PromoActivationRecord record) async {
    value = record;
  }
}

final class FilePromoActivationStore implements PromoActivationStore {
  FilePromoActivationStore(this.file);

  final File file;

  static Future<PromoActivationStore> create() async {
    try {
      final support = await getApplicationSupportDirectory();
      return FilePromoActivationStore(
        File(
          '${support.path}${Platform.pathSeparator}'
          'cardock_promo_activation_v1.json',
        ),
      );
    } on Object {
      return const UnavailablePromoActivationStore();
    }
  }

  @override
  Future<PromoActivationRecord?> read() async {
    for (final candidate in <File>[
      file,
      File('${file.path}.bak'),
      File('${file.path}.tmp'),
    ]) {
      try {
        if (!await candidate.exists()) continue;
        final decoded = jsonDecode(await candidate.readAsString());
        final parsed = PromoActivationRecord.tryParse(decoded);
        if (parsed != null) return parsed;
      } on Object {
        continue;
      }
    }
    return null;
  }

  @override
  Future<void> write(PromoActivationRecord record) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
    if (await file.exists()) {
      await file.copy(backup.path);
      await file.delete();
    }
    await temporary.rename(file.path);
  }
}
