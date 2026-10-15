const stage1EnglishTranslations = <String, String>{
  '请选择下一步。找回访问不会显示旧密码；删除本机数据无法撤销。':
      'Choose what to do next. Recovering access will not show the old password; deleting local data cannot be undone.',
  '通过密保重设保险库密码': 'Reset a vault password with security questions',
  '旧密码不会被找回或显示；必须选对预设的三道问题，并通过本机指纹或安全级人脸。':
      'The old password will not be retrieved or shown. You must select the correct three preset questions and pass fingerprint or secure face authentication on this device.',
  '当前入口没有可用的密码恢复配置':
      'No password-recovery configuration is available from this entry',
  '选择密保找回访问': 'Recover access with security questions',
  '删除本机数据并重新开始': 'Delete local data and start over',
  '之后可创建新保险库，再从外部 .asmbackup 文件恢复其中的真实库记录；独立诱饵库不会随真实库备份恢复，且仍需对应备份密码。':
      'Afterward, create a new vault and restore the real-vault records contained in an external .asmbackup file. The separate decoy vault is not restored from a real-vault backup, and the corresponding backup password is still required.',
  '真实库、诱饵库、回收站、本地恢复凭据、自动备份配置和临时录入资料都会清除。外部备份不会删除。':
      'The real vault, decoy vault, trash, local recovery credentials, automatic backup configuration, and temporary input data will all be erased. External backups will not be deleted.',
  '此操作不会找回旧密码，也不会解密旧数据；没有可用备份的数据将永久丢失。外部 .asmbackup 文件和合法完整版授权会保留。恢复备份仍需对应备份密码。':
      'This operation cannot retrieve the old password or decrypt old data. Data without a usable backup will be lost permanently. External .asmbackup files and valid full-version entitlement will be retained. Restoring a backup still requires its backup password.',
  '保险库密码恢复准备': 'Vault password recovery readiness',
  '真实库和诱饵库均已配置恢复': 'Recovery configured for both real and decoy vaults',
  '仅真实库已配置恢复': 'Recovery configured for the real vault only',
  '仅诱饵库已配置恢复': 'Recovery configured for the decoy vault only',
  "自动备份周期": "Automatic backup interval",
  "7 天（每周）": "7 days (weekly)",
  "15 天（半个月）": "15 days (half a month)",
  "30 天（一个月）": "30 days (one month)",
  "下次自动备份": "Next automatic backup",
  "备份周期已保存。": "Backup interval saved.",
  "备份周期保存失败，原设置保持不变。":
      "Could not save the interval. Your previous setting is unchanged.",
  "到期后完整解锁时自动备份，即使内容相同也会生成。仅保留最近 3 份；应用自动校验新备份，成功后自动删除最旧文件，无需手动验证。":
      "After the interval is due, back up when fully unlocked, even if the content is unchanged. Keep only the latest 3 backups. The app checks each new backup and then deletes the oldest automatically. No manual verification is needed.",
  "周期从最近一次成功的自动备份起计算；选择后自动保存。":
      "The interval starts from the last successful automatic backup. Changes are saved automatically.",
  "新备份已验证，但旧文件删除失败；将自动重试清理。":
      "The new backup is verified, but old files could not be deleted. Cleanup will retry automatically.",
  "旧自动备份清理未完成，请到数据安全与备份检查。":
      "Old automatic backups could not be cleaned up. Check Data safety and backup.",
  "没有可用的自动备份，请到数据安全与备份检查。":
      "No automatic backup is available. Check Data safety and backup.",
  "自动备份已超过计划时间，请到数据安全与备份检查。":
      "The scheduled backup is overdue. Check Data safety and backup.",
  '数据安全与备份': 'Data safety and backup',
  '回收站': 'Trash',
  '搜索回收站': 'Search trash',
  '回收站中没有匹配记录。': 'No matching records in trash.',
  '保留 30 天，可恢复原记录与关联关系': 'Keep for 30 days; restore records and links',
  '记录保留 30 天，到期后在完整解锁时自动清理。恢复会保留原账期和状态。':
      'Records stay for 30 days. Expired records are cleared after full unlock. Restoring keeps the original billing dates and status.',
  '删除：{date} · 剩余 {days} 天': 'Deleted: {date} · {days} days left',
  '恢复此项': 'Restore this item',
  '恢复整个删除组合': 'Restore deletion group',
  '永久删除': 'Delete permanently',
  '清空回收站': 'Empty trash',
  '输入“清空回收站”': 'Type “清空回收站”',
  '永久删除回收站记录？': 'Permanently delete trash records?',
  '此操作无法撤销。已记录的历史费用仍会保留；外部备份文件不受影响。':
      'This cannot be undone. Recorded expenses and external backup files are retained.',
  '当前保险库密码': 'Current vault password',
  '操作完成。': 'Operation completed.',
  '操作未完成，原数据保持不变。': 'Operation not completed. Original data is unchanged.',
  '请完整解锁当前保险库。': 'Fully unlock the current vault.',
  '请完整解锁真实保险库。': 'Fully unlock the primary vault.',
  '移入回收站？': 'Move to trash?',
  '移入回收站': 'Move to trash',
  '记录将在回收站保留 30 天，可恢复。这不会注销对应平台账号。':
      'Keep in trash for 30 days with restore available. This does not close the account on its platform.',
  '这个账号关联了{countLabel}，将一起移入回收站保留 30 天。历史费用保留；这不会在对应平台取消订阅或停止扣费。':
      'The linked {countLabel} will also stay in trash for 30 days. Historical expenses remain. This does not cancel subscriptions or stop charges on the platform.',
  '关联的{countLabel}也将移入回收站保留 30 天。历史费用保留；这不会在对应平台取消订阅或停止扣费。':
      'The linked {countLabel} will also stay in trash for 30 days. Historical expenses remain. This does not cancel subscriptions or stop charges on the platform.',
  '记录将在回收站保留 30 天；这不会在对应平台取消订阅或停止扣费。':
      'Keep in trash for 30 days. This does not cancel the subscription or stop charges on its platform.',
  '账号及关联订阅已移入回收站。': 'Account and linked subscriptions moved to trash.',
  '订阅记录已移入回收站。': 'Subscription moved to trash.',
  '移入回收站失败，原记录保持不变。':
      'Could not move to trash. Original records are unchanged.',
  '恢复失败，回收站记录保持不变。': 'Restore failed. Trash records are unchanged.',
  '无法恢复，请先恢复关联账号或选择恢复整个删除组合。':
      'Restore the linked account first, or restore the entire deletion group.',
  '永久删除失败，回收站记录保持不变。':
      'Permanent deletion failed. Trash records are unchanged.',
  '回收站自动清理未完成，可稍后重试。':
      'Automatic trash cleanup did not finish. Try again later.',
  '回收站中有相似记录': 'Similar records are in trash',
  '可以先到回收站恢复原记录，也可以继续新增。回收站记录不会阻止本次保存。':
      'Restore the original from trash, or continue creating a new record. Trash records do not block this save.',
  '查看回收站': 'View trash',
  '继续新增': 'Create another',
  '回收站中有相似记录，可先恢复；这些记录不会阻止本次导入。':
      'Similar records are in trash and can be restored. They do not block this import.',
  '导出可读数据': 'Export readable data',
  '加密备份用于Cardock恢复。CSV / JSON 为明文，可被其他程序读取，不能直接恢复保险库。':
      'Encrypted backups restore Cardock. CSV / JSON is plaintext readable by other apps and cannot restore a vault directly.',
  '导出格式': 'Export format',
  '包含回收站记录': 'Include trash records',
  '包含当前账号密码': 'Include current account passwords',
  '包含当前账号密码？': 'Include current account passwords?',
  '文件包含明文密码，任何取得文件的人都能读取。密码变更历史仅包含日期，不包含旧密码。':
      'Anyone with this file can read its plaintext passwords. Password history contains dates only, never previous passwords.',
  '账号 {accounts} · 订阅 {subscriptions} · 回收站 {trash}':
      'Accounts {accounts} · Subscriptions {subscriptions} · Trash {trash}',
  '包含明文备注。历史费用会保留，关联记录可能已被删除。':
      'Includes plaintext notes. Historical expenses remain; linked records may have been deleted.',
  '验证密码并导出': 'Verify password and export',
  '已导出 {format} · {time} · 包含密码：{passwords}。文件为明文，请妥善保存。':
      'Exported {format} · {time} · Passwords included: {passwords}. This is plaintext. Store it securely.',
  '导出已取消或未完成。': 'Export cancelled or incomplete.',
  '可读导出未完成，请检查保存位置。':
      'Readable export did not finish. Check the save location.',
  'CSV / JSON 为明文，默认不含账号密码。':
      'CSV / JSON is plaintext; passwords are excluded by default.',
  '最近加密备份': 'Latest encrypted backup',
  '手动备份': 'Manual backup',
  '自动备份': 'Automatic backup',
  '最近完整验证': 'Latest full verification',
  '已启用，仅完整解锁真实库时工作': 'Enabled; runs only with the primary vault fully unlocked',
  '未启用': 'Not enabled',
  '目录授权': 'Folder access',
  '授权有效': 'Access granted',
  '目录权限失效': 'Folder access expired',
  '未选择或待检查': 'Not selected or awaiting check',
  '已验证且仍存在的自动备份': 'Verified automatic backups currently accessible',
  '{count} 份 · 保留 {keep} 份': '{count} files · Keep {keep}',
  '{count} 份': '{count} files',
  '待备份更改': 'Changes awaiting backup',
  '没有待处理更改': 'No pending changes',
  '最近备份失败': 'Latest backup failure',
  '账号 {accounts} · 订阅 {subscriptions} · 最近到期 {time}':
      'Accounts {accounts} · Subscriptions {subscriptions} · Next expiry {time}',
  '主密码恢复准备': 'Master password recovery readiness',
  '已配置恢复方式': 'Recovery method configured',
  '尚未配置恢复方式': 'Recovery method not configured',
  '下次配置保留份数': 'Files to keep in the next configuration',
  '选择或更换备份目录与密码': 'Set or change backup folder and password',
  '先生成并验证一份新备份，再保存配置。':
      'Create and verify a new backup before saving configuration.',
  '立即自动备份': 'Back up now',
  '使用本机已配置的目录和独立备份密码':
      'Use the configured folder and independent backup password',
  '关闭自动备份': 'Turn off automatic backup',
  '关闭自动备份？': 'Turn off automatic backup?',
  '保留外部文件，可稍后重新配置。': 'External files are retained. Configure again later.',
  '已生成的外部备份不会删除。': 'Existing external backups will not be deleted.',
  '验证已有备份': 'Verify an existing backup',
  '重新选择文件并完整解密，不改变本机数据。':
      'Select a file and fully decrypt it without changing local data.',
  '恢复前仍需当前主密码和明确确认。':
      'Restoring still requires the current master password and explicit confirmation.',
  '数据安全帮助': 'Data safety help',
  '备份、验证、恢复与重建说明': 'Backup, verification, restore and rebuild guidance',
  '加密备份需要对应备份密码。建议将已验证文件保存在另一处。可读导出包含明文备注。回收站保留 30 天。忘记主密码时，可在锁屏使用已配置恢复方式，或受控删除本机数据后新建保险库，再恢复自己的备份。':
      'Encrypted backups need their backup password. Keep a verified copy in a second location. Readable exports include plaintext notes. Trash retains records for 30 days. If you forget the master password, use configured recovery from the lock screen, or confirm local deletion, create a vault, and restore your backup.',
  '应用 {version} · 加密备份格式 v2 · 可读导出格式 v1':
      'App {version} · Encrypted backup v2 · Readable export v1',
  '手动备份的时间是历史验证记录；请重新选择文件检查当前可用性。':
      'Manual backup timestamps record past verification. Select the file again to check current availability.',
  '.asmbackup · 独立备份密码': '.asmbackup · Independent backup password',
  '尚无记录': 'No record yet',
  '自动备份独立密码': 'Independent automatic backup password',
  '密码仅由本机真实保险库加密保护，不进入备份文件。忘记密码无法恢复旧文件；更换密码只影响以后生成的备份。':
      'The password is encrypted by the local primary vault and excluded from backup payloads. Forgotten passwords cannot recover old files. Changes affect future backups only.',
  '再次输入备份密码': 'Enter backup password again',
  '两次备份密码不一致。': 'Backup passwords do not match.',
  '首份备份已重新读取并完整验证，自动备份已启用。':
      'The first backup was read back and fully verified. Automatic backup is enabled.',
  '自动备份已完整验证。': 'Automatic backup fully verified.',
  '无法取得目录授权。': 'Could not obtain folder access.',
  '目录权限失效，请重新选择目录。': 'Folder access expired. Select the folder again.',
  '备份目录或文件不存在。': 'The backup folder or file is missing.',
  '保存位置空间不足。': 'The save location is out of space.',
  '文件提供方拒绝操作。': 'The document provider refused the operation.',
  '文件写入后无法重新读取。': 'The written file could not be read back.',
  '文件完整解密验证失败，旧有效备份已保留。':
      'Full decryption verification failed. Previous valid backups are retained.',
  '设备备份配置无法解密或版本不受支持，自动备份已停用。':
      'Device backup settings are unreadable or unsupported. Automatic backup is disabled.',
  '写入中断，旧有效备份已保留。':
      'Writing was interrupted. Previous valid backups are retained.',
  '备份未完成，请检查保存位置后重试。': 'Backup incomplete. Check the location and retry.',
  '备份已完整验证，本机数据未改变。': 'Backup fully verified. Local data is unchanged.',
  '备份目录权限失效，请到数据安全与备份重新授权。':
      'Backup folder access expired. Grant access again in Data safety and backup.',
  '自动备份连续失败，请到数据安全与备份检查。':
      'Automatic backup has failed repeatedly. Check Data safety and backup.',
  '更改已等待备份超过一天，请到数据安全与备份检查。':
      'Changes have awaited backup for over a day. Check Data safety and backup.',
  '尚无已验证的加密备份，建议到数据安全与备份准备。':
      'No verified encrypted backup yet. Prepare one in Data safety and backup.',
  '超过 7 天未验证备份，建议检查备份可用性。':
      'No backup verification in over 7 days. Check that your backup is usable.',
  '稍后提醒': 'Remind me later',
  '忘记密码或重新开始': 'Forgot password or start over',
  '已配置恢复方式：可使用原有恢复入口验证并重设主密码。':
      'A recovery method is configured. Use the existing recovery entry to verify and reset the master password.',
  '使用已配置的恢复方式': 'Use configured recovery',
  '使用已有加密备份：先创建新的保险库，再在设置中验证并恢复备份。需要对应备份密码。':
      'To use an encrypted backup: create a new vault, then verify and restore the backup in Settings. Its backup password is required.',
  '删除本机Cardock数据并重新开始': 'Delete local Cardock data and start again',
  '删除本机Cardock数据并重新开始：真实库、诱饵库、回收站、本地恢复凭据、自动备份配置和临时录入资料都会清除。外部备份不会删除。':
      'Start again by deleting local data: primary vault, decoy vault, trash, local recovery credentials, automatic backup settings and temporary input. External backups are retained.',
  'Cardock不能找回忘记的主密码。重建不会解密旧数据；没有可用备份的数据将永久丢失。外部 .asmbackup 文件和合法完整版授权会保留。恢复备份仍需对应备份密码。':
      'Cardock cannot retrieve a forgotten master password. Rebuilding does not decrypt old data. Data without a usable backup will be lost permanently. External .asmbackup files and valid full-version entitlement remain. Restoring still requires the backup password.',
  '了解后验证设备身份': 'Continue to device verification',
  '验证设备身份': 'Verify device identity',
  '确认删除本机Cardock数据': 'Confirm deletion of local Cardock data',
  '设备未设置系统锁屏凭据。必须完成双重文字确认，并按住按钮至少 3 秒。':
      'No system screen-lock credential is set. Enter both confirmation phrases and hold the button for at least 3 seconds.',
  '输入“删除本机Cardock数据”': 'Type “删除本机Cardock数据”',
  '输入“我理解没有备份将无法恢复”': 'Type “我理解没有备份将无法恢复”',
  '按住至少 3 秒': 'Hold for at least 3 seconds',
  '长按确认已完成': 'Hold confirmation completed',
  '最终确认：删除本机数据？': 'Final confirmation: delete local data?',
  '删除后无法撤销。外部备份文件不会删除。':
      'Deletion cannot be undone. External backup files are retained.',
  '删除并重新开始': 'Delete and start again',
  '正在重建，请稍候…': 'Rebuilding, please wait…',
  '重建未完成；若清理已开始，请重新打开应用继续完成。':
      'Rebuild did not finish. If cleanup has started, reopen the app to complete it.',
  '系统身份验证未完成。': 'System identity verification did not complete.',
};

