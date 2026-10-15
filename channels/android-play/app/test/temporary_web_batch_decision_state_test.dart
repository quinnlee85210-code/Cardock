import 'package:account_subscription_manager/core/temporary_web/temporary_web_batch_decision_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const account = TemporaryWebBatchDecisionRow(
    id: 'account-row-2',
    kind: 'account',
    canImport: true,
    hasDuplicate: true,
    duplicateContext: '发现 1 个疑似重复项。',
    defaultResolution: 'skip',
    subscriptionTargetRequired: false,
  );
  const subscription = TemporaryWebBatchDecisionRow(
    id: 'subscription-row-2',
    kind: 'subscription',
    canImport: true,
    hasDuplicate: false,
    defaultResolution: 'skip',
    subscriptionTargetRequired: true,
    subscriptionTargetIds: <String>{'existing-account-a'},
  );

  test('切换或加入另一类文件只恢复仍有效的逐行决议', () {
    final result = reconcileTemporaryWebBatchDecisions(
      previousRows: const <TemporaryWebBatchDecisionRow>[account, subscription],
      previousSelectedRowIds: const <String>{'subscription-row-2'},
      previousDuplicateResolutions: const <String, String>{
        'account-row-2': 'importAsNew',
      },
      previousSubscriptionTargets: const <String, String>{
        'subscription-row-2': 'existing-account-a',
      },
      rows: const <TemporaryWebBatchDecisionRow>[
        account,
        subscription,
        TemporaryWebBatchDecisionRow(
          id: 'subscription-row-3',
          kind: 'subscription',
          canImport: true,
          hasDuplicate: false,
          defaultResolution: 'skip',
          subscriptionTargetRequired: false,
        ),
      ],
    );

    expect(result.selectedRowIds, <String>{
      'subscription-row-2',
      'subscription-row-3',
    });
    expect(result.duplicateResolutions['account-row-2'], 'importAsNew');
    expect(
      result.subscriptionTargets['subscription-row-2'],
      'existing-account-a',
    );
  });

  test('同类替换即使复用行号也只重置该类而保留另一类', () {
    final result = reconcileTemporaryWebBatchDecisions(
      previousRows: const <TemporaryWebBatchDecisionRow>[account, subscription],
      previousSelectedRowIds: const <String>{'subscription-row-2'},
      previousDuplicateResolutions: const <String, String>{
        'account-row-2': 'importAsNew',
      },
      previousSubscriptionTargets: const <String, String>{
        'subscription-row-2': 'existing-account-a',
      },
      rows: const <TemporaryWebBatchDecisionRow>[account, subscription],
      resetDocumentKinds: const <String>{'account'},
    );

    expect(result.selectedRowIds, <String>{
      'account-row-2',
      'subscription-row-2',
    });
    expect(result.duplicateResolutions['account-row-2'], 'skip');
    expect(
      result.subscriptionTargets['subscription-row-2'],
      'existing-account-a',
    );
  });

  test('失效目标、变化的重复上下文和消失行不会继承旧决议', () {
    final result = reconcileTemporaryWebBatchDecisions(
      previousRows: const <TemporaryWebBatchDecisionRow>[
        account,
        subscription,
        TemporaryWebBatchDecisionRow(
          id: 'account-row-99',
          kind: 'account',
          canImport: true,
          hasDuplicate: false,
          defaultResolution: 'skip',
          subscriptionTargetRequired: false,
        ),
      ],
      previousSelectedRowIds: const <String>{
        'account-row-2',
        'account-row-99',
        'subscription-row-2',
      },
      previousDuplicateResolutions: const <String, String>{
        'account-row-2': 'fillEmptyFieldsOnly',
        'account-row-99': 'importAsNew',
      },
      previousSubscriptionTargets: const <String, String>{
        'subscription-row-2': 'existing-account-a',
        'subscription-row-99': 'stale-target',
      },
      rows: const <TemporaryWebBatchDecisionRow>[
        TemporaryWebBatchDecisionRow(
          id: 'account-row-2',
          kind: 'account',
          canImport: true,
          hasDuplicate: true,
          duplicateContext: '发现 2 个疑似重复项。',
          defaultResolution: 'skip',
          subscriptionTargetRequired: false,
        ),
        TemporaryWebBatchDecisionRow(
          id: 'subscription-row-2',
          kind: 'subscription',
          canImport: true,
          hasDuplicate: false,
          defaultResolution: 'skip',
          subscriptionTargetRequired: true,
          subscriptionTargetIds: <String>{'existing-account-b'},
        ),
      ],
    );

    expect(result.selectedRowIds, <String>{
      'account-row-2',
      'subscription-row-2',
    });
    expect(result.duplicateResolutions, <String, String>{
      'account-row-2': 'skip',
    });
    expect(result.subscriptionTargets, <String, String>{
      'subscription-row-2': 'existing-account-b',
    });
    expect(result.selectedRowIds, isNot(contains('account-row-99')));
  });

  test('首次预览只有一个可选账号时自动关联并进入选择集', () {
    final result = reconcileTemporaryWebBatchDecisions(
      previousRows: const <TemporaryWebBatchDecisionRow>[],
      previousSelectedRowIds: const <String>{},
      previousDuplicateResolutions: const <String, String>{},
      previousSubscriptionTargets: const <String, String>{},
      rows: const <TemporaryWebBatchDecisionRow>[account, subscription],
    );

    expect(result.selectedRowIds, <String>{
      'account-row-2',
      'subscription-row-2',
    });
    expect(result.duplicateResolutions, <String, String>{
      'account-row-2': 'skip',
    });
    expect(result.subscriptionTargets, <String, String>{
      'subscription-row-2': 'existing-account-a',
    });
  });

  test('没有可选账号或存在多个账号时仍要求用户明确选择', () {
    final result = reconcileTemporaryWebBatchDecisions(
      previousRows: const <TemporaryWebBatchDecisionRow>[],
      previousSelectedRowIds: const <String>{},
      previousDuplicateResolutions: const <String, String>{},
      previousSubscriptionTargets: const <String, String>{},
      rows: const <TemporaryWebBatchDecisionRow>[
        TemporaryWebBatchDecisionRow(
          id: 'subscription-row-none',
          kind: 'subscription',
          canImport: true,
          hasDuplicate: false,
          defaultResolution: 'skip',
          subscriptionTargetRequired: true,
        ),
        TemporaryWebBatchDecisionRow(
          id: 'subscription-row-many',
          kind: 'subscription',
          canImport: true,
          hasDuplicate: false,
          defaultResolution: 'skip',
          subscriptionTargetRequired: true,
          subscriptionTargetIds: <String>{'account-a', 'account-b'},
        ),
      ],
    );

    expect(result.selectedRowIds, isEmpty);
    expect(result.subscriptionTargets, isEmpty);
  });
}
