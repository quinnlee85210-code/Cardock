import 'package:account_subscription_manager/core/branding/brand_catalog.dart';
import 'package:account_subscription_manager/core/branding/brand_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/brand_catalog_fixture.dart';

void main() {
  late CardockBrandMatcher matcher;

  setUp(() {
    final catalog = CardockBrandCatalog.fromJson(
      catalogFixture(<Map<String, Object?>>[
        brandFixture(
          brandId: 'youtube',
          canonicalName: 'YouTube',
          aliases: const <String>['YouTube', 'You Tube'],
        ),
        brandFixture(
          brandId: 'youtube-music',
          canonicalName: 'YouTube Music',
          aliases: const <String>['YouTube Music'],
        ),
        brandFixture(
          brandId: 'spotify',
          canonicalName: 'Spotify',
          aliases: const <String>['Spotify', 'Spotify Music'],
        ),
        brandFixture(
          brandId: 'x',
          canonicalName: 'X',
          aliases: const <String>['X', 'Twitter'],
        ),
      ]),
    );
    matcher = CardockBrandMatcher(catalog);
  });

  test('binds exact compatibility-normalized aliases', () {
    final result = matcher.resolve('Ｙｏｕ Ｔｕｂｅ');
    expect(result.kind, CardockBrandMatchKind.exact);
    expect(result.entry?.brandId, 'youtube');
    expect(result.isAutomaticallyBound, isTrue);
  });

  test('binds only a sufficiently long unique prefix', () {
    expect(matcher.resolve('spot').kind, CardockBrandMatchKind.uniquePrefix);
    expect(matcher.resolve('spot').entry?.brandId, 'spotify');

    final sharedPrefix = matcher.resolve('yout');
    expect(sharedPrefix.kind, CardockBrandMatchKind.monogramFallback);
    expect(sharedPrefix.entry, isNull);
  });

  test('never auto-binds ambiguous short words', () {
    final result = matcher.resolve('X');
    expect(result.kind, CardockBrandMatchKind.monogramFallback);
    expect(result.entry, isNull);
    expect(result.isAutomaticallyBound, isFalse);
  });

  test('does not reinterpret an exact collision as a unique prefix', () {
    final collisionMatcher = CardockBrandMatcher(
      CardockBrandCatalog.fromJson(
        catalogFixture(<Map<String, Object?>>[
          brandFixture(
            brandId: 'shared-one',
            canonicalName: 'Shared One',
            aliases: const <String>['Shared', 'Shared Plus'],
          ),
          brandFixture(
            brandId: 'shared-two',
            canonicalName: 'Shared Two',
            aliases: const <String>['Shared'],
          ),
        ]),
      ),
    );

    final result = collisionMatcher.resolve('Shared');
    expect(result.kind, CardockBrandMatchKind.monogramFallback);
    expect(result.entry, isNull);
  });

  test('fuzzy matches are suggestions only and opt-in', () {
    final quiet = matcher.resolve('Spootify');
    expect(quiet.suggestions, isEmpty);
    expect(quiet.entry, isNull);

    final suggested = matcher.resolve('Spootify', includeSuggestions: true);
    expect(suggested.kind, CardockBrandMatchKind.monogramFallback);
    expect(suggested.entry, isNull);
    expect(suggested.suggestions.first.entry.brandId, 'spotify');
  });

  test('returns deterministic monogram and category fallbacks', () {
    final monogram = matcher.resolve(
      'North Star',
      category: 'cloud_vps_domain',
    );
    expect(monogram.kind, CardockBrandMatchKind.monogramFallback);
    expect(monogram.monogramText, 'NS');
    expect(monogram.category, 'cloud_vps_domain');

    final category = matcher.resolve(' ', category: 'telecom');
    expect(category.kind, CardockBrandMatchKind.categoryFallback);
    expect(category.monogramText, isNull);
    expect(category.category, 'telecom');
  });
}
