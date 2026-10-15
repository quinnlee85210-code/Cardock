// Stage 4 product copy. Chinese source keys; no user data.
const stage4EnglishTranslations = <String, String>{
  "隐私模式": "Private",
  "服务名称模式": "Service name",
  "完整订阅摘要模式": "Full subscription summary",
  "通知内容隐私": "Notification privacy",
  "默认仅显示通用事项；同一时刻的多项同类提醒始终合并为通用数量摘要。":
      "Generic content is the default. Reminders of the same type at the same time always use a combined generic count.",
  "仅在真实保险库完整解锁且空闲时可修改；诱饵库和订阅只读视图不可修改。":
      "Change this only while the real vault is fully unlocked and idle. Decoy vaults and read-only subscription views cannot change it.",
  "切回隐私模式会重排待发提醒，但无法删除其他设备或系统已经保留的通知副本。":
      "Switching to Private rebuilds pending reminders. Copies already retained by the system or other devices cannot be removed.",
  "允许通知显示订阅信息？": "Show subscription information in notifications?",
  "服务名称、日期和金额可能出现在锁屏、通知历史、手表或系统同步中，并在切回隐私模式后继续保留。账号、密码和备注永远不会进入通知。":
      "Service names, dates and amounts may appear on lock screens, in notification history, on watches or through system sync, and remain after switching back to Private. Login details, passwords and notes are never included.",
  "确认显示": "Allow display",
  "通知隐私设置已保存；待发提醒按当前设置重新协调。":
      "Notification privacy saved; pending reminders are reconciled with the current setting.",
  "通知隐私设置未完成，请重试；业务数据未改变。":
      "Notification privacy could not be saved. Retry; your records have not changed.",
  "不设置": "None",
  "当天": "On the day",
  "1 天前": "1 day before",
  "3 天前": "3 days before",
  "7 天前": "7 days before",
  "系统日历可能同步到华为、Google、Microsoft 等云账户。外部事件 不再受Cardock加密保险库控制；Cardock无法删除其他应用或云端副本。修改Cardock记录不会更新外部事件，重复添加仍可能产生重复日程。":
      "Your calendar may sync to cloud accounts such as Huawei, Google or Microsoft. External events are outside the encrypted Cardock vault; Cardock cannot remove copies in other apps or the cloud. Editing a Cardock record does not update external events, and repeated additions may create duplicates.",
  "确认打开系统日历？": "Open system calendar?",
  "共 {count} 个事件；提醒：{alarm}": "{count} events; reminder: {alarm}",
  "日历应用可能忽略提醒点，请在保存界面核对。":
      "Calendar apps may ignore the reminder offset. Check it before saving.",
  "无法打开系统日历。请确认手机已安装可用的日历应用后重试。":
      "Cannot open the system calendar. Check that a calendar app is installed and available, then try again.",
  "已打开系统日历编辑界面，请核对提醒并自行保存；Cardock无法确认保存结果。":
      "The system calendar editor is open. Check the reminder and save it yourself; Cardock cannot confirm whether it was saved.",
  "加入系统日历": "Add to system calendar",
  "请完整解锁当前保险库后加入系统日历。":
      "Fully unlock the current vault to add a system calendar event.",
  "本次日历内容（独立于通知隐私设置）":
      "Content for this event (separate from notification privacy)",
  "本次日历提醒": "Reminder for this event",
  "当前无法生成日历预览，请完整解锁后重新打开。":
      "Calendar preview is unavailable. Fully unlock and reopen this page.",
  "预览：续费 {renewals}、试用 {trials}；排除 {excluded} 条记录":
      "Preview: {renewals} renewals, {trials} trials; {excluded} records excluded",
  "已暂停、取消或结束": "Paused, cancelled or ended",
  "日期早于今天": "Date is before today",
  "无法可靠确定日期": "Date cannot be determined reliably",
  "续费日期与历史区间冲突": "Renewal date conflicts with history",
  "预览日历内容": "Preview calendar content",
  "当前记录没有可添加的有效日历日期。": "This record has no valid date to add to the calendar.",
  "确认并打开系统日历": "Confirm and open calendar",
  "Chrome 密码 CSV": "Chrome passwords CSV",
  "Google Password Manager CSV": "Google Password Manager CSV",
  "支持 Chrome、Google Password Manager、Bitwarden、KeePassXC、1Password 与 Cardock 模板":
      "Supports Chrome, Google Password Manager, Bitwarden, KeePassXC, 1Password and Cardock templates",
  "XLSX、DOCX、CSV、TSV 或 TXT 文件可能包含明文密码。请仅在可信设备操作，不要发送到聊天或公共网盘。解析只在本次内存中进行；导入与加密备份核对后，请自行处理源文件。备份仅保护已导入的记录，不会保护或删除外部 CSV 及其他副本。":
      "XLSX, DOCX, CSV, TSV or TXT files may contain plaintext passwords. Use a trusted device; do not send them to chats or public cloud drives. Parsing uses memory for this session only. After checking the import and encrypted backup, handle the source file yourself. Backups protect imported records only; they do not protect or delete external CSV files or other copies.",
  "改用通用映射": "Use generic mapping",
  "所选来源：{selected}；实际识别：{actual}。文件结构不匹配，尚未生成导入计划；可改用通用映射。":
      "Selected source: {selected}; detected: {actual}. The structure does not match, so no import plan was created. You can use generic mapping.",
  "保留密码 {preserved} · 掩码已排除 {masked} · 空密码 {empty} · 未映射列 {unmapped} · 未解决重复 {unresolved}":
      "Passwords kept {preserved} · masked excluded {masked} · empty {empty} · unmapped columns {unmapped} · unresolved duplicates {unresolved}",
  "源文件可能仍含明文密码。请先核对导入记录和加密备份，再自行处理源文件；Cardock 不会删除外部文件，也无法清理聊天、网盘、回收站或其他设备中的副本。自动备份只保护已导入的加密记录。":
      "The source file may still contain plaintext passwords. Check imported records and encrypted backups, then handle the source yourself. Cardock does not delete external files and cannot clear copies in chats, cloud drives, trash or other devices. Automatic backups protect imported encrypted records only.",
};

