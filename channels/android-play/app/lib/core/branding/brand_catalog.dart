import 'brand_entry.dart';
import 'brand_name_normalizer.dart';

final class CardockBrandCatalog {
  CardockBrandCatalog._({
    required this.entries,
    required this.byId,
    required this.aliasBrandIds,
    required this.ambiguousKeys,
  });

  factory CardockBrandCatalog.fromJson(Object? value) {
    if (value is! Map<Object?, Object?> || value['schemaVersion'] != 1) {
      throw const FormatException('品牌运行时目录版本不受支持');
    }
    if (value['normalizationPolicy'] != cardockBrandNormalizationPolicy) {
      throw const FormatException('品牌目录归一化策略不受支持');
    }
    final rawBrands = value['brands'];
    if (rawBrands is! List<Object?> || rawBrands.isEmpty) {
      throw const FormatException('品牌运行时目录为空');
    }

    final entries = rawBrands.map(CardockBrandEntry.fromJson).toList();
    final byId = <String, CardockBrandEntry>{};
    final aliasIds = <String, Set<String>>{};
    final explicitlyAmbiguous = <String>{};

    for (final entry in entries) {
      if (byId[entry.brandId] != null) {
        throw FormatException('品牌 ID 重复：${entry.brandId}');
      }
      byId[entry.brandId] = entry;

      for (final value in <String>[entry.canonicalName, ...entry.aliases]) {
        final key = normalizeCardockBrandName(value);
        if (key.isEmpty) continue;
        (aliasIds[key] ??= <String>{}).add(entry.brandId);
      }
      for (final value in entry.ambiguousAliases) {
        final key = normalizeCardockBrandName(value);
        if (key.isNotEmpty) explicitlyAmbiguous.add(key);
      }
    }

    final collisions = aliasIds.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key);
    final ambiguousKeys = <String>{
      ...explicitlyAmbiguous,
      ...collisions,
      ...cardockNeverAutoBindAliases,
    };

    return CardockBrandCatalog._(
      entries: List<CardockBrandEntry>.unmodifiable(entries),
      byId: Map<String, CardockBrandEntry>.unmodifiable(byId),
      aliasBrandIds: Map<String, Set<String>>.unmodifiable(
        aliasIds.map(
          (key, ids) => MapEntry(key, Set<String>.unmodifiable(ids)),
        ),
      ),
      ambiguousKeys: Set<String>.unmodifiable(ambiguousKeys),
    );
  }

  final List<CardockBrandEntry> entries;
  final Map<String, CardockBrandEntry> byId;
  final Map<String, Set<String>> aliasBrandIds;
  final Set<String> ambiguousKeys;
}

final Set<String> cardockNeverAutoBindAliases = Set<String>.unmodifiable(
  const <String>[
    'x',
    'max',
    'line',
    'three',
    'bell',
    'm1',
    'tm',
    'one',
    'prime',
  ].map(normalizeCardockBrandName),
);
