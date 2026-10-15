import 'package:url_launcher/url_launcher.dart';

abstract interface class ExternalUrlLauncher {
  Future<bool> open(String input);
}

final class SafeUrlLauncher implements ExternalUrlLauncher {
  const SafeUrlLauncher();

  @override
  Future<bool> open(String input) {
    final uri = normalizeExternalHttpUrl(input);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Uri normalizeExternalHttpUrl(String input) {
  final normalized = input.trim();
  if (normalized.isEmpty) {
    throw const FormatException('网址不能为空');
  }
  if (normalized.runes.any((rune) => rune <= 0x20 || rune == 0x7f)) {
    throw const FormatException('网址不能包含空白或控制字符');
  }
  if (normalized.contains(r'\')) {
    throw const FormatException('网址格式无效');
  }

  final domainWithPort = RegExp(
    r'^[^/?#:]+(?:\.[^/?#:]+)*:\d+(?:[/?#]|$)',
    caseSensitive: false,
  ).hasMatch(normalized);
  final explicitScheme = RegExp(
    r'^[A-Za-z][A-Za-z0-9+.-]*:',
  ).hasMatch(normalized);

  final candidate = normalized.startsWith('//')
      ? 'https:$normalized'
      : (!explicitScheme || domainWithPort)
      ? 'https://$normalized'
      : normalized;
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('仅支持不含账号信息的 http/https 网址');
  }
  if (uri.host.startsWith('.') || uri.host.endsWith('.')) {
    throw const FormatException('网址主机格式无效');
  }
  try {
    uri.port;
  } on FormatException {
    throw const FormatException('网址端口格式无效');
  }
  return uri;
}
