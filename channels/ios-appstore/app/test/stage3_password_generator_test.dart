import 'dart:math';

import 'package:account_subscription_manager/core/security/account_password_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'secure production generator defaults to 20 characters and all classes',
    () {
      final generator = AccountPasswordGenerator();
      final results = <String>{};
      for (var i = 0; i < 100; i++) {
        final value = generator.generate();
        results.add(value);
        expect(value.length, 20);
        expect(value, matches(RegExp('[A-Z]')));
        expect(value, matches(RegExp('[a-z]')));
        expect(value, matches(RegExp('[2-9]')));
        expect(
          value
              .split('')
              .any(AccountPasswordGenerator.symbolCharacters.contains),
          isTrue,
        );
        expect(
          value
              .split('')
              .any(AccountPasswordGenerator.ambiguousCharacters.contains),
          isFalse,
        );
        expect(value, isNot(contains(RegExp('[\\s"\'\x00-\x1f]'))));
      }
      expect(results, hasLength(100));
    },
  );
  for (final length in [8, 64]) {
    test('length boundary $length retains every selected category', () {
      final generator = AccountPasswordGenerator.forTesting(Random(3));
      for (var i = 0; i < 100; i++) {
        final value = generator.generate(
          options: AccountPasswordOptions(length: length),
        );
        expect(value.length, length);
        expect(value, matches(RegExp('[A-Z]')));
        expect(value, matches(RegExp('[a-z]')));
        expect(value, matches(RegExp('[2-9]')));
        expect(
          value
              .split('')
              .any(AccountPasswordGenerator.symbolCharacters.contains),
          isTrue,
        );
      }
    });
  }
  for (var bits = 1; bits < 16; bits++) {
    test('all nonempty category selections $bits are honored', () {
      final options = AccountPasswordOptions(
        uppercase: bits & 1 != 0,
        lowercase: bits & 2 != 0,
        digits: bits & 4 != 0,
        symbols: bits & 8 != 0,
        excludeAmbiguous: false,
      );
      final value = AccountPasswordGenerator.forTesting(
        Random(bits),
      ).generate(options: options);
      final alphabets = [
        AccountPasswordGenerator.uppercaseCharacters,
        AccountPasswordGenerator.lowercaseCharacters,
        AccountPasswordGenerator.digitCharacters,
        AccountPasswordGenerator.symbolCharacters,
      ];
      for (var bit = 0; bit < 4; bit++) {
        expect(
          value.split('').any(alphabets[bit].contains),
          bits & (1 << bit) != 0,
        );
      }
    });
  }
  test('invalid configurations reject before generation', () {
    final generator = AccountPasswordGenerator();
    for (final length in [7, 65]) {
      expect(
        () =>
            generator.generate(options: AccountPasswordOptions(length: length)),
        throwsArgumentError,
      );
    }
    expect(
      () => generator.generate(
        options: const AccountPasswordOptions(
          uppercase: false,
          lowercase: false,
          digits: false,
          symbols: false,
        ),
      ),
      throwsArgumentError,
    );
  });
  test(
    'test seam supports deterministic replay without production random fallback',
    () {
      expect(
        AccountPasswordGenerator.forTesting(Random(72)).generate(),
        AccountPasswordGenerator.forTesting(Random(72)).generate(),
      );
      expect(
        AccountPasswordGenerator.symbolCharacters,
        isNot(contains(RegExp('[\\s"\'\x00-\x1f]'))),
      );
    },
  );
}
