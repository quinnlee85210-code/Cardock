import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_codec.dart'
    show crockfordBase32Encode;
import 'package:account_subscription_manager/core/entitlements/review_access_codec.dart';

// Run only through scripts/Initialize-CardockReviewAccess.ps1, which first
// verifies owner-only ACLs. No secrets or credentials are printed.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw StateError('Project and protected backup required');
  }
  final root = Directory(args[0]).absolute.path;
  final private = Directory('$root/private-signing/review-access');
  final backup = Directory(args[1]);
  if (!private.existsSync() ||
      !backup.existsSync() ||
      !backup.absolute.path.startsWith(
        '$root${Platform.pathSeparator}backups${Platform.pathSeparator}',
      )) {
    throw StateError('Protected paths required');
  }
  final seedFile = File('${private.path}/issuer.seed');
  final algorithm = Ed25519();
  final key = seedFile.existsSync()
      ? await algorithm.newKeyPairFromSeed(await seedFile.readAsBytes())
      : await algorithm.newKeyPair();
  if (!seedFile.existsSync()) {
    await seedFile.writeAsBytes(
      await key.extractPrivateKeyBytes(),
      flush: true,
    );
  }
  final publicKey = await key.extractPublicKey();
  final verifier = ReviewAccessVerifier(publicKey: publicKey.bytes);
  final credentialFile = File('${private.path}/credential.txt');
  String credential;
  if (credentialFile.existsSync()) {
    credential = (await credentialFile.readAsString()).trim();
  } else {
    final random = Random.secure();
    final audience = (await Sha256().hash(
      utf8.encode(reviewAccessApplicationId),
    )).bytes;
    final payload = <int>[
      1,
      1,
      1,
      1,
      1,
      ...audience,
      ...List<int>.generate(16, (_) => random.nextInt(256)),
    ];
    final signature = await algorithm.sign([
      ...utf8.encode(reviewAccessDomain),
      ...payload,
    ], keyPair: key);
    credential =
        'CR1${crockfordBase32Encode([...payload, ...signature.bytes])}';
    await credentialFile.writeAsString(credential, flush: true);
  }
  if (!await verifier.verify(credential)) {
    throw StateError('Credential verification failed');
  }
  final fields = <String, String>{
    'Name': 'Cardock full-feature review access',
    'Username': '',
    'Password': '',
    'Other information':
        'Set your own local vault password. Tap bottom-right Settings, then Language (语言) > English. Open Unlock Full Version > Review access. Paste $credential and tap Enable review access. All record limits and themes are free. Use fictional data; vault passwords still apply.',
  };
  for (final entry in <String, int>{
    'Name': 60,
    'Username': 100,
    'Password': 100,
    'Other information': 500,
  }.entries) {
    if (fields[entry.key]!.length > entry.value) {
      throw StateError('Console field exceeds limit');
    }
  }
  final jsonFile = File('${private.path}/console-fields.json');
  final textFile = File('${private.path}/console-fields.txt');
  final deliveries = <File, String>{
    jsonFile: const JsonEncoder.withIndent('  ').convert(fields),
    textFile: fields.entries.map((e) => '${e.key}:\n${e.value}\n').join('\n'),
  };
  for (final entry in deliveries.entries) {
    if (entry.key.existsSync()) {
      if (await entry.key.readAsString() == entry.value) continue;
      final prior = File(
        '${backup.path}/${entry.key.uri.pathSegments.last}.before',
      );
      if (prior.existsSync()) {
        throw StateError('Refusing to overwrite prior delivery');
      }
      await entry.key.copy(prior.path);
      if (base64Encode(
            (await Sha256().hash(await entry.key.readAsBytes())).bytes,
          ) !=
          base64Encode(
            (await Sha256().hash(await prior.readAsBytes())).bytes,
          )) {
        throw StateError('Prior delivery backup mismatch');
      }
    }
    await entry.key.writeAsString(entry.value, flush: true);
  }
  for (final source in [seedFile, credentialFile, jsonFile, textFile]) {
    final target = File('${backup.path}/${source.uri.pathSegments.last}');
    if (target.existsSync()) throw StateError('Refusing to overwrite backup');
    await source.copy(target.path);
    if (base64Encode((await Sha256().hash(await source.readAsBytes())).bytes) !=
        base64Encode((await Sha256().hash(await target.readAsBytes())).bytes)) {
      throw StateError('Backup mismatch');
    }
  }
  final config = File(
    '$root/app/lib/core/entitlements/review_access_public_key.dart',
  );
  final code =
      '// Public verification key for free review access only. Private signer stays outside Git.\nconst reviewAccessPublicKey = <int>[${publicKey.bytes.join(',')}];\n';
  if (config.existsSync()) {
    final existing = await config.readAsString();
    final match = RegExp(r'<int>\[([\s\S]*?)\]').firstMatch(existing);
    final values = match == null
        ? <int>[]
        : RegExp(r'\d+')
              .allMatches(match.group(1)!)
              .map((m) => int.parse(m.group(0)!))
              .toList();
    if (base64Encode(values) != base64Encode(publicKey.bytes)) {
      throw StateError('Existing public key differs; refusing rotation');
    }
  }
  if (!config.existsSync()) await config.writeAsString(code);
  stdout.writeln(
    jsonEncode({
      'credentialVerified': true,
      'credentialLength': credential.length,
      'fieldLengths': fields.map((k, v) => MapEntry(k, v.length)),
      'publicKeyBase64': base64Encode(publicKey.bytes),
      'privateBackupFiles': 4,
    }),
  );
}
