import 'dart:math';

/// Options stay in the current editor session. No generated history is stored.
final class AccountPasswordOptions {
  const AccountPasswordOptions({
    this.length = 20,
    this.uppercase = true,
    this.lowercase = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = true,
  });

  final int length;
  final bool uppercase;
  final bool lowercase;
  final bool digits;
  final bool symbols;
  final bool excludeAmbiguous;

  int get categoryCount =>
      [uppercase, lowercase, digits, symbols].where((value) => value).length;

  AccountPasswordOptions copyWith({
    int? length,
    bool? uppercase,
    bool? lowercase,
    bool? digits,
    bool? symbols,
    bool? excludeAmbiguous,
  }) => AccountPasswordOptions(
    length: length ?? this.length,
    uppercase: uppercase ?? this.uppercase,
    lowercase: lowercase ?? this.lowercase,
    digits: digits ?? this.digits,
    symbols: symbols ?? this.symbols,
    excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
  );

  void validate() {
    if (length < 8 || length > 64) {
      throw ArgumentError('密码长度应为 8–64 位');
    }
    if (categoryCount == 0) throw ArgumentError('至少保留一种字符类别');
  }
}

final class AccountPasswordGenerator {
  AccountPasswordGenerator() : _random = Random.secure();

  /// Deterministic seam for tests; production always uses the secure constructor.
  AccountPasswordGenerator.forTesting(Random random) : _random = random;

  final Random _random;
  static const uppercaseCharacters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const lowercaseCharacters = 'abcdefghijklmnopqrstuvwxyz';
  static const digitCharacters = '0123456789';
  static const symbolCharacters = '!@#%^&*()-_=+[]{}:,.?';
  static const ambiguousCharacters = 'Il1O0o';

  String generate({
    AccountPasswordOptions options = const AccountPasswordOptions(),
  }) {
    options.validate();
    String filtered(String input) => options.excludeAmbiguous
        ? input.split('').where((c) => !ambiguousCharacters.contains(c)).join()
        : input;
    final categories = <String>[
      if (options.uppercase) filtered(uppercaseCharacters),
      if (options.lowercase) filtered(lowercaseCharacters),
      if (options.digits) filtered(digitCharacters),
      if (options.symbols) symbolCharacters,
    ];
    final alphabet = categories.join();
    final output = <String>[
      for (final category in categories)
        category[_random.nextInt(category.length)],
    ];
    while (output.length < options.length) {
      // Random.nextInt provides a uniform bounded value, without modulo bias.
      output.add(alphabet[_random.nextInt(alphabet.length)]);
    }
    for (var index = output.length - 1; index > 0; index--) {
      final other = _random.nextInt(index + 1);
      final saved = output[index];
      output[index] = output[other];
      output[other] = saved;
    }
    return output.join();
  }
}
