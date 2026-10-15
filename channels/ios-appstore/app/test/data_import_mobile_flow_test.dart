import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/data_import/presentation/data_migration_center_page.dart';
import 'package:account_subscription_manager/features/data_import/presentation/app_data_import_ui_controller.dart';
import 'package:account_subscription_manager/features/data_import/presentation/data_import_ui_controller.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _masterPassword = 'TEST-ONLY-MOBILE-IMPORT-1234';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('手机伴随文件逐条敏感确认，提交及撤销包含全部字段', () async {
    final harness = await _MobileHarness.create();
    addTearDown(harness.dispose);
    await harness.controller.loadFile(
      fileName: 'accounts.csv',
      bytes: _accountsCsv(),
    );
    await harness.controller.loadCustomFieldFile(
      fileName: 'account_custom_fields.csv',
      bytes: _csv([
        [
          'account_key',
          'field_order',
          'field_name',
          'field_type',
          'field_value',
        ],
        ['account-key-1', '0', '普通字段', 'text', ' value '],
        ['account-key-1', '1', '敏感字段', 'sensitive_text', 'TEST-ONLY-CUSTOM'],
      ]),
    );
    expect(harness.controller.state.customFields.length, 2);
    final sensitive = harness.controller.state.customFields.last;
    expect(sensitive.included, false);
    expect(sensitive.displayValue, '••••••');
    harness.controller.setCustomFieldDecision(
      sensitive.rowNumber,
      include: true,
      replaceExisting: false,
      sensitiveConfirmed: true,
    );
    await _advanceToConfirmation(harness.controller);
    expect(harness.controller.state.errorMessage, isNull);
    harness.controller.setFinalConfirmation(true);
    await harness.controller.commit();
    expect(harness.state.accounts.single.customFields.map((f) => f.value), [
      ' value ',
      'TEST-ONLY-CUSTOM',
    ]);
    expect(harness.controller.state.customFields, isEmpty);
    expect(await harness.state.undoLastBatchImport(), true);
    expect(harness.state.accounts, isEmpty);
  });

  test('手机伴随关联错误明确拒绝且锁定清空决策和原值引用', () async {
    final harness = await _MobileHarness.create();
    addTearDown(harness.dispose);
    await harness.controller.loadFile(
      fileName: 'accounts.csv',
      bytes: _accountsCsv(),
    );
    await harness.controller.loadCustomFieldFile(
      fileName: 'fields.csv',
      bytes: _csv([
        [
          'account_key',
          'field_order',
          'field_name',
          'field_type',
          'field_value',
        ],
        ['missing', '0', 'Field', 'text', 'x'],
      ]),
    );
    expect(harness.controller.state.errorMessage, contains('account_key'));
    expect(harness.state.accounts, isEmpty);
    await harness.controller.loadCustomFieldFile(
      fileName: 'fields.csv',
      bytes: _csv([
        [
          'account_key',
          'field_order',
          'field_name',
          'field_type',
          'field_value',
        ],
        ['account-key-1', '0', 'Field', 'sensitive_text', 'TEST-ONLY-CUSTOM'],
      ]),
    );
    expect(harness.controller.state.customFields.length, 1);
    harness.state.lock();
    expect(harness.controller.state.customFields, isEmpty);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('伴随字段逐项确认 ${locale.languageCode} 320宽200%字体', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _StaticDataImportUiController(
        const DataImportUiState(
          step: DataImportWizardStep.mapping,
          customFields: [
            DataImportCustomFieldView(
              rowNumber: 2,
              accountKey: 'fixture',
              name: 'Sensitive field',
              typeCode: 'sensitive_text',
              sensitive: true,
              included: false,
              replaceExisting: false,
              confirmed: false,
              conflict: true,
              displayValue: '••••••',
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: DataMigrationCenterPage(
            controller: controller,
            ownsController: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(AppLocalizations(locale).translate('我明确确认导入此敏感字段值')),
        findsOneWidget,
      );
    });
  }

  test('后台读取及双文件两个顺序均保留 typed row 选择边界', () async {
    for (final accountsFirst in <bool>[true, false]) {
      final harness = await _MobileHarness.create();
      try {
        final firstName = accountsFirst ? 'accounts.csv' : 'subscriptions.csv';
        final firstBytes = accountsFirst ? _accountsCsv() : _subscriptionsCsv();
        final secondName = accountsFirst ? 'subscriptions.csv' : 'accounts.csv';
        final secondBytes = accountsFirst
            ? _subscriptionsCsv()
            : _accountsCsv();

        final load = harness.controller.loadFile(
          fileName: firstName,
          bytes: firstBytes,
        );
        expect(harness.controller.state.working, isTrue);
        expect(harness.controller.state.parseProgress, isNotNull);
        await load;
        expect(harness.controller.state.working, isFalse);
        expect(harness.controller.state.parseProgress, isNull);

        await harness.controller.appendFile(
          fileName: secondName,
          bytes: secondBytes,
        );
        expect(harness.controller.state.errorMessage, isNull);
        expect(harness.controller.state.fileName, firstName);
        expect(harness.controller.state.additionalFileName, secondName);
        expect(harness.controller.state.step, DataImportWizardStep.mapping);

        final account = harness.controller.state.rows.singleWhere(
          (row) => row.id == 'account-row-2',
        );
        final subscription = harness.controller.state.rows.singleWhere(
          (row) => row.id == 'subscription-row-2',
        );
        expect(account.kind, DataImportRecordKind.account);
        expect(subscription.kind, DataImportRecordKind.subscription);

        harness.controller.setRowSelected(account.id, false);
        expect(
          harness.controller.state.rows
              .singleWhere((row) => row.id == account.id)
              .selected,
          isFalse,
        );
        expect(
          harness.controller.state.rows
              .singleWhere((row) => row.id == subscription.id)
              .selected,
          isTrue,
        );
        harness.controller.setRowSelected(account.id, true);
        expect(harness.controller.state.selectedCount, 2);
      } finally {
        await harness.dispose();
      }
    }
  });

  test('订阅缺少可证明 account_key 时必须显式选择已有账号', () async {
    final harness = await _MobileHarness.create(
      existingAccounts: <AccountDraft>[
        AccountDraft(
          platformName: 'Target Account',
          loginAccount: 'target@example.invalid',
        ),
      ],
    );
    addTearDown(harness.dispose);
    final existingId = harness.state.accounts.single.id;

    await harness.controller.loadFile(
      fileName: 'subscriptions.csv',
      bytes: _subscriptionsCsv(accountKey: ''),
    );
    var row = harness.controller.state.rows.single;
    expect(row.kind, DataImportRecordKind.subscription);
    expect(row.subscriptionTargetRequired, isTrue);
    expect(row.issue, isNotNull);
    expect(row.subscriptionTargetOptions, contains(existingId));

    harness.controller.setSubscriptionAccountTarget(row.id, existingId);
    row = harness.controller.state.rows.single;
    expect(row.selectedSubscriptionTargetId, existingId);
    expect(row.subscriptionTargetRequired, isFalse);
    expect(row.issue, isNull);

    await _advanceToConfirmation(harness.controller);
    expect(harness.controller.state.errorMessage, isNull);
    expect(harness.controller.state.step, DataImportWizardStep.confirmation);
    expect(harness.controller.state.planSummary?.newAccounts, 0);
    expect(harness.controller.state.planSummary?.formalSubscriptions, 1);
    expect(harness.controller.state.planSummary?.pendingSubscriptionDrafts, 0);
  });

  test('双文件计划把正式订阅与待完善草稿分流并原子提交统计', () async {
    final harness = await _MobileHarness.create();
    addTearDown(harness.dispose);

    await harness.controller.loadFile(
      fileName: 'accounts.csv',
      bytes: _accountsCsv(platformName: 'alibabagroup.com'),
    );
    await harness.controller.appendFile(
      fileName: 'subscriptions.csv',
      bytes: _subscriptionsCsv(includePending: true),
    );

    var accountRow = harness.controller.state.rows.singleWhere(
      (row) => row.kind == DataImportRecordKind.account,
    );
    expect(
      accountRow.brandSuggestionOptions,
      hasLength(greaterThanOrEqualTo(2)),
    );
    final selectedBrand = accountRow.brandSuggestionOptions.keys.first;
    harness.controller.selectBrandSuggestion(accountRow.id, selectedBrand);
    accountRow = harness.controller.state.rows.singleWhere(
      (row) => row.kind == DataImportRecordKind.account,
    );
    expect(accountRow.selectedBrandSuggestionId, selectedBrand);

    await _advanceToConfirmation(harness.controller);
    final plan = harness.controller.state.planSummary;
    expect(harness.controller.state.step, DataImportWizardStep.confirmation);
    expect(plan?.newAccounts, 1);
    expect(plan?.updatedAccounts, 0);
    expect(plan?.formalSubscriptions, 1);
    expect(plan?.pendingSubscriptionDrafts, 1);
    expect(plan?.unsupportedItems, 0);
    expect(plan?.quotaAllowed, isTrue);

    harness.controller.setFinalConfirmation(true);
    await harness.controller.commit();
    final summary = harness.controller.state.commitSummary;
    expect(harness.controller.state.step, DataImportWizardStep.result);
    expect(summary?.importedAccounts, 1);
    expect(summary?.formalSubscriptions, 1);
    expect(summary?.pendingSubscriptionDrafts, 1);
    expect(summary?.rollbackAvailable, isTrue);
    expect(harness.state.accounts, hasLength(1));
    expect(harness.state.subscriptions, hasLength(1));
    expect(harness.state.pendingSubscriptionDrafts, hasLength(1));
  });

  test('masked 逐行确认、多个已有目标及 fieldByField 都必须显式解决', () async {
    final harness = await _MobileHarness.create(
      existingAccounts: <AccountDraft>[
        AccountDraft(
          platformName: 'Fictitious Duplicate',
          loginAccount: 'duplicate@example.invalid',
          boundEmail: 'duplicate@example.invalid',
          password: 'TEST-ONLY-OLD-A',
          website: 'https://a.example.invalid',
          notes: 'existing-a',
        ),
        AccountDraft(
          platformName: 'Fictitious Duplicate',
          loginAccount: 'duplicate@example.invalid',
          boundEmail: 'duplicate@example.invalid',
          password: 'TEST-ONLY-OLD-B',
          website: 'https://b.example.invalid',
          notes: 'existing-b',
        ),
      ],
    );
    addTearDown(harness.dispose);

    await harness.controller.loadFile(
      fileName: 'accounts.csv',
      bytes: _accountsCsv(
        platformName: 'Fictitious Duplicate',
        loginAccount: 'duplicate@example.invalid',
        password: '********',
        url: 'https://import.example.invalid',
        notes: 'imported-note',
      ),
    );
    await harness.controller.next();
    await harness.controller.next();
    var row = harness.controller.state.rows.single;
    expect(harness.controller.state.step, DataImportWizardStep.passwordPreview);
    expect(row.passwordStatus, DataImportPasswordStatus.maskedReviewRequired);
    expect(row.maskedPasswordConfirmed, isFalse);
    expect(harness.controller.state.fieldSuggestions, isNotEmpty);

    harness.controller.setMaskedPasswordConfirmed(row.id, true);
    harness.controller.acceptAllFieldSuggestions();
    row = harness.controller.state.rows.single;
    expect(row.maskedPasswordConfirmed, isTrue);
    expect(row.passwordStatus, DataImportPasswordStatus.encryptedForImport);
    expect(
      harness.controller.state.fieldSuggestions.every((item) => item.accepted),
      isTrue,
    );

    await harness.controller.next();
    row = harness.controller.state.rows.single;
    expect(harness.controller.state.step, DataImportWizardStep.duplicates);
    expect(row.duplicateTargetOptions, hasLength(2));
    expect(row.duplicateDescription, isNotNull);

    harness.controller.setDuplicateResolution(
      row.id,
      DataImportDuplicateResolution.fieldByField,
    );
    harness.controller.setDuplicateUpdateTarget(
      row.id,
      harness.state.accounts.last.id,
    );
    row = harness.controller.state.rows.single;
    expect(row.selectedDuplicateTargetId, harness.state.accounts.last.id);
    expect(row.conflictingFields, isNotEmpty);
    expect(
      row.fieldComparisons.keys,
      containsAll(<String>[
        'platformName',
        'loginAccount',
        'phone',
        'email',
        'url',
        'notes',
        'password',
      ]),
    );
    expect(
      row.fieldComparisons['url']?.existingValue,
      'https://b.example.invalid',
    );
    expect(
      row.fieldComparisons['url']?.importedValue,
      'https://import.example.invalid',
    );
    expect(row.fieldComparisons['notes']?.existingValue, 'existing-b');
    expect(row.fieldComparisons['notes']?.importedValue, 'imported-note');
    expect(
      row.fieldComparisons['password']?.passwordComparison,
      DataImportPasswordComparison.different,
    );
    expect(row.fieldComparisons['password']?.existingValue, isEmpty);
    expect(row.fieldComparisons['password']?.importedValue, isEmpty);
    expect(row.fieldChoices['url'], isFalse);
    expect(row.fieldChoices['notes'], isFalse);
    expect(
      row.fieldChoices['password'],
      isNull,
      reason: '密码不同仍需逐条明确确认，不能被默认或批量覆盖。',
    );
    for (final field in row.conflictingFields) {
      harness.controller.setDuplicateFieldChoice(row.id, field, false);
    }

    await harness.controller.next();
    expect(harness.controller.state.errorMessage, isNull);
    expect(harness.controller.state.step, DataImportWizardStep.confirmation);
    expect(harness.controller.state.planSummary?.newAccounts, 0);
    expect(harness.controller.state.planSummary?.updatedAccounts, 1);
  });

  test('手机逐字段对现有空值默认保留，密码为空也必须逐条显式选择才写入', () async {
    final harness = await _MobileHarness.create(
      existingAccounts: <AccountDraft>[
        AccountDraft(
          platformName: 'Fictitious Empty Existing',
          loginAccount: 'same@example.invalid',
        ),
      ],
    );
    addTearDown(harness.dispose);

    await harness.controller.loadFile(
      fileName: 'accounts.csv',
      bytes: _accountsCsv(
        platformName: 'Fictitious Empty Existing',
        loginAccount: 'same@example.invalid',
        phone: '13800000000',
        email: 'new@example.invalid',
        password: 'TEST-ONLY-EXPLICIT-PASSWORD',
        url: 'https://new.example.invalid',
        notes: 'new note',
      ),
    );
    await harness.controller.next();
    await harness.controller.next();
    await harness.controller.next();
    var row = harness.controller.state.rows.single;
    expect(harness.controller.state.step, DataImportWizardStep.duplicates);

    harness.controller.setDuplicateResolution(
      row.id,
      DataImportDuplicateResolution.fieldByField,
    );
    row = harness.controller.state.rows.single;
    expect(
      row.conflictingFields,
      containsAll(<String>['phone', 'email', 'url', 'notes', 'password']),
    );
    for (final field in <String>['phone', 'email', 'url', 'notes']) {
      expect(row.fieldChoices[field], isFalse, reason: '$field 的现有空值也必须默认保留。');
    }
    expect(
      row.fieldComparisons['password']?.passwordComparison,
      DataImportPasswordComparison.existingEmpty,
    );
    expect(row.fieldChoices['password'], isNull, reason: '现有密码为空仍不得自动采用导入密码。');

    harness.controller.setDuplicateFieldChoice(row.id, 'password', true);
    row = harness.controller.state.rows.single;
    expect(row.fieldChoices['password'], isTrue);
    await harness.controller.next();
    expect(harness.controller.state.step, DataImportWizardStep.confirmation);
    harness.controller.setFinalConfirmation(true);
    await harness.controller.commit();

    final saved = harness.state.accounts.single;
    expect(saved.boundPhone, isNull);
    expect(saved.boundEmail, isNull);
    expect(saved.website, isNull);
    expect(saved.notes, isNull);
    expect(saved.password, 'TEST-ONLY-EXPLICIT-PASSWORD');
  });

  test('clear 与锁定都会把文件、预览、计划和敏感状态归零', () async {
    final harness = await _MobileHarness.create();
    addTearDown(harness.dispose);

    await harness.controller.loadFile(
      fileName: 'accounts.csv',
      bytes: _accountsCsv(password: 'TEST-ONLY-CLEAR-ME'),
    );
    expect(harness.controller.state.rows, isNotEmpty);
    harness.controller.clearSensitiveMemory();
    _expectZeroSensitiveState(harness.controller.state, canWrite: true);

    await harness.controller.loadFile(
      fileName: 'accounts.csv',
      bytes: _accountsCsv(password: 'TEST-ONLY-LOCK-ME'),
    );
    expect(harness.controller.state.rows, isNotEmpty);
    harness.state.lock();
    _expectZeroSensitiveState(harness.controller.state, canWrite: false);
    expect(harness.controller.state.errorMessage, isNotNull);
  });

  testWidgets('逐字段新旧值三语在320x640与200%字体下可滚动且密码不显示明文', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _StaticDataImportUiController(
      DataImportUiState(
        step: DataImportWizardStep.duplicates,
        fileName: 'accounts.csv',
        fileSize: 512,
        detectedFormat: 'Cardock 账号模板',
        rows: <DataImportPreviewRow>[
          DataImportPreviewRow(
            id: 'account:2',
            kind: DataImportRecordKind.account,
            title: 'Fictitious Compare',
            subtitle: 'compare@example.invalid',
            passwordStatus: DataImportPasswordStatus.encryptedForImport,
            duplicateDescription: '疑似重复',
            duplicateResolution: DataImportDuplicateResolution.fieldByField,
            conflictingFields: const <String>{
              'platformName',
              'loginAccount',
              'phone',
              'email',
              'url',
              'notes',
              'password',
            },
            fieldChoices: const <String, bool>{
              'platformName': false,
              'loginAccount': false,
              'phone': false,
              'email': false,
              'url': false,
              'notes': false,
            },
            fieldComparisons: const <String, DataImportFieldComparison>{
              'platformName': DataImportFieldComparison(
                fieldName: 'platformName',
                existingValue: 'Fictitious Existing',
                importedValue: 'Fictitious Compare',
              ),
              'loginAccount': DataImportFieldComparison(
                fieldName: 'loginAccount',
                existingValue: 'old-login@example.invalid',
                importedValue: 'compare@example.invalid',
              ),
              'phone': DataImportFieldComparison(
                fieldName: 'phone',
                existingValue: '+10000000001',
                importedValue: '+10000000002',
              ),
              'email': DataImportFieldComparison(
                fieldName: 'email',
                existingValue: 'old@example.invalid',
                importedValue: 'new@example.invalid',
              ),
              'url': DataImportFieldComparison(
                fieldName: 'url',
                existingValue: 'https://old.example.invalid',
                importedValue: 'https://new.example.invalid',
              ),
              'notes': DataImportFieldComparison(
                fieldName: 'notes',
                existingValue: 'existing note that remains private',
                importedValue: 'imported note shown for comparison',
              ),
              'password': DataImportFieldComparison(
                fieldName: 'password',
                passwordComparison: DataImportPasswordComparison.different,
              ),
            },
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: DataMigrationCenterPage(
            controller: controller,
            ownsController: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final l10n = AppLocalizations(locale);
      expect(
        find.text(l10n.translate('Cardock 现有内容')),
        findsNWidgets(6),
        reason: locale.toString(),
      );
      expect(
        find.text(l10n.translate('本次导入内容')),
        findsNWidgets(6),
        reason: locale.toString(),
      );
      expect(
        find.text(l10n.translate('不同')),
        findsOneWidget,
        reason: locale.toString(),
      );
      expect(find.text('TEST-ONLY-EXISTING-PASSWORD'), findsNothing);
      expect(find.text('TEST-ONLY-IMPORTED-PASSWORD'), findsNothing);
      expect(tester.takeException(), isNull, reason: locale.toString());
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: locale.toString());
    }
  });

  testWidgets('文件步骤三语文案与 FilePicker 五类扩展保持一致', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    FilePicker? originalPicker;
    try {
      originalPicker = FilePicker.platform;
    } on Object {
      originalPicker = null;
    }
    final picker = _RecordingFilePicker();
    FilePicker.platform = picker;
    addTearDown(() {
      if (originalPicker != null) {
        FilePicker.platform = originalPicker;
      } else {
        FilePickerIO.registerWith();
      }
    });

    final controller = _StaticDataImportUiController(
      const DataImportUiState(step: DataImportWizardStep.file),
    );
    addTearDown(controller.dispose);
    const supportCopy =
        '支持单个 XLSX、DOCX、CSV、TSV 或 TXT 文件，最大 10 MiB。XLSX 读取首个工作表，DOCX 读取首个表格；文件只在本次内存流程中处理。';
    const warningCopy =
        'XLSX、DOCX、CSV、TSV 或 TXT 文件可能包含明文密码。请仅在可信设备操作，不要发送到聊天或公共网盘。解析只在本次内存中进行；导入与加密备份核对后，请自行处理源文件。备份仅保护已导入的记录，不会保护或删除外部 CSV 及其他副本。';
    const expectedExtensions = <String>['xlsx', 'docx', 'csv', 'tsv', 'txt'];

    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: DataMigrationCenterPage(
            controller: controller,
            ownsController: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations(locale);
      final localizedSupport = l10n.translate(supportCopy);
      expect(
        find.text(localizedSupport),
        findsOneWidget,
        reason: locale.toString(),
      );
      for (final extension in expectedExtensions) {
        expect(localizedSupport, contains(extension.toUpperCase()));
      }

      final pickerButton = find.byKey(
        const ValueKey<String>('data-import-file-picker'),
      );
      await tester.ensureVisible(pickerButton);
      await tester.tap(pickerButton);
      await tester.pumpAndSettle();
      final localizedWarning = l10n.translate(warningCopy);
      expect(
        find.text(localizedWarning),
        findsOneWidget,
        reason: locale.toString(),
      );
      for (final extension in expectedExtensions) {
        expect(localizedWarning, contains(extension.toUpperCase()));
      }
      await tester.tap(find.text(l10n.translate('继续选择文件')));
      await tester.pumpAndSettle();
    }

    expect(picker.callCount, AppLocalizations.supportedLocales.length);
    expect(picker.type, FileType.custom);
    expect(picker.allowedExtensions, expectedExtensions);
    expect(picker.allowMultiple, isFalse);
    expect(picker.withData, isTrue);
  });

  testWidgets('文件步骤在解析前拦截加密备份与 ICS 并清零所选字节', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final cases = <({String name, Uint8List bytes, String message})>[
      (
        name: 'backup.asmbackup',
        bytes: Uint8List.fromList(
          utf8.encode('{"magic":"ASM_PORTABLE_BACKUP","formatVersion":2}'),
        ),
        message: '这是 Cardock 加密备份。请返回设置并使用“恢复 Cardock 加密备份”；此处只导入外部表格或文档。',
      ),
      (
        name: 'Cardock-calendar.ics',
        bytes: Uint8List.fromList(
          utf8.encode('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR'),
        ),
        message: '这是日历 .ics 文件，只包含日历事件，不是账号与订阅备份，不能在这里恢复。',
      ),
    ];

    for (final testCase in cases) {
      final controller = _StaticDataImportUiController(
        const DataImportUiState(step: DataImportWizardStep.file),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: DataMigrationCenterPage(
            controller: controller,
            ownsController: false,
            documentPicker: () async =>
                (name: testCase.name, bytes: testCase.bytes),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('data-import-file-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续选择文件'));
      await tester.pumpAndSettle();

      expect(find.text(testCase.message), findsOneWidget);
      expect(controller.loadFileCallCount, 0);
      expect(controller.state.fileName, isNull);
      expect(testCase.bytes.every((value) => value == 0), isTrue);
      expect(controller.nextCallCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('有效文件读取后留在第二步并明确提示核对字段', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final selectedBytes = Uint8List.fromList(
      utf8.encode('platform,login\nExample,user@example.invalid'),
    );
    final controller = _StaticDataImportUiController(
      const DataImportUiState(step: DataImportWizardStep.file),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DataMigrationCenterPage(
          controller: controller,
          ownsController: false,
          documentPicker: () async =>
              (name: 'accounts.csv', bytes: selectedBytes),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('data-import-file-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续选择文件'));
    await tester.pumpAndSettle();

    expect(controller.loadFileCallCount, 1);
    expect(controller.nextCallCount, 0);
    expect(controller.state.step, DataImportWizardStep.file);
    expect(controller.state.fileName, 'accounts.csv');
    expect(find.text('文件已读取；可追加配套表，或点击“下一步”核对字段。'), findsWidgets);
    expect(find.text('下一步：核对字段'), findsOneWidget);
    expect(selectedBytes.every((value) => value == 0), isTrue);

    final next = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('data-import-next')),
    );
    expect(next.onPressed, isNotNull);
    next.onPressed!();
    await tester.pump();
    expect(controller.nextCallCount, 1);
  });

  testWidgets('控制器静默取消时不误报文件已读取', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final selectedBytes = Uint8List.fromList(
      utf8.encode('platform,login\nExample,user@example.invalid'),
    );
    final controller = _StaticDataImportUiController(
      const DataImportUiState(step: DataImportWizardStep.file),
      loadFileSucceeds: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DataMigrationCenterPage(
          controller: controller,
          ownsController: false,
          documentPicker: () async =>
              (name: 'cancelled.csv', bytes: selectedBytes),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('data-import-file-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续选择文件'));
    await tester.pumpAndSettle();

    expect(controller.loadFileCallCount, 1);
    expect(controller.state.fileName, isNull);
    expect(find.textContaining('文件已读取'), findsNothing);
    expect(selectedBytes.every((value) => value == 0), isTrue);
  });

  testWidgets('系统文件选择器失活期间保留首表并可追加配套表', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final selectedBytes = Uint8List.fromList(
      utf8.encode('name,amount\nPlan,10'),
    );
    final picker = Completer<({String name, Uint8List bytes})?>();
    final controller = _StaticDataImportUiController(
      const DataImportUiState(
        step: DataImportWizardStep.file,
        fileName: 'accounts.csv',
        fileSize: 24,
        detectedFormat: 'CSV',
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DataMigrationCenterPage(
          controller: controller,
          ownsController: false,
          documentPicker: () => picker.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final append = find.byKey(
      const ValueKey<String>('data-import-append-file-picker'),
    );
    await tester.tap(append);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续选择文件'));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(controller.clearSensitiveMemoryCallCount, 0);
    expect(controller.state.fileName, 'accounts.csv');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    picker.complete((name: 'subscriptions.csv', bytes: selectedBytes));
    await tester.pumpAndSettle();

    expect(controller.appendFileCallCount, 1);
    expect(controller.state.fileName, 'accounts.csv');
    expect(controller.state.additionalFileName, 'subscriptions.csv');
    expect(controller.clearSensitiveMemoryCallCount, 0);
    expect(find.text('配套文件已读取；请点击“下一步”核对字段。'), findsOneWidget);
    expect(selectedBytes.every((value) => value == 0), isTrue);
  });
}

Future<void> _advanceToConfirmation(DataImportUiController controller) async {
  while (controller.state.step.index <
          DataImportWizardStep.confirmation.index &&
      controller.state.errorMessage == null) {
    await controller.next();
  }
}

void _expectZeroSensitiveState(
  DataImportUiState state, {
  required bool canWrite,
}) {
  expect(state.canWrite, canWrite);
  expect(state.fileName, isNull);
  expect(state.fileSize, 0);
  expect(state.additionalFileName, isNull);
  expect(state.additionalFileSize, 0);
  expect(state.detectedFormat, isNull);
  expect(state.mappings, isEmpty);
  expect(state.rows, isEmpty);
  expect(state.fieldSuggestions, isEmpty);
  expect(state.customFields, isEmpty);
  expect(state.planSummary, isNull);
  expect(state.commitSummary, isNull);
  expect(state.finalConfirmation, isFalse);
  expect(state.working, isFalse);
  expect(state.parseProgress, isNull);
}

Uint8List _accountsCsv({
  String accountKey = 'account-key-1',
  String platformName = 'Fictitious Service',
  String loginAccount = 'user@example.invalid',
  String phone = '',
  String email = '',
  String password = 'TEST-ONLY-PASSWORD',
  String url = 'https://service.example.invalid',
  String notes = 'safe-note',
}) => _csv(<List<String>>[
  <String>[
    'account_key',
    'platform_name',
    'login_account',
    'phone',
    'email',
    'password',
    'url',
    'notes',
  ],
  <String>[
    accountKey,
    platformName,
    loginAccount,
    phone,
    email,
    password,
    url,
    notes,
  ],
]);

Uint8List _subscriptionsCsv({
  String accountKey = 'account-key-1',
  bool includePending = false,
}) => _csv(<List<String>>[
  <String>[
    'account_key',
    'plan_name',
    'amount',
    'currency',
    'billing_cycle',
    'subscription_start_date',
    'next_renewal_date',
    'auto_renew',
    'payment_method',
    'reminder_days',
    'notes',
  ],
  <String>[
    accountKey,
    'Fictitious Pro',
    '12.50',
    'USD',
    'monthly',
    '2026-08-30',
    '2026-09-30',
    'true',
    'Test Card',
    '3',
    'formal-note',
  ],
  if (includePending)
    <String>[
      accountKey,
      'Needs Review',
      '',
      'USD',
      'custom',
      '',
      '2026-10-30',
      'false',
      'Test Card',
      '5',
      'pending-note',
    ],
]);

Uint8List _csv(List<List<String>> rows) => Uint8List.fromList(
  utf8.encode(rows.map((row) => row.join(',')).join('\n')),
);

final class _MobileHarness {
  _MobileHarness(this.directory, this.state, this.controller);

  final Directory directory;
  final AppState state;
  final AppDataImportUiController controller;

  static Future<_MobileHarness> create({
    List<AccountDraft> existingAccounts = const <AccountDraft>[],
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-mobile-import-flow-',
    );
    final state = AppState(
      vaultStore: EncryptedVaultStore(
        directoryProvider: () async => directory,
        creationKdf: _testKdf,
      ),
    );
    await state.initialize();
    expect(await state.createVault(_masterPassword), VaultActionResult.success);
    for (final draft in existingAccounts) {
      expect(
        (await state.createAccount(
          draft,
          duplicateApprovedRevision: state.localWebRevision,
        )).saved,
        isTrue,
      );
    }
    final controller = AppDataImportUiController(appState: state);
    return _MobileHarness(directory, state, controller);
  }

  Future<void> dispose() async {
    controller.dispose();
    state.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

final class _StaticDataImportUiController extends DataImportUiController {
  _StaticDataImportUiController(this._state, {this.loadFileSucceeds = true});

  DataImportUiState _state;
  final bool loadFileSucceeds;
  int loadFileCallCount = 0;
  int appendFileCallCount = 0;
  int nextCallCount = 0;
  int clearSensitiveMemoryCallCount = 0;

  @override
  DataImportUiState get state => _state;

  @override
  List<DataImportSourceOption> get sources => const <DataImportSourceOption>[];

  @override
  void acceptAllFieldSuggestions() {}

  @override
  void acceptFieldSuggestion(String suggestionId) {}

  @override
  void back() {}

  @override
  void cancelParsing() {}

  @override
  void clearSensitiveMemory() {
    clearSensitiveMemoryCallCount += 1;
  }

  @override
  Future<void> commit() async {}

  @override
  void ignoreAllFieldSuggestions() {}

  @override
  void ignoreBrandSuggestions(String rowId) {}

  @override
  Future<bool> loadFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    loadFileCallCount += 1;
    if (!loadFileSucceeds) return false;
    _state = DataImportUiState(
      step: DataImportWizardStep.file,
      fileName: fileName,
      fileSize: bytes.length,
      detectedFormat: 'CSV',
    );
    notifyListeners();
    return true;
  }

  @override
  Future<bool> appendFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    appendFileCallCount += 1;
    _state = DataImportUiState(
      step: DataImportWizardStep.file,
      fileName: _state.fileName,
      fileSize: _state.fileSize,
      additionalFileName: fileName,
      additionalFileSize: bytes.length,
      detectedFormat: _state.detectedFormat,
    );
    notifyListeners();
    return true;
  }

  @override
  Future<void> next() async {
    nextCallCount += 1;
  }

  @override
  void removeRow(String rowId) {}

  @override
  void selectBrandSuggestion(String rowId, String brandId) {}

  @override
  Future<void> selectSource(String sourceId) async {}

  @override
  void setDuplicateFieldChoice(
    String rowId,
    String fieldName,
    bool useImportedValue,
  ) {}

  @override
  void setDuplicateResolution(
    String rowId,
    DataImportDuplicateResolution resolution,
  ) {}

  @override
  void setDuplicateUpdateTarget(String rowId, String existingAccountId) {}

  @override
  void setFinalConfirmation(bool confirmed) {}

  @override
  void setMaskedPasswordConfirmed(String rowId, bool confirmed) {}

  @override
  void setRowSelected(String rowId, bool selected) {}

  @override
  Future<void> updateMapping({
    required int columnIndex,
    required String? targetField,
  }) async {}
}

final class _RecordingFilePicker extends FilePicker {
  int callCount = 0;
  FileType? type;
  List<String>? allowedExtensions;
  bool? allowMultiple;
  bool? withData;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    callCount += 1;
    this.type = type;
    this.allowedExtensions = allowedExtensions == null
        ? null
        : List<String>.unmodifiable(allowedExtensions);
    this.allowMultiple = allowMultiple;
    this.withData = withData;
    return null;
  }
}
