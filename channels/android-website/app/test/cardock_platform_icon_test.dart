import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/branding/brand_catalog.dart';
import 'package:account_subscription_manager/core/branding/brand_matcher.dart';
import 'package:account_subscription_manager/shared/widgets/cardock_platform_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/brand_catalog_fixture.dart';

void main() {
  testWidgets('renders deterministic monogram and category fallbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            CardockPlatformIcon(
              resolution: cardockBrandFallbackResolution('North Star'),
            ),
            CardockPlatformIcon(
              resolution: cardockBrandFallbackResolution(
                '',
                category: 'cloud_vps_domain',
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('NS'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
  });

  testWidgets('uses the offline asset path, tint, and semantic label', (
    tester,
  ) async {
    final catalog = _catalog();
    final resolution = CardockBrandMatcher(catalog).resolve('Spotify');
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: CardockPlatformIcon(
          resolution: resolution,
          semanticLabel: 'Spotify 离线品牌图标',
          imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('brand-asset-spotify')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Spotify 离线品牌图标'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.colorBlendMode, BlendMode.srcIn);
    semantics.dispose();
  });

  testWidgets(
    'resolved wrapper paints fallback before shared lookup completes',
    (tester) async {
      final completer = Completer<CardockBrandCatalog>();
      await tester.pumpWidget(
        MaterialApp(
          home: CardockResolvedPlatformIcon(
            name: 'Spotify Music',
            catalogFuture: completer.future,
            imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
          ),
        ),
      );

      expect(find.text('SM'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      completer.complete(_catalog());
      await tester.pump();

      expect(find.text('SM'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('brand-asset-spotify')),
        findsOneWidget,
      );
    },
  );
}

CardockBrandCatalog _catalog() => CardockBrandCatalog.fromJson(
  catalogFixture(<Map<String, Object?>>[
    brandFixture(
      brandId: 'spotify',
      canonicalName: 'Spotify',
      aliases: const <String>['Spotify', 'Spotify Music'],
    ),
  ]),
);

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
