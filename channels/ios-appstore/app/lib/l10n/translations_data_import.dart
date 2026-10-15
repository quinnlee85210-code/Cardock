const Map<String, String> dataImportEnglishTranslations = <String, String>{
  '数据迁移中心': 'Data migration center',
  '外部数据导入': 'External data import',
  '从密码管理器或 XLSX、DOCX、CSV、TSV、TXT 文件快速整理':
      'Quickly organize data from a password manager or an XLSX, DOCX, CSV, '
      'TSV, or TXT file',
  '所有解析、预览和提交都在本机完成；提交前会再次核对当前保险库代次和数量限制。':
      'Parsing, previewing, and saving all happen on this device. The current '
      'vault revision and item limits are checked again before saving.',
  '选择文件并开始导入': 'Choose a file and start importing',
  '从原应用导出文件': 'Export a file from the original app',
  '支持 Bitwarden、KeePassXC、1Password 与 Cardock 模板，可导入 XLSX、DOCX、CSV、TSV、TXT':
      'Supports Bitwarden, KeePassXC, 1Password, and Cardock templates in '
      'XLSX, DOCX, CSV, TSV, or TXT format',
  '用电脑批量整理': 'Organize a batch on a computer',
  '复用现有一次性连接和端到端加密；最终仍在手机审批':
      'Uses the existing one-time, end-to-end encrypted connection; final '
      'approval still happens on the phone',
  '继续完善订阅': 'Complete subscriptions',
  '当前没有待完善订阅': 'There are no incomplete subscriptions',
  '有 {count} 条加密草稿等待补全': '{count} encrypted drafts are waiting to be completed',
  '撤销最近一次批量导入': 'Undo the latest batch import',
  '格式与安全说明': 'Format and security information',
  '10 MiB / 5000 行；敏感列排除、遮挡密码确认与内存清理':
      '10 MiB / 5,000 rows; sensitive-column exclusion, masked-password '
      'confirmation, and memory clearing',
  '当前没有可撤销的批量导入': 'There is no batch import to undo',
  '导入后业务数据已变化，无法安全整体撤销；可点此明确丢弃旧回滚点':
      'Business data changed after the import, so the batch cannot be safely '
      'undone. Tap here to explicitly discard the old rollback point.',
  '加密回滚点无法读取，已禁止应用；可点此明确丢弃':
      'The encrypted rollback point cannot be read and will not be applied. '
      'Tap here to explicitly discard it.',
  '加密回滚点仍可用；请确认后撤销最近一次批量导入':
      'The encrypted rollback point is available. Confirm to undo the latest '
      'batch import.',
  '丢弃批量导入回滚点？': 'Discard the batch import rollback point?',
  '这只会删除最近一次批量导入的独立加密回滚点，不会改变当前账号、订阅或备份恢复前回滚。删除后无法恢复。':
      'This deletes only the separate encrypted rollback point for the latest '
      'batch import. It does not change current accounts, subscriptions, or '
      'the pre-restore rollback. This cannot be undone.',
  '确认丢弃回滚点': 'Discard rollback point',
  '批量导入回滚点已丢弃': 'The batch import rollback point was discarded',
  '未能丢弃批量导入回滚点': 'The batch import rollback point could not be discarded',
  '影响 {affected} 条：新增账号 {added}、更新 {updated}、正式订阅 {formal}、草稿 {drafts}':
      'Affects {affected} items: {added} new accounts, {updated} updates, '
      '{formal} complete subscriptions, and {drafts} drafts',
  '先从原应用导出': 'Export from the original app first',
  '在原密码管理器中选择 CSV 导出，或下载 Cardock 空模板后用 Excel / WPS 填写。导入支持 XLSX、DOCX、CSV、TSV、TXT；这些文件可能包含明文密码，请不要上传到网盘。导入后请在确认备份无误后自行安全删除源文件。':
      'Choose CSV export in the original password manager, or download a '
      'blank Cardock template and fill it in with Excel or WPS. Imports '
      'support XLSX, DOCX, CSV, TSV, and TXT. These files may contain '
      'plaintext passwords. Do not upload them to cloud storage. After '
      'importing, verify your backup and then securely delete the source file '
      'yourself.',
  '知道了': 'Got it',
  '支持 XLSX、DOCX、CSV、TSV、TXT；XLSX 读取首个工作表，DOCX 读取首个表格，文本文件支持 UTF-8 / UTF-16 BOM 以及逗号、制表符或分号分隔。单文件不超过 10 MiB、5000 行、200 列。\n\n未识别列不会静默写入；一次性验证码等敏感列会按规则排除。密码默认遮挡，疑似星号或圆点占位值不会自动导入。\n\n流程离开前台、锁定保险库、取消或完成后会清理本次内存；不会申请新的存储权限。':
      'Supports XLSX, DOCX, CSV, TSV, and TXT. For XLSX, only the first '
      'worksheet is read; for DOCX, only the first table is read. Text files '
      'support UTF-8 or UTF-16 BOM with comma, tab, or semicolon delimiters. '
      'Each file is limited to 10 MiB, 5,000 rows, and 200 columns.\n\n'
      'Unrecognized columns are never written silently. Sensitive columns '
      'such as one-time passwords are excluded by rule. Passwords are masked '
      'by default, and suspected asterisk or dot placeholders are not '
      'imported automatically.\n\nThis import is cleared from memory when the '
      'app leaves the foreground, the vault is locked, or the flow is canceled '
      'or completed. No new storage permission is requested.',
  '打开导入文件前确认': 'Before opening the import file',
  'XLSX、DOCX、CSV、TSV 或 TXT 导入文件可能包含明文密码。文件只在本次内存流程中解析；请确认它来自可信位置，不要上传到网盘，并在导入和加密备份核对完成后自行安全删除源文件。':
      'An XLSX, DOCX, CSV, TSV, or TXT import file may contain plaintext '
      'passwords. The file is parsed only in memory for this import. Make sure '
      'it comes from a trusted location, do not upload it to cloud storage, '
      'and securely delete it yourself after checking the import and '
      'encrypted backup.',
  '继续选择文件': 'Continue to file selection',
  '无法读取所选文件，请重新选择。': 'The selected file could not be read. Choose it again.',
  '文件不能超过 10 MiB。': 'The file cannot exceed 10 MiB.',
  '这是 Cardock 加密备份。请返回设置并使用“恢复 Cardock 加密备份”；此处只导入外部表格或文档。':
      'This is a Cardock encrypted backup. Return to Settings and use '
      '“Restore Cardock encrypted backup”; this flow imports only external '
      'tables or documents.',
  '这是日历 .ics 文件，只包含日历事件，不是账号与订阅备份，不能在这里恢复。':
      'This is an .ics calendar file containing calendar events, not an '
      'account and subscription backup. It cannot be restored here.',
  '不支持此文件；这里只能导入 XLSX、DOCX、CSV、TSV 或 TXT。':
      'This file is not supported. Only XLSX, DOCX, CSV, TSV, or TXT can be '
      'imported here.',
  '自定义字段文件已读取；请继续核对字段。':
      'The custom-field file was read. Continue reviewing the fields.',
  '配套文件已读取；请点击“下一步”核对字段。':
      'The companion file was read. Select “Next” to review the fields.',
  '文件已读取；可追加配套表，或点击“下一步”核对字段。':
      'The file was read. Add a companion table or select “Next” to review '
      'the fields.',
  '数据迁移与批量导入': 'Data migration and batch import',
  '第 {current} 步，共 7 步': 'Step {current} of 7',
  '当前不能批量导入': 'Batch import is currently unavailable',
  '订阅只读视图、保险库已锁定或正在处理其他写入。请回到真实或诱饵保险库的完整解锁状态后重试。':
      'The subscription-only view is active, the vault is locked, or another '
      'write is in progress. Fully unlock the real or decoy vault and try '
      'again.',
  '正在本机后台解析文件…': 'Parsing the file in the background on this device…',
  '取消解析': 'Cancel parsing',
  '未继续执行': 'The import did not continue',
  '选择数据来源': 'Choose a data source',
  '只启用已经过格式验证的适配器；也可以选择通用表格并在下一步核对字段映射。':
      'Only adapters with verified formats are enabled. You can also choose '
      'a generic table and review the field mapping in the next step.',
  '选择一个文件': 'Choose a file',
  '支持单个 XLSX、DOCX、CSV、TSV 或 TXT 文件，最大 10 MiB。XLSX 读取首个工作表，DOCX 读取首个表格；文件只在本次内存流程中处理。':
      'Supports one XLSX, DOCX, CSV, TSV, or TXT file up to 10 MiB. Only the '
      'first worksheet in XLSX or first table in DOCX is read. The file is '
      'processed only in memory for this import.',
  '此入口不读取 .asmbackup 加密备份或 .ics 日历文件。':
      'This flow does not read .asmbackup encrypted backups or .ics calendar '
      'files.',
  '{bytes} 字节': '{bytes} bytes',
  '配套文件：{name} · {bytes} 字节': 'Companion file: {name} · {bytes} bytes',
  '尚未选择文件': 'No file selected',
  '选择文件': 'Choose file',
  '重新选择文件': 'Choose another file',
  '追加配套账号或订阅表': 'Add a companion account or subscription table',
  '下一步：核对字段': 'Next: review fields',
  '检测并核对字段映射': 'Detect and review field mappings',
  '检测结果：{format}': 'Detected format: {format}',
  '待检测': 'Not detected yet',
  '该列属于排除的敏感字段，不会进入预览或保险库。':
      'This is an excluded sensitive column and will not enter the preview or '
      'vault.',
  '导入为': 'Import as',
  '忽略此列': 'Ignore this column',
  '登录账号字段建议': 'Login field suggestions',
  '只在目标邮箱或手机号为空时建议；接受后登录账号原值保持不变。':
      'Suggested only when the target email address or phone number is empty. '
      'Accepting a suggestion does not change the original login value.',
  '邮箱 · {value}': 'Email · {value}',
  '手机号 · {value}': 'Phone · {value}',
  '接受此项': 'Accept',
  '全部忽略': 'Ignore all',
  '全部接受': 'Accept all',
  '预览密码状态': 'Review password status',
  '这里只显示密码状态，不显示密码原文，也不提供“全部显示”。':
      'Only password status is shown here. Password values are never shown, '
      'and there is no “show all” option.',
  '疑似星号或圆点遮挡占位值；默认不导入。仅在确认这就是要保存的真实密码时勾选。':
      'This looks like an asterisk or dot placeholder and is excluded by '
      'default. Select it only after confirming that it is the actual password '
      'you intend to save.',
  '品牌匹配候选': 'Brand match candidates',
  '已忽略品牌建议': 'Brand suggestions ignored',
  '忽略这些建议': 'Ignore these suggestions',
  '未包含密码': 'No password included',
  '将加密导入': 'Will be imported encrypted',
  '已按规则排除': 'Excluded by rule',
  '遮挡占位值 · 默认排除': 'Masked placeholder · excluded by default',
  '处理重复项': 'Resolve duplicates',
  '默认跳过疑似重复项。合并只补充空字段，不覆盖已有密码或非空内容。':
      'Suspected duplicates are skipped by default. Merging fills only empty '
      'fields and never overwrites an existing password or nonempty value.',
  '从本次导入中移除': 'Remove from this import',
  '重复项处理': 'Duplicate handling',
  '跳过': 'Skip',
  '只补充已有记录的空字段': 'Fill only empty fields in the existing item',
  '逐字段选择': 'Choose field by field',
  '仍创建另一条记录': 'Create another item anyway',
  '选择要更新的已有账号': 'Choose the existing account to update',
  '关联到保险库中的账号': 'Link to an account in the vault',
  '也可返回文件步骤追加含相同 account_key 的账号表。':
      'You can also return to the file step and add an account table with the '
      'same account_key.',
  '逐字段决定（已有密码原文不会显示）':
      'Choose each field (the existing password is never shown)',
  '请先选择要更新的已有账号，再逐字段核对。':
      'Choose the existing account to update before comparing each field.',
  'Cardock 现有内容': 'Existing Cardock value',
  '本次导入内容': 'Imported value',
  '密码比较结果': 'Password comparison result',
  '用户选择': 'Your choice',
  '密码不同，必须逐条明确确认；不会批量覆盖。':
      'The passwords differ. Confirm this row explicitly; passwords are never '
      'overwritten in bulk.',
  '保留已有': 'Keep existing',
  '使用导入': 'Use imported value',
  '使用导入（追加）': 'Use imported value (append)',
  '相同': 'Same',
  '不同': 'Different',
  '现有为空': 'Existing is empty',
  '导入为空': 'Imported value is empty',
  '平台名称': 'Platform name',
  '登录账号': 'Sign-in ID',
  '手机号': 'Phone number',
  '邮箱': 'Email',
  '密码（仅状态比较）': 'Password (status comparison only)',
  '网址': 'Website',
  '备注（使用导入=追加）': 'Notes (using imported value appends it)',
  '最终确认': 'Final confirmation',
  '目标保险库：当前真实保险库': 'Target vault: current real vault',
  '提交前和提交时都会重新核对保险库范围与数据代次。':
      'The vault scope and data revision are checked again before and during '
      'the save.',
  '新增账号': 'Add account',
  '更新账号': 'Updated accounts',
  '跳过账号': 'Skipped accounts',
  '正式订阅': 'Complete subscriptions',
  '待完善订阅': 'Incomplete subscriptions',
  '不支持项目': 'Unsupported items',
  '额度复核': 'Limit check',
  '剩余账号 不限 · 剩余订阅 不限':
      'Remaining accounts: unlimited · Remaining subscriptions: unlimited',
  '剩余账号 {accounts} · 剩余订阅 不限':
      'Remaining accounts: {accounts} · Remaining subscriptions: unlimited',
  '剩余账号 不限 · 剩余订阅 {subscriptions}':
      'Remaining accounts: unlimited · Remaining subscriptions: '
      '{subscriptions}',
  '剩余账号 {accounts} · 剩余订阅 {subscriptions}':
      'Remaining accounts: {accounts} · Remaining subscriptions: '
      '{subscriptions}',
  '不限': 'Unlimited',
  '我已核对来源、映射、密码状态和重复项处理。':
      'I have reviewed the source, mappings, password status, and duplicate '
      'handling.',
  '提交时会再次核对权威预览 token、保险库代次和免费版数量限制；任何冲突都会整批停止。':
      'When saving, Cardock checks the authoritative preview token, vault '
      'revision, and free-plan limits again. Any conflict stops the entire '
      'batch.',
  '导入未完成': 'Import not completed',
  '批量导入已完成': 'Batch import complete',
  '账号 {accounts} · 正式订阅 {formal} · 待完善 {pending} · 合并 {merged} · 跳过 {skipped} · 不支持 {unsupported}':
      'Accounts {accounts} · Complete subscriptions {formal} · Incomplete '
      '{pending} · Merged {merged} · Skipped {skipped} · Unsupported '
      '{unsupported}',
  '最近一次批量导入的本机加密回滚可用。':
      'An encrypted on-device rollback is available for the latest batch '
      'import.',
  '本次没有生成可用的批量导入回滚；请先核对记录。':
      'No usable batch-import rollback was created. Review the imported items '
      'first.',
  '源文件可能仍含明文密码。请先核对导入记录和加密备份，再回到文件管理器自行安全删除；Cardock 不会擅自删除外部文件。':
      'The source file may still contain plaintext passwords. Review the '
      'imported items and encrypted backup, then return to your file manager '
      'and securely delete it yourself. Cardock never deletes external files '
      'without your action.',
  '继续完善订阅（{count}）': 'Complete subscriptions ({count})',
  '完成并清空内存': 'Finish and clear memory',
  '上一步': 'Previous',
  '确认并加密导入': 'Confirm and import encrypted',
  '下一步': 'Next',
  '自动检测': 'Detect automatically',
  '优先匹配已验证的来源；无法唯一识别时使用通用表格并要求核对映射。':
      'Prefers a verified source. If no unique match is possible, uses the '
      'generic table format and requires mapping review.',
  '已验证的账号导入格式': 'Verified account import format',
  '已验证的订阅导入格式': 'Verified subscription import format',
  '尚未完成官方格式验证，当前禁用':
      'Disabled because official format verification is incomplete',
  '该来源尚未完成格式验证，当前不能启用。':
      'This source cannot be enabled until its format has been verified.',
  '保险库当前不能写入，请重新完整解锁。': 'The vault is not writable. Fully unlock it again.',
  '文件解析或来源检测失败；本机数据未改变。':
      'File parsing or source detection failed. On-device data was not '
      'changed.',
  '请先读取第一张账号或订阅表。':
      'Load the first account or subscription table before adding another.',
  '当前会话不能再追加文件；如需重选请清空后重新开始。':
      'No more files can be added to this session. To choose again, clear the '
      'session and restart.',
  '追加文件来源尚未完成格式验证。':
      'The added file source has not passed format verification.',
  '第二个文件必须是已验证的订阅表。': 'The second file must be a verified subscription table.',
  '第二个文件必须是已验证的账号表。': 'The second file must be a verified account table.',
  '第二个文件无法作为配套账号/订阅表追加；本机数据未改变。':
      'The second file could not be added as a companion account or '
      'subscription table. On-device data was not changed.',
  '字段映射无效。': 'The field mapping is invalid.',
  '字段映射冲突，请核对重复目标和被排除的敏感列。':
      'Field mappings conflict. Review duplicate targets and excluded '
      'sensitive columns.',
  '该行没有需要确认的遮挡占位密码。': 'This row has no masked placeholder password to confirm.',
  '所选已有账号不再是当前重复候选。':
      'The selected existing account is no longer a duplicate candidate.',
  '所选关联账号已不可用，请重新选择。':
      'The selected linked account is no longer available. Choose again.',
  '请先选择并读取一个文件。': 'Choose and load a file first.',
  '请先为每条订阅选择本次导入的账号或保险库中的已有账号。':
      'For each subscription, choose an account from this import or an '
      'existing account in the vault.',
  '仍有未处理的重复项或免费版数量限制，未进入最终确认。':
      'Unresolved duplicates or free-plan limits remain, so final '
      'confirmation is not available.',
  '当前步骤无法继续；请核对映射、重复项和数量限制。':
      'This step cannot continue. Review mappings, duplicates, and item '
      'limits.',
  '权威预览计划无效，请返回重新核对。':
      'The authoritative preview plan is invalid. Go back and review it '
      'again.',
  '保险库数据已变化，权威预览已失效；请重新导入文件。':
      'Vault data changed, so the authoritative preview expired. Import the '
      'file again.',
  '免费版可用数量已变化，本次整批未写入。':
      'Free-plan availability changed. Nothing from this batch was written.',
  '保险库已锁定或处于订阅只读视图，本次整批未写入。':
      'The vault is locked or in subscription-only view. Nothing from this '
      'batch was written.',
  '本机加密写入失败，本次整批未提交。':
      'The encrypted on-device write failed. The batch was not committed.',
  '批量导入校验失败，本次整批未写入。':
      'Batch-import validation failed. Nothing from the batch was written.',
  '保险库状态已变化，迁移内存已清空。':
      'The vault state changed, so migration data was cleared from memory.',
  '已有账号': 'Existing account',
  '第 {row} 行账号': 'Account on row {row}',
  '该行缺少账号必要字段或包含无效值。':
      'This row is missing required account fields or contains an invalid '
      'value.',
  '发现 {count} 个疑似重复项。': '{count} possible duplicates found.',
  '第 {row} 行订阅草稿': 'Subscription draft on row {row}',
  '请选择关联账号，或先追加含相同 account_key 的账号表。':
      'Choose a linked account, or first add an account table containing the '
      'same account_key.',
  '分号': 'Semicolon',
  '订阅只读视图不能导入，请先完整解锁保险库':
      'Import is unavailable in subscription-only view; fully unlock the '
      'vault first',
  '诱饵保险库不能使用真实数据迁移中心':
      'The decoy vault cannot use the real-data migration center',
  '{count} 条加密草稿等待补全': '{count} encrypted drafts are waiting to be completed',
  '独立加密回滚 · 将影响 {count} 条记录':
      'Separate encrypted rollback · affects {count} items',
  '仅撤销最近一次批量导入，不使用备份恢复副本':
      'Undoes only the latest batch import; does not use the backup-restore '
      'copy',
  '撤销最近一次批量导入？': 'Undo the latest batch import?',
  '这与“恢复到上次备份导入前”完全独立。只会撤销最近一次批量导入的精确加密快照：新增账号 {added}、更新账号 {updated}、正式订阅 {formal}、待完善草稿 {pending}，共影响 {affected} 条。\n\n如果批量导入后已有其他保存，入口会自动失效，不会覆盖后续修改。':
      'This is completely separate from “restore to before the last backup '
      'import.” It only undoes the exact encrypted snapshot of the latest '
      'batch import: {added} new accounts, {updated} updated accounts, '
      '{formal} complete subscriptions, and {pending} incomplete drafts, '
      'affecting {affected} items in total.\n\nIf anything else is saved after '
      'the batch import, this option expires automatically and cannot '
      'overwrite later changes.',
  '确认撤销这一次批量导入': 'Confirm undo for this batch import',
  '最近一次批量导入已撤销。': 'The latest batch import was undone.',
  '撤销条件已变化；没有覆盖当前数据。':
      'The undo conditions changed. Current data was not overwritten.',
  '没有待完善订阅。批量导入中的不完整订阅会加密保存在这里。':
      'There are no incomplete subscriptions. Incomplete subscriptions from '
      'batch imports are stored here encrypted.',
  '关联 {account} · 还需完善 {count} 项':
      'Linked to {account} · {count} fields still needed',
  '订阅已完善并加密保存。': 'The subscription was completed and saved encrypted.',
  '订阅内容仍不完整或数量限制已变化；原草稿已保留。':
      'The subscription is still incomplete or item limits changed. The '
      'original draft was kept.',
  '关联账号': 'Linked account',
  '正在保存…': 'Saving…',
  '完成并转为正式订阅': 'Complete and save as a subscription',
  '确认批量导入': 'Confirm batch import',
  '账号关联键': 'Account link key',
  '密码': 'Password',
  '备注': 'Notes',
  '方案名称': 'Plan name',
  '金额': 'Amount',
  '币种': 'Currency',
  '账单周期': 'Billing cycle',
  '首次订阅日期': 'First subscription date',
  '下次续费日期': 'Next renewal date',
  '自动续费': 'Auto-renew',
  '支付方式': 'Payment method',
  '提前提醒天数': 'Reminder lead time in days',
  '先确认导出文件中缺失的正式订阅字段。Cardock 不会猜测续费日期、账单周期、自动续费或提醒天数。':
      'First confirm the required subscription fields missing from the '
      'exported file. Cardock never guesses the renewal date, billing cycle, '
      'auto-renew setting, or reminder lead time.',
  '先确认导出文件中缺失的正式订阅字段。Cardock 不会用续费日期代替首次订阅日期，也不会猜测日期、账单周期、自动续费或提醒天数。':
      'First confirm the required subscription fields missing from the '
      'exported file. Cardock never substitutes the renewal date for the '
      'first subscription date, and never guesses dates, billing cycle, '
      'auto-renew setting, or reminder lead time.',
  '尚未选择': 'Not selected',
  '选择': 'Choose',
  '每几个周期': 'Number of cycle units',
  '周期单位': 'Cycle unit',
  '天': 'Day',
  '周': 'Week',
  '月': 'Month',
  '年': 'Year',
  '是否自动续费': 'Auto-renew?',
  '是': 'Yes',
  '否': 'No',
  '请输入 0 到 365。': 'Enter a number from 0 to 365.',
  '使用这些值继续填写': 'Continue with these values',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过 · 剩余账号 {accounts} · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: passed · Remaining accounts {accounts} · Remaining subscriptions {subscriptions}\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过 · 剩余账号 {accounts}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: passed · Remaining accounts {accounts}\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过 · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: passed · Remaining subscriptions {subscriptions}\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: passed\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过 · 剩余账号 {accounts} · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: failed · Remaining accounts {accounts} · Remaining subscriptions {subscriptions}\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过 · 剩余账号 {accounts}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: failed · Remaining accounts {accounts}\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过 · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: failed · Remaining subscriptions {subscriptions}\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      'Current real vault · {selected} selected\nNew accounts {added} · Updated accounts {updated} · Skipped accounts {skipped}\nComplete subscriptions {formal} · Incomplete drafts {pending} · Unsupported {unsupported}\nLimit check: failed\nPassword values are not shown on this approval card. The vault revision and plan are checked again when you approve.',
};

