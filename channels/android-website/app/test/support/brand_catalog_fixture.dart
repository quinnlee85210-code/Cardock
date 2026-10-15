import 'package:account_subscription_manager/core/branding/brand_name_normalizer.dart';

Map<String, Object?> brandFixture({
  required String brandId,
  required String canonicalName,
  List<String>? aliases,
  List<String>? ambiguousAliases,
  String category = 'productivity_ai_dev',
  String renderMode = 'mono_brand',
  String? monogramText,
}) => <String, Object?>{
  'brandId': brandId,
  'canonicalName': canonicalName,
  'aliases': aliases ?? <String>[canonicalName],
  'ambiguousAliases': ambiguousAliases ?? const <String>[],
  'categories': <String>[category],
  'regions': const <String>['global'],
  'assetPath': 'assets/brands/v1/icons/$brandId.png',
  'assetFormat': 'png',
  'renderMode': renderMode,
  'brandColor': '#3F63D8',
  'opticalScale': 1.0,
  'minimumRenderableDp': 24,
  'monogramText': renderMode == 'monogram'
      ? (monogramText ?? canonicalName.substring(0, 1).toUpperCase())
      : null,
  'sourceKind': renderMode == 'monogram'
      ? 'cardock_generated_monogram'
      : 'simple_icons_cc0',
  'trademarkAuthorization': 'not_granted',
};

Map<String, Object?> catalogFixture(List<Map<String, Object?>> brands) =>
    <String, Object?>{
      'schemaVersion': 1,
      'catalogVersion': 'test-v1',
      'normalizationPolicy': cardockBrandNormalizationPolicy,
      'brands': brands,
    };
