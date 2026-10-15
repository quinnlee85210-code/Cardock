import 'dart:convert';

import 'package:flutter/services.dart';

import '../security/account_comparison.dart';
import 'brand_catalog.dart';

final class CardockBrandCatalogLoader {
  const CardockBrandCatalogLoader({
    this.assetPath = 'assets/brands/v1/runtime_catalog.json',
  });

  final String assetPath;

  Future<CardockBrandCatalog> load({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    return decode(source);
  }

  CardockBrandCatalog decode(String source) {
    final catalog = CardockBrandCatalog.fromJson(jsonDecode(source));
    AccountComparison.configureCatalog(catalog);
    return catalog;
  }
}
