enum CardockBrandRenderMode { monoBrand, monogram }

CardockBrandRenderMode _renderModeFromJson(Object? value) => switch (value) {
  'mono_brand' => CardockBrandRenderMode.monoBrand,
  'monogram' => CardockBrandRenderMode.monogram,
  _ => throw const FormatException('品牌渲染模式无效'),
};

final class CardockBrandEntry {
  const CardockBrandEntry({
    required this.brandId,
    required this.canonicalName,
    required this.aliases,
    required this.ambiguousAliases,
    required this.categories,
    required this.regions,
    required this.assetPath,
    required this.renderMode,
    required this.brandColor,
    required this.opticalScale,
    required this.minimumRenderableDp,
    required this.sourceKind,
    required this.trademarkAuthorization,
    this.monogramText,
  });

  factory CardockBrandEntry.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('品牌目录条目格式无效');
    }

    String requiredString(String key) {
      final field = value[key];
      if (field is! String || field.trim().isEmpty) {
        throw FormatException('品牌目录缺少 $key');
      }
      return field.trim();
    }

    List<String> stringList(String key, {bool allowEmpty = false}) {
      final field = value[key];
      if (field is! List<Object?> ||
          (!allowEmpty && field.isEmpty) ||
          field.any((item) => item is! String || item.trim().isEmpty)) {
        throw FormatException('品牌目录字段 $key 无效');
      }
      return List<String>.unmodifiable(
        field.cast<String>().map((item) => item.trim()),
      );
    }

    final brandId = requiredString('brandId');
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(brandId)) {
      throw const FormatException('品牌 ID 无效');
    }

    final color = requiredString('brandColor');
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
      throw const FormatException('品牌颜色无效');
    }

    final scale = value['opticalScale'];
    if (scale is! num || scale < 0.8 || scale > 1.15) {
      throw const FormatException('品牌视觉比例无效');
    }
    final minimumDp = value['minimumRenderableDp'];
    if (minimumDp is! num || minimumDp < 16 || minimumDp > 64) {
      throw const FormatException('品牌最小渲染尺寸无效');
    }

    final renderMode = _renderModeFromJson(value['renderMode']);
    final monogram = value['monogramText'];
    if (renderMode == CardockBrandRenderMode.monogram &&
        (monogram is! String || monogram.trim().isEmpty)) {
      throw const FormatException('自有字母标缺少文字');
    }

    return CardockBrandEntry(
      brandId: brandId,
      canonicalName: requiredString('canonicalName'),
      aliases: stringList('aliases'),
      ambiguousAliases: stringList('ambiguousAliases', allowEmpty: true),
      categories: stringList('categories'),
      regions: stringList('regions'),
      assetPath: requiredString('assetPath'),
      renderMode: renderMode,
      brandColor: color.toUpperCase(),
      opticalScale: scale.toDouble(),
      minimumRenderableDp: minimumDp.toDouble(),
      monogramText: monogram is String ? monogram.trim() : null,
      sourceKind: requiredString('sourceKind'),
      trademarkAuthorization: requiredString('trademarkAuthorization'),
    );
  }

  final String brandId;
  final String canonicalName;
  final List<String> aliases;
  final List<String> ambiguousAliases;
  final List<String> categories;
  final List<String> regions;
  final String assetPath;
  final CardockBrandRenderMode renderMode;
  final String brandColor;
  final double opticalScale;
  final double minimumRenderableDp;
  final String? monogramText;
  final String sourceKind;
  final String trademarkAuthorization;
}
