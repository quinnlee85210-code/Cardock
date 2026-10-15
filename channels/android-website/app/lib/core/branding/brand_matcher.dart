import 'dart:math' as math;

import 'brand_catalog.dart';
import 'brand_entry.dart';
import 'brand_name_normalizer.dart';

enum CardockBrandMatchKind {
  exact,
  uniquePrefix,
  monogramFallback,
  categoryFallback,
}

final class CardockBrandSuggestion {
  const CardockBrandSuggestion({required this.entry, required this.distance});

  final CardockBrandEntry entry;
  final int distance;
}

final class CardockBrandResolution {
  const CardockBrandResolution({
    required this.kind,
    required this.suggestions,
    this.entry,
    this.monogramText,
    this.category,
  });

  final CardockBrandMatchKind kind;
  final CardockBrandEntry? entry;
  final String? monogramText;
  final String? category;
  final List<CardockBrandSuggestion> suggestions;

  bool get isAutomaticallyBound =>
      kind == CardockBrandMatchKind.exact ||
      kind == CardockBrandMatchKind.uniquePrefix;
}

final class CardockBrandMatcher {
  const CardockBrandMatcher(this.catalog);

  final CardockBrandCatalog catalog;

  CardockBrandResolution resolve(
    String input, {
    String? category,
    bool includeSuggestions = false,
    int suggestionLimit = 5,
  }) {
    final key = normalizeCardockBrandName(input);
    if (key.isEmpty) {
      return cardockBrandFallbackResolution(input, category: category);
    }

    final exactIds = catalog.aliasBrandIds[key];
    if (exactIds != null &&
        exactIds.length == 1 &&
        !catalog.ambiguousKeys.contains(key)) {
      return CardockBrandResolution(
        kind: CardockBrandMatchKind.exact,
        entry: catalog.byId[exactIds.single],
        suggestions: const <CardockBrandSuggestion>[],
      );
    }

    if (_prefixIsLongEnough(key) &&
        !catalog.ambiguousKeys.contains(key) &&
        !_isRiskyPrefix(key)) {
      final ids = <String>{};
      for (final alias in catalog.aliasBrandIds.entries) {
        if (alias.key.startsWith(key) &&
            !catalog.ambiguousKeys.contains(alias.key)) {
          ids.addAll(alias.value);
          if (ids.length > 1) break;
        }
      }
      if (ids.length == 1) {
        return CardockBrandResolution(
          kind: CardockBrandMatchKind.uniquePrefix,
          entry: catalog.byId[ids.single],
          suggestions: const <CardockBrandSuggestion>[],
        );
      }
    }

    final suggestions = includeSuggestions
        ? _suggest(key, limit: suggestionLimit)
        : const <CardockBrandSuggestion>[];
    final fallback = cardockBrandFallbackResolution(input, category: category);
    return CardockBrandResolution(
      kind: fallback.kind,
      monogramText: fallback.monogramText,
      category: fallback.category,
      suggestions: suggestions,
    );
  }

  bool _isRiskyPrefix(String key) => cardockNeverAutoBindAliases.any(
    (ambiguous) => ambiguous.startsWith(key) || key.startsWith(ambiguous),
  );

  List<CardockBrandSuggestion> _suggest(String query, {required int limit}) {
    if (limit <= 0) return const <CardockBrandSuggestion>[];
    final suggestions = <CardockBrandSuggestion>[];
    for (final entry in catalog.entries) {
      var best = _levenshtein(
        query,
        normalizeCardockBrandName(entry.canonicalName),
      );
      for (final alias in entry.aliases) {
        best = math.min(
          best,
          _levenshtein(query, normalizeCardockBrandName(alias)),
        );
      }
      final threshold = query.length <= 4 ? 1 : 2;
      if (best <= threshold) {
        suggestions.add(CardockBrandSuggestion(entry: entry, distance: best));
      }
    }
    suggestions.sort((left, right) {
      final distance = left.distance.compareTo(right.distance);
      if (distance != 0) return distance;
      return left.entry.canonicalName.compareTo(right.entry.canonicalName);
    });
    return List<CardockBrandSuggestion>.unmodifiable(suggestions.take(limit));
  }
}

CardockBrandResolution cardockBrandFallbackResolution(
  String input, {
  String? category,
}) {
  final key = normalizeCardockBrandName(input);
  return CardockBrandResolution(
    kind: key.isEmpty
        ? CardockBrandMatchKind.categoryFallback
        : CardockBrandMatchKind.monogramFallback,
    monogramText: key.isEmpty ? null : _monogram(input),
    category: category,
    suggestions: const <CardockBrandSuggestion>[],
  );
}

bool _prefixIsLongEnough(String key) {
  final asciiOnly = key.runes.every((rune) => rune <= 0x7F);
  return key.runes.length >= (asciiOnly ? 4 : 2);
}

String _monogram(String input) {
  final words = input
      .trim()
      .split(RegExp(r'[\s\-_.:/]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length >= 2) {
    return String.fromCharCodes(<int>[
      words.first.runes.first,
      words[1].runes.first,
    ]).toUpperCase();
  }
  final runes = input
      .trim()
      .runes
      .where((rune) {
        final normalized = normalizeCardockBrandName(String.fromCharCode(rune));
        return normalized.isNotEmpty;
      })
      .take(2)
      .toList();
  return runes.isEmpty ? '?' : String.fromCharCodes(runes).toUpperCase();
}

int _levenshtein(String left, String right) {
  if (left == right) return 0;
  if (left.isEmpty) return right.length;
  if (right.isEmpty) return left.length;
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var i = 0; i < left.length; i++) {
    final current = List<int>.filled(right.length + 1, 0)..[0] = i + 1;
    for (var j = 0; j < right.length; j++) {
      final substitution = previous[j] + (left[i] == right[j] ? 0 : 1);
      current[j + 1] = math.min(
        math.min(current[j] + 1, previous[j + 1] + 1),
        substitution,
      );
    }
    previous = current;
  }
  return previous.last;
}
