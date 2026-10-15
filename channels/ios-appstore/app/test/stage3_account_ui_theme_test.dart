import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_analysis.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_custom_fields_editor.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_duplicate_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stage3_account_ui_test.dart' show host, account, reveal;

void main() {
  for (final family in CardockThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'custom fields ${family.name}/${brightness.name} use theme at 320px 200%',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = AccountCustomFieldsController([
            for (final type in AccountCustomFieldType.values)
              AccountCustomField(
                id: type.name,
                name: 'Field ${type.name}',
                type: type,
                value: '',
                order: type.index,
              ),
          ]);
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            host(
              Theme(
                data: AppTheme.build(family, brightness),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: AccountCustomFieldsEditor(controller: controller),
                  ),
                ),
              ),
              locale: const Locale('en'),
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await reveal(
            tester,
            find.byKey(const ValueKey('move-custom-field-up-4')),
          );
          expect(
            tester
                .getSize(find.byKey(const ValueKey('move-custom-field-up-4')))
                .height,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(
            find.byKey(const ValueKey('move-custom-field-up-4')),
          );
          await tester.pumpAndSettle();
          expect(controller.toFields()[3].type, AccountCustomFieldType.number);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets(
      'duplicate confirmation ${locale.languageCode} is usable at 320px 200%',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAccountDuplicateDialog(
                    context: context,
                    candidates: [
                      AccountDuplicateCandidate(
                        account: account(1),
                        inTrash: false,
                        matchingFields: {'platformName+loginAccount'},
                      ),
                    ],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('duplicate-return-edit')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
}
