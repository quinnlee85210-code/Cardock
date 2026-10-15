import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/entitlements/promo_activation_codec.dart';
import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || arguments.contains('--help')) {
      _printUsage();
      return;
    }
    final command = arguments.first;
    final options = _parseOptions(arguments.skip(1).toList(growable: false));
    switch (command) {
      case 'keygen':
        await _keygen(options);
      case 'sign':
        await _sign(options);
      case 'verify':
        await _verify(options);
      case 'interactive':
        await _interactive(options);
      default:
        throw UsageException('未知子命令：$command');
    }
  } on UsageException catch (error) {
    stderr.writeln(error.message);
    _printUsage(toStderr: true);
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('操作失败：$error');
    exitCode = 1;
  }
}

Future<void> _keygen(Map<String, String?> options) async {
  final keyFile = File(_keyPath(options));
  if (await keyFile.exists() && !options.containsKey('force')) {
    throw UsageException('私钥文件已存在；如确认替换，请增加 --force。');
  }
  await keyFile.parent.create(recursive: true);
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final extracted = await keyPair.extract();
  try {
    final publicKey = await extracted.extractPublicKey();
    final document = <String, Object>{
      'version': 1,
      'algorithm': 'Ed25519',
      'privateSeed': base64Encode(extracted.bytes),
      'publicKey': base64Encode(publicKey.bytes),
    };
    await keyFile.writeAsString(jsonEncode(document), flush: true);
    stdout.writeln('私钥已写入本地忽略文件：${keyFile.path}');
    stdout.writeln('请把以下公钥常量复制到应用配置：');
    stdout.writeln('static const List<int> publicKeyBytes = <int>[');
    for (var index = 0; index < publicKey.bytes.length; index += 8) {
      final candidateEnd = index + 8;
      final end = candidateEnd < publicKey.bytes.length
          ? candidateEnd
          : publicKey.bytes.length;
      stdout.writeln('  ${publicKey.bytes.sublist(index, end).join(', ')},');
    }
    stdout.writeln('];');
  } finally {
    extracted.destroy();
  }
}

Future<void> _sign(Map<String, String?> options) async {
  final request = options['request'];
  if (request == null || !isValidPromoRequestCode(request)) {
    throw UsageException('sign 需要有效的 --request <8位申请码>。');
  }
  final keyPair = await _loadKeyPair(File(_keyPath(options)));
  try {
    final code = await const PromoActivationIssuer().issue(
      requestCode: request,
      keyPair: keyPair,
    );
    final csvFile = File(_csvPath(options));
    await _appendIssuedCode(
      csvFile,
      issuedAtUtc: DateTime.now().toUtc(),
      requestCode: normalizePromoRequestCode(request),
      activationCode: code,
      note: options['note'] ?? '',
    );
    stdout.writeln(code);
    stdout.writeln('签发记录已追加：${csvFile.path}');
  } finally {
    keyPair.destroy();
  }
}

Future<void> _verify(Map<String, String?> options) async {
  final code = options['code'];
  if (code == null || code.trim().isEmpty) {
    throw UsageException('verify 需要 --code <激活码>。');
  }
  final requestCode = readPromoRequestCodeUnchecked(code);
  if (requestCode == null) throw const FormatException('激活码格式不正确');
  final keyPair = await _loadKeyPair(File(_keyPath(options)));
  try {
    final publicKey = await keyPair.extractPublicKey();
    final verification = await PromoActivationVerifier(
      publicKeyBytes: publicKey.bytes,
    ).verify(activationCode: code, expectedRequestCode: requestCode);
    if (!verification.isValid) {
      throw const FormatException('签名验证失败');
    }
    stdout.writeln('验证通过');
    stdout.writeln('申请码：${verification.requestCode}');
    stdout.writeln('签发时间：${verification.issuedAtUtc!.toIso8601String()}');
  } finally {
    keyPair.destroy();
  }
}

