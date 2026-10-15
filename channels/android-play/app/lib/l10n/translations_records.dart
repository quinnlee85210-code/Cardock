import '../core/preferences/language_preferences.dart';
import '../features/accounts/domain/account_record.dart';
import '../features/subscriptions/domain/subscription_record.dart';
import '../core/security/vault_recovery.dart';

String localizedAccountCategory(CardockLanguage language, String value) {
  if (!accountCategories.contains(value)) return value;
  return switch (language) {
    CardockLanguage.simplifiedChinese => value,
    CardockLanguage.english => switch (value) {
      'AI工具' => 'AI tools',
      '影音娱乐' => 'Entertainment',
      '购物' => 'Shopping',
      '社交' => 'Social',
      '办公' => 'Productivity',
      '云服务' => 'Cloud services',
      '金融' => 'Finance',
      '保险' => 'Insurance',
      '其他' => 'Other',
      _ => value,
    },
    CardockLanguage.japanese => switch (value) {
      'AI工具' => 'AIツール',
      '影音娱乐' => '動画・音楽',
      '购物' => 'ショッピング',
      '社交' => 'ソーシャル',
      '办公' => '仕事効率化',
      '云服务' => 'クラウドサービス',
      '金融' => '金融',
      '保险' => '保険',
      '其他' => 'その他',
      _ => value,
    },
  };
}

String localizedSubscriptionStatus(
  CardockLanguage language,
  SubscriptionStatus status,
) => switch (language) {
  CardockLanguage.simplifiedChinese => status.label,
  CardockLanguage.english => switch (status) {
    SubscriptionStatus.active => 'Active',
    SubscriptionStatus.paused => 'Paused',
    SubscriptionStatus.cancelled => 'Canceled',
    SubscriptionStatus.expired => 'Expired',
  },
  CardockLanguage.japanese => switch (status) {
    SubscriptionStatus.active => '有効',
    SubscriptionStatus.paused => '一時停止',
    SubscriptionStatus.cancelled => '解約済み',
    SubscriptionStatus.expired => '期限切れ',
  },
};

String localizedSubscriptionCycle(
  CardockLanguage language,
  SubscriptionCycleUnit unit,
  int count,
) {
  if (language == CardockLanguage.simplifiedChinese) {
    if (count == 1) return '每${unit.label}';
    return unit == SubscriptionCycleUnit.month
        ? '每$count个月'
        : '每$count${unit.label}';
  }
  if (language == CardockLanguage.japanese) {
    if (count == 1) {
      return switch (unit) {
        SubscriptionCycleUnit.day => '毎日',
        SubscriptionCycleUnit.week => '毎週',
        SubscriptionCycleUnit.month => '毎月',
        SubscriptionCycleUnit.year => '毎年',
      };
    }
    final label = switch (unit) {
      SubscriptionCycleUnit.day => '日',
      SubscriptionCycleUnit.week => '週間',
      SubscriptionCycleUnit.month => 'か月',
      SubscriptionCycleUnit.year => '年',
    };
    return '$count$labelごと';
  }
  final unitLabel = switch (unit) {
    SubscriptionCycleUnit.day => count == 1 ? 'day' : 'days',
    SubscriptionCycleUnit.week => count == 1 ? 'week' : 'weeks',
    SubscriptionCycleUnit.month => count == 1 ? 'month' : 'months',
    SubscriptionCycleUnit.year => count == 1 ? 'year' : 'years',
  };
  return count == 1 ? 'Every $unitLabel' : 'Every $count $unitLabel';
}

String localizedRecordDate(CardockLanguage language, DateTime value) {
  final date = DateTime(value.year, value.month, value.day);
  if (language == CardockLanguage.english) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
  return '${date.year}年${date.month}月${date.day}日';
}

String localizedRecordDateTime(CardockLanguage language, DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final date = localizedRecordDate(language, value);
  return language == CardockLanguage.english
      ? '$date, $hour:$minute'
      : '$date $hour:$minute';
}

String localizedMonthDay(CardockLanguage language, DateTime value) {
  if (language == CardockLanguage.english) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}';
  }
  return '${value.month}月${value.day}日';
}

String localizedRecordMonth(CardockLanguage language, int month) {
  if (language == CardockLanguage.english) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
  return '$month月';
}

String localizedAccountCount(CardockLanguage language, int count) =>
    switch (language) {
      CardockLanguage.simplifiedChinese => '$count个账号',
      CardockLanguage.english => count == 1 ? '1 account' : '$count accounts',
      CardockLanguage.japanese => '$count件のアカウント',
    };

String localizedSubscriptionCount(CardockLanguage language, int count) =>
    switch (language) {
      CardockLanguage.simplifiedChinese => '$count个订阅',
      CardockLanguage.english =>
        count == 1 ? '1 subscription' : '$count subscriptions',
      CardockLanguage.japanese => '$count件のサブスクリプション',
    };

String localizedSubscriptionItemCount(CardockLanguage language, int count) =>
    language == CardockLanguage.simplifiedChinese
    ? '$count项订阅'
    : localizedSubscriptionCount(language, count);

String localizedRenewalDayCount(CardockLanguage language, int count) =>
    switch (language) {
      CardockLanguage.simplifiedChinese => '$count个具体续费日',
      CardockLanguage.english =>
        count == 1 ? '1 renewal date' : '$count renewal dates',
      CardockLanguage.japanese => '$count件の更新日',
    };

String localizedRecordCount(CardockLanguage language, int count) =>
    switch (language) {
      CardockLanguage.simplifiedChinese => '$count项',
      CardockLanguage.english => count == 1 ? '1 record' : '$count records',
      CardockLanguage.japanese => '$count件',
    };

String localizedDaysBefore(CardockLanguage language, int days) =>
    switch (language) {
      CardockLanguage.simplifiedChinese => '提前$days天',
      CardockLanguage.english =>
        days == 1 ? '1 day before' : '$days days before',
      CardockLanguage.japanese => '$days日前',
    };

String localizedRenewalHistoryCount(CardockLanguage language, int count) =>
    switch (language) {
      CardockLanguage.simplifiedChinese => '已记录$count次',
      CardockLanguage.english =>
        count == 1 ? 'Recorded once' : 'Recorded $count times',
      CardockLanguage.japanese => '$count回記録済み',
    };

String localizedRenewalTiming(CardockLanguage language, int days) {
  if (days == 0) {
    return switch (language) {
      CardockLanguage.simplifiedChinese => '今天续费',
      CardockLanguage.english => 'Renews today',
      CardockLanguage.japanese => '本日更新',
    };
  }
  return switch (language) {
    CardockLanguage.simplifiedChinese => '$days天后续费',
    CardockLanguage.english =>
      days == 1 ? 'Renews in 1 day' : 'Renews in $days days',
    CardockLanguage.japanese => '$days日後に更新',
  };
}

String localizedVaultRecoveryQuestion(
  CardockLanguage language,
  String questionId,
) {
  if (language == CardockLanguage.simplifiedChinese) {
    return vaultRecoveryQuestionLabel(questionId);
  }
  if (language == CardockLanguage.english) {
    return switch (questionId) {
      'childhood_city' => 'Which city did you live in the longest as a child?',
      'first_school' => 'What was the name of the first school you attended?',
      'first_teacher' => 'What was your first teacher’s family name?',
      'childhood_friend' => 'What was the name of your childhood friend?',
      'first_pet' => 'What was the name of your first pet?',
      'favorite_book' => 'Which book has stayed with you the most?',
      'favorite_food' => 'What was your favorite food as a child?',
      'first_trip' => 'Where did you go on your first long trip?',
      _ => vaultRecoveryQuestionLabel(questionId),
    };
  }
  return switch (questionId) {
    'childhood_city' => '子どもの頃、最も長く暮らした都市はどこですか？',
    'first_school' => '最初に通った学校の名前は何ですか？',
    'first_teacher' => '最初の先生の名字は何ですか？',
    'childhood_friend' => '子どもの頃の友人の名前は何ですか？',
    'first_pet' => '最初に飼ったペットの名前は何ですか？',
    'favorite_book' => '最も心に残っている本は何ですか？',
    'favorite_food' => '子どもの頃に一番好きだった食べ物は何ですか？',
    'first_trip' => '初めて遠出した場所はどこですか？',
    _ => vaultRecoveryQuestionLabel(questionId),
  };
}

