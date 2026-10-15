import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/security/offline_password_advisor.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_service.dart';

void main() {
  for (final value in [
    'Abcdef1!' * 4,
    '春夏秋冬山河湖海' * 4,
    ('Q7!mR2#x' * 4).substring(0, 29),
  ]) {
    test(
      'repeated short blocks are not rated strong: ${value.runes.length}',
      () {
        expect(
          OfflinePasswordAdvisor.assess(value).strength,
          NewPasswordStrength.rejected,
        );
      },
    );
  }
  for (final value in [
    'River-Cobalt-Window-74!Safe',
    '山间清风拂过竹林夜空星河映照远方灯火-28!',
    'marble cobalt lantern meadow river valley',
    'aC7!zR2@qP9#tM4%vN8&xK6',
  ]) {
    test(
      'unrelated long and multilingual passphrases remain usable: ${value.runes.length}',
      () {
        expect(OfflinePasswordAdvisor.assess(value).accepted, isTrue);
      },
    );
  }
  test(
    'legacy repeated backup password remains exact and can restore',
    () async {
      final codec = PortableBackupCodec();
      final password = 'Abcdef1!' * 4;
      final bytes = await File(
        'test/fixtures/legacy_repeated_synthetic.json',
      ).readAsBytes();
      final restored = await codec.read(
        bytes: bytes,
        backupMasterPassword: password,
      );
      expect(restored.snapshot.accounts, isEmpty);
    },
  );
  test(
    'backup stream accepts exact 16 MiB boundary without metadata',
    () async {
      final bytes = await readBoundedBackup(
        Stream.fromIterable(List.generate(256, (_) => Uint8List(65536))),
      );
      expect(bytes.length, maximumPortableBackupBytes);
    },
  );
  test('backup stream cancels after first excess chunk', () async {
    var finished = false, afterOverflow = false;
    Stream<List<int>> input() async* {
      try {
        yield Uint8List(maximumPortableBackupBytes);
        yield [1];
        afterOverflow = true;
        yield [2];
      } finally {
        finished = true;
      }
    }

    await expectLater(readBoundedBackup(input()), throwsFormatException);
    expect(finished, isTrue);
    expect(afterOverflow, isFalse);
  });
  test('empty and damaged streams fail without a partial selection', () async {
    await expectLater(
      readBoundedBackup(const Stream.empty()),
      throwsFormatException,
    );
    await expectLater(
      readBoundedBackup(Stream.error(const FormatException('synthetic'))),
      throwsFormatException,
    );
  });
  test('corrupt bounded bytes are rejected by production codec', () async {
    final bytes = await readBoundedBackup(Stream.value([1, 2, 3]));
    await expectLater(
      PortableBackupCodec().read(
        bytes: bytes,
        backupMasterPassword: 'Synthetic-Archive-2026!',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
