import 'dart:math' as math;

import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../domain/account_analysis.dart';
import '../domain/account_record.dart';

enum AccountDuplicateChoice { revise, addAnyway, restored }

String accountDuplicateFieldLabel(String field) => switch (field) {
  'platformName+loginAccount' => '平台与登录账号',
  'domain+loginAccount' => '主域名与登录账号',
  'platformName+email' => '平台与绑定邮箱',
  'platformName+phone' => '平台与绑定手机号',
  'platformName+username+domain' => '平台、用户名与主域名',
  _ => field,
};

Future<AccountDuplicateChoice?> showAccountDuplicateDialog({
  required BuildContext context,
  required List<AccountDuplicateCandidate> candidates,
  Future<void> Function(AccountRecord account)? onOpenAccount,
  Future<bool> Function(AccountRecord account)? onRestoreAccount,
}) {
  final active = candidates.where((c) => !c.inTrash).toList();
  final trash = candidates.where((c) => c.inTrash).toList();
  final rows = <Object>[
    '请核对以下候选。不会自动合并、覆盖密码或恢复记录。',
    if (active.isNotEmpty) ...['活动账号中的相似记录', ...active],
    if (trash.isNotEmpty) ...['回收站中的相似记录', ...trash],
  ];
  return showDialog<AccountDuplicateChoice>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('发现相似账号记录'),
      content: SizedBox(
        width: 460,
        height: math.min(400, MediaQuery.sizeOf(context).height * 0.45),
        child: ListView.builder(
          key: const ValueKey('duplicate-candidate-list'),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is String) {
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Semantics(
                  header: index > 0,
                  child: Text(
                    row,
                    style: index > 0
                        ? Theme.of(context).textTheme.titleSmall
                        : null,
                  ),
                ),
              );
            }
            final candidate = row as AccountDuplicateCandidate;
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(candidate.account.platformName, translate: false),
                  Text(
                    context.tr('匹配依据：{fields}', {
                      'fields': candidate.matchingFields
                          .map(accountDuplicateFieldLabel)
                          .map(context.tr)
                          .join(' · '),
                    }),
                    translate: false,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (onOpenAccount != null)
                        TextButton(
                          onPressed: () => onOpenAccount(candidate.account),
                          child: const Text('查看现有记录'),
                        ),
                      if (candidate.inTrash && onRestoreAccount != null)
                        TextButton(
                          onPressed: () async {
                            final restored = await onRestoreAccount(
                              candidate.account,
                            );
                            if (restored && context.mounted) {
                              Navigator.pop(
                                context,
                                AccountDuplicateChoice.restored,
                              );
                            }
                          },
                          child: const Text('恢复回收站记录'),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('duplicate-return-edit'),
          onPressed: () =>
              Navigator.pop(context, AccountDuplicateChoice.revise),
          child: const Text('返回修改'),
        ),
        FilledButton(
          key: const ValueKey('duplicate-add-anyway'),
          onPressed: () =>
              Navigator.pop(context, AccountDuplicateChoice.addAnyway),
          child: const Text('仍然新增'),
        ),
      ],
    ),
  );
}
