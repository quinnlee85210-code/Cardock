import 'package:account_subscription_manager/core/branding/brand_catalog.dart';
import 'package:account_subscription_manager/core/branding/brand_catalog_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/brand_catalog_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads schema v1 and builds immutable ID and alias indexes', () {
    final catalog = CardockBrandCatalog.fromJson(
      catalogFixture(<Map<String, Object?>>[
        brandFixture(
          brandId: 'spotify',
          canonicalName: 'Spotify',
          aliases: const <String>['Spotify', 'Spotify Music'],
        ),
      ]),
    );

    expect(catalog.entries, hasLength(1));
    expect(catalog.byId['spotify']?.canonicalName, 'Spotify');
    expect(catalog.aliasBrandIds['spotifymusic'], <String>{'spotify'});
    expect(
      () => catalog.entries.add(catalog.entries.single),
      throwsUnsupportedError,
    );
  });

  test('rejects unknown future schema and duplicate stable IDs', () {
    expect(
      () => CardockBrandCatalog.fromJson(<String, Object?>{
        'schemaVersion': 2,
        'brands': <Object?>[],
      }),
      throwsFormatException,
    );
    expect(
      () => CardockBrandCatalog.fromJson(
        catalogFixture(<Map<String, Object?>>[
          brandFixture(brandId: 'same', canonicalName: 'First'),
          brandFixture(brandId: 'same', canonicalName: 'Second'),
        ]),
      ),
      throwsFormatException,
    );
  });

  test('rejects old, missing, or unknown normalization policies', () {
    final brand = brandFixture(brandId: 'local', canonicalName: 'Local');
    for (final policy in <Object?>[
      null,
      'cardock_compat_v1_not_full_icu_nfkc',
      'unicode_nfkc_future_v2',
    ]) {
      expect(
        () => CardockBrandCatalog.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'normalizationPolicy': policy,
          'brands': <Object?>[brand],
        }),
        throwsFormatException,
      );
    }
  });

  test('colliding aliases and hard short words are always ambiguous', () {
    final catalog = CardockBrandCatalog.fromJson(
      catalogFixture(<Map<String, Object?>>[
        brandFixture(
          brandId: 'first',
          canonicalName: 'First',
          aliases: const <String>['Shared', 'X'],
        ),
        brandFixture(
          brandId: 'second',
          canonicalName: 'Second',
          aliases: const <String>['Shared'],
        ),
      ]),
    );

    expect(catalog.ambiguousKeys, containsAll(<String>['shared', 'x']));
  });

  test('loader decodes catalog text without network or persistence', () {
    const loader = CardockBrandCatalogLoader();
    final catalog = loader.decode('''
      {"schemaVersion":1,
       "normalizationPolicy":"unicode_nfkc_v1_runtime_unorm_dart_0.3.2_unicode17_build_corpus_parity_v1",
       "brands":[{
        "brandId":"local","canonicalName":"Local","aliases":["Local"],
        "ambiguousAliases":[],"categories":["productivity_ai_dev"],
        "regions":["global"],"assetPath":"assets/brands/v1/icons/local.png",
        "renderMode":"monogram","brandColor":"#3F63D8","opticalScale":1.0,
        "minimumRenderableDp":24,"monogramText":"LO",
        "sourceKind":"cardock_generated_monogram",
        "trademarkAuthorization":"not_granted"
      }]}
    ''');

    expect(catalog.byId, contains('local'));
  });

  test('bundled catalog freezes V5 coverage and local asset paths', () async {
    final catalog = await const CardockBrandCatalogLoader().load();
    final aliasCount = catalog.entries.fold<int>(
      0,
      (total, entry) => total + entry.aliases.length,
    );

    expect(catalog.entries, hasLength(600));
    expect(catalog.byId, hasLength(600));
    expect(aliasCount, 1824);
    expect(
      catalog.entries.where(
        (entry) => entry.sourceKind == 'cardock_generated_monogram',
      ),
      hasLength(117),
    );
    expect(
      catalog.entries.map((entry) => entry.assetPath).toSet(),
      hasLength(600),
    );
  });
}
