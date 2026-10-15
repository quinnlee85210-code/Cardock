import 'dart:typed_data';

import 'package:account_subscription_manager/core/notifications/notification_reconciliation_state.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationReconciliationCodec', () {
    late SecretKeyData key;
    late Uint8List vaultId;
    late NotificationReconciliationCodec codec;

    setUp(() {
      key = SecretKeyData.random(length: 32);
      vaultId = Uint8List.fromList(List<int>.generate(16, (index) => index));
      codec = NotificationReconciliationCodec();
    });

    tearDown(() {
      key.destroy();
      vaultId.fillRange(0, vaultId.length, 0);
    });

    test('pending state round-trips without business content', () async {
      final state = NotificationReconciliationState(
        operationId: 'operation-0123456789abcdef',
        targetGeneration: 42,
        stateRevision: 7,
        createdAtUtc: DateTime.utc(2026, 8, 30, 12),
        attemptCount: 2,
        lastAttemptAtUtc: DateTime.utc(2026, 8, 30, 12, 1),
      );

      final encoded = await codec.encodePending(
        state: state,
        dataKey: key,
        vaultInstanceId: vaultId,
      );
      final decoded = await codec.decode(
        encoded: encoded,
        dataKey: key,
        vaultInstanceId: vaultId,
      );

      expect(decoded.pending?.operationId, state.operationId);
      expect(decoded.pending?.targetGeneration, 42);
      expect(decoded.pending?.stateRevision, 7);
      expect(decoded.pending?.attemptCount, 2);
      expect(decoded.pending?.createdAtUtc, DateTime.utc(2026, 8, 30, 12));
      expect(
        decoded.pending?.lastAttemptAtUtc,
        DateTime.utc(2026, 8, 30, 12, 1),
      );
      expect(String.fromCharCodes(encoded), isNot(contains('operation-')));
      expect(String.fromCharCodes(encoded), isNot(contains('subscription')));
    });

    test(
      'cleared tombstone prevents an older pending item resurfacing',
      () async {
        final encoded = await codec.encodeCleared(
          stateRevision: 8,
          dataKey: key,
          vaultInstanceId: vaultId,
        );
        final decoded = await codec.decode(
          encoded: encoded,
          dataKey: key,
          vaultInstanceId: vaultId,
        );

        expect(decoded.pending, isNull);
        expect(decoded.clearedStateRevision, 8);
      },
    );

    test('tamper and cross-vault copy are rejected', () async {
      final encoded = await codec.encodePending(
        state: NotificationReconciliationState(
          operationId: 'operation-0123456789abcdef',
          targetGeneration: 2,
          stateRevision: 1,
          createdAtUtc: DateTime.utc(2026, 8, 30),
          attemptCount: 0,
        ),
        dataKey: key,
        vaultInstanceId: vaultId,
      );
      final tampered = Uint8List.fromList(encoded);
      tampered[tampered.length - 8] ^= 1;
      final otherVault = Uint8List.fromList(
        List<int>.generate(16, (index) => index + 1),
      );

      await expectLater(
        codec.decode(encoded: tampered, dataKey: key, vaultInstanceId: vaultId),
        throwsA(isA<NotificationReconciliationFormatException>()),
      );
      await expectLater(
        codec.decode(
          encoded: encoded,
          dataKey: key,
          vaultInstanceId: otherVault,
        ),
        throwsA(isA<NotificationReconciliationFormatException>()),
      );
      otherVault.fillRange(0, otherVault.length, 0);
    });
  });
}