const stage1JapaneseTranslations = <String, String>{
  '请选择下一步。找回访问不会显示旧密码；删除本机数据无法撤销。':
      '次の操作を選んでください。アクセスの復旧で以前のパスワードが表示されることはなく、本機データの削除は取り消せません。',
  '通过密保重设保险库密码': '秘密の質問で保管庫のパスワードを再設定',
  '旧密码不会被找回或显示；必须选对预设的三道问题，并通过本机指纹或安全级人脸。':
      '以前のパスワードを取得または表示することはできません。設定済みの正しい3つの質問を選び、この端末の指紋認証または安全な顔認証を完了する必要があります。',
  '当前入口没有可用的密码恢复配置': 'この入口から利用できるパスワード復旧設定はありません',
  '选择密保找回访问': '秘密の質問でアクセスを復旧',
  '删除本机数据并重新开始': '本機データを削除してやり直す',
  '之后可创建新保险库，再从外部 .asmbackup 文件恢复其中的真实库记录；独立诱饵库不会随真实库备份恢复，且仍需对应备份密码。':
      'その後、新しい保管庫を作成し、外部の .asmbackup ファイルに含まれる実際の保管庫の記録を復元できます。独立したおとり保管庫は実際の保管庫のバックアップから復元されず、対応するバックアップパスワードも必要です。',
  '真实库、诱饵库、回收站、本地恢复凭据、自动备份配置和临时录入资料都会清除。外部备份不会删除。':
      '実際の保管庫、おとり保管庫、ごみ箱、端末内の復旧情報、自動バックアップ設定、一時入力データはすべて消去されます。外部バックアップは削除されません。',
  '此操作不会找回旧密码，也不会解密旧数据；没有可用备份的数据将永久丢失。外部 .asmbackup 文件和合法完整版授权会保留。恢复备份仍需对应备份密码。':
      'この操作で以前のパスワードを取得したり、古いデータを復号したりすることはできません。利用可能なバックアップがないデータは永久に失われます。外部の .asmbackup ファイルと有効な完全版の権利は保持されます。バックアップの復元には対応するバックアップパスワードが必要です。',
  '保险库密码恢复准备': '保管庫のパスワード復旧準備',
  '真实库和诱饵库均已配置恢复': '実際の保管庫とおとり保管庫の両方に復旧を設定済み',
  '仅真实库已配置恢复': '実際の保管庫にのみ復旧を設定済み',
  '仅诱饵库已配置恢复': 'おとり保管庫にのみ復旧を設定済み',
  "自动备份周期": "自動バックアップの間隔",
  "7 天（每周）": "7日（毎週）",
  "15 天（半个月）": "15日（半月）",
  "30 天（一个月）": "30日（1か月）",
  "下次自动备份": "次回の自動バックアップ",
  "备份周期已保存。": "バックアップ間隔を保存しました。",
  "备份周期保存失败，原设置保持不变。": "間隔を保存できませんでした。以前の設定は保持されています。",
  "到期后完整解锁时自动备份，即使内容相同也会生成。仅保留最近 3 份；应用自动校验新备份，成功后自动删除最旧文件，无需手动验证。":
      "期限が来た後、完全にロック解除すると内容が同じでも自動バックアップを作成します。最新の3件のみを保持します。アプリが新しいバックアップを自動検証し、成功後に最も古いファイルを自動削除します。手動検証は不要です。",
  "周期从最近一次成功的自动备份起计算；选择后自动保存。": "間隔は前回の自動バックアップ成功時点から計算します。選択すると自動保存されます。",
  "新备份已验证，但旧文件删除失败；将自动重试清理。":
      "新しいバックアップの検証は成功しましたが、古いファイルを削除できませんでした。自動的に再試行します。",
  "旧自动备份清理未完成，请到数据安全与备份检查。": "古い自動バックアップの削除が完了していません。データ保護とバックアップ画面で確認してください。",
  "没有可用的自动备份，请到数据安全与备份检查。": "利用できる自動バックアップがありません。データ保護とバックアップ画面で確認してください。",
  "自动备份已超过计划时间，请到数据安全与备份检查。": "自動バックアップの予定時刻を過ぎています。データ保護とバックアップ画面で確認してください。",
  '数据安全与备份': 'データ保護とバックアップ',
  '回收站': 'ごみ箱',
  '搜索回收站': 'ごみ箱を検索',
  '回收站中没有匹配记录。': '一致する記録はありません。',
  '保留 30 天，可恢复原记录与关联关系': '30 日間保持し、記録と関連付けを復元できます',
  '记录保留 30 天，到期后在完整解锁时自动清理。恢复会保留原账期和状态。':
      '記録は 30 日間保持され、期限後の完全ロック解除時に削除されます。復元時は元の請求日と状態を維持します。',
  '删除：{date} · 剩余 {days} 天': '削除：{date} · 残り {days} 日',
  '恢复此项': 'この記録を復元',
  '恢复整个删除组合': '削除グループ全体を復元',
  '永久删除': '完全に削除',
  '清空回收站': 'ごみ箱を空にする',
  '输入“清空回收站”': '「清空回收站」と入力',
  '永久删除回收站记录？': 'ごみ箱の記録を完全に削除しますか？',
  '此操作无法撤销。已记录的历史费用仍会保留；外部备份文件不受影响。': '取り消せません。記録済みの過去の費用と外部バックアップは保持されます。',
  '当前保险库密码': '現在の保管庫パスワード',
  '操作完成。': '操作が完了しました。',
  '操作未完成，原数据保持不变。': '操作は未完了です。元のデータは変更されていません。',
  '请完整解锁当前保险库。': '現在の保管庫を完全にロック解除してください。',
  '请完整解锁真实保险库。': '実際の保管庫を完全にロック解除してください。',
  '移入回收站？': 'ごみ箱に移動しますか？',
  '移入回收站': 'ごみ箱に移動',
  '记录将在回收站保留 30 天，可恢复。这不会注销对应平台账号。':
      'ごみ箱で 30 日間保持し、復元できます。サービス側のアカウントは削除されません。',
  '这个账号关联了{countLabel}，将一起移入回收站保留 30 天。历史费用保留；这不会在对应平台取消订阅或停止扣费。':
      '関連する {countLabel} もごみ箱で 30 日間保持します。過去の費用は残ります。サービス側の契約や請求は停止されません。',
  '关联的{countLabel}也将移入回收站保留 30 天。历史费用保留；这不会在对应平台取消订阅或停止扣费。':
      '関連する {countLabel} もごみ箱で 30 日間保持します。過去の費用は残ります。サービス側の契約や請求は停止されません。',
  '记录将在回收站保留 30 天；这不会在对应平台取消订阅或停止扣费。': 'ごみ箱で 30 日間保持します。サービス側の契約や請求は停止されません。',
  '账号及关联订阅已移入回收站。': 'アカウントと関連する契約をごみ箱に移動しました。',
  '订阅记录已移入回收站。': '契約記録をごみ箱に移動しました。',
  '移入回收站失败，原记录保持不变。': '移動できませんでした。元の記録は変更されていません。',
  '恢复失败，回收站记录保持不变。': '復元できませんでした。ごみ箱の記録は保持されています。',
  '无法恢复，请先恢复关联账号或选择恢复整个删除组合。': '関連アカウントを先に復元するか、削除グループ全体を復元してください。',
  '永久删除失败，回收站记录保持不变。': '完全削除できませんでした。ごみ箱の記録は保持されています。',
  '回收站自动清理未完成，可稍后重试。': 'ごみ箱の自動整理が未完了です。後で再試行できます。',
  '回收站中有相似记录': 'ごみ箱に類似する記録があります',
  '可以先到回收站恢复原记录，也可以继续新增。回收站记录不会阻止本次保存。':
      'ごみ箱から元の記録を復元するか、新規作成を続けられます。ごみ箱の記録は保存を妨げません。',
  '查看回收站': 'ごみ箱を見る',
  '继续新增': '新規作成を続ける',
  '回收站中有相似记录，可先恢复；这些记录不会阻止本次导入。': 'ごみ箱の類似記録を先に復元できます。これらは今回のインポートを妨げません。',
  '导出可读数据': '読み取り可能なデータを出力',
  '加密备份用于Cardock恢复。CSV / JSON 为明文，可被其他程序读取，不能直接恢复保险库。':
      '暗号化バックアップは Cardock の復元用です。CSV / JSON は他のアプリで読める平文で、保管庫の直接復元には使えません。',
  '导出格式': '出力形式',
  '包含回收站记录': 'ごみ箱の記録を含める',
  '包含当前账号密码': '現在のアカウントパスワードを含める',
  '包含当前账号密码？': '現在のアカウントパスワードを含めますか？',
  '文件包含明文密码，任何取得文件的人都能读取。密码变更历史仅包含日期，不包含旧密码。':
      'ファイルを入手した人は平文のパスワードを読めます。変更履歴には日付のみを含め、古いパスワードは含めません。',
  '账号 {accounts} · 订阅 {subscriptions} · 回收站 {trash}':
      'アカウント {accounts} · 契約 {subscriptions} · ごみ箱 {trash}',
  '包含明文备注。历史费用会保留，关联记录可能已被删除。': '平文のメモを含みます。過去の費用は保持されますが、関連記録は削除済みの場合があります。',
  '验证密码并导出': 'パスワードを確認して出力',
  '已导出 {format} · {time} · 包含密码：{passwords}。文件为明文，请妥善保存。':
      '{format} を出力 · {time} · パスワードを含む：{passwords}。平文のため安全に保管してください。',
  '导出已取消或未完成。': '出力はキャンセルされたか未完了です。',
  '可读导出未完成，请检查保存位置。': '出力が完了しませんでした。保存先を確認してください。',
  'CSV / JSON 为明文，默认不含账号密码。': 'CSV / JSON は平文です。初期設定ではパスワードを含めません。',
  '最近加密备份': '最新の暗号化バックアップ',
  '手动备份': '手動バックアップ',
  '自动备份': '自動バックアップ',
  '最近完整验证': '最新の完全検証',
  '已启用，仅完整解锁真实库时工作': '有効：実際の保管庫の完全ロック解除中のみ実行',
  '未启用': '無効',
  '目录授权': 'フォルダーのアクセス権',
  '授权有效': 'アクセス権は有効',
  '目录权限失效': 'アクセス権が無効',
  '未选择或待检查': '未選択または未確認',
  '已验证且仍存在的自动备份': '検証済みで現在もアクセス可能な自動バックアップ',
  '{count} 份 · 保留 {keep} 份': '{count} 件 · {keep} 件保持',
  '{count} 份': '{count} 件',
  '待备份更改': 'バックアップ待ちの変更',
  '没有待处理更改': '保留中の変更なし',
  '最近备份失败': '最新のバックアップ失敗',
  '账号 {accounts} · 订阅 {subscriptions} · 最近到期 {time}':
      'アカウント {accounts} · 契約 {subscriptions} · 次の期限 {time}',
  '主密码恢复准备': 'マスターパスワードの回復準備',
  '已配置恢复方式': '回復方法は設定済み',
  '尚未配置恢复方式': '回復方法は未設定',
  '下次配置保留份数': '次の設定で保持する件数',
  '选择或更换备份目录与密码': '保存先とパスワードを設定・変更',
  '先生成并验证一份新备份，再保存配置。': '新しいバックアップを作成・検証してから設定を保存します。',
  '立即自动备份': '今すぐバックアップ',
  '使用本机已配置的目录和独立备份密码': '設定済みの保存先と独立したパスワードを使用',
  '关闭自动备份': '自動バックアップを無効にする',
  '关闭自动备份？': '自動バックアップを無効にしますか？',
  '保留外部文件，可稍后重新配置。': '外部ファイルを保持し、後で再設定できます。',
  '已生成的外部备份不会删除。': '作成済みの外部バックアップは削除されません。',
  '验证已有备份': '既存のバックアップを検証',
  '重新选择文件并完整解密，不改变本机数据。': 'ファイルを選び直して完全に復号します。本機のデータは変更しません。',
  '恢复前仍需当前主密码和明确确认。': '復元には現在のマスターパスワードと明確な確認が必要です。',
  '数据安全帮助': 'データ保護ヘルプ',
  '备份、验证、恢复与重建说明': 'バックアップ・検証・復元・再構築の説明',
  '加密备份需要对应备份密码。建议将已验证文件保存在另一处。可读导出包含明文备注。回收站保留 30 天。忘记主密码时，可在锁屏使用已配置恢复方式，或受控删除本机数据后新建保险库，再恢复自己的备份。':
      '暗号化バックアップには対応するパスワードが必要です。検証済みのコピーを別の場所にも保管してください。読み取り可能な出力には平文のメモを含みます。ごみ箱は 30 日間保持します。マスターパスワードを忘れた場合はロック画面で回復するか、本機の削除を確認して新規保管庫を作成し、バックアップを復元します。',
  '应用 {version} · 加密备份格式 v2 · 可读导出格式 v1':
      'アプリ {version} · 暗号化バックアップ v2 · 読み取り可能な出力 v1',
  '手动备份的时间是历史验证记录；请重新选择文件检查当前可用性。':
      '手動バックアップの時刻は過去の検証記録です。現在の可用性はファイルを選び直して確認してください。',
  '.asmbackup · 独立备份密码': '.asmbackup · 独立したバックアップパスワード',
  '尚无记录': '記録なし',
  '自动备份独立密码': '自動バックアップ用の独立したパスワード',
  '密码仅由本机真实保险库加密保护，不进入备份文件。忘记密码无法恢复旧文件；更换密码只影响以后生成的备份。':
      'パスワードは本機の実際の保管庫で暗号化し、バックアップ内容には含めません。忘れると古いファイルを復元できません。変更は今後のバックアップにのみ適用されます。',
  '再次输入备份密码': 'バックアップパスワードを再入力',
  '两次备份密码不一致。': 'パスワードが一致しません。',
  '首份备份已重新读取并完整验证，自动备份已启用。': '最初のバックアップを再読込して完全検証しました。自動バックアップは有効です。',
  '自动备份已完整验证。': '自動バックアップを完全検証しました。',
  '无法取得目录授权。': 'フォルダーへのアクセスを許可できませんでした。',
  '目录权限失效，请重新选择目录。': 'アクセス権が無効です。フォルダーを選び直してください。',
  '备份目录或文件不存在。': '保存先またはファイルが見つかりません。',
  '保存位置空间不足。': '保存先の空き容量が不足しています。',
  '文件提供方拒绝操作。': 'ファイル提供元が操作を拒否しました。',
  '文件写入后无法重新读取。': '書き込んだファイルを再読込できません。',
  '文件完整解密验证失败，旧有效备份已保留。': '完全な復号検証に失敗しました。以前の有効なバックアップは保持しています。',
  '设备备份配置无法解密或版本不受支持，自动备份已停用。': '端末の設定を復号できないか未対応の版です。自動バックアップは無効です。',
  '写入中断，旧有效备份已保留。': '書込みが中断されました。以前の有効なバックアップは保持しています。',
  '备份未完成，请检查保存位置后重试。': 'バックアップは未完了です。保存先を確認して再試行してください。',
  '备份已完整验证，本机数据未改变。': 'バックアップを完全検証しました。本機のデータは変更していません。',
  '备份目录权限失效，请到数据安全与备份重新授权。': '保存先へのアクセス権が無効です。データ保護とバックアップ画面で再許可してください。',
  '自动备份连续失败，请到数据安全与备份检查。': '自動バックアップが続けて失敗しました。データ保護とバックアップ画面を確認してください。',
  '更改已等待备份超过一天，请到数据安全与备份检查。': '変更が 1 日以上バックアップ待ちです。データ保護とバックアップ画面を確認してください。',
  '尚无已验证的加密备份，建议到数据安全与备份准备。': '検証済みの暗号化バックアップはありません。データ保護とバックアップ画面で準備してください。',
  '超过 7 天未验证备份，建议检查备份可用性。': '7 日以上バックアップを検証していません。利用可能か確認してください。',
  '稍后提醒': '後で通知',
  '忘记密码或重新开始': 'パスワードを忘れた・やり直す',
  '已配置恢复方式：可使用原有恢复入口验证并重设主密码。':
      '回復方法が設定されています。既存の回復画面で本人確認し、マスターパスワードを再設定できます。',
  '使用已配置的恢复方式': '設定済みの回復方法を使用',
  '使用已有加密备份：先创建新的保险库，再在设置中验证并恢复备份。需要对应备份密码。':
      '暗号化バックアップを使う場合は、新しい保管庫を作成し、設定で検証して復元します。対応するバックアップパスワードが必要です。',
  '删除本机Cardock数据并重新开始': '本機の Cardock データを削除して再開',
  '删除本机Cardock数据并重新开始：真实库、诱饵库、回收站、本地恢复凭据、自动备份配置和临时录入资料都会清除。外部备份不会删除。':
      '本機のデータを削除して再開します。実際の保管庫、おとり保管庫、ごみ箱、復旧情報、自動バックアップ設定、一時入力を消去します。外部バックアップは削除しません。',
  'Cardock不能找回忘记的主密码。重建不会解密旧数据；没有可用备份的数据将永久丢失。外部 .asmbackup 文件和合法完整版授权会保留。恢复备份仍需对应备份密码。':
      '忘れたマスターパスワードは取得できません。再構築は古いデータを復号しません。利用可能なバックアップがないデータは永久に失われます。外部の .asmbackup と有効な完全版の権利は保持します。復元には対応するバックアップパスワードが必要です。',
  '了解后验证设备身份': '理解して端末を認証',
  '验证设备身份': '端末の本人確認',
  '确认删除本机Cardock数据': '本機の Cardock データの削除を確認',
  '设备未设置系统锁屏凭据。必须完成双重文字确认，并按住按钮至少 3 秒。':
      '端末の画面ロック認証が未設定です。2 つの確認文を入力し、ボタンを 3 秒以上押し続けてください。',
  '输入“删除本机Cardock数据”': '「删除本机Cardock数据」と入力',
  '输入“我理解没有备份将无法恢复”': '「我理解没有备份将无法恢复」と入力',
  '按住至少 3 秒': '3 秒以上押し続ける',
  '长按确认已完成': '長押し確認が完了',
  '最终确认：删除本机数据？': '最終確認：本機のデータを削除しますか？',
  '删除后无法撤销。外部备份文件不会删除。': '削除は取り消せません。外部バックアップは削除しません。',
  '删除并重新开始': '削除して再開',
  '正在重建，请稍候…': '再構築中です。お待ちください…',
  '重建未完成；若清理已开始，请重新打开应用继续完成。': '再構築は未完了です。消去が開始済みの場合、アプリを開き直して完了してください。',
  '系统身份验证未完成。': 'システムの本人確認が完了しませんでした。',
};