Future<void> _interactive(Map<String, String?> options) async {
  stdout.writeln('Cardock 离线推广激活码签发');
  stdout.writeln('本流程将在本机完成签发和公钥自校验，不会发起网络请求。');
  stdout.writeln();
  stdout.write('请输入用户提供的 8 位申请码：');
  final requestInput = stdin.readLineSync(encoding: utf8);
  if (requestInput == null || !isValidPromoRequestCode(requestInput)) {
    throw UsageException('申请码格式不正确，应为应用显示的 8 位申请码。');
  }
  final requestCode = normalizePromoRequestCode(requestInput);

  stdout.write('请输入本机备注（可留空，例如“亲友-张三”）：');
  final note = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
  stdout.writeln();
  stdout.writeln('申请码：$requestCode');
  stdout.writeln('备注：${note.isEmpty ? '未填写' : note}');
  stdout.write('确认签发永久完整版？请输入 YES：');
  final confirmation = stdin.readLineSync(encoding: utf8)?.trim().toUpperCase();
  if (confirmation != 'YES') {
    stdout.writeln('已取消，未签发激活码，也未写入签发记录。');
    return;
  }

  final keyPair = await _loadKeyPair(File(_keyPath(options)));
  try {
    final issuedAtUtc = DateTime.now().toUtc();
    final code = await const PromoActivationIssuer().issue(
      requestCode: requestCode,
      keyPair: keyPair,
      issuedAtUtc: issuedAtUtc,
    );
    final publicKey = await keyPair.extractPublicKey();
    final verification = await PromoActivationVerifier(
      publicKeyBytes: publicKey.bytes,
    ).verify(activationCode: code, expectedRequestCode: requestCode);
    if (!verification.isValid || verification.canonicalCode != code) {
      throw const FormatException('签发后的公钥自校验失败，未写入签发记录');
    }

    final csvFile = File(_csvPath(options));
    await _appendIssuedCode(
      csvFile,
      issuedAtUtc: issuedAtUtc,
      requestCode: requestCode,
      activationCode: code,
      note: note,
    );
    stdout.writeln();
    stdout.writeln('签发并验证通过，请只把下面这一行激活码发送给对应用户：');
    stdout.writeln(code);
    stdout.writeln();
    stdout.writeln('申请码：${verification.requestCode}');
    stdout.writeln('签发时间：${verification.issuedAtUtc!.toIso8601String()}');
    stdout.writeln('本地记录：${csvFile.path}');
  } finally {
    keyPair.destroy();
  }
}

Future<SimpleKeyPairData> _loadKeyPair(File file) async {
  if (!await file.exists()) {
    throw UsageException('找不到私钥文件：${file.path}');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic> ||
      decoded['version'] != 1 ||
      decoded['algorithm'] != 'Ed25519' ||
      decoded['privateSeed'] is! String ||
      decoded['publicKey'] is! String) {
    throw const FormatException('私钥文件格式不正确');
  }
  final seed = base64Decode(decoded['privateSeed']! as String);
  final storedPublic = base64Decode(decoded['publicKey']! as String);
  if (seed.length != 32 || storedPublic.length != 32) {
    throw const FormatException('私钥文件长度不正确');
  }
  final extracted = await (await Ed25519().newKeyPairFromSeed(seed)).extract();
  final derivedPublic = await extracted.extractPublicKey();
  if (!_bytesEqual(derivedPublic.bytes, storedPublic)) {
    extracted.destroy();
    throw const FormatException('私钥与公钥不匹配');
  }
  return extracted;
}

Future<void> _appendIssuedCode(
  File file, {
  required DateTime issuedAtUtc,
  required String requestCode,
  required String activationCode,
  required String note,
}) async {
  await file.parent.create(recursive: true);
  final isNew = !await file.exists() || await file.length() == 0;
  final sink = file.openWrite(mode: FileMode.append);
  try {
    if (isNew) {
      sink.writeln('issued_at_utc,request_code,activation_code,note');
    }
    sink.writeln(
      <String>[
        issuedAtUtc.toIso8601String(),
        requestCode,
        activationCode,
        note,
      ].map(_csvCell).join(','),
    );
  } finally {
    await sink.close();
  }
}

String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

Map<String, String?> _parseOptions(List<String> arguments) {
  final result = <String, String?>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) {
      throw UsageException('无法识别参数：$argument');
    }
    final name = argument.substring(2);
    if (name == 'force') {
      result[name] = null;
      continue;
    }
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw UsageException('--$name 缺少参数值。');
    }
    result[name] = arguments[++index];
  }
  return result;
}

String _keyPath(Map<String, String?> options) =>
    options['key'] ??
    '${_toolDirectory()}${Platform.pathSeparator}promo_private.key';

String _csvPath(Map<String, String?> options) =>
    options['csv'] ??
    '${_toolDirectory()}${Platform.pathSeparator}issued_codes.csv';

String _toolDirectory() => File.fromUri(Platform.script).parent.path;

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

void _printUsage({bool toStderr = false}) {
  const usage = '''
离线推广签码工具

  dart run tool/promo_signer/promo_signer.dart keygen [--key <路径>] [--force]
  dart run tool/promo_signer/promo_signer.dart sign --request <申请码> [--note <备注>] [--key <路径>] [--csv <路径>]
  dart run tool/promo_signer/promo_signer.dart verify --code <激活码> [--key <路径>]
  dart run tool/promo_signer/promo_signer.dart interactive [--key <路径>] [--csv <路径>]
''';
  (toStderr ? stderr : stdout).write(usage);
}

final class UsageException implements Exception {
  const UsageException(this.message);

  final String message;
}
