import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../branding/brand_catalog.dart';
import '../branding/brand_name_normalizer.dart';

/// Comparison copies only. Never change the user's stored values.
abstract final class AccountComparison {
  static CardockBrandCatalog? _catalog;
  static int catalogRevision = 0;

  static void configureCatalog(CardockBrandCatalog catalog) {
    if (identical(_catalog, catalog)) return;
    _catalog = catalog;
    catalogRevision++;
  }

  static String platform(String? value) {
    final key = normalizeCardockBrandName(value ?? '');
    final catalog = _catalog;
    final ids = catalog?.aliasBrandIds[key];
    if (ids != null &&
        ids.length == 1 &&
        !catalog!.ambiguousKeys.contains(key)) {
      return 'brand:${ids.single}';
    }
    return key.isEmpty ? '' : 'name:$key';
  }

  static String login(String? value) => unorm.nfkc(value ?? '').trim();
  static String email(String? value) => login(value).toLowerCase();
  static String phone(String? value) => unorm
      .nfkc(value ?? '')
      .trim()
      .replaceAll(RegExp(r'[\s\-()\u2010\u2011\u2012\u2013\u2014\u2212]'), '');

  static String domain(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return '';
    }
    var host = uri.host.toLowerCase();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.startsWith('www.')) host = host.substring(4);
    // A bounded local suffix table, with conservative exact-host fallback for
    // unknown multi-level public suffixes. No DNS or external lookup.
    final parts = host.split('.');
    if (parts.length < 3 ||
        RegExp(r'^[0-9.]+$').hasMatch(host) ||
        host.contains(':')) {
      return host;
    }
    const common = {
      'com',
      'org',
      'net',
      'io',
      'app',
      'dev',
      'ai',
      'edu',
      'gov',
      'cn',
      'jp',
      'uk',
      'au',
      'de',
      'fr',
      'ca',
      'us',
      'ch',
      'me',
      'tv',
      'info',
      'biz',
      'co',
    };
    const twoLevel = {
      'com.cn',
      'net.cn',
      'org.cn',
      'gov.cn',
      'edu.cn',
      'co.uk',
      'org.uk',
      'ac.uk',
      'com.au',
      'net.au',
      'org.au',
      'co.jp',
      'ne.jp',
      'or.jp',
      'co.nz',
      'co.in',
      'com.hk',
      'com.tw',
      'com.sg',
      'com.br',
      'co.kr',
    };
    final tail = parts.sublist(parts.length - 2).join('.');
    if (twoLevel.contains(tail)) {
      return parts.sublist(parts.length - 3).join('.');
    }
    // Shared hosting tenants must not be merged by their hosting provider.
    const tenants = {
      'github.io',
      'pages.dev',
      'blogspot.com',
      'appspot.com',
      'vercel.app',
      'netlify.app',
      'azurewebsites.net',
      'herokuapp.com',
      'cloudfront.net',
    };
    if (tenants.contains(tail)) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return common.contains(parts.last) ? tail : host;
  }

  static Map<String, String> duplicateKeys({
    required String platformName,
    String? loginAccount,
    String? username,
    String? emailValue,
    String? phoneValue,
    String? website,
  }) {
    final p = platform(platformName),
        l = login(loginAccount),
        u = login(username);
    final e = email(emailValue), ph = phone(phoneValue), d = domain(website);
    return duplicateKeysFromNormalized(
      platformValue: p,
      loginValue: l,
      usernameValue: u,
      emailValue: e,
      phoneValue: ph,
      domainValue: d,
    );
  }

  static Map<String, String> duplicateKeysFromNormalized({
    required String platformValue,
    required String loginValue,
    String usernameValue = '',
    required String emailValue,
    required String phoneValue,
    required String domainValue,
  }) {
    final p = platformValue,
        l = loginValue,
        u = usernameValue,
        e = emailValue,
        ph = phoneValue,
        d = domainValue;
    final keys = <String, String>{};
    void add(String kind, String a, String b) {
      if (a.isNotEmpty && b.isNotEmpty) keys[jsonEncode([kind, a, b])] = kind;
    }

    add('platformName+loginAccount', p, l);
    add('domain+loginAccount', d, l);
    add('platformName+email', p, e);
    add('platformName+phone', p, ph);
    if (p.isNotEmpty && u.isNotEmpty && d.isNotEmpty) {
      keys[jsonEncode(['platformName+username+domain', p, u, d])] =
          'platformName+username+domain';
    }
    return keys;
  }
}
