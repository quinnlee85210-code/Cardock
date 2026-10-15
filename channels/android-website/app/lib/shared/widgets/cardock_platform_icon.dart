import 'dart:math' as math;

import '../../l10n/context_l10n.dart';
import '../../l10n/localized_material.dart';

import '../../core/branding/brand_catalog.dart';
import '../../core/branding/brand_catalog_loader.dart';
import '../../core/branding/brand_entry.dart';
import '../../core/branding/brand_matcher.dart';
import '../../core/theme/cardock_tokens.dart';

typedef CardockBrandImageProviderBuilder =
    ImageProvider<Object> Function(String assetPath);

enum CardockPlatformIconRole { neutral, account, subscription }

/// Resolves a user-entered platform name against the bundled offline catalog.
///
/// The catalog is loaded once for the process. Each widget instance owns only
/// its resolution future, so user-entered names are not retained in a static
/// cache. The first frame always uses a deterministic local fallback.
class CardockResolvedPlatformIcon extends StatefulWidget {
  const CardockResolvedPlatformIcon({
    required this.name,
    this.category,
    this.size = 40,
    this.role = CardockPlatformIconRole.neutral,
    this.semanticLabel,
    this.imageProviderBuilder,
    this.catalogFuture,
    super.key,
  });

  final String name;
  final String? category;
  final double size;
  final CardockPlatformIconRole role;
  final String? semanticLabel;
  final CardockBrandImageProviderBuilder? imageProviderBuilder;

  /// Test seam; production callers use the shared bundled catalog future.
  final Future<CardockBrandCatalog>? catalogFuture;

  @override
  State<CardockResolvedPlatformIcon> createState() =>
      _CardockResolvedPlatformIconState();
}

class _CardockResolvedPlatformIconState
    extends State<CardockResolvedPlatformIcon> {
  static final Future<CardockBrandCatalog> _sharedCatalog =
      const CardockBrandCatalogLoader().load();

  late CardockBrandResolution _fallback;
  late Future<CardockBrandResolution> _resolutionFuture;

  @override
  void initState() {
    super.initState();
    _prepareResolution();
  }

  @override
  void didUpdateWidget(CardockResolvedPlatformIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        oldWidget.category != widget.category ||
        oldWidget.catalogFuture != widget.catalogFuture) {
      _prepareResolution();
    }
  }

  void _prepareResolution() {
    _fallback = cardockBrandFallbackResolution(
      widget.name,
      category: widget.category,
    );
    _resolutionFuture = (widget.catalogFuture ?? _sharedCatalog)
        .then(
          (catalog) => CardockBrandMatcher(catalog).resolve(
            widget.name,
            category: widget.category,
            includeSuggestions: false,
          ),
        )
        .onError((_, _) => _fallback);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CardockBrandResolution>(
    future: _resolutionFuture,
    initialData: _fallback,
    builder: (context, snapshot) => CardockPlatformIcon(
      resolution: snapshot.data ?? _fallback,
      size: widget.size,
      role: widget.role,
      semanticLabel: widget.semanticLabel,
      imageProviderBuilder: widget.imageProviderBuilder,
    ),
  );
}

class CardockPlatformIcon extends StatelessWidget {
  const CardockPlatformIcon({
    required this.resolution,
    this.size = 40,
    this.role = CardockPlatformIconRole.neutral,
    this.semanticLabel,
    this.imageProviderBuilder,
    super.key,
  });