const Map<String, String> recordsEnglishTranslations = <String, String>{
  '按账号分类': 'By account category',
  '当日已续费': 'Already renewed today',
  '继续续费': 'Renew again',
  '今天已经记录过续费，下次续费日期为{date}。继续会再延后一个计费周期并新增一笔支出，是否继续？':
      'A renewal was already recorded today. The next renewal is {date}. Continuing will advance it by another billing cycle and record another payment. Continue?',
  '编辑费用记录': 'Edit expense record',
  '只修改这笔费用，不改变订阅金额、计费周期或下次续费日期。':
      'Only this expense changes. The subscription amount, billing cycle and next renewal date stay the same.',
  '删除这笔费用？': 'Delete this expense?',
  '将从统计中删除“{service}”的这笔费用。订阅和下次续费日期保持不变；误点续费造成的日期延后，可在订阅详情中编辑修正。':
      'This expense for “{service}” will be removed from statistics. The subscription and next renewal date stay the same. Correct any accidental date extension in the subscription details.',
  '费用记录已删除。': 'Expense deleted.',
  '订阅已变化，请重新打开记录。': 'The subscription changed. Reopen the record.',
  '忘记密码？恢复保险库访问': 'Forgot a password? Recover vault access',
  '恢复功能不会显示旧密码，只会在选对三道密保并通过本机系统强认证后重设保险库密码。':
      'Recovery never shows the old password. It resets a vault password only after the correct three security questions are selected and strong system authentication succeeds on this device.',
  '两次输入的新密码不一致。': 'The new passwords do not match.',
  '旧密码不会被显示': 'The old password will not be shown',
  '下方会直接显示你设置时选择的三道问题。请填写对应答案，再通过本机指纹或安全级人脸。成功后会生成全新数据密钥并重设密码。':
      'The three questions you chose during setup are shown below. Enter their answers, then pass fingerprint or secure face authentication on this device. Success creates a new data key and resets the password.',
  '此入口有多组已配置的密保问题。请选择要回答的一组；页面不会标明它对应哪个保险库。':
      'More than one configured question set is available from this entry. Choose one to answer; the page does not identify which vault it belongs to.',
  '已配置密保问题组': 'Configured security-question set',
  '问题组 {number}': 'Question set {number}',
  '新保险库密码': 'New vault password',
  '再次输入新保险库密码': 'Re-enter new vault password',
  '验证并重设保险库密码': 'Verify and reset vault password',
  '恢复不会显示旧密码或密保答案，只会在答对当前显示的三道问题并通过本机系统强认证后重设密码。':
      'Recovery never shows the old password or security answers. It resets the password only after all three displayed questions and strong system authentication on this device both succeed.',
  '请输入{minimum}到{maximum}个字符的密码':
      'Enter a password with {minimum}–{maximum} characters',
  '首页': 'Home',
  '账号': 'Accounts',
  '订阅': 'Subscriptions',
  '设置': 'Settings',
  '安全、隐私与本地保险库': 'Security, privacy, and local vault',
  '{count}个账号 · 本地加密档案': '{count} accounts · Encrypted locally',
  '{count}个订阅 · 按具体续费日期排列': '{count} subscriptions · Sorted by renewal date',
  '{countLabel} · 本地加密档案': '{countLabel} · Encrypted locally',
  '{countLabel} · 按具体续费日期排列': '{countLabel} · Sorted by renewal date',
  '新增账号或订阅': 'Add an account or subscription',
  '新增记录': 'Add a record',
  '选择要保存到本机加密保险库的记录类型。':
      'Choose the type of record to save in the encrypted vault on this device.',
  '新增账号': 'Add account',
  '记录登录资料、密码和账号备注': 'Save sign-in details, passwords, and account notes',
  '新增订阅': 'Add subscription',
  '记录套餐、续费日期和提醒': 'Save plan details, renewal dates, and reminders',
  '立即锁定': 'Lock now',
  '账号排序偏好未能保存，请稍后重试。':
      'The account sort preference could not be saved. Try again later.',
  '订阅排序偏好未能保存，请稍后重试。':
      'The subscription sort preference could not be saved. Try again later.',
  '订阅只读视图不能新增记录，请改用真实主密码解锁。':
      'Records cannot be added in the subscription-only view. Unlock with the real master password.',
  '保存失败，记录未写入。': 'Save failed. The record was not written.',
  '已加密保存到本机。': 'Encrypted and saved on this device.',
  '修改失败，原账号记录仍保留。': 'Update failed. The original account record is unchanged.',
  '订阅已加密保存。': 'Subscription encrypted and saved.',
  '保存失败，订阅未写入。': 'Save failed. The subscription was not written.',
  '订阅修改已加密保存。': 'Subscription changes encrypted and saved.',
  '修改失败，订阅未写入。': 'Update failed. The subscription was not written.',
  '知道了': 'Got it',
  '账号信息仍处于加密锁定状态': 'Account information is still encrypted and locked',
  '当前生物识别只解开了独立的订阅只读视图。要查看账号、编辑记录或使用备份，请改用真实主密码。':
      'Biometrics opened only the separate subscription-only view. Use the real master password to view accounts, edit records, or use backups.',
  '锁定并改用主密码': 'Lock and use master password',
  '账号详情': 'Account details',
  '编辑账号': 'Edit account',
  '删除账号': 'Delete account',
  '确认删除账号？': 'Delete this account?',
  '删除后无法在应用内恢复。': 'This cannot be undone in the app.',
  '这个账号关联了{count}项订阅，确认后将一并删除，且无法在应用内恢复。':
      'This account has {count} linked subscriptions. They will also be deleted and cannot be recovered in the app.',
  '关联的{count}项订阅也会一并删除，且无法在应用内恢复。':
      '{count} linked subscriptions will also be deleted and cannot be recovered in the app.',
  '这个账号关联了{countLabel}，确认后将一并删除，且无法在应用内恢复。':
      'This account has {countLabel}. They will also be deleted and cannot be recovered in the app.',
  '关联的{countLabel}也会一并删除，且无法在应用内恢复。':
      '{countLabel} linked to this account will also be deleted and cannot be recovered in the app.',
  '确认删除': 'Delete',
  '删除失败，原记录仍保留。': 'Delete failed. The original record is unchanged.',
  '账号及关联订阅已删除。': 'The account and its linked subscriptions were deleted.',
  '基本资料': 'Basic details',
  '补充信息': 'Additional information',
  '分类': 'Category',
  '未分类': 'Uncategorized',
  '平台或应用名称 *': 'Platform or app name *',
  '平台或应用名称不能为空': 'Platform or app name is required',
  '平台或应用名称过长': 'Platform or app name is too long',
  '登录账号': 'Sign-in ID',
  '用户名': 'Username',
  '绑定手机号': 'Linked phone number',
  '绑定邮箱': 'Linked email',
  '登录密码': 'Sign-in password',
  '官方网址或登录网址': 'Official or sign-in website',
  '备注': 'Notes',
  '未填写': 'Not provided',
  '复制{label}': 'Copy {label}',
  '已安全复制{label}，60秒后自动清除。':
      '{label} copied securely. It will be cleared in 60 seconds.',
  '复制失败，未写入剪贴板。': 'Could not copy. Nothing was written to the clipboard.',
  '安全复制登录密码': 'Copy sign-in password securely',
  '显示密码30秒': 'Show password for 30 seconds',
  '隐藏密码': 'Hide password',
  '显示密码': 'Show password',
  '使用系统浏览器打开': 'Open in system browser',
  '打开网址失败。': 'Could not open the website.',
  '系统没有可打开该网址的应用。': 'No app is available to open this website.',
  '订阅记录（{count}）': 'Subscriptions ({count})',
  '这个账号暂无订阅记录。': 'This account has no subscription records.',
  '{cycle} · {date}续费': '{cycle} · Renews {date}',
  '账号操作': 'Account actions',
  '安全信息': 'Security information',
  '联系绑定': 'Linked contact details',
  '支付方式': 'Payment method',
  '账号卡片，{name}': 'Account card, {name}',
  '账号卡片，{name}，{subscriptions}': 'Account card, {name}, {subscriptions}',
  '{service}，{account}，{amount}，{date}，{status}':
      '{service}, {account}, {amount}, {date}, {status}',
  '{service}，{status}': '{service}, {status}',
  '{name}图标': '{name} icon',
  '平台图标': 'Platform icon',
  '平台品牌预览图标': 'Platform brand preview icon',
  '无订阅': 'No subscriptions',
  '{count}项订阅': '{count} subscriptions',
  '关联订阅：暂无': 'Linked subscriptions: none',
  '关联订阅：{names}': 'Linked subscriptions: {names}',
  '关联订阅：{names}，另有{count}项': 'Linked subscriptions: {names}, plus {count} more',
  '账号摘要：未填写': 'Account summary: not provided',
  '账号摘要：{value}': 'Account summary: {value}',
  '{label}：{status}': '{label}: {status}',
  '已填写': 'Provided',
  '按最近使用排序': 'Sorted by most recently used',
  '找到{count}个账号': '{count} accounts found',
  '找到{countLabel}': '{countLabel} found',
  '筛选': 'Filter',
  '选择账号排序方式': 'Choose account sort order',
  '待处理续费优先': 'Renewals due soonest',
  '最近添加': 'Newest first',
  '最早添加': 'Oldest first',
  '名称顺序': 'Name (A–Z)',
  '暂无账号记录': 'No account records',
  '每个平台账号会作为一张独立记录卡加密保存在本机。':
      'Each platform account is encrypted and stored on this device as a separate record card.',
  '没有匹配的账号': 'No matching accounts',
  '可以更换搜索词或分类后再试。': 'Try a different search term or category.',
  '{category}分类，共{count}个账号': '{category} category, {count} accounts',
  '{category}分类，共{countLabel}': '{category} category, {countLabel}',
  '展开{category}分类': 'Expand {category} category',
  '折叠{category}分类': 'Collapse {category} category',
  '{count}个账号': '{count} accounts',
  '搜索平台、用户名、账号、手机号或邮箱':
      'Search platform, username, sign-in ID, phone, or email',
  '全部': 'All',
  '不分类': 'No category',
  '分类（可选）': 'Category (optional)',
  '自定义分类…': 'Custom category…',
  '自定义分类 *': 'Custom category *',
  '请输入自定义分类': 'Enter a custom category',
  '支持中文，例如“学习课程”或“开发者服务”。':
      'Unicode text is supported, for example “Courses” or “Developer services.”',
  '基本信息': 'Basic information',
  '唯一必填项；同一平台可以建立多个账号记录。':
      'The only required field. You can keep multiple accounts for the same platform.',
  '请输入平台或应用名称': 'Enter a platform or app name',
  '账号与补充信息': 'Account and additional information',
  '登录资料优先；手机号、邮箱、网址与备注均可留空':
      'Sign-in details come first; phone, email, website, and notes are optional',
  '支持中文；可与登录账号分别记录。':
      'Unicode text is supported and can be stored separately from the sign-in ID.',
  '支持中文账号；输入法是否学习内容取决于系统设置。':
      'Unicode sign-in IDs are supported. Whether the keyboard learns input depends on system settings.',
  '登录密码处理': 'Sign-in password handling',
  '保留现有密码': 'Keep existing password',
  '替换密码': 'Replace password',
  '清除已保存密码': 'Remove saved password',
  '保存后将从本机加密库中移除这个账号的登录密码。':
      'Saving will remove this account’s sign-in password from the encrypted vault on this device.',
  '新登录密码 *': 'New sign-in password *',
  '支持中文、空格和任意字符；仅保存在本机加密库。':
      'Unicode text, spaces, and arbitrary characters are supported. The password stays only in the local encrypted vault.',
  '请输入新登录密码': 'Enter a new sign-in password',
  '支持中文域名，并按输入的原文保存在本机。':
      'Internationalized domain names are supported and saved exactly as entered on this device.',
  '支持中文、换行和任意字符；请勿填写验证码、恢复码或安全问题答案。':
      'Unicode text, line breaks, and arbitrary characters are supported. Do not enter verification codes, recovery codes, or security answers.',
  '这个账号已有订阅': 'This account has a subscription',
  '开启后，账号和首条订阅会一次性加密保存。':
      'When enabled, the account and first subscription are encrypted and saved together.',
  '首条订阅信息': 'First subscription details',
  '加密保存': 'Encrypt and save',
  '保存修改': 'Save changes',
  '离线品牌预览': 'Offline brand preview',
  '离线品牌预览，等待输入平台名称': 'Offline brand preview; waiting for a platform name',
  '离线品牌预览，{name}': 'Offline brand preview, {name}',
  '输入名称后实时匹配，未命中时使用字母标。':
      'Matches locally as you type; a monogram is used when there is no match.',
  '离线候选（仅在点选后替换输入）': 'Offline suggestions (input changes only after selection)',
  '模糊候选，不会自动绑定': 'Fuzzy match; never linked automatically',
  '记录只会写入本机加密库，不会上传。除平台名称外，其余字段均可留空。':
      'Records are written only to the encrypted vault on this device and are never uploaded. Every field except the platform name is optional.',
  '订阅详情': 'Subscription details',
  '这条订阅记录已删除或不可用。': 'This subscription record was deleted or is unavailable.',
  '即将续费': 'Upcoming',
  '全部订阅': 'All subscriptions',
  '已到期': 'Expired',
  '已取消': 'Canceled',
  '30天内续费': 'Renewing within 30 days',
  '本月订阅续费总额': 'This month’s renewal total (CNY)',
  '次月续费总额': 'Next month’s renewal total (CNY)',
  '逾期待确认': 'Overdue · Review needed',
  '共{count}项，点击记录查看完整详情': '{count} records · Select one to view full details',
  '共{countLabel}，点击记录查看完整详情': '{countLabel} · Select one to view full details',
  '清除筛选': 'Clear filter',
  '选择订阅排序方式': 'Choose subscription sort order',
  '使用真实主密码后可修改并保存排序':
      'Unlock with the real master password to change and save the sort order',
  '排序': 'Sort',
  '排序：{mode}': 'Sort: {mode}',
  '订阅只读视图不可保存排序；请使用真实主密码解锁。':
      'The sort order cannot be saved in the subscription-only view. Unlock with the real master password.',
  '共{count}个订阅': '{count} subscriptions',
  '订阅统计 · 共{count}个订阅': 'Subscription summary · {count} subscriptions',
  '订阅统计 · 共{countLabel}': 'Subscription summary · {countLabel}',
  '订阅统计 · {countLabel}': 'Subscription summary · {countLabel}',
  '共{countLabel}': '{countLabel}',
  '本地加密 · 汇率合计使用离线参考值':
      'Encrypted locally · Totals use offline reference exchange rates',
  '暂无{label}记录': 'No {label} records',
  '可以新增独立订阅，也可以关联到现有账号。':
      'Add a standalone subscription or link it to an existing account.',
  '可以直接新增独立订阅，以后再按需关联账号。':
      'Add a standalone subscription now and link an account later if needed.',
  '编辑订阅': 'Edit subscription',
  '订阅会加密保存在本机；可以独立记录，也可以选择关联账号。这里只记录信息，不会执行付款或取消。':
      'Subscriptions are encrypted and stored on this device. They can be standalone or linked to an account. This app only records information; it does not make payments or cancel services.',
  '关联账号（可选）': 'Linked account (optional)',
  '不关联账号时，将保存为独立订阅。':
      'Without a linked account, this will be saved as a standalone subscription.',
  '不关联账号 · 独立订阅': 'No linked account · Standalone subscription',
  '加密保存订阅': 'Encrypt and save subscription',
  '订阅服务 *': 'Subscription service *',
  '例如：高级会员、云存储、专业版。': 'For example: Premium, cloud storage, or Pro.',
  '请输入订阅服务名称': 'Enter the subscription service name',
  '套餐名称（可选）': 'Plan name (optional)',
  '月度版、家庭版、年度版': 'Monthly, Family, Annual',
  '金额（可选）': 'Amount (optional)',
  '金额格式无效': 'Invalid amount format',
  '金额格式无效，最多保留4位小数':
      'Invalid amount format. Use no more than 4 decimal places.',
  '币种': 'Currency',
  '币种格式无效': 'Invalid currency code',
  '默认币种格式无效': 'Invalid default currency code',
  '计费周期': 'Billing cycle',
  '每月': 'Monthly',
  '每季度': 'Quarterly',
  '每半年': 'Every 6 months',
  '每年': 'Yearly',
  '自定义': 'Custom',
  '周期数量': 'Cycle count',
  '请输入1到120': 'Enter a number from 1 to 120',
  '周期单位': 'Cycle unit',
  '天': 'Day',
  '周': 'Week',
  '月': 'Month',
  '年': 'Year',
  '首次订阅日期': 'First subscription date',
  '下次续费日期（自动）': 'Next renewal date (automatic)',
  '下次续费日期（手动）': 'Next renewal date (manual)',
  '选择首次订阅日期': 'Select first subscription date',
  '选择下次续费日期': 'Select next renewal date',
  '计算结果超过支持的日期范围，已暂设为2300-12-31，请调整首次日期或周期。':
      'The calculated date exceeds the supported range and was temporarily set to Dec 31, 2300. Adjust the first date or billing cycle.',
  '已按首次订阅日期和计费周期自动计算。':
      'Calculated automatically from the first subscription date and billing cycle.',
  '当前为手动日期，可用于记录赠送天数等特殊情况。':
      'This date is manual and can record special cases such as bonus days.',
  '恢复自动': 'Use automatic date',
  '自动续费': 'Auto-renew',
  '仅记录当前设置，不会代替平台执行续费或取消。':
      'This only records the current setting. It does not renew or cancel with the provider.',
  '支付方式（可选）': 'Payment method (optional)',
  '只填写支付宝、微信、银行卡等方式名称，不要填写卡号。':
      'Enter only a payment-method name, such as Alipay, WeChat Pay, or bank card. Do not enter a card number.',
  '本机到期提醒': 'On-device renewal reminder',
  '提醒内容默认隐藏平台、账号与金额。':
      'Reminder content hides the platform, account, and amount by default.',
  '提前提醒': 'Remind me before renewal',
  '续费当天': 'On the renewal date',
  '提前{days}天': '{days} days before',
  '订阅状态': 'Subscription status',
  '取消或恢复请使用订阅卡片上的专用操作。':
      'Use the dedicated action on the subscription card to cancel or restore.',
  '正常': 'Normal',
  '暂停': 'Paused',
  '独立订阅': 'Standalone subscription',
  '关联账号不可用': 'Linked account unavailable',
  '金额未填写': 'Amount not provided',
  '金额待补充': 'Amount needed',
  '删除订阅记录': 'Delete subscription record',
  '折叠卡片': 'Collapse card',
  '展开卡片': 'Expand card',
  '可折叠卡片': 'Collapsible cards',
  '紧凑列表': 'Compact list',
  '首次订阅：': 'First subscribed:',
  '下次续费：': 'Next renewal:',
  '周期：': 'Cycle:',
  '自动续费：': 'Auto-renew:',
  '是': 'Yes',
  '否': 'No',
  '本机提醒：': 'On-device reminder:',
  '已关闭': 'Off',
  '已延后到：': 'Snoozed until:',
  '金额：': 'Amount:',
  '支付方式：': 'Payment method:',
  '本机记录取消：': 'Cancellation recorded:',
  '权益截止：': 'Access ends:',
  '已记录续费：': 'Renewals recorded:',
  '已记录{count}次': 'Recorded {count} times',
  '已续费': 'Renewed',
  '延后提醒': 'Snooze reminder',
  '记录取消': 'Record cancellation',
  '恢复记录': 'Restore record',
  '查看详情': 'View details',
  '操作未保存，请稍后重试。': 'The action was not saved. Try again later.',
  '确认已续费？': 'Mark as renewed?',
  '本机日期将从{date}只推进一个{cycle}周期。此操作不会向平台付款。':
      'The on-device date will advance from {date} by one billing cycle ({cycle}). No payment will be made to the provider.',
  '确认已续费': 'Mark renewed',
  '已推进一期续费日期。': 'The renewal date was advanced by one cycle.',
  '延后本机提醒': 'Snooze on-device reminder',
  '1小时后提醒': 'Remind me in 1 hour',
  '5小时后提醒': 'Remind me in 5 hours',
  '10小时后提醒': 'Remind me in 10 hours',
  '明天提醒': 'Remind me tomorrow',
  '3天后提醒': 'Remind me in 3 days',
  '7天后提醒': 'Remind me in 7 days',
  '选择日期…': 'Choose date…',
  '选择再次提醒日期': 'Select reminder date',
  '已更新本机提醒日期。': 'The on-device reminder date was updated.',
  '已更新本机提醒时间。': 'The on-device reminder time was updated.',
  '记录为已取消': 'Record as canceled',
  '这只会更新本机记录并停止本机提醒，不会在对应平台取消订阅、停止扣费或申请退款。请仍到平台核实。':
      'This updates the on-device record and stops its reminder only. It does not cancel the subscription, stop charges, or request a refund from the provider. Verify the status with the provider.',
  '选择权益截止日': 'Choose access end date',
  '选择权益截止日期': 'Select access end date',
  '仅记录取消': 'Record cancellation only',
  '已在本机记录取消；请继续到平台核实。':
      'Cancellation was recorded on this device. Verify it with the provider.',
  '恢复本机订阅记录？': 'Restore this on-device subscription record?',
  '恢复后状态改为正常并重新启用本机提醒，不会在平台重新订阅。':
      'The status will return to Active and on-device reminders will resume. This does not resubscribe with the provider.',
  '已恢复本机订阅记录。': 'The on-device subscription record was restored.',
  '删除这条订阅记录？': 'Delete this subscription record?',
  '删除后无法在应用内恢复；这不会在对应平台取消订阅或停止扣费。':
      'This cannot be undone in the app. It does not cancel the subscription or stop charges with the provider.',
  '订阅记录已删除。': 'Subscription record deleted.',
  '今天续费': 'Renews today',
  '{days}天后续费': 'Renews in {days} days',
  '已暂停': 'Paused',
  '订阅服务': 'Subscription service',
  '套餐名称': 'Plan name',
  '计费周期数量必须为1到120': 'Billing cycle count must be from 1 to 120',
  '提前提醒天数必须为0到365': 'Reminder lead time must be from 0 to 365 days',
  '默认提醒天数必须为0到365': 'Default reminder lead time must be from 0 to 365 days',
  '下次续费日期不能早于首次订阅日期':
      'The next renewal date cannot be earlier than the first subscription date',
  '权益截止日期不能早于取消日期':
      'The access end date cannot be earlier than the cancellation date',
  '关联账号无效': 'Invalid linked account',
  '订阅记录编号无效': 'Invalid subscription record ID',
  '订阅记录格式无效': 'Invalid subscription record format',
  '订阅状态无效': 'Invalid subscription status',
  '计费周期单位无效': 'Invalid billing cycle unit',
  '计费周期无效': 'Invalid billing cycle',
  '日期格式无效': 'Invalid date format',
  '日期超出支持范围': 'Date is outside the supported range',
  '续费历史格式无效': 'Invalid renewal history format',
  '续费后的日期必须晚于原续费日期':
      'The renewed date must be later than the previous renewal date',
  '已取消订阅需先恢复后再记录续费':
      'Restore a canceled subscription before recording a renewal',
  '只有正常订阅可以延后提醒': 'Only active subscriptions can snooze reminders',
  '近期续费': 'Upcoming renewals',
  '未来30天暂无续费': 'No renewals in the next 30 days',
  '未来{count}项 · 左右滑动查看': '{count} upcoming · Swipe sideways to view',
  '30天明细': '30-day details',
  '最近查看': 'Recently viewed',
  '还没有最近查看的账号': 'No recently viewed accounts yet',
  '继续处理最近访问的账号': 'Continue with recently viewed accounts',
  '全部账号': 'All accounts',
  '暂无': 'None',
  '待换算': 'Conversion needed',
  '汇率基准：{period}116个官方公布日算术平均':
      'Exchange-rate basis: {period}, arithmetic mean across 116 official publication days',
  '2026上半年': 'H1 2026',
  'TWD为114个重合日的官方交叉参考':
      'TWD uses the official cross-rate reference for 114 overlapping days',
  '{count}项未计入': '{count} excluded',
  '运行时离线': 'Offline at runtime',
  '离开应用后立即锁定': 'Lock immediately after leaving the app',
  '{count}秒后自动锁定': 'Lock automatically after {count} seconds',
  '{count}分钟后自动锁定': 'Lock automatically after {count} min',
  '本地加密，{lock}': 'Encrypted locally, {lock}',
  '本地加密 · {lock}': 'Encrypted locally · {lock}',
  '30天续费雷达': '30-day renewal radar',
  '未来30天': 'Next 30 days',
  '项续费': 'renewals',
  '未来30天暂无具体续费日期': 'No specific renewal dates in the next 30 days',
  '最近{date} · {countLabel}': 'Next: {date} · {countLabel}',
  '未来30天有{countLabel}续费，打开30天续费明细':
      '{countLabel} due in the next 30 days. Open 30-day renewal details.',
  '未来30天没有待续费项目': 'No renewals due in the next 30 days',
  '{service}，{account}，{amount}，{renewal}':
      '{service}, {account}, {amount}, {renewal}',
  '{countLabel}已逾期或到期，待确认': '{countLabel} overdue or expired · Review needed',
  '卡坞 · Cardock，{accounts}，{subscriptions}':
      'Cardock, {accounts}, {subscriptions}',
  '搜索账号': 'Search accounts',
  '打开{name}账号详情': 'Open {name} account details',
  '从第一张账号卡开始': 'Start with your first account card',
  '记录平台账号，并关联你的订阅': 'Save a platform account and link its subscriptions',
  '未来 30 天': 'Next 30 days',
  '项待续费': 'renewals due',
  '今日概览': 'Today’s overview',
  '今天': 'Today',
  '近期': 'Upcoming',
  '30天+': '30+ days',
  '{label}，{value}，{detail}': '{label}, {value}, {detail}',
  '{label}，{value}': '{label}, {value}',
  '{label}，{amount}': '{label}, {amount}',
  '本地记录已锁定': 'Local records are locked',
  '请输入本地主密码。应用离开前台后会保持锁定。':
      'Enter the local master password. The app remains locked after it leaves the foreground.',
  '解锁': 'Unlock',
  '使用指纹或人脸解锁': 'Unlock with fingerprint or face',
  '忘记主密码？恢复保险库访问': 'Forgot the master password? Recover vault access',
  '主密码不会被保存或显示；请定期导出加密备份，并与备份密码分开保存。':
      'The master password is never saved or displayed. Export encrypted backups regularly and store the backup password separately.',
  '恢复功能不会显示旧密码，只会在三道密保与本机系统强认证同时通过后重设主密码。':
      'Recovery never reveals the old password. It resets the master password only after all three security answers and strong system authentication on this device succeed.',
  '主密码输入暂缓，约{duration}后可重试；生物识别和已配置的恢复方式仍可使用。':
      'Master-password entry is temporarily blocked. Try again in about {duration}; biometrics and configured recovery methods remain available.',
  '设置本地主密码': 'Set a local master password',
  '创建只属于这台设备的本机加密库':
      'Create an encrypted vault that belongs only to this device',
  '主密码只用于解锁本机数据，不会上传，也无法通过短信或邮箱找回。请设置仅用于本应用的高强度主密码，并妥善离线保存。':
      'The master password unlocks data on this device only. It is never uploaded and cannot be recovered by text message or email. Use a strong password unique to this app and store it safely offline.',
  '主密码': 'Master password',
  '再次输入主密码': 'Re-enter master password',
  '离线生成高强度随机密码': 'Generate a strong random password offline',
  '{assessment} 请立即离线保存并核对；应用不会替你保存或找回。':
      '{assessment} Save it offline now and verify it. The app will not store or recover it for you.',
  '创建加密库': 'Create vault',
  '忘记主密码将无法恢复本地记录。创建后可在设置中启用生物识别并导出加密备份。':
      'Until you set up password recovery, forgetting the master password will prevent you from recovering access to the current vault on this device. After creating the vault, enable biometrics, set up password recovery, and export an encrypted backup in Settings.',
  '两次输入的主密码不一致，请重新输入。': 'The master passwords do not match. Enter them again.',
  '恢复保险库访问': 'Recover vault access',
  '旧主密码不会被显示': 'The old master password will not be shown',
  '三道密保答案与本机指纹或安全级人脸必须同时通过。成功后会生成全新数据密钥并重设主密码。':
      'All three security answers and a fingerprint or secure face authentication on this device must pass. Success creates a new data key and resets the master password.',
  '请输入该问题的完整答案': 'Enter the complete answer to this question',
  '新主密码': 'New master password',
  '再次输入新主密码': 'Re-enter new master password',
  '两次输入的新主密码不一致': 'The new master passwords do not match',
  '两次输入的新主密码不一致。': 'The new master passwords do not match.',
  '验证并重设主密码': 'Verify and reset master password',
  '恢复只适用于本机当前保险库；复制到其他设备的文件不能绕过本机强认证。':
      'Recovery applies only to the current vault on this device. Files copied to another device cannot bypass strong authentication on this device.',
  '无法完成恢复。请重新核对三道答案并通过本机系统强认证。':
      'Recovery could not be completed. Check all three answers and pass strong system authentication on this device.',
  '16–128个字符；建议含大小写字母、数字和符号，或使用本机离线生成。':
      '16–128 characters. Use upper- and lowercase letters, numbers, and symbols, or generate a password offline on this device.',
  '{minimum}到128个字符；输入只在本机验证。':
      '{minimum}–128 characters. Input is verified only on this device.',
  '请输入{minimum}到128个字符的密码': 'Enter a password with {minimum}–128 characters',
  '隐藏主密码': 'Hide master password',
  '显示主密码': 'Show master password',
  '正在打开本机加密库…': 'Opening the local encrypted vault…',
  '无法访问本机加密存储。': 'The encrypted on-device storage could not be accessed.',
  'Cardock 标志': 'Cardock logo',
  'Cardock 标志按钮': 'Cardock logo button',
  '新密码至少需要16个字符；更推荐使用离线生成的随机密码。':
      'Use at least 16 characters. An offline-generated random password is recommended.',
  '密码不能超过128个字符。': 'The password cannot exceed 128 characters.',
  '密码包含常见弱口令或连续数字，请换一组完全不同的内容。':
      'This password contains a common weak phrase or number sequence. Choose something entirely different.',
  '密码重复规律过强，请增加互不相关的字符或使用离线生成。':
      'This password repeats too predictably. Add unrelated characters or generate one offline.',
  '长密码仍需至少包含两类不同字符，避免使用单一重复模式。':
      'Even a long password needs at least two character types. Avoid a single repeated pattern.',
  '16到23字符的密码至少需要三类字符；也可改用更长的离线随机密码。':
      'A 16–23 character password needs at least three character types, or use a longer offline-generated password.',
  '满足本机强密码建议；请离线妥善保管，遗失后无法找回。':
      'Meets the on-device strong-password guidance. Store it safely offline; it cannot be recovered if lost.',
  '可以使用；若用于长期保存重要账号，仍推荐离线生成的随机密码。':
      'Usable. For long-term protection of important accounts, an offline-generated random password is still recommended.',
  'AI工具': 'AI tools',
  '影音娱乐': 'Entertainment',
  '购物': 'Shopping',
  '社交': 'Social',
  '办公': 'Productivity',
  '云服务': 'Cloud services',
  '金融': 'Finance',
  '保险': 'Insurance',
  '通信': 'Telecom',
  '云': 'Cloud',
  '邮箱': 'Email',
  '网址': 'Website',
  '个月': 'months',
  '登录密码内容过长': 'The sign-in password is too long',
  '网址格式无效，仅支持安全的 http/https 地址。':
      'Invalid URL. Only safe http/https URLs are supported.',
  '账号记录格式无效': 'Invalid account record format',
  '账号修改已加密保存。': 'Account changes encrypted and saved.',
};

