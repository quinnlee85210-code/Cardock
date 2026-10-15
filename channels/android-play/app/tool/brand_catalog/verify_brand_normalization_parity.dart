import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:account_subscription_manager/core/branding/brand_name_normalizer.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final master = File(options.masterPath).absolute;
    final output = File(options.outputPath).absolute;
    if (!master.existsSync()) {
      throw FormatException('Master manifest not found: ${master.path}');
    }
    if (!output.parent.existsSync() ||
        output.parent.path.toLowerCase() != master.parent.path.toLowerCase()) {
      throw const FormatException(
        'Parity output must use the existing master manifest directory',
      );
    }
    if (output.uri.pathSegments.last !=
        'cardock-brand-catalog-v1-normalization-parity.json') {
      throw const FormatException('Unexpected parity manifest filename');
    }

    final masterBytes = await master.readAsBytes();
    final decoded = jsonDecode(utf8.decode(masterBytes));
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Master manifest schema is unsupported');
    }
    final parity = decoded['normalizationParity'];
    if (parity is! Map<String, Object?> ||
        parity['normalizationPolicy'] != cardockBrandNormalizationPolicy) {
      throw const FormatException('Master normalization policy is unsupported');
    }
    final rawCases = parity['cases'];
    final declaredCount = parity['caseCount'];
    final casesSha256 = parity['casesSha256'];
    final pythonVersion = parity['pythonUnidataVersion'];
    if (rawCases is! List<Object?> ||
        declaredCount is! int ||
        rawCases.length != declaredCount ||
        casesSha256 is! String ||
        !RegExp(r'^[0-9A-F]{64}$').hasMatch(casesSha256) ||
        pythonVersion is! String ||
        pythonVersion.isEmpty) {
      throw const FormatException(
        'Master normalization parity cases are invalid',
      );
    }

    final seenRaw = <String>{};
    final mismatches = <Map<String, Object?>>[];
    for (final rawCase in rawCases) {
      if (rawCase is! Map<String, Object?>) {
        throw const FormatException('Normalization parity case is invalid');
      }
      final raw = rawCase['raw'];
      final buildKey = rawCase['buildKey'];
      if (raw is! String || buildKey is! String || !seenRaw.add(raw)) {
        throw const FormatException(
          'Normalization parity cases must contain unique string values',
        );
      }
      final runtimeKey = normalizeCardockBrandName(raw);
      if (runtimeKey != buildKey) {
        mismatches.add(<String, Object?>{
          'raw': raw,
          'buildKey': buildKey,
          'runtimeKey': runtimeKey,
        });
      }
    }

    final masterDigest = await Sha256().hash(masterBytes);
    final masterSha256 = _hex(masterDigest.bytes);
    final result = <String, Object?>{
      'schemaVersion': 1,
      'status': mismatches.isEmpty ? 'passed' : 'failed',
      'generatedAtUtc': decoded['generatedAtUtc'],
      'normalizationPolicy': cardockBrandNormalizationPolicy,
      'runtimeNormalizer': <String, Object?>{
        'package': 'unorm_dart',
        'version': '0.3.2',
        'unicodeVersion': '17.0',
      },
      'buildNormalizer': <String, Object?>{
        'engine': parity['buildEngine'],
        'unicodeVersion': pythonVersion,
      },
      'sourceMasterFile': master.uri.pathSegments.last,
      'sourceMasterSha256': masterSha256,
      'parityCasesSha256': casesSha256,
      'caseCount': rawCases.length,
      'matchedCaseCount': rawCases.length - mismatches.length,
      'mismatchCount': mismatches.length,
      'mismatches': mismatches.take(50).toList(growable: false),
    };
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      encoding: utf8,
      flush: true,
    );
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'caseCount': rawCases.length,
        'mismatchCount': mismatches.length,
        'sourceMasterSha256': masterSha256,
        'status': result['status'],
      }),
    );
    if (mismatches.isNotEmpty) {
      exitCode = 1;
    }
  } on Object catch (error) {
    stderr.writeln('NORMALIZATION_PARITY_FAIL: $error');
    exitCode = 1;
  }
}

({String masterPath, String outputPath}) _parseArguments(
  List<String> arguments,
) {
  String? masterPath;
  String? outputPath;
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length) {
      throw const FormatException(
        'Parity tool arguments must be key/value pairs',
      );
    }
    switch (arguments[index]) {
      case '--master':
        if (masterPath != null) {
          throw const FormatException('Duplicate --master argument');
        }
        masterPath = arguments[index + 1];
      case '--output':
        if (outputPath != null) {
          throw const FormatException('Duplicate --output argument');
        }
        outputPath = arguments[index + 1];
      default:
        throw FormatException('Unknown argument: ${arguments[index]}');
    }
  }
  if (masterPath == null || outputPath == null) {
    throw const FormatException('--master and --output are required');
  }
  return (masterPath: masterPath, outputPath: outputPath);
}

String _hex(List<int> bytes) => bytes
    .map((value) => value.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();