  final CardockBrandResolution resolution;
  final double size;
  final CardockPlatformIconRole role;
  final String? semanticLabel;
  final CardockBrandImageProviderBuilder? imageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final entry = resolution.entry;
    final scheme = Theme.of(context).colorScheme;
    final palette = context.cardockTheme.palette;
    final brand = _parseHex(entry?.brandColor) ?? scheme.primary;
    final semanticContainer = switch (role) {
      CardockPlatformIconRole.account => palette.accountIconBackground,
      CardockPlatformIconRole.subscription =>
        palette.subscriptionIconBackground,
      CardockPlatformIconRole.neutral => palette.brandContainer,
    };
    final semanticGlyph = switch (role) {
      CardockPlatformIconRole.account => palette.accountAccent,
      CardockPlatformIconRole.subscription => palette.subscriptionAccent,
      CardockPlatformIconRole.neutral => palette.textPrimary,
    };
    final hasBrandAsset = entry?.renderMode == CardockBrandRenderMode.monoBrand;
    final container = hasBrandAsset
        ? Color.alphaBlend(brand.withValues(alpha: 0.1), semanticContainer)
        : semanticContainer;
    final desiredGlyph = hasBrandAsset ? brand : semanticGlyph;
    final glyph = _contrastRatio(desiredGlyph, container) >= 3
        ? desiredGlyph
        : palette.textPrimary;
    final label =
        semanticLabel ??
        (entry == null
            ? context.tr('平台图标')
            : context.tr('{name}图标', <String, Object?>{
                'name': entry.canonicalName,
              }));

    return Semantics(
      container: true,
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey<String>('cardock-platform-icon-container'),
          width: size,
          height: size,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: container,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          alignment: Alignment.center,
          child: _content(context, entry, glyph),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, CardockBrandEntry? entry, Color glyph) {
    final matchedEntry = entry;
    if (matchedEntry != null &&
        matchedEntry.renderMode == CardockBrandRenderMode.monoBrand) {
      final provider =
          imageProviderBuilder?.call(matchedEntry.assetPath) ??
          AssetImage(matchedEntry.assetPath);
      return Transform.scale(
        scale: matchedEntry.opticalScale,
        child: Image(
          key: ValueKey<String>('brand-asset-${matchedEntry.brandId}'),
          image: provider,
          width: size * 0.58,
          height: size * 0.58,
          fit: BoxFit.contain,
          color: glyph,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) =>
              _monogram(matchedEntry.monogramText, glyph),
        ),
      );
    }

    final monogram = entry?.monogramText ?? resolution.monogramText;
    if (monogram != null && monogram.isNotEmpty) {
      return _monogram(monogram, glyph);
    }
    return Icon(
      _categoryIcon(resolution.category),
      key: const ValueKey<String>('brand-category-fallback'),
      size: size * 0.54,
      color: glyph,
    );
  }

  Widget _monogram(String? value, Color color) => Text(
    value?.isNotEmpty == true ? value! : '?',
    translate: false,
    key: const ValueKey<String>('brand-monogram'),
    maxLines: 1,
    overflow: TextOverflow.clip,
    style: TextStyle(
      color: color,
      fontSize: size * 0.34,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    ),
  );
}

IconData _categoryIcon(String? category) {
  final value = category?.toLowerCase() ?? '';
  if (value.contains('crypto') || value.contains('金融')) {
    return Icons.account_balance_wallet_outlined;
  }
  if (value.contains('telecom') || value.contains('通信')) {
    return Icons.cell_tower_outlined;
  }
  if (value.contains('cloud') || value.contains('云')) {
    return Icons.cloud_outlined;
  }
  if (value.contains('mail') || value.contains('邮箱')) {
    return Icons.alternate_email;
  }
  if (value.contains('social') || value.contains('社交')) {
    return Icons.forum_outlined;
  }
  if (value.contains('shop') || value.contains('购物')) {
    return Icons.shopping_bag_outlined;
  }
  if (value.contains('ai') || value.contains('办公')) {
    return Icons.auto_awesome_outlined;
  }
  return Icons.apps_outlined;
}

Color? _parseHex(String? value) {
  if (value == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

double _contrastRatio(Color left, Color right) {
  final leftLuminance = left.computeLuminance();
  final rightLuminance = right.computeLuminance();
  return (math.max(leftLuminance, rightLuminance) + 0.05) /
      (math.min(leftLuminance, rightLuminance) + 0.05);
}
