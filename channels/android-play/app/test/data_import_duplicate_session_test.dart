import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

TabularDocument _document(List<List<String>> rows) =>
    const TabularImportParser().parse(
      _bytes(rows.map((row) => row.join(',')).join('\n')),
    );

List<String> get _accountHeaders => <String>[
  'account_key',
  'platform_name',
  'login_account',
  'phone',
  'email',
  'password',
  'url',
  'notes',
];

List<String> get _subscriptionHeaders => <String>[
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
];

AccountImportDraft _draft(
  int row, {
  String platformName = 'Fake Service',
  String loginAccount = 'fake-user',
  String email = '',
  String phone = '',
  String password = '',
  String url = 'https://example.invalid/path',
  String notes = '',
}) => AccountImportDraft(
  originalRowNumber: row,
  sourceId: 'fixture|row:$row',
  adapterId: 'fixture',
  platformName: platformName,
  loginAccount: loginAccount,
  email: email,
  phone: phone,
  password: password,
  url: url,
  notes: notes,
);

void main() {
  const detector = ImportDuplicateDetector();

  test('同键保存所有 existing 候选且文件内三重重复不丢候选', () {
    final existing = <ExistingAccountSummary>[
      const ExistingAccountSummary(
        id: 'existing-1',
        platformName: 'Fake Service',
        loginAccount: 'fake-user',
        url: 'https://example.invalid/a',
      ),
      const ExistingAccountSummary(
        id: 'existing-2',
        platformName: 'Fake Service',
        loginAccount: 'fake-user',
        url: 'https://example.invalid/b',
      ),
    ];
    final existingMatches = detector.detect(
      imported: <AccountImportDraft>[_draft(2)],
      existing: existing,
    );
    final internalMatches = detector.detect(
      imported: <AccountImportDraft>[_draft(2), _draft(3), _draft(4)],
      existing: const <ExistingAccountSummary>[],
    );

    expect(existingMatches, hasLength(2));
    expect(
      existingMatches.map((candidate) => candidate.existingAccountId).toSet(),
      <String>{'existing-1', 'existing-2'},
    );
    expect(internalMatches, hasLength(3));
    expect(
      internalMatches.where((candidate) => candidate.importRowNumber == 4),
      hasLength(2),
    );
  });

  test('导入非空值即使现有为空也进入逐字段决议，导入为空不产生写入决议', () {
    final emptyExistingCandidate = detector
        .detect(
          imported: <AccountImportDraft>[
            _draft(
              2,
              email: 'new@example.invalid',
              phone: '13800000000',
              password: 'TEST-ONLY-NEW-PASSWORD',
              url: 'https://example.invalid/new',
              notes: 'new note',
            ),
          ],
          existing: const <ExistingAccountSummary>[
            ExistingAccountSummary(
              id: 'existing-empty',
              platformName: 'Fake Service',
              loginAccount: 'fake-user',
            ),
          ],
        )
        .single;

    expect(
      emptyExistingCandidate.conflictingFields,
      containsAll(<String>['email', 'phone', 'password', 'url', 'notes']),
    );
    expect(
      emptyExistingCandidate.passwordComparison,
      ImportPasswordComparison.existingEmpty,
    );

    final changedIdentityCandidate = detector
        .detect(
          imported: <AccountImportDraft>[
            _draft(
              3,
              platformName: 'Imported Service',
              loginAccount: 'imported-user',
              email: 'anchor@example.invalid',
              url: 'https://example.invalid/new',
            ),
          ],
          existing: const <ExistingAccountSummary>[
            ExistingAccountSummary(
              id: 'existing-identity',
              platformName: 'Existing Service',
              loginAccount: 'existing-user',
              email: 'anchor@example.invalid',
              url: 'https://example.invalid/old',
              password: 'TEST-ONLY-EXISTING-PASSWORD',
              notes: 'existing note',
            ),
          ],
        )
        .single;

    expect(
      changedIdentityCandidate.conflictingFields,
      containsAll(<String>['platformName', 'loginAccount', 'url']),
    );
    expect(
      changedIdentityCandidate.conflictingFields,
      isNot(contains('password')),
      reason: '导入为空没有可写值，不应制造覆盖决议。',
    );
    expect(
      changedIdentityCandidate.conflictingFields,
      isNot(contains('notes')),
    );
  });

  test('重复置信度保守分级，URL/密码/备注冲突只输出状态', () {
    const existing = ExistingAccountSummary(
      id: 'existing-1',
      platformName: 'Fake Service',
      loginAccount: 'CaseUser',
      password: 'fake-old-password',
      url: 'https://example.invalid/old',
      notes: 'old note',
    );
    final high = detector
        .detect(
          imported: <AccountImportDraft>[
            _draft(
              2,
              loginAccount: 'CaseUser',
              password: 'fake-new-password',
              url: 'https://example.invalid/new',
              notes: 'new note',
            ),
          ],
          existing: const <ExistingAccountSummary>[existing],
        )
        .single;
    final medium = detector
        .detect(
          imported: <AccountImportDraft>[_draft(2, loginAccount: 'caseuser')],
          existing: const <ExistingAccountSummary>[existing],
        )
        .single;
    final related = detector
        .detect(
          imported: <AccountImportDraft>[
            _draft(2, platformName: 'Other', loginAccount: 'other'),
          ],
          existing: const <ExistingAccountSummary>[existing],
        )
        .single;

    expect(high.confidence, ImportDuplicateConfidence.high);
    expect(
      high.conflictingFields,
      containsAll(<String>['url', 'password', 'notes']),
    );
    expect(high.conflictingFields, isNot(contains('domain')));
    expect(high.passwordComparison, ImportPasswordComparison.different);
    expect(high.hasExistingPassword, isTrue);
    expect(medium.confidence, ImportDuplicateConfidence.medium);
    expect(related.confidence, ImportDuplicateConfidence.related);
    final safe = jsonEncode(high.toSafePreviewJson());
    expect(safe, isNot(contains('fake-old-password')));
    expect(safe, isNot(contains('fake-new-password')));
  });

  test('100/1000/5000 条唯一数据使用索引完成且无伪重复', () {
    for (final count in <int>[100, 1000, 5000]) {
      final imported = List<AccountImportDraft>.generate(
        count,
        (index) => _draft(
          index + 2,
          platformName: 'Fake Service $index',
          loginAccount: 'fake-user-$index',
          url: 'https://service-$index.example.invalid',
        ),
      );
      final stopwatch = Stopwatch()..start();
      final result = detector.detect(
        imported: imported,
        existing: const <ExistingAccountSummary>[],
      );
      stopwatch.stop();
      expect(result, isEmpty, reason: count.toString());
      if (count == 5000) {
        expect(stopwatch.elapsed.inSeconds, lessThan(30));
      }
    }
  });

  test('2/100/5000 行 sourceId 稳定唯一且 adapterId 独立', () {
    final registry = ImportSourceRegistry.standard();
    final adapter = registry.adapterById('cardock_accounts_template');
    for (final count in <int>[2, 100, 5000]) {
      final document = TabularDocument(
        headers: _accountHeaders,
        rows: List<TabularRow>.generate(
          count,
          (index) => TabularRow(
            values: <String>[
              'key-$index',
              'Fake $index',
              'user-$index',
              '',
              '',
              'fake-pass-$index',
              '',
              '',
            ],
            originalRowNumber: index + 2,
          ),
        ),
        encoding: TabularSourceEncoding.utf8,
        delimiter: ',',
        hasHeader: true,
        originalByteLength: count,
      );
      final drafts = const ImportFieldMapper()
          .mapAccounts(
            document,
            adapter: adapter,
            documentSlotId: 'account-document',
          )
          .drafts;

      expect(drafts.map((draft) => draft.sourceId).toSet(), hasLength(count));
      expect(
        drafts.every((draft) => draft.adapterId == 'cardock_accounts_template'),
        isTrue,
      );
    }
  });

  test('遮挡密码未确认时按 importedEmpty 去重并从 plan 清空，确认后重算', () {
    final controller = ImportSessionController();
    controller.loadParsedDocument(
      _document(<List<String>>[
        _accountHeaders,
        <String>[
          'key-1',
          'Fake Service',
          'fake-user',
          '',
          '',
          '******',
          'https://example.invalid',
          '',
        ],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 11,
    );
    controller.mapAccounts();
    const existing = ExistingAccountSummary(
      id: 'existing-1',
      platformName: 'Fake Service',
      loginAccount: 'fake-user',
      password: 'fake-existing-password',
      url: 'https://example.invalid',
    );
    var snapshot = controller.detectDuplicates(const <ExistingAccountSummary>[
      existing,
    ]);
    var candidate = snapshot.duplicateCandidates.single;

    expect(
      candidate.passwordComparison,
      ImportPasswordComparison.importedEmpty,
    );
    expect(candidate.conflictingFields, isNot(contains('password')));
    controller.setDuplicateResolution(
      candidate.id,
      ImportDuplicateResolution.fieldByField,
    );
    expect(
      controller.buildPlan().plan!.accountUpdates.single.draft.password,
      isEmpty,
    );

    snapshot = controller.setMaskedPasswordConfirmed(2, confirmed: true);
    expect(snapshot.duplicateCandidates, isEmpty);
    snapshot = controller.detectDuplicates(const <ExistingAccountSummary>[
      existing,
    ]);
    candidate = snapshot.duplicateCandidates.single;
    expect(candidate.passwordComparison, ImportPasswordComparison.different);
    expect(candidate.conflictingFields, contains('password'));
    controller.setDuplicateResolution(
      candidate.id,
      ImportDuplicateResolution.fieldByField,
    );
    controller.setDuplicateFieldChoice(
      candidate.id,
      fieldName: 'password',
      useImportedValue: true,
    );
    final plan = controller.buildPlan().plan!;
    expect(plan.accountUpdates.single.useImportedField['password'], isTrue);
    expect(plan.accountUpdates.single.draft.password, '******');
  });

  test('逐字段必须明确密码/备注/URL，决议键与 AppState 一致', () {
    final controller = ImportSessionController();
    controller.loadParsedDocument(
      _document(<List<String>>[
        _accountHeaders,
        <String>[
          'key-1',
          'Fake Service',
          'fake-user',
          '',
          '',
          'fake-new-password',
          'https://example.invalid/new',
          'new note',
        ],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 12,
    );
    controller.mapAccounts();
    final candidate = controller
        .detectDuplicates(const <ExistingAccountSummary>[
          ExistingAccountSummary(
            id: 'existing-1',
            platformName: 'Fake Service',
            loginAccount: 'fake-user',
            password: 'fake-old-password',
            url: 'https://example.invalid/old',
            notes: 'old note',
          ),
        ])
        .duplicateCandidates
        .single;
    controller.setDuplicateResolution(
      candidate.id,
      ImportDuplicateResolution.fieldByField,
    );
    expect(controller.snapshot.duplicateCandidates.single.isResolved, isFalse);
    controller.setDuplicateFieldChoice(
      candidate.id,
      fieldName: 'password',
      useImportedValue: false,
    );
    controller.setDuplicateFieldChoice(
      candidate.id,
      fieldName: 'notes',
      useImportedValue: true,
    );
    controller.setDuplicateFieldChoice(
      candidate.id,
      fieldName: 'url',
      useImportedValue: true,
    );

    final update = controller.buildPlan().plan!.accountUpdates.single;
    expect(update.useImportedField['password'], isFalse);
    expect(update.useImportedField['notes'], isTrue);
    expect(update.useImportedField['url'], isTrue);
    expect(update.useImportedField, isNot(contains('domain')));
  });

  test('多 existing 更新未选目标时 fail-closed，显式目标后才入 plan', () {
    final controller = ImportSessionController();
    controller.loadParsedDocument(
      _document(<List<String>>[
        _accountHeaders,
        <String>[
          'key-1',
          'Fake Service',
          'fake-user',
          '',
          '',
          '',
          'https://example.invalid',
          '',
        ],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 13,
    );
    controller.mapAccounts();
    final candidates =
        controller.detectDuplicates(const <ExistingAccountSummary>[
          ExistingAccountSummary(
            id: 'existing-1',
            platformName: 'Fake Service',
            loginAccount: 'fake-user',
            url: 'https://example.invalid',
          ),
          ExistingAccountSummary(
            id: 'existing-2',
            platformName: 'Fake Service',
            loginAccount: 'fake-user',
            url: 'https://example.invalid',
          ),
        ]).duplicateCandidates;
    for (final candidate in candidates) {
      controller.setDuplicateResolution(
        candidate.id,
        ImportDuplicateResolution.fillEmptyFieldsOnly,
      );
    }

    expect(() => controller.buildPlan(), throwsStateError);
    controller.setDuplicateUpdateTarget(2, 'existing-2');
    expect(
      controller.buildPlan().plan!.accountUpdates.single.existingAccountId,
      'existing-2',
    );
  });

  test('双文档同 plan 保留建议/品牌，account_key 一对多且生成键不误关联', () {
    final controller = ImportSessionController(
      brandSuggestionResolver: (platformName, url) =>
          ImportBrandSuggestionResult.multipleCandidates(<String>[
            'brand-a',
            'brand-b',
          ]),
    );
    final accountDocument = _document(<List<String>>[
      _accountHeaders,
      <String>[
        'key-a',
        'Fake A',
        'fake@example.invalid',
        '',
        '',
        'fake-pass-a',
        'https://a.example.invalid',
        '',
      ],
      <String>[
        'key-b',
        'Fake B',
        'fake-user-b',
        '',
        '',
        'fake-pass-b',
        'https://b.example.invalid',
        '',
      ],
    ]);
    final subscriptionDocument = _document(<List<String>>[
      _subscriptionHeaders,
      <String>[
        'key-a',
        'Plan 1',
        '10',
        'USD',
        'monthly',
        '2026-09-01',
        '2026-10-01',
        'true',
        'Fake Card',
        '2',
        '',
      ],
      <String>[
        'key-a',
        'Plan 2',
        '20',
        'USD',
        'annual',
        '2026-10-01',
        '2027-10-01',
        'false',
        'Fake Card',
        '5',
        '',
      ],
      <String>[
        '',
        'Plan 3',
        '30',
        'USD',
        'quarterly',
        '2026-09-01',
        '2026-12-01',
        'yes',
        'Fake Card',
        '1',
        '',
      ],
    ]);
    controller.loadParsedDocument(
      accountDocument,
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 21,
    );
    var snapshot = controller.mapAccounts();
    final suggestionId = snapshot.fieldSuggestions.single.id;
    controller.acceptFieldSuggestion(suggestionId);
    controller.selectBrandSuggestion(2, 'brand-b');
    snapshot = controller.appendSubscriptionDocument(subscriptionDocument);

    expect(snapshot.fieldSuggestions.single.accepted, isTrue);
    expect(snapshot.selectedBrandSuggestions[2], 'brand-b');
    var plan = controller
        .buildPlan(isFormalSubscriptionValid: (draft) => true)
        .plan!;
    expect(plan.expectedVaultRevision, 21);
    expect(plan.newAccounts, hasLength(2));
    expect(plan.formalSubscriptions, hasLength(2));
    expect(plan.pendingSubscriptionDrafts, hasLength(1));
    expect(plan.unresolvedSubscriptionAccountCount, 1);
    expect(plan.unresolvedBrandSuggestionCount, 1);
    expect(plan.canCommit, isFalse);
    expect(plan.newAccounts.first.email, 'fake@example.invalid');
    expect(plan.newAccounts.first.loginAccount, 'fake@example.invalid');
    expect(plan.newAccounts.first.brandSuggestion, 'brand-b');
    expect(
      plan.formalSubscriptions.map((draft) => draft.accountKey).toSet(),
      <String>{'key-a'},
    );
    final generatedSubscriptionKey =
        snapshot.subscriptionMapping!.drafts.last.accountKey;
    expect(generatedSubscriptionKey, contains('subscription-document'));
    expect(
      generatedSubscriptionKey,
      isNot(snapshot.accountMapping!.drafts.first.accountKey),
    );

    controller.setSubscriptionAccountTarget(4, importedAccountKey: 'key-b');
    controller.ignoreBrandSuggestions(3);
    plan = controller
        .buildPlan(isFormalSubscriptionValid: (draft) => true)
        .plan!;
    expect(plan.canCommit, isTrue);
    expect(plan.formalSubscriptions, hasLength(3));
    expect(plan.unresolvedBrandSuggestionCount, 0);
    expect(plan.formalSubscriptions.last.accountKey, 'key-b');
    expect(plan.formalSubscriptions.last.accountTargetConfirmed, isTrue);
    expect(
      plan.formalSubscriptions.map((draft) => draft.sourceId).toSet(),
      hasLength(3),
    );
    expect(
      plan.newAccounts.map((draft) => draft.sourceId).toSet(),
      hasLength(2),
    );
  });

  test('订阅先账号后也生成单一 plan，同行号跨文档 sourceId 不冲突', () {
    final controller = ImportSessionController();
    final subscriptionDocument = _document(<List<String>>[
      _subscriptionHeaders,
      <String>[
        'key-a',
        'Plan',
        '10',
        'USD',
        'monthly',
        '2026-09-01',
        '2026-10-01',
        'true',
        'Fake Card',
        '2',
        '',
      ],
    ]);
    final accountDocument = _document(<List<String>>[
      _accountHeaders,
      <String>[
        'key-a',
        'Fake A',
        'fake@example.invalid',
        '',
        '',
        'fake-pass',
        'https://a.example.invalid',
        '',
      ],
    ]);
    controller.loadParsedDocument(
      subscriptionDocument,
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 22,
    );
    controller.mapSubscriptions();
    var snapshot = controller.appendAccountDocument(accountDocument);
    controller.acceptFieldSuggestion(snapshot.fieldSuggestions.single.id);
    snapshot = controller.buildPlan(isFormalSubscriptionValid: (draft) => true);
    final plan = snapshot.plan!;

    expect(plan.canCommit, isTrue);
    expect(plan.newAccounts.single.email, 'fake@example.invalid');
    expect(plan.formalSubscriptions.single.accountKey, 'key-a');
    expect(
      plan.newAccounts.single.sourceId,
      isNot(plan.formalSubscriptions.single.sourceId),
    );
    expect(plan.newAccounts.single.originalRowNumber, 2);
    expect(plan.formalSubscriptions.single.originalRowNumber, 2);
  });

  test('generated 订阅未选目标禁止提交，显式 existing target 真正写入 plan', () {
    final controller = ImportSessionController();
    controller.loadParsedDocument(
      _document(<List<String>>[
        _subscriptionHeaders,
        <String>[
          '',
          'Plan',
          '10',
          'USD',
          'monthly',
          '2026-09-01',
          '2026-10-01',
          'true',
          'Fake Card',
          '2',
          '',
        ],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 23,
    );
    controller.mapSubscriptions();
    var plan = controller
        .buildPlan(isFormalSubscriptionValid: (draft) => true)
        .plan!;
    expect(plan.unresolvedSubscriptionAccountCount, 1);
    expect(plan.canCommit, isFalse);

    controller.setSubscriptionAccountTarget(
      2,
      existingAccountId: 'account-existing',
    );
    plan = controller
        .buildPlan(isFormalSubscriptionValid: (draft) => true)
        .plan!;
    final subscription = plan.formalSubscriptions.single;
    expect(plan.canCommit, isTrue);
    expect(subscription.accountKey, 'account-existing');
    expect(subscription.targetExistingAccountId, 'account-existing');
    expect(subscription.accountTargetConfirmed, isTrue);
  });

  test('额度拒绝会阻止 commit 且 revision 保留', () {
    final controller = ImportSessionController();
    controller.loadParsedDocument(
      _document(<List<String>>[
        _accountHeaders,
        <String>['key-1', 'Fake', '', '', '', '', '', ''],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 31,
    );
    controller.mapAccounts();
    final plan = controller
        .buildPlan(
          quotaValidator: (accounts, subscriptions) =>
              ImportQuotaValidationResult(
                allowed: false,
                requestedAccounts: accounts,
                requestedSubscriptions: subscriptions,
                errorCode: 'quota_exceeded',
              ),
        )
        .plan!;

    expect(plan.expectedVaultRevision, 31);
    expect(plan.quota.errorCode, 'quota_exceeded');
    expect(plan.canCommit, isFalse);
  });

  test('多品牌候选必须逐行选择或忽略，唯一精确品牌自动采用', () {
    ImportSessionController controllerWith(
      ImportBrandSuggestionResult Function(String, String) resolver,
    ) => ImportSessionController(brandSuggestionResolver: resolver);

    final multiple = controllerWith(
      (platform, url) => ImportBrandSuggestionResult.multipleCandidates(
        const <String>['brand-a', 'brand-b'],
      ),
    );
    multiple.loadParsedDocument(
      _document(<List<String>>[
        _accountHeaders,
        <String>['key-1', 'Fake', 'fake-user', '', '', '', '', ''],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 40,
    );
    multiple.mapAccounts();
    var plan = multiple.buildPlan().plan!;
    expect(plan.unresolvedBrandSuggestionCount, 1);
    expect(plan.canCommit, isFalse);
    expect(plan.toSummaryJson()['unresolvedBrandSuggestionCount'], 1);
    expect(jsonEncode(plan.toSummaryJson()), isNot(contains('brand-a')));

    multiple.selectBrandSuggestion(2, 'brand-b');
    plan = multiple.buildPlan().plan!;
    expect(plan.unresolvedBrandSuggestionCount, 0);
    expect(plan.newAccounts.single.brandSuggestion, 'brand-b');
    expect(plan.canCommit, isTrue);

    multiple.ignoreBrandSuggestions(2);
    plan = multiple.buildPlan().plan!;
    expect(plan.unresolvedBrandSuggestionCount, 0);
    expect(plan.newAccounts.single.brandSuggestion, isNull);
    expect(plan.newAccounts.single.brandSuggestionIgnored, isTrue);
    expect(plan.canCommit, isTrue);

    final exact = controllerWith(
      (platform, url) => ImportBrandSuggestionResult.exactUnique('brand-only'),
    );
    exact.loadParsedDocument(
      _document(<List<String>>[
        _accountHeaders,
        <String>['key-1', 'Fake', 'fake-user', '', '', '', '', ''],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 41,
    );
    exact.mapAccounts();
    final exactPlan = exact.buildPlan().plan!;
    expect(exactPlan.unresolvedBrandSuggestionCount, 0);
    expect(exactPlan.newAccounts.single.brandSuggestion, 'brand-only');
    expect(exactPlan.canCommit, isTrue);

    final directPlan = ImportPlan(
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 41,
      newAccounts: <AccountImportDraft>[
        AccountImportDraft(
          originalRowNumber: 2,
          sourceId: 'direct-brand-row',
          platformName: 'Fake',
          brandSuggestionCandidates: const <String>['brand-a', 'brand-b'],
        ),
      ],
      accountUpdates: const <AccountUpdatePlan>[],
      skippedAccounts: const <AccountImportDraft>[],
      formalSubscriptions: const <SubscriptionImportDraft>[],
      pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
      unsupportedItemCount: 0,
      unresolvedDuplicateCount: 0,
      quota: const ImportQuotaValidationResult.unlimited(
        requestedAccounts: 1,
        requestedSubscriptions: 0,
      ),
    );
    expect(directPlan.unresolvedBrandSuggestionCount, 1);
    expect(directPlan.canCommit, isFalse);
  });

  test('取消全部行与仅 skipped 或 unsupported 的计划均为零写且不可提交', () {
    final controller = ImportSessionController();
    controller.loadParsedDocument(
      _document(<List<String>>[
        _accountHeaders,
        <String>['key-1', 'Fake', 'fake-user', '', '', '', '', ''],
      ]),
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 42,
    );
    controller.mapAccounts();
    controller.setAccountRowSelected(2, false);
    final skippedPlan = controller.buildPlan().plan!;
    expect(skippedPlan.skippedAccounts, hasLength(1));
    expect(skippedPlan.writeOperationCount, 0);
    expect(skippedPlan.hasWriteOperations, isFalse);
    expect(skippedPlan.canCommit, isFalse);

    final unsupportedOnly = ImportPlan(
      vaultScopeId: 'real-vault',
      expectedVaultRevision: 42,
      newAccounts: const <AccountImportDraft>[],
      accountUpdates: const <AccountUpdatePlan>[],
      skippedAccounts: const <AccountImportDraft>[],
      formalSubscriptions: const <SubscriptionImportDraft>[],
      pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
      unsupportedItemCount: 3,
      unresolvedDuplicateCount: 0,
      quota: const ImportQuotaValidationResult.unlimited(
        requestedAccounts: 0,
        requestedSubscriptions: 0,
      ),
    );
    expect(unsupportedOnly.writeOperationCount, 0);
    expect(unsupportedOnly.canCommit, isFalse);
    expect(unsupportedOnly.toSummaryJson()['hasWriteOperations'], isFalse);
  });
}
