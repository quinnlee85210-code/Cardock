import 'dart:async';
import 'dart:typed_data';
import 'package:account_subscription_manager/app/app_state.dart';

import 'package:account_subscription_manager/features/data_import/presentation/app_data_import_ui_controller.dart';
import 'package:account_subscription_manager/features/data_import/presentation/data_migration_center_hub_page.dart';
import 'package:account_subscription_manager/features/data_import/presentation/data_migration_center_page.dart';
import 'package:account_subscription_manager/features/data_import/presentation/data_import_ui_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_vault_store.dart';

void main() {
  testWidgets(
    'import route rebuild preserves its controller and selected step',
    (tester) async {
      final state = AppState(
        vaultStore: FakeVaultStore(
          configured: true,
          acceptedPassword: 'TEST-ONLY-MASTER-1234',
        ),
      );
      addTearDown(state.dispose);
      await state.initialize();
      expect(
        await state.unlock('TEST-ONLY-MASTER-1234'),
        VaultActionResult.success,
      );
      var creations = 0;
      var pickerResult = Completer<({String name, Uint8List bytes})?>();
      await tester.pumpWidget(
        MaterialApp(
          home: DataMigrationCenterHubPage(
            appState: state,
            documentPicker: () => pickerResult.future,
            controllerFactory: () {
              creations++;
              return AppDataImportUiController(appState: state);
            },
            onOpenComputerBatch: null,
            onUndoLastBatch: () async {},
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('start-data-import-wizard')));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<DataMigrationCenterPage>(find.byType(DataMigrationCenterPage))
          .controller;
      controller.next();
      await tester.pumpAndSettle();
      expect(controller.state.step, DataImportWizardStep.file);
      final route = ModalRoute.of(
        tester.element(find.byType(DataMigrationCenterPage)),
      )!;
      route.changedExternalState();
      await tester.pumpAndSettle();
      expect(creations, 1);
      expect(
        tester
            .widget<DataMigrationCenterPage>(
              find.byType(DataMigrationCenterPage),
            )
            .controller,
        same(controller),
      );
      expect(controller.state.step, DataImportWizardStep.file);
      final page = tester.widget<DataMigrationCenterPage>(
        find.byType(DataMigrationCenterPage),
      );
      final picking = page.documentPicker();
      expect(state.externalInteractionInProgress, isTrue);
      pickerResult.complete(null);
      expect(await picking, isNull);
      expect(state.externalInteractionInProgress, isFalse);
      pickerResult = Completer<({String name, Uint8List bytes})?>();
      final failed = page.documentPicker();
      expect(state.externalInteractionInProgress, isTrue);
      pickerResult.completeError(StateError('test-only picker failure'));
      await expectLater(failed, throwsStateError);
      expect(state.externalInteractionInProgress, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