const Map<String, String> dataImportJapaneseTranslations = <String, String>{
  '数据迁移中心': 'データ移行センター',
  '外部数据导入': '外部データをインポート',
  '从密码管理器或 XLSX、DOCX、CSV、TSV、TXT 文件快速整理':
      'パスワードマネージャー、または XLSX、DOCX、CSV、TSV、TXT ファイルのデータをすばやく整理',
  '所有解析、预览和提交都在本机完成；提交前会再次核对当前保险库代次和数量限制。':
      '解析、プレビュー、保存はすべてこの端末内で行います。保存前に現在の保管庫の世代と件数上限を再確認します。',
  '选择文件并开始导入': 'ファイルを選んでインポートを開始',
  '从原应用导出文件': '移行元アプリからファイルを書き出す',
  '支持 Bitwarden、KeePassXC、1Password 与 Cardock 模板，可导入 XLSX、DOCX、CSV、TSV、TXT':
      'Bitwarden、KeePassXC、1Password、Cardock のテンプレートに対応し、XLSX、DOCX、CSV、TSV、TXT をインポートできます',
  '用电脑批量整理': 'パソコンで一括整理',
  '复用现有一次性连接和端到端加密；最终仍在手机审批': '既存の一時接続とエンドツーエンド暗号化を使用し、最終承認はスマートフォンで行います',
  '继续完善订阅': 'サブスクリプションを補完',
  '当前没有待完善订阅': '補完が必要なサブスクリプションはありません',
  '有 {count} 条加密草稿等待补全': '暗号化された下書き {count} 件が補完を待っています',
  '撤销最近一次批量导入': '直近の一括インポートを取り消す',
  '格式与安全说明': '形式とセキュリティについて',
  '10 MiB / 5000 行；敏感列排除、遮挡密码确认与内存清理':
      '10 MiB / 5,000 行。機密列の除外、伏せ字パスワードの確認、メモリ消去',
  '当前没有可撤销的批量导入': '取り消せる一括インポートはありません',
  '导入后业务数据已变化，无法安全整体撤销；可点此明确丢弃旧回滚点':
      'インポート後に業務データが変更されたため、安全に一括で取り消せません。ここをタップすると古いロールバックポイントを明示的に破棄できます。',
  '加密回滚点无法读取，已禁止应用；可点此明确丢弃':
      '暗号化ロールバックポイントを読み取れないため、適用は禁止されています。ここをタップすると明示的に破棄できます。',
  '加密回滚点仍可用；请确认后撤销最近一次批量导入': '暗号化ロールバックポイントは利用できます。確認して直近の一括インポートを取り消してください。',
  '丢弃批量导入回滚点？': '一括インポートのロールバックポイントを破棄しますか？',
  '这只会删除最近一次批量导入的独立加密回滚点，不会改变当前账号、订阅或备份恢复前回滚。删除后无法恢复。':
      '直近の一括インポート用の独立した暗号化ロールバックポイントだけを削除します。現在のアカウント、サブスクリプション、バックアップ復元前のロールバックは変更しません。削除後は元に戻せません。',
  '确认丢弃回滚点': 'ロールバックポイントを破棄',
  '批量导入回滚点已丢弃': '一括インポートのロールバックポイントを破棄しました',
  '未能丢弃批量导入回滚点': '一括インポートのロールバックポイントを破棄できませんでした',
  '影响 {affected} 条：新增账号 {added}、更新 {updated}、正式订阅 {formal}、草稿 {drafts}':
      '影響 {affected} 件：新規アカウント {added} 件、更新 {updated} 件、正式なサブスクリプション {formal} 件、下書き {drafts} 件',
  '先从原应用导出': '先に移行元アプリから書き出してください',
  '在原密码管理器中选择 CSV 导出，或下载 Cardock 空模板后用 Excel / WPS 填写。导入支持 XLSX、DOCX、CSV、TSV、TXT；这些文件可能包含明文密码，请不要上传到网盘。导入后请在确认备份无误后自行安全删除源文件。':
      '移行元のパスワードマネージャーで CSV 書き出しを選ぶか、Cardock の空テンプレートをダウンロードして Excel / WPS で入力してください。XLSX、DOCX、CSV、TSV、TXT をインポートできます。これらのファイルには平文のパスワードが含まれることがあります。クラウドストレージへアップロードせず、インポート後にバックアップを確認してから元ファイルをご自身で安全に削除してください。',
  '知道了': '了解',
  '支持 XLSX、DOCX、CSV、TSV、TXT；XLSX 读取首个工作表，DOCX 读取首个表格，文本文件支持 UTF-8 / UTF-16 BOM 以及逗号、制表符或分号分隔。单文件不超过 10 MiB、5000 行、200 列。\n\n未识别列不会静默写入；一次性验证码等敏感列会按规则排除。密码默认遮挡，疑似星号或圆点占位值不会自动导入。\n\n流程离开前台、锁定保险库、取消或完成后会清理本次内存；不会申请新的存储权限。':
      'XLSX、DOCX、CSV、TSV、TXT に対応します。XLSX は最初のワークシート、DOCX は最初の表だけを読み取ります。テキストファイルは UTF-8 / UTF-16 BOM 付きで、カンマ、タブ、セミコロン区切りに対応します。1 ファイルは 10 MiB、5,000 行、200 列までです。\n\n認識できない列を暗黙に書き込むことはありません。ワンタイムパスワードなどの機密列は規則に従って除外されます。パスワードは既定で伏せ字になり、アスタリスクや点による伏せ字とみられる値は自動でインポートされません。\n\nアプリがバックグラウンドへ移動したとき、保管庫をロックしたとき、または処理をキャンセル・完了したときに、この処理のデータをメモリから消去します。新しいストレージ権限は要求しません。',
  '打开导入文件前确认': 'インポートファイルを開く前の確認',
  'XLSX、DOCX、CSV、TSV 或 TXT 导入文件可能包含明文密码。文件只在本次内存流程中解析；请确认它来自可信位置，不要上传到网盘，并在导入和加密备份核对完成后自行安全删除源文件。':
      'XLSX、DOCX、CSV、TSV、TXT のインポートファイルには平文のパスワードが含まれることがあります。ファイルは今回の処理中のみメモリ上で解析されます。信頼できる場所のファイルであることを確認し、クラウドストレージへアップロードしないでください。インポート結果と暗号化バックアップを確認した後、元ファイルをご自身で安全に削除してください。',
  '继续选择文件': 'ファイル選択へ進む',
  '无法读取所选文件，请重新选择。': '選択したファイルを読み込めません。選び直してください。',
  '文件不能超过 10 MiB。': 'ファイルは 10 MiB 以下にしてください。',
  '这是 Cardock 加密备份。请返回设置并使用“恢复 Cardock 加密备份”；此处只导入外部表格或文档。':
      'これは Cardock 暗号化バックアップです。設定へ戻り、「Cardock 暗号化バックアップを復元」を使用してください。ここでは外部の表または文書だけをインポートします。',
  '这是日历 .ics 文件，只包含日历事件，不是账号与订阅备份，不能在这里恢复。':
      'これはカレンダーイベントだけを含む .ics ファイルで、アカウントとサブスクリプションのバックアップではありません。ここでは復元できません。',
  '不支持此文件；这里只能导入 XLSX、DOCX、CSV、TSV 或 TXT。':
      'このファイルには対応していません。ここでは XLSX、DOCX、CSV、TSV、TXT のみインポートできます。',
  '自定义字段文件已读取；请继续核对字段。': 'カスタムフィールドファイルを読み込みました。引き続きフィールドを確認してください。',
  '配套文件已读取；请点击“下一步”核对字段。': '対応ファイルを読み込みました。「次へ」を選んでフィールドを確認してください。',
  '文件已读取；可追加配套表，或点击“下一步”核对字段。':
      'ファイルを読み込みました。対応する表を追加するか、「次へ」を選んでフィールドを確認してください。',
  '数据迁移与批量导入': 'データ移行と一括インポート',
  '第 {current} 步，共 7 步': '全 7 ステップ中 {current} ステップ目',
  '当前不能批量导入': '現在、一括インポートは利用できません',
  '订阅只读视图、保险库已锁定或正在处理其他写入。请回到真实或诱饵保险库的完整解锁状态后重试。':
      'サブスクリプションのみの表示、保管庫のロック、または別の書き込み処理中です。真の保管庫またはおとり保管庫を完全にロック解除してから、もう一度お試しください。',
  '正在本机后台解析文件…': 'この端末のバックグラウンドでファイルを解析しています…',
  '取消解析': '解析をキャンセル',
  '未继续执行': '処理は続行されませんでした',
  '选择数据来源': 'データの取得元を選択',
  '只启用已经过格式验证的适配器；也可以选择通用表格并在下一步核对字段映射。':
      '形式を検証済みのアダプターだけを有効にしています。汎用表を選び、次のステップでフィールド対応を確認することもできます。',
  '选择一个文件': 'ファイルを選択',
  '支持单个 XLSX、DOCX、CSV、TSV 或 TXT 文件，最大 10 MiB。XLSX 读取首个工作表，DOCX 读取首个表格；文件只在本次内存流程中处理。':
      '10 MiB までの XLSX、DOCX、CSV、TSV、TXT ファイルを 1 つ選べます。XLSX は最初のワークシート、DOCX は最初の表だけを読み取ります。ファイルは今回の処理中のみメモリ上で扱われます。',
  '此入口不读取 .asmbackup 加密备份或 .ics 日历文件。':
      'ここでは .asmbackup 暗号化バックアップや .ics カレンダーファイルを読み込みません。',
  '{bytes} 字节': '{bytes} バイト',
  '配套文件：{name} · {bytes} 字节': '対応ファイル：{name} · {bytes} バイト',
  '尚未选择文件': 'ファイルが選択されていません',
  '选择文件': 'ファイルを選択',
  '重新选择文件': '別のファイルを選択',
  '追加配套账号或订阅表': '対応するアカウント表またはサブスクリプション表を追加',
  '下一步：核对字段': '次へ：フィールドを確認',
  '检测并核对字段映射': 'フィールド対応を検出して確認',
  '检测结果：{format}': '検出結果：{format}',
  '待检测': '未検出',
  '该列属于排除的敏感字段，不会进入预览或保险库。': 'この列は除外対象の機密フィールドです。プレビューにも保管庫にも入りません。',
  '导入为': 'インポート先',
  '忽略此列': 'この列を無視',
  '登录账号字段建议': 'ログインフィールドの候補',
  '只在目标邮箱或手机号为空时建议；接受后登录账号原值保持不变。':
      '対象のメールアドレスまたは電話番号が空の場合にのみ候補を示します。採用しても元のログイン値は変わりません。',
  '邮箱 · {value}': 'メールアドレス · {value}',
  '手机号 · {value}': '電話番号 · {value}',
  '接受此项': '採用',
  '全部忽略': 'すべて無視',
  '全部接受': 'すべて採用',
  '预览密码状态': 'パスワードの状態を確認',
  '这里只显示密码状态，不显示密码原文，也不提供“全部显示”。':
      'ここにはパスワードの状態だけを表示します。パスワードそのものは表示せず、「すべて表示」もありません。',
  '疑似星号或圆点遮挡占位值；默认不导入。仅在确认这就是要保存的真实密码时勾选。':
      'アスタリスクまたは点による伏せ字とみられるため、既定ではインポートしません。保存する実際のパスワードであることを確認できた場合だけ選択してください。',
  '品牌匹配候选': 'ブランド一致候補',
  '已忽略品牌建议': 'ブランド候補を無視しました',
  '忽略这些建议': 'これらの候補を無視',
  '未包含密码': 'パスワードなし',
  '将加密导入': '暗号化してインポート',
  '已按规则排除': '規則により除外済み',
  '遮挡占位值 · 默认排除': '伏せ字のプレースホルダー · 既定で除外',
  '处理重复项': '重複項目を処理',
  '默认跳过疑似重复项。合并只补充空字段，不覆盖已有密码或非空内容。':
      '重複の可能性がある項目は既定でスキップします。統合では空のフィールドだけを補完し、既存のパスワードや空でない値は上書きしません。',
  '从本次导入中移除': '今回のインポートから削除',
  '重复项处理': '重複項目の処理',
  '跳过': 'スキップ',
  '只补充已有记录的空字段': '既存項目の空フィールドだけを補完',
  '逐字段选择': 'フィールドごとに選択',
  '仍创建另一条记录': '別の項目として作成',
  '选择要更新的已有账号': '更新する既存アカウントを選択',
  '关联到保险库中的账号': '保管庫内のアカウントに関連付ける',
  '也可返回文件步骤追加含相同 account_key 的账号表。':
      'ファイルのステップへ戻り、同じ account_key を含むアカウント表を追加することもできます。',
  '逐字段决定（已有密码原文不会显示）': 'フィールドごとに決定（既存のパスワードは表示されません）',
  '请先选择要更新的已有账号，再逐字段核对。': '更新する既存アカウントを選択してから、各フィールドを確認してください。',
  'Cardock 现有内容': 'Cardock の既存内容',
  '本次导入内容': '今回のインポート内容',
  '密码比较结果': 'パスワードの比較結果',
  '用户选择': 'ユーザーの選択',
  '密码不同，必须逐条明确确认；不会批量覆盖。':
      'パスワードが異なります。この行で明示的に確認してください。パスワードを一括上書きすることはありません。',
  '保留已有': '既存の値を保持',
  '使用导入': 'インポート値を使用',
  '使用导入（追加）': 'インポート値を使用（追記）',
  '相同': '同じ',
  '不同': '異なる',
  '现有为空': '既存の値が空',
  '导入为空': 'インポート値が空',
  '平台名称': 'プラットフォーム名',
  '登录账号': 'ログインID',
  '手机号': '電話番号',
  '邮箱': 'メール',
  '密码（仅状态比较）': 'パスワード（状態のみ比較）',
  '网址': 'URL',
  '备注（使用导入=追加）': 'メモ（インポート値を使用すると追記）',
  '最终确认': '最終確認',
  '目标保险库：当前真实保险库': '対象の保管庫：現在の真の保管庫',
  '提交前和提交时都会重新核对保险库范围与数据代次。': '保存の前と保存時に、保管庫の範囲とデータ世代を再確認します。',
  '新增账号': 'アカウントを追加',
  '更新账号': '更新するアカウント',
  '跳过账号': 'スキップするアカウント',
  '正式订阅': '正式なサブスクリプション',
  '待完善订阅': '補完が必要なサブスクリプション',
  '不支持项目': '未対応項目',
  '额度复核': '上限の再確認',
  '剩余账号 不限 · 剩余订阅 不限': '残りのアカウント：無制限 · 残りのサブスクリプション：無制限',
  '剩余账号 {accounts} · 剩余订阅 不限': '残りのアカウント：{accounts} · 残りのサブスクリプション：無制限',
  '剩余账号 不限 · 剩余订阅 {subscriptions}':
      '残りのアカウント：無制限 · 残りのサブスクリプション：{subscriptions}',
  '剩余账号 {accounts} · 剩余订阅 {subscriptions}':
      '残りのアカウント：{accounts} · 残りのサブスクリプション：{subscriptions}',
  '不限': '無制限',
  '我已核对来源、映射、密码状态和重复项处理。': '取得元、フィールド対応、パスワードの状態、重複項目の処理を確認しました。',
  '提交时会再次核对权威预览 token、保险库代次和免费版数量限制；任何冲突都会整批停止。':
      '保存時に、確定プレビューの token、保管庫の世代、無料版の件数上限を再確認します。競合があれば一括処理全体を停止します。',
  '导入未完成': 'インポートは完了していません',
  '批量导入已完成': '一括インポートが完了しました',
  '账号 {accounts} · 正式订阅 {formal} · 待完善 {pending} · 合并 {merged} · 跳过 {skipped} · 不支持 {unsupported}':
      'アカウント {accounts} · 正式なサブスクリプション {formal} · 要補完 {pending} · 統合 {merged} · スキップ {skipped} · 未対応 {unsupported}',
  '最近一次批量导入的本机加密回滚可用。': '直近の一括インポート用に、端末内の暗号化ロールバックを利用できます。',
  '本次没有生成可用的批量导入回滚；请先核对记录。': '今回、利用可能な一括インポートのロールバックは作成されませんでした。先に項目を確認してください。',
  '源文件可能仍含明文密码。请先核对导入记录和加密备份，再回到文件管理器自行安全删除；Cardock 不会擅自删除外部文件。':
      '元ファイルには平文のパスワードが残っている可能性があります。インポートした項目と暗号化バックアップを確認してから、ファイル管理アプリへ戻り、ご自身で安全に削除してください。Cardock が外部ファイルを無断で削除することはありません。',
  '继续完善订阅（{count}）': 'サブスクリプションを補完（{count}）',
  '完成并清空内存': '完了してメモリを消去',
  '上一步': '前へ',
  '确认并加密导入': '確認して暗号化インポート',
  '下一步': '次へ',
  '自动检测': '自動検出',
  '优先匹配已验证的来源；无法唯一识别时使用通用表格并要求核对映射。':
      '検証済みの取得元を優先します。一意に識別できない場合は汎用表を使用し、フィールド対応の確認を求めます。',
  '已验证的账号导入格式': '検証済みのアカウントインポート形式',
  '已验证的订阅导入格式': '検証済みのサブスクリプションインポート形式',
  '尚未完成官方格式验证，当前禁用': '公式形式の検証が完了していないため無効',
  '该来源尚未完成格式验证，当前不能启用。': 'この取得元は形式の検証が完了していないため、現在は有効にできません。',
  '保险库当前不能写入，请重新完整解锁。': '現在、保管庫へ書き込めません。完全にロック解除し直してください。',
  '文件解析或来源检测失败；本机数据未改变。': 'ファイルの解析または取得元の検出に失敗しました。端末内のデータは変更されていません。',
  '请先读取第一张账号或订阅表。': '先に 1 つ目のアカウント表またはサブスクリプション表を読み込んでください。',
  '当前会话不能再追加文件；如需重选请清空后重新开始。':
      'このセッションにはこれ以上ファイルを追加できません。選び直す場合は内容を消去して最初からやり直してください。',
  '追加文件来源尚未完成格式验证。': '追加ファイルの取得元は形式の検証が完了していません。',
  '第二个文件必须是已验证的订阅表。': '2 つ目のファイルは検証済みのサブスクリプション表である必要があります。',
  '第二个文件必须是已验证的账号表。': '2 つ目のファイルは検証済みのアカウント表である必要があります。',
  '第二个文件无法作为配套账号/订阅表追加；本机数据未改变。':
      '2 つ目のファイルを対応するアカウント表またはサブスクリプション表として追加できませんでした。端末内のデータは変更されていません。',
  '字段映射无效。': 'フィールド対応が無効です。',
  '字段映射冲突，请核对重复目标和被排除的敏感列。': 'フィールド対応が競合しています。重複する割り当て先と除外された機密列を確認してください。',
  '该行没有需要确认的遮挡占位密码。': 'この行には確認が必要な伏せ字のパスワードがありません。',
  '所选已有账号不再是当前重复候选。': '選択した既存アカウントは現在の重複候補ではなくなりました。',
  '所选关联账号已不可用，请重新选择。': '選択した関連アカウントは利用できなくなりました。選び直してください。',
  '请先选择并读取一个文件。': '先にファイルを選択して読み込んでください。',
  '请先为每条订阅选择本次导入的账号或保险库中的已有账号。':
      'サブスクリプションごとに、今回インポートするアカウントまたは保管庫内の既存アカウントを選択してください。',
  '仍有未处理的重复项或免费版数量限制，未进入最终确认。': '未処理の重複項目または無料版の件数上限が残っているため、最終確認へ進めません。',
  '当前步骤无法继续；请核对映射、重复项和数量限制。': 'このステップを続行できません。フィールド対応、重複項目、件数上限を確認してください。',
  '权威预览计划无效，请返回重新核对。': '確定プレビュー計画が無効です。戻ってもう一度確認してください。',
  '保险库数据已变化，权威预览已失效；请重新导入文件。':
      '保管庫のデータが変更されたため、確定プレビューは無効になりました。ファイルをもう一度インポートしてください。',
  '免费版可用数量已变化，本次整批未写入。': '無料版で利用可能な件数が変わりました。今回の一括データは何も書き込まれていません。',
  '保险库已锁定或处于订阅只读视图，本次整批未写入。':
      '保管庫がロックされているか、サブスクリプションのみの表示になっています。今回の一括データは何も書き込まれていません。',
  '本机加密写入失败，本次整批未提交。': '端末内の暗号化書き込みに失敗しました。一括処理は保存されていません。',
  '批量导入校验失败，本次整批未写入。': '一括インポートの検証に失敗しました。今回の一括データは何も書き込まれていません。',
  '保险库状态已变化，迁移内存已清空。': '保管庫の状態が変わったため、移行データをメモリから消去しました。',
  '已有账号': '既存アカウント',
  '第 {row} 行账号': '{row} 行目のアカウント',
  '该行缺少账号必要字段或包含无效值。': 'この行にはアカウントの必須フィールドがないか、無効な値が含まれています。',
  '发现 {count} 个疑似重复项。': '重複の可能性がある項目が {count} 件見つかりました。',
  '第 {row} 行订阅草稿': '{row} 行目のサブスクリプション下書き',
  '请选择关联账号，或先追加含相同 account_key 的账号表。':
      '関連付けるアカウントを選択するか、同じ account_key を含むアカウント表を先に追加してください。',
  '分号': 'セミコロン',
  '订阅只读视图不能导入，请先完整解锁保险库': 'サブスクリプションのみの表示ではインポートできません。先に保管庫を完全にロック解除してください',
  '诱饵保险库不能使用真实数据迁移中心': 'おとり保管庫では真のデータ移行センターを使用できません',
  '{count} 条加密草稿等待补全': '暗号化された下書き {count} 件が補完を待っています',
  '独立加密回滚 · 将影响 {count} 条记录': '独立した暗号化ロールバック · {count} 件に影響',
  '仅撤销最近一次批量导入，不使用备份恢复副本': '直近の一括インポートだけを取り消し、バックアップ復元用コピーは使用しません',
  '撤销最近一次批量导入？': '直近の一括インポートを取り消しますか？',
  '这与“恢复到上次备份导入前”完全独立。只会撤销最近一次批量导入的精确加密快照：新增账号 {added}、更新账号 {updated}、正式订阅 {formal}、待完善草稿 {pending}，共影响 {affected} 条。\n\n如果批量导入后已有其他保存，入口会自动失效，不会覆盖后续修改。':
      'これは「前回のバックアップインポート前に戻す」とは完全に独立しています。直近の一括インポートの正確な暗号化スナップショットだけを取り消します。新規アカウント {added} 件、更新したアカウント {updated} 件、正式なサブスクリプション {formal} 件、要補完の下書き {pending} 件、合計 {affected} 件に影響します。\n\n一括インポート後に別の保存が行われると、この項目は自動的に無効になり、その後の変更を上書きすることはありません。',
  '确认撤销这一次批量导入': 'この一括インポートの取り消しを確定',
  '最近一次批量导入已撤销。': '直近の一括インポートを取り消しました。',
  '撤销条件已变化；没有覆盖当前数据。': '取り消し条件が変わりました。現在のデータは上書きされていません。',
  '没有待完善订阅。批量导入中的不完整订阅会加密保存在这里。':
      '補完が必要なサブスクリプションはありません。一括インポートの不完全なサブスクリプションはここに暗号化して保存されます。',
  '关联 {account} · 还需完善 {count} 项': '{account} に関連付け済み · 残り {count} 項目',
  '订阅已完善并加密保存。': 'サブスクリプションを補完し、暗号化して保存しました。',
  '订阅内容仍不完整或数量限制已变化；原草稿已保留。': 'サブスクリプションがまだ不完全か、件数上限が変わりました。元の下書きは保持されています。',
  '关联账号': '関連アカウント',
  '正在保存…': '保存しています…',
  '完成并转为正式订阅': '補完して正式なサブスクリプションとして保存',
  '确认批量导入': '一括インポートを確認',
  '账号关联键': 'アカウント関連キー',
  '密码': 'パスワード',
  '备注': 'メモ',
  '方案名称': 'プラン名',
  '金额': '金額',
  '币种': '通貨',
  '账单周期': '請求周期',
  '首次订阅日期': '利用開始日',
  '下次续费日期': '次回更新日',
  '自动续费': '自動更新',
  '支付方式': '支払い方法',
  '提前提醒天数': '事前通知の日数',
  '先确认导出文件中缺失的正式订阅字段。Cardock 不会猜测续费日期、账单周期、自动续费或提醒天数。':
      'まず、書き出したファイルにない正式なサブスクリプションの必須項目を確認してください。Cardock が更新日、請求周期、自動更新、通知日数を推測することはありません。',
  '先确认导出文件中缺失的正式订阅字段。Cardock 不会用续费日期代替首次订阅日期，也不会猜测日期、账单周期、自动续费或提醒天数。':
      'まず、書き出したファイルにない正式なサブスクリプションの必須項目を確認してください。Cardock は次回更新日を利用開始日の代わりに使わず、日付、請求周期、自動更新、通知日数を推測しません。',
  '尚未选择': '未選択',
  '选择': '選択',
  '每几个周期': '周期単位の数',
  '周期单位': '周期の単位',
  '天': '日',
  '周': '週',
  '月': '月',
  '年': '年',
  '是否自动续费': '自動更新しますか？',
  '是': 'はい',
  '否': 'いいえ',
  '请输入 0 到 365。': '0 から 365 までの数値を入力してください。',
  '使用这些值继续填写': 'この値で入力を続ける',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过 · 剩余账号 {accounts} · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：合格 · 残りのアカウント {accounts} 件 · 残りのサブスクリプション {subscriptions} 件\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过 · 剩余账号 {accounts}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：合格 · 残りのアカウント {accounts} 件\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过 · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：合格 · 残りのサブスクリプション {subscriptions} 件\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：通过\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：合格\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过 · 剩余账号 {accounts} · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：不合格 · 残りのアカウント {accounts} 件 · 残りのサブスクリプション {subscriptions} 件\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过 · 剩余账号 {accounts}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：不合格 · 残りのアカウント {accounts} 件\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过 · 剩余订阅 {subscriptions}\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：不合格 · 残りのサブスクリプション {subscriptions} 件\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
  '当前真实保险库 · 已选 {selected} 条\n新增账号 {added} · 更新账号 {updated} · 跳过账号 {skipped}\n正式订阅 {formal} · 待完善草稿 {pending} · 不支持 {unsupported}\n额度复核：未通过\n审批卡不显示密码原文；批准时会再次核对保险库代次和计划。':
      '現在の真の保管庫 · {selected} 件を選択\n新規アカウント {added} 件 · 更新するアカウント {updated} 件 · スキップするアカウント {skipped} 件\n正式なサブスクリプション {formal} 件 · 要補完の下書き {pending} 件 · 未対応 {unsupported} 件\n上限の再確認：不合格\nこの承認カードにはパスワードそのものを表示しません。承認時に保管庫の世代と計画を再確認します。',
};