const stage4JapaneseTranslations = <String, String>{
  "隐私模式": "プライバシー",
  "服务名称模式": "サービス名",
  "完整订阅摘要模式": "購読の詳細概要",
  "通知内容隐私": "通知のプライバシー",
  "默认仅显示通用事项；同一时刻的多项同类提醒始终合并为通用数量摘要。":
      "初期設定では一般的な内容のみ表示します。同じ時刻の同種の通知は、常に件数だけの概要にまとめます。",
  "仅在真实保险库完整解锁且空闲时可修改；诱饵库和订阅只读视图不可修改。":
      "実保管庫が完全に解除され、処理中でない場合のみ変更できます。おとり保管庫と購読の読み取り専用表示では変更できません。",
  "切回隐私模式会重排待发提醒，但无法删除其他设备或系统已经保留的通知副本。":
      "プライバシーに戻すと未送信の通知を再設定します。システムや他の端末に保存された通知のコピーは削除できません。",
  "允许通知显示订阅信息？": "通知に購読情報を表示しますか？",
  "服务名称、日期和金额可能出现在锁屏、通知历史、手表或系统同步中，并在切回隐私模式后继续保留。账号、密码和备注永远不会进入通知。":
      "サービス名、日付、金額はロック画面、通知履歴、時計、システム同期に表示され、プライバシーに戻しても残る場合があります。ログイン情報、パスワード、メモは含めません。",
  "确认显示": "表示を許可",
  "通知隐私设置已保存；待发提醒按当前设置重新协调。": "通知のプライバシーを保存しました。未送信の通知を現在の設定に合わせて調整します。",
  "通知隐私设置未完成，请重试；业务数据未改变。": "通知のプライバシーを保存できませんでした。再試行してください。記録は変更されていません。",
  "不设置": "設定しない",
  "当天": "当日",
  "1 天前": "1 日前",
  "3 天前": "3 日前",
  "7 天前": "7 日前",
  "系统日历可能同步到华为、Google、Microsoft 等云账户。外部事件 不再受Cardock加密保险库控制；Cardock无法删除其他应用或云端副本。修改Cardock记录不会更新外部事件，重复添加仍可能产生重复日程。":
      "システムカレンダーは Huawei、Google、Microsoft などのクラウドと同期する場合があります。外部の予定 は Cardock の暗号化保管庫の管理外となり、他のアプリやクラウドのコピーは削除できません。Cardock の記録を変更しても外部の予定は更新されず、再度追加すると重複する場合があります。",
  "确认打开系统日历？": "システムカレンダーを開きますか？",
  "共 {count} 个事件；提醒：{alarm}": "予定 {count} 件、通知：{alarm}",
  "日历应用可能忽略提醒点，请在保存界面核对。": "カレンダーアプリが通知の指定を無視する場合があります。保存前に確認してください。",
  "无法打开系统日历。请确认手机已安装可用的日历应用后重试。":
      "システムカレンダーを開けません。利用可能なカレンダーアプリがインストールされていることを確認し、再試行してください。",
  "已打开系统日历编辑界面，请核对提醒并自行保存；Cardock无法确认保存结果。":
      "システムカレンダーの編集画面を開きました。通知を確認して保存してください。Cardock では保存結果を確認できません。",
  "加入系统日历": "システムカレンダーに追加",
  "请完整解锁当前保险库后加入系统日历。": "システムカレンダーに追加するには、現在の保管庫を完全に解除してください。",
  "本次日历内容（独立于通知隐私设置）": "今回のカレンダー内容（通知のプライバシーとは別）",
  "本次日历提醒": "今回のカレンダー通知",
  "当前无法生成日历预览，请完整解锁后重新打开。": "カレンダーをプレビューできません。完全に解除してから、この画面を開き直してください。",
  "预览：续费 {renewals}、试用 {trials}；排除 {excluded} 条记录":
      "プレビュー：更新 {renewals} 件、試用 {trials} 件、除外 {excluded} 件",
  "已暂停、取消或结束": "一時停止、解約、または終了",
  "日期早于今天": "日付が今日より前",
  "无法可靠确定日期": "日付を確実に判断できない",
  "续费日期与历史区间冲突": "更新日が履歴の期間と矛盾",
  "预览日历内容": "カレンダー内容のプレビュー",
  "当前记录没有可添加的有效日历日期。": "この記録には追加できる有効な日付がありません。",
  "确认并打开系统日历": "確認してカレンダーを開く",
  "Chrome 密码 CSV": "Chrome パスワード CSV",
  "Google Password Manager CSV": "Google Password Manager CSV",
  "支持 Chrome、Google Password Manager、Bitwarden、KeePassXC、1Password 与 Cardock 模板":
      "Chrome、Google Password Manager、Bitwarden、KeePassXC、1Password、Cardock テンプレートに対応",
  "XLSX、DOCX、CSV、TSV 或 TXT 文件可能包含明文密码。请仅在可信设备操作，不要发送到聊天或公共网盘。解析只在本次内存中进行；导入与加密备份核对后，请自行处理源文件。备份仅保护已导入的记录，不会保护或删除外部 CSV 及其他副本。":
      "XLSX、DOCX、CSV、TSV、TXT には平文のパスワードが含まれる場合があります。信頼できる端末で操作し、チャットや公開クラウドに送らないでください。解析は今回のメモリ内のみで行います。取り込みと暗号化バックアップを確認後、元ファイルを処理してください。バックアップは取り込み済みの記録だけを保護し、外部の CSV やコピーを保護・削除しません。",
  "改用通用映射": "汎用の対応付けを使う",
  "所选来源：{selected}；实际识别：{actual}。文件结构不匹配，尚未生成导入计划；可改用通用映射。":
      "選択した形式：{selected}、検出結果：{actual}。ファイル構造が一致しないため、取り込み計画を作成していません。汎用の対応付けに切り替えられます。",
  "保留密码 {preserved} · 掩码已排除 {masked} · 空密码 {empty} · 未映射列 {unmapped} · 未解决重复 {unresolved}":
      "保持したパスワード {preserved} · マスク除外 {masked} · 空欄 {empty} · 未対応の列 {unmapped} · 未解決の重複 {unresolved}",
  "源文件可能仍含明文密码。请先核对导入记录和加密备份，再自行处理源文件；Cardock 不会删除外部文件，也无法清理聊天、网盘、回收站或其他设备中的副本。自动备份只保护已导入的加密记录。":
      "元ファイルには平文のパスワードが残る場合があります。取り込んだ記録と暗号化バックアップを確認後、元ファイルを処理してください。Cardock は外部ファイルを削除せず、チャット、クラウド、ごみ箱、他の端末のコピーも消去できません。自動バックアップは取り込み済みの暗号化記録だけを保護します。",
};
