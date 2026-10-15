import 'package:account_subscription_manager/core/branding/brand_name_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cardock Unicode NFKC brand normalizer', () {
    test('folds fullwidth ASCII and common separators', () {
      expect(normalizeCardockBrandName('Ｇｏｏｇｌｅ　Ｃｌｏｕｄ'), 'googlecloud');
      expect(normalizeCardockBrandName('A‑B—C'), 'abc');
    });

    test('covers Unicode compatibility characters and ligatures', () {
      expect(normalizeCardockBrandName('K ﬃ Å'), 'kffiå');
      expect(normalizeCardockBrandName('A·B / C'), 'abc');
    });

    test('normalizes compatibility numerals and unit symbols', () {
      expect(normalizeCardockBrandName('①'), '1');
      expect(normalizeCardockBrandName('㎏'), 'kg');
    });

    test('removes the fixed Unicode White_Space boundary', () {
      expect(normalizeCardockBrandName('A\u0085B\u2028C\u2029D'), 'abcd');
      expect(normalizeCardockBrandName('A\u1680B\u205FC'), 'abc');
    });

    test('uses lowercase and does not overclaim full case folding', () {
      expect(normalizeCardockBrandName('Straße'), 'straße');
      expect(normalizeCardockBrandName('STRASSE'), 'strasse');
      expect(normalizeCardockBrandName('Σ'), 'σ');
      expect(normalizeCardockBrandName('ς'), 'ς');
    });
  });
}