const Map<String, String> recordsJapaneseTranslations = <String, String>{
  '按账号分类': 'アカウント分類順',
  '当日已续费': '本日は更新済みです',
  '继续续费': '続けて更新',
  '今天已经记录过续费，下次续费日期为{date}。继续会再延后一个计费周期并新增一笔支出，是否继续？':
      '本日はすでに更新を記録しています。次回更新日は{date}です。続けるとさらに1請求期間延長され、支出が1件追加されます。続けますか？',
  '编辑费用记录': '支出記録を編集',
  '只修改这笔费用，不改变订阅金额、计费周期或下次续费日期。':
      'この支出のみを変更します。サブスクリプションの金額・請求周期・次回更新日は変わりません。',
  '删除这笔费用？': 'この支出を削除しますか？',
  '将从统计中删除“{service}”的这笔费用。订阅和下次续费日期保持不变；误点续费造成的日期延后，可在订阅详情中编辑修正。':
      '「{service}」のこの支出を統計から削除します。サブスクリプションと次回更新日は変わりません。誤操作による日付の延長は、サブスクリプションの詳細で修正できます。',
  '费用记录已删除。': '支出を削除しました。',
  '订阅已变化，请重新打开记录。': 'サブスクリプションが変更されました。記録を開き直してください。',
  '忘记密码？恢复保险库访问': 'パスワードを忘れた場合：保管庫へのアクセスを復旧',
  '恢复功能不会显示旧密码，只会在选对三道密保并通过本机系统强认证后重设保险库密码。':
      '復旧で以前のパスワードが表示されることはありません。正しい3つの秘密の質問を選び、この端末の強力なシステム認証に成功した場合にのみ、保管庫のパスワードを再設定します。',
  '两次输入的新密码不一致。': '新しいパスワードが一致しません。',
  '旧密码不会被显示': '以前のパスワードは表示されません',
  '下方会直接显示你设置时选择的三道问题。请填写对应答案，再通过本机指纹或安全级人脸。成功后会生成全新数据密钥并重设密码。':
      '設定時に選んだ3つの質問が下に表示されます。対応する答えを入力し、この端末の指紋認証または安全な顔認証を完了してください。成功すると、新しいデータキーを生成してパスワードを再設定します。',
  '此入口有多组已配置的密保问题。请选择要回答的一组；页面不会标明它对应哪个保险库。':
      'この入口には複数の設定済み質問セットがあります。回答するセットを選択してください。どの保管庫に対応するかは表示されません。',
  '已配置密保问题组': '設定済みの秘密の質問セット',
  '问题组 {number}': '質問セット {number}',
  '新保险库密码': '新しい保管庫パスワード',
  '再次输入新保险库密码': '新しい保管庫パスワードを再入力',
  '验证并重设保险库密码': '認証して保管庫のパスワードを再設定',
  '恢复不会显示旧密码或密保答案，只会在答对当前显示的三道问题并通过本机系统强认证后重设密码。':
      '復旧で以前のパスワードや秘密の質問の答えが表示されることはありません。表示された3つの質問に正しく答え、この端末の強力なシステム認証に成功した場合にのみ、パスワードを再設定します。',
  '请输入{minimum}到{maximum}个字符的密码': '{minimum}～{maximum}文字のパスワードを入力してください',
  '首页': 'ホーム',
  '账号': 'アカウント',
  '订阅': 'サブスクリプション',
  '设置': '設定',
  '安全、隐私与本地保险库': 'セキュリティ、プライバシー、ローカル保管庫',
  '{count}个账号 · 本地加密档案': 'アカウント{count}件 · 端末内で暗号化',
  '{count}个订阅 · 按具体续费日期排列': 'サブスクリプション{count}件 · 更新日順',
  '{countLabel} · 本地加密档案': '{countLabel} · 端末内で暗号化',
  '{countLabel} · 按具体续费日期排列': '{countLabel} · 更新日順',
  '新增账号或订阅': 'アカウントまたはサブスクリプションを追加',
  '新增记录': '記録を追加',
  '选择要保存到本机加密保险库的记录类型。': 'この端末の暗号化保管庫に保存する記録の種類を選択します。',
  '新增账号': 'アカウントを追加',
  '记录登录资料、密码和账号备注': 'ログイン情報、パスワード、アカウントメモを記録',
  '新增订阅': 'サブスクリプションを追加',
  '记录套餐、续费日期和提醒': 'プラン、更新日、リマインダーを記録',
  '立即锁定': '今すぐロック',
  '账号排序偏好未能保存，请稍后重试。': 'アカウントの並び順を保存できませんでした。しばらくしてから再試行してください。',
  '订阅排序偏好未能保存，请稍后重试。': 'サブスクリプションの並び順を保存できませんでした。しばらくしてから再試行してください。',
  '订阅只读视图不能新增记录，请改用真实主密码解锁。':
      'サブスクリプション専用表示では記録を追加できません。実際のマスターパスワードでロックを解除してください。',
  '保存失败，记录未写入。': '保存に失敗しました。記録は書き込まれていません。',
  '已加密保存到本机。': '暗号化してこの端末に保存しました。',
  '修改失败，原账号记录仍保留。': '更新に失敗しました。元のアカウント記録は保持されています。',
  '订阅已加密保存。': 'サブスクリプションを暗号化して保存しました。',
  '保存失败，订阅未写入。': '保存に失敗しました。サブスクリプションは書き込まれていません。',
  '订阅修改已加密保存。': 'サブスクリプションの変更を暗号化して保存しました。',
  '修改失败，订阅未写入。': '更新に失敗しました。サブスクリプションは書き込まれていません。',
  '知道了': '了解',
  '账号信息仍处于加密锁定状态': 'アカウント情報は暗号化されたままロックされています',
  '当前生物识别只解开了独立的订阅只读视图。要查看账号、编辑记录或使用备份，请改用真实主密码。':
      '生体認証で開いたのは独立したサブスクリプション専用表示だけです。アカウントの表示、記録の編集、バックアップの利用には、実際のマスターパスワードを使用してください。',
  '锁定并改用主密码': 'ロックしてマスターパスワードを使用',
  '账号详情': 'アカウントの詳細',
  '编辑账号': 'アカウントを編集',
  '删除账号': 'アカウントを削除',
  '确认删除账号？': 'このアカウントを削除しますか？',
  '删除后无法在应用内恢复。': '削除するとアプリ内では復元できません。',
  '这个账号关联了{count}项订阅，确认后将一并删除，且无法在应用内恢复。':
      'このアカウントには{count}件のサブスクリプションが関連付けられています。確認すると一緒に削除され、アプリ内では復元できません。',
  '关联的{count}项订阅也会一并删除，且无法在应用内恢复。': '関連するサブスクリプション{count}件も削除され、アプリ内では復元できません。',
  '这个账号关联了{countLabel}，确认后将一并删除，且无法在应用内恢复。':
      'このアカウントには{countLabel}が関連付けられています。確認すると一緒に削除され、アプリ内では復元できません。',
  '关联的{countLabel}也会一并删除，且无法在应用内恢复。': '関連する{countLabel}も削除され、アプリ内では復元できません。',
  '确认删除': '削除する',
  '删除失败，原记录仍保留。': '削除に失敗しました。元の記録は保持されています。',
  '账号及关联订阅已删除。': 'アカウントと関連するサブスクリプションを削除しました。',
  '基本资料': '基本情報',
  '补充信息': '追加情報',
  '分类': 'カテゴリ',
  '未分类': '未分類',
  '平台或应用名称 *': 'サービスまたはアプリ名 *',
  '平台或应用名称不能为空': 'サービスまたはアプリ名を入力してください',
  '平台或应用名称过长': 'サービスまたはアプリ名が長すぎます',
  '登录账号': 'ログインID',
  '用户名': 'ユーザー名',
  '绑定手机号': '登録電話番号',
  '绑定邮箱': '登録メールアドレス',
  '登录密码': 'ログインパスワード',
  '官方网址或登录网址': '公式またはログイン用URL',
  '备注': 'メモ',
  '未填写': '未入力',
  '复制{label}': '{label}をコピー',
  '已安全复制{label}，60秒后自动清除。': '{label}を安全にコピーしました。60秒後に自動消去します。',
  '复制失败，未写入剪贴板。': 'コピーできませんでした。クリップボードには書き込まれていません。',
  '安全复制登录密码': 'ログインパスワードを安全にコピー',
  '显示密码30秒': 'パスワードを30秒間表示',
  '隐藏密码': 'パスワードを隠す',
  '显示密码': 'パスワードを表示',
  '使用系统浏览器打开': 'システムブラウザで開く',
  '打开网址失败。': 'URLを開けませんでした。',
  '系统没有可打开该网址的应用。': 'このURLを開けるアプリがありません。',
  '订阅记录（{count}）': 'サブスクリプション記録（{count}）',
  '这个账号暂无订阅记录。': 'このアカウントにはサブスクリプション記録がありません。',
  '{cycle} · {date}续费': '{cycle} · {date}に更新',
  '账号操作': 'アカウント操作',
  '安全信息': 'セキュリティ情報',
  '联系绑定': '登録連絡先',
  '支付方式': '支払い方法',
  '账号卡片，{name}': 'アカウントカード、{name}',
  '账号卡片，{name}，{subscriptions}': 'アカウントカード、{name}、{subscriptions}',
  '{service}，{account}，{amount}，{date}，{status}':
      '{service}、{account}、{amount}、{date}、{status}',
  '{service}，{status}': '{service}、{status}',
  '{name}图标': '{name}のアイコン',
  '平台图标': 'サービスのアイコン',
  '平台品牌预览图标': 'ブランドプレビューのアイコン',
  '无订阅': 'サブスクリプションなし',
  '{count}项订阅': 'サブスクリプション{count}件',
  '关联订阅：暂无': '関連するサブスクリプション：なし',
  '关联订阅：{names}': '関連するサブスクリプション：{names}',
  '关联订阅：{names}，另有{count}项': '関連するサブスクリプション：{names}、ほか{count}件',
  '账号摘要：未填写': 'アカウント概要：未入力',
  '账号摘要：{value}': 'アカウント概要：{value}',
  '{label}：{status}': '{label}：{status}',
  '已填写': '入力済み',
  '按最近使用排序': '最近使用した順',
  '找到{count}个账号': 'アカウントが{count}件見つかりました',
  '找到{countLabel}': '{countLabel}見つかりました',
  '筛选': '絞り込み',
  '选择账号排序方式': 'アカウントの並び順を選択',
  '待处理续费优先': '更新日の近い順',
  '最近添加': '追加日時の新しい順',
  '最早添加': '追加日時の古い順',
  '名称顺序': '名前順',
  '暂无账号记录': 'アカウント記録はありません',
  '每个平台账号会作为一张独立记录卡加密保存在本机。': '各サービスのアカウントは個別の記録カードとして暗号化され、この端末に保存されます。',
  '没有匹配的账号': '一致するアカウントはありません',
  '可以更换搜索词或分类后再试。': '検索語またはカテゴリを変えて再試行してください。',
  '{category}分类，共{count}个账号': '{category}カテゴリ、アカウント{count}件',
  '{category}分类，共{countLabel}': '{category}カテゴリ、{countLabel}',
  '展开{category}分类': '{category}カテゴリを展開',
  '折叠{category}分类': '{category}カテゴリを折りたたむ',
  '{count}个账号': 'アカウント{count}件',
  '搜索平台、用户名、账号、手机号或邮箱': 'サービス、ユーザー名、ログインID、電話番号、メールを検索',
  '全部': 'すべて',
  '不分类': '分類しない',
  '分类（可选）': 'カテゴリ（任意）',
  '自定义分类…': 'カスタムカテゴリ…',
  '自定义分类 *': 'カスタムカテゴリ *',
  '请输入自定义分类': 'カスタムカテゴリを入力してください',
  '支持中文，例如“学习课程”或“开发者服务”。': 'Unicode文字を使用できます。例：「学習コース」「開発者サービス」。',
  '基本信息': '基本情報',
  '唯一必填项；同一平台可以建立多个账号记录。': '必須項目はこれだけです。同じサービスに複数のアカウント記録を作成できます。',
  '请输入平台或应用名称': 'サービスまたはアプリ名を入力してください',
  '账号与补充信息': 'アカウントと追加情報',
  '登录资料优先；手机号、邮箱、网址与备注均可留空': 'ログイン情報を優先します。電話番号、メール、URL、メモは任意です',
  '支持中文；可与登录账号分别记录。': 'Unicode文字を使用でき、ログインIDとは別に記録できます。',
  '支持中文账号；输入法是否学习内容取决于系统设置。':
      'Unicode文字のログインIDを使用できます。入力内容をキーボードが学習するかどうかはシステム設定によります。',
  '登录密码处理': 'ログインパスワードの扱い',
  '保留现有密码': '現在のパスワードを保持',
  '替换密码': 'パスワードを置き換える',
  '清除已保存密码': '保存済みパスワードを削除',
  '保存后将从本机加密库中移除这个账号的登录密码。': '保存すると、このアカウントのログインパスワードが端末内の暗号化保管庫から削除されます。',
  '新登录密码 *': '新しいログインパスワード *',
  '支持中文、空格和任意字符；仅保存在本机加密库。': 'Unicode文字、空白、任意の文字を使用できます。端末内の暗号化保管庫にのみ保存されます。',
  '请输入新登录密码': '新しいログインパスワードを入力してください',
  '支持中文域名，并按输入的原文保存在本机。': '国際化ドメイン名を使用でき、入力した文字列のままこの端末に保存されます。',
  '支持中文、换行和任意字符；请勿填写验证码、恢复码或安全问题答案。':
      'Unicode文字、改行、任意の文字を使用できます。確認コード、復旧コード、秘密の質問の答えは入力しないでください。',
  '这个账号已有订阅': 'このアカウントにはサブスクリプションがある',
  '开启后，账号和首条订阅会一次性加密保存。': '有効にすると、アカウントと最初のサブスクリプションをまとめて暗号化して保存します。',
  '首条订阅信息': '最初のサブスクリプション情報',
  '加密保存': '暗号化して保存',
  '保存修改': '変更を保存',
  '离线品牌预览': 'オフラインブランドプレビュー',
  '离线品牌预览，等待输入平台名称': 'オフラインブランドプレビュー、サービス名の入力待ち',
  '离线品牌预览，{name}': 'オフラインブランドプレビュー、{name}',
  '输入名称后实时匹配，未命中时使用字母标。': '入力に合わせて端末内で照合し、一致しない場合は文字アイコンを使用します。',
  '离线候选（仅在点选后替换输入）': 'オフライン候補（選択した場合のみ入力を置き換えます）',
  '模糊候选，不会自动绑定': 'あいまい一致の候補。自動では関連付けません',
  '记录只会写入本机加密库，不会上传。除平台名称外，其余字段均可留空。':
      '記録は端末内の暗号化保管庫にのみ書き込まれ、アップロードされません。サービス名以外はすべて任意です。',
  '订阅详情': 'サブスクリプションの詳細',
  '这条订阅记录已删除或不可用。': 'このサブスクリプション記録は削除されたか、利用できません。',
  '即将续费': 'まもなく更新',
  '全部订阅': 'すべて',
  '已到期': '期限切れ',
  '已取消': '解約済み',
  '30天内续费': '30日以内に更新',
  '本月订阅续费总额': '今月の更新合計（CNY）',
  '次月续费总额': '来月の更新合計（CNY）',
  '逾期待确认': '期限超過・要確認',
  '共{count}项，点击记录查看完整详情': '{count}件 · 記録を選択すると詳細を表示します',
  '共{countLabel}，点击记录查看完整详情': '{countLabel} · 記録を選択すると詳細を表示します',
  '清除筛选': '絞り込みを解除',
  '选择订阅排序方式': 'サブスクリプションの並び順を選択',
  '使用真实主密码后可修改并保存排序': '実際のマスターパスワードでロックを解除すると、並び順を変更して保存できます',
  '排序': '並び順',
  '排序：{mode}': '並び順：{mode}',
  '订阅只读视图不可保存排序；请使用真实主密码解锁。':
      'サブスクリプション専用表示では並び順を保存できません。実際のマスターパスワードでロックを解除してください。',
  '共{count}个订阅': 'サブスクリプション{count}件',
  '订阅统计 · 共{count}个订阅': 'サブスクリプション概要 · {count}件',
  '订阅统计 · 共{countLabel}': 'サブスクリプション概要 · {countLabel}',
  '订阅统计 · {countLabel}': 'サブスクリプション概要 · {countLabel}',
  '共{countLabel}': '{countLabel}',
  '本地加密 · 汇率合计使用离线参考值': '端末内で暗号化 · 合計にはオフライン参考為替レートを使用',
  '暂无{label}记录': '{label}の記録はありません',
  '可以新增独立订阅，也可以关联到现有账号。': '単独のサブスクリプションを追加するか、既存のアカウントに関連付けられます。',
  '可以直接新增独立订阅，以后再按需关联账号。': 'まず単独のサブスクリプションとして追加し、必要になったら後でアカウントに関連付けられます。',
  '编辑订阅': 'サブスクリプションを編集',
  '订阅会加密保存在本机；可以独立记录，也可以选择关联账号。这里只记录信息，不会执行付款或取消。':
      'サブスクリプションは暗号化してこの端末に保存されます。単独で記録することも、アカウントに関連付けることもできます。このアプリは情報を記録するだけで、支払いや解約は行いません。',
  '关联账号（可选）': '関連アカウント（任意）',
  '不关联账号时，将保存为独立订阅。': 'アカウントに関連付けない場合は、単独のサブスクリプションとして保存されます。',
  '不关联账号 · 独立订阅': '関連アカウントなし · 単独のサブスクリプション',
  '加密保存订阅': '暗号化して保存',
  '订阅服务 *': 'サブスクリプションサービス *',
  '例如：高级会员、云存储、专业版。': '例：プレミアム会員、クラウドストレージ、Proプラン。',
  '请输入订阅服务名称': 'サブスクリプションサービス名を入力してください',
  '套餐名称（可选）': 'プラン名（任意）',
  '月度版、家庭版、年度版': '月額、ファミリー、年額',
  '金额（可选）': '金額（任意）',
  '金额格式无效': '金額の形式が正しくありません',
  '金额格式无效，最多保留4位小数': '金額の形式が正しくありません。小数点以下は4桁までです。',
  '币种': '通貨',
  '币种格式无效': '通貨コードの形式が正しくありません',
  '默认币种格式无效': '既定の通貨コードの形式が正しくありません',
  '计费周期': '請求周期',
  '每月': '毎月',
  '每季度': '3か月ごと',
  '每半年': '6か月ごと',
  '每年': '毎年',
  '自定义': 'カスタム',
  '周期数量': '周期の数',
  '请输入1到120': '1～120の数値を入力してください',
  '周期单位': '周期の単位',
  '天': '日',
  '周': '週',
  '月': '月',
  '年': '年',
  '首次订阅日期': '利用開始日',
  '下次续费日期（自动）': '次回更新日（自動）',
  '下次续费日期（手动）': '次回更新日（手動）',
  '选择首次订阅日期': '利用開始日を選択',
  '选择下次续费日期': '次回更新日を選択',
  '计算结果超过支持的日期范围，已暂设为2300-12-31，请调整首次日期或周期。':
      '計算結果が対応範囲を超えたため、一時的に2300年12月31日に設定しました。利用開始日または周期を調整してください。',
  '已按首次订阅日期和计费周期自动计算。': '利用開始日と請求周期から自動計算しました。',
  '当前为手动日期，可用于记录赠送天数等特殊情况。': '現在は手動設定です。無料期間などの特別な条件を記録できます。',
  '恢复自动': '自動計算に戻す',
  '自动续费': '自動更新',
  '仅记录当前设置，不会代替平台执行续费或取消。': '現在の設定を記録するだけで、サービス側で更新や解約を行うことはありません。',
  '支付方式（可选）': '支払い方法（任意）',
  '只填写支付宝、微信、银行卡等方式名称，不要填写卡号。':
      'Alipay、WeChat Pay、銀行カードなど、支払い方法の名称だけを入力してください。カード番号は入力しないでください。',
  '本机到期提醒': '端末内の更新リマインダー',
  '提醒内容默认隐藏平台、账号与金额。': 'リマインダーでは、サービス、アカウント、金額を初期状態で非表示にします。',
  '提前提醒': '事前通知',
  '续费当天': '更新当日',
  '提前{days}天': '{days}日前',
  '订阅状态': 'サブスクリプションの状態',
  '取消或恢复请使用订阅卡片上的专用操作。': '解約または再開には、サブスクリプションカードの専用操作を使用してください。',
  '正常': '正常',
  '暂停': '一時停止',
  '独立订阅': '単独のサブスクリプション',
  '关联账号不可用': '関連アカウントを利用できません',
  '金额未填写': '金額未入力',
  '金额待补充': '金額を追加してください',
  '删除订阅记录': 'サブスクリプション記録を削除',
  '折叠卡片': 'カードを折りたたむ',
  '展开卡片': 'カードを展開',
  '可折叠卡片': '折りたたみカード',
  '紧凑列表': 'コンパクトリスト',
  '首次订阅：': '利用開始日：',
  '下次续费：': '次回更新：',
  '周期：': '周期：',
  '自动续费：': '自動更新：',
  '是': 'はい',
  '否': 'いいえ',
  '本机提醒：': '端末内リマインダー：',
  '已关闭': 'オフ',
  '已延后到：': '再通知日：',
  '金额：': '金額：',
  '支付方式：': '支払い方法：',
  '本机记录取消：': '解約記録日：',
  '权益截止：': '利用終了日：',
  '已记录续费：': '更新記録：',
  '已记录{count}次': '{count}回記録済み',
  '已续费': '更新済み',
  '延后提醒': 'リマインダーを延期',
  '记录取消': '解約を記録',
  '恢复记录': '記録を再開',
  '查看详情': '詳細を見る',
  '操作未保存，请稍后重试。': '操作を保存できませんでした。しばらくしてから再試行してください。',
  '确认已续费？': '更新済みとして記録しますか？',
  '本机日期将从{date}只推进一个{cycle}周期。此操作不会向平台付款。':
      '端末内の更新日を{date}から1回分進めます（更新周期：{cycle}）。サービスへの支払いは行いません。',
  '确认已续费': '更新済みとして記録',
  '已推进一期续费日期。': '更新日を1周期分進めました。',
  '延后本机提醒': '端末内リマインダーを延期',
  '1小时后提醒': '1時間後に通知',
  '5小时后提醒': '5時間後に通知',
  '10小时后提醒': '10時間後に通知',
  '明天提醒': '明日通知',
  '3天后提醒': '3日後に通知',
  '7天后提醒': '7日後に通知',
  '选择日期…': '日付を選択…',
  '选择再次提醒日期': '再通知日を選択',
  '已更新本机提醒日期。': '端末内リマインダーの日付を更新しました。',
  '已更新本机提醒时间。': '端末内リマインダーの時刻を更新しました。',
  '记录为已取消': '解約済みとして記録',
  '这只会更新本机记录并停止本机提醒，不会在对应平台取消订阅、停止扣费或申请退款。请仍到平台核实。':
      '端末内の記録を更新し、端末内リマインダーを停止するだけです。サービス側での解約、請求停止、返金申請は行いません。サービス側でも確認してください。',
  '选择权益截止日': '利用終了日を選択',
  '选择权益截止日期': '利用終了日を選択',
  '仅记录取消': '解約だけを記録',
  '已在本机记录取消；请继续到平台核实。': 'この端末に解約を記録しました。サービス側でも確認してください。',
  '恢复本机订阅记录？': '端末内のサブスクリプション記録を再開しますか？',
  '恢复后状态改为正常并重新启用本机提醒，不会在平台重新订阅。':
      '状態を有効に戻して端末内リマインダーを再開します。サービス側で再契約することはありません。',
  '已恢复本机订阅记录。': '端末内のサブスクリプション記録を再開しました。',
  '删除这条订阅记录？': 'このサブスクリプション記録を削除しますか？',
  '删除后无法在应用内恢复；这不会在对应平台取消订阅或停止扣费。': '削除するとアプリ内では復元できません。サービス側での解約や請求停止は行いません。',
  '订阅记录已删除。': 'サブスクリプション記録を削除しました。',
  '今天续费': '本日更新',
  '{days}天后续费': '{days}日後に更新',
  '已暂停': '一時停止',
  '订阅服务': 'サブスクリプションサービス',
  '套餐名称': 'プラン名',
  '计费周期数量必须为1到120': '請求周期の数は1～120で指定してください',
  '提前提醒天数必须为0到365': '事前通知の日数は0～365で指定してください',
  '默认提醒天数必须为0到365': '既定の通知日数は0～365で指定してください',
  '下次续费日期不能早于首次订阅日期': '次回更新日は利用開始日より前に設定できません',
  '权益截止日期不能早于取消日期': '利用終了日は解約記録日より前に設定できません',
  '关联账号无效': '関連アカウントが無効です',
  '订阅记录编号无效': 'サブスクリプション記録IDが無効です',
  '订阅记录格式无效': 'サブスクリプション記録の形式が無効です',
  '订阅状态无效': 'サブスクリプションの状態が無効です',
  '计费周期单位无效': '請求周期の単位が無効です',
  '计费周期无效': '請求周期が無効です',
  '日期格式无效': '日付の形式が無効です',
  '日期超出支持范围': '日付が対応範囲外です',
  '续费历史格式无效': '更新履歴の形式が無効です',
  '续费后的日期必须晚于原续费日期': '更新後の日付は以前の更新日より後である必要があります',
  '已取消订阅需先恢复后再记录续费': '解約済みのサブスクリプションは、再開してから更新を記録してください',
  '只有正常订阅可以延后提醒': 'リマインダーを延期できるのは有効なサブスクリプションだけです',
  '近期续费': '近日中の更新',
  '未来30天暂无续费': '今後30日間の更新はありません',
  '未来{count}项 · 左右滑动查看': '今後{count}件 · 横にスワイプして表示',
  '30天明细': '30日間の詳細',
  '最近查看': '最近表示した項目',
  '还没有最近查看的账号': '最近表示したアカウントはありません',
  '继续处理最近访问的账号': '最近表示したアカウントを続けて確認',
  '全部账号': 'すべてのアカウント',
  '暂无': 'なし',
  '待换算': '換算待ち',
  '汇率基准：{period}116个官方公布日算术平均': '為替レート基準：{period}、公式公表日116日分の算術平均',
  '2026上半年': '2026年上半期',
  'TWD为114个重合日的官方交叉参考': 'TWDは重複する114日分の公式クロスレートを参照',
  '{count}项未计入': '{count}件は未集計',
  '运行时离线': '実行時はオフライン',
  '离开应用后立即锁定': 'アプリを離れるとすぐにロック',
  '{count}秒后自动锁定': '{count}秒後に自動ロック',
  '{count}分钟后自动锁定': '{count}分後に自動ロック',
  '本地加密，{lock}': '端末内で暗号化、{lock}',
  '本地加密 · {lock}': '端末内で暗号化 · {lock}',
  '30天续费雷达': '30日間の更新レーダー',
  '未来30天': '今後30日間',
  '项续费': '件更新',
  '未来30天暂无具体续费日期': '今後30日間に具体的な更新日はありません',
  '最近{date} · {countLabel}': '次回：{date} · {countLabel}',
  '未来30天有{countLabel}续费，打开30天续费明细': '今後30日間に{countLabel}が更新予定です。30日間の詳細を開きます。',
  '未来30天没有待续费项目': '今後30日間に更新予定の項目はありません',
  '{service}，{account}，{amount}，{renewal}':
      '{service}、{account}、{amount}、{renewal}',
  '{countLabel}已逾期或到期，待确认': '{countLabel}が期限超過または期限切れです。確認してください',
  '卡坞 · Cardock，{accounts}，{subscriptions}':
      'Cardock、{accounts}、{subscriptions}',
  '搜索账号': 'アカウントを検索',
  '打开{name}账号详情': '{name}のアカウント詳細を開く',
  '从第一张账号卡开始': '最初のアカウントカードを作成',
  '记录平台账号，并关联你的订阅': 'サービスのアカウントを記録し、サブスクリプションを関連付けます',
  '未来 30 天': '今後30日間',
  '项待续费': '件更新予定',
  '今日概览': '今日の概要',
  '今天': '今日',
  '近期': '近日',
  '30天+': '30日以上',
  '{label}，{value}，{detail}': '{label}、{value}、{detail}',
  '{label}，{value}': '{label}、{value}',
  '{label}，{amount}': '{label}、{amount}',
  '本地记录已锁定': '端末内の記録はロックされています',
  '请输入本地主密码。应用离开前台后会保持锁定。': 'ローカルマスターパスワードを入力してください。アプリが前面から離れた後もロック状態を維持します。',
  '解锁': 'ロックを解除',
  '使用指纹或人脸解锁': '指紋または顔認証でロック解除',
  '忘记主密码？恢复保险库访问': 'マスターパスワードを忘れた場合：保管庫へのアクセスを復旧',
  '主密码不会被保存或显示；请定期导出加密备份，并与备份密码分开保存。':
      'マスターパスワードは保存も表示もされません。暗号化バックアップを定期的に書き出し、バックアップ用パスワードとは別に保管してください。',
  '恢复功能不会显示旧密码，只会在三道密保与本机系统强认证同时通过后重设主密码。':
      '復旧機能は以前のパスワードを表示しません。3つの秘密の質問とこの端末の強固なシステム認証の両方に成功した場合のみ、マスターパスワードを再設定します。',
  '主密码输入暂缓，约{duration}后可重试；生物识别和已配置的恢复方式仍可使用。':
      'マスターパスワードの入力は一時的に停止されています。約{duration}後に再試行できます。生体認証と設定済みの復旧方法は引き続き利用できます。',
  '设置本地主密码': 'ローカルマスターパスワードを設定',
  '创建只属于这台设备的本机加密库': 'この端末専用の暗号化保管庫を作成します',
  '主密码只用于解锁本机数据，不会上传，也无法通过短信或邮箱找回。请设置仅用于本应用的高强度主密码，并妥善离线保存。':
      'マスターパスワードはこの端末のデータを開くためだけに使用され、アップロードされません。SMSやメールで復元することもできません。このアプリ専用の強力なパスワードを設定し、安全にオフライン保管してください。',
  '主密码': 'マスターパスワード',
  '再次输入主密码': 'マスターパスワードを再入力',
  '离线生成高强度随机密码': '強力なランダムパスワードをオフライン生成',
  '{assessment} 请立即离线保存并核对；应用不会替你保存或找回。':
      '{assessment} 今すぐオフラインで保存し、内容を確認してください。アプリは保存も復元も行いません。',
  '创建加密库': '保管庫を作成',
  '忘记主密码将无法恢复本地记录。创建后可在设置中启用生物识别并导出加密备份。':
      'パスワード復旧を設定する前にマスターパスワードを忘れると、この端末の現在の保管庫へのアクセスを復旧できません。保管庫の作成後、設定で生体認証とパスワード復旧を有効にし、暗号化バックアップを書き出してください。',
  '两次输入的主密码不一致，请重新输入。': 'マスターパスワードが一致しません。もう一度入力してください。',
  '恢复保险库访问': '保管庫へのアクセスを復旧',
  '旧主密码不会被显示': '以前のマスターパスワードは表示されません',
  '三道密保答案与本机指纹或安全级人脸必须同时通过。成功后会生成全新数据密钥并重设主密码。':
      '3つの秘密の質問と、この端末の指紋または安全な顔認証の両方に成功する必要があります。成功すると新しいデータキーを生成し、マスターパスワードを再設定します。',
  '请输入该问题的完整答案': 'この質問の答えをすべて入力してください',
  '新主密码': '新しいマスターパスワード',
  '再次输入新主密码': '新しいマスターパスワードを再入力',
  '两次输入的新主密码不一致': '新しいマスターパスワードが一致しません',
  '两次输入的新主密码不一致。': '新しいマスターパスワードが一致しません。',
  '验证并重设主密码': '認証してマスターパスワードを再設定',
  '恢复只适用于本机当前保险库；复制到其他设备的文件不能绕过本机强认证。':
      '復旧はこの端末の現在の保管庫にのみ適用されます。別の端末にコピーしたファイルで、この端末の強固な認証を回避することはできません。',
  '无法完成恢复。请重新核对三道答案并通过本机系统强认证。':
      '復旧を完了できませんでした。3つの答えを再確認し、この端末の強固なシステム認証を完了してください。',
  '16–128个字符；建议含大小写字母、数字和符号，或使用本机离线生成。':
      '16～128文字。英大文字・小文字、数字、記号を含めるか、この端末でオフライン生成してください。',
  '{minimum}到128个字符；输入只在本机验证。': '{minimum}～128文字。入力内容はこの端末内でのみ検証されます。',
  '请输入{minimum}到128个字符的密码': '{minimum}～128文字のパスワードを入力してください',
  '隐藏主密码': 'マスターパスワードを隠す',
  '显示主密码': 'マスターパスワードを表示',
  '正在打开本机加密库…': '端末内の暗号化保管庫を開いています…',
  '无法访问本机加密存储。': '端末内の暗号化ストレージにアクセスできませんでした。',
  'Cardock 标志': 'Cardockロゴ',
  'Cardock 标志按钮': 'Cardockロゴボタン',
  '新密码至少需要16个字符；更推荐使用离线生成的随机密码。':
      '新しいパスワードは16文字以上にしてください。オフライン生成のランダムパスワードを推奨します。',
  '密码不能超过128个字符。': 'パスワードは128文字以内にしてください。',
  '密码包含常见弱口令或连续数字，请换一组完全不同的内容。':
      'よく使われる弱い語句または連続した数字が含まれています。まったく異なる内容にしてください。',
  '密码重复规律过强，请增加互不相关的字符或使用离线生成。': '繰り返しの規則性が強すぎます。無関係な文字を加えるか、オフラインで生成してください。',
  '长密码仍需至少包含两类不同字符，避免使用单一重复模式。': '長いパスワードでも2種類以上の文字が必要です。同じパターンの繰り返しは避けてください。',
  '16到23字符的密码至少需要三类字符；也可改用更长的离线随机密码。':
      '16～23文字の場合は3種類以上の文字が必要です。より長いオフライン生成パスワードも利用できます。',
  '满足本机强密码建议；请离线妥善保管，遗失后无法找回。':
      '端末内の強力なパスワード推奨条件を満たしています。紛失すると復旧できないため、オフラインで安全に保管してください。',
  '可以使用；若用于长期保存重要账号，仍推荐离线生成的随机密码。':
      '使用できます。重要なアカウントを長期間保管する場合は、オフライン生成のランダムパスワードを推奨します。',
  'AI工具': 'AIツール',
  '影音娱乐': '動画・音楽',
  '购物': 'ショッピング',
  '社交': 'ソーシャル',
  '办公': '仕事効率化',
  '云服务': 'クラウドサービス',
  '金融': '金融',
  '保险': '保険',
  '通信': '通信',
  '云': 'クラウド',
  '邮箱': 'メール',
  '网址': 'URL',
  '个月': 'か月',
  '登录密码内容过长': 'ログインパスワードが長すぎます',
  '网址格式无效，仅支持安全的 http/https 地址。': 'URLの形式が正しくありません。安全なhttp/https URLのみ使用できます。',
  '账号记录格式无效': 'アカウント記録の形式が無効です',
  '账号修改已加密保存。': 'アカウントの変更を暗号化して保存しました。',
};
