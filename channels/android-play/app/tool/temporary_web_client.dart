// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:math';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/temporary_web/temporary_web_batch_decision_state.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_crypto.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_pairing.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:archive/archive.dart';

const bool _includePairingDiagnostics = bool.fromEnvironment(
  'CARDOCK_BROWSER_DIAGNOSTICS',
);
const String _customCurrencyValue = '__custom__';

enum _PageLanguage { simplifiedChinese, english, japanese }

typedef _PageTranslation = ({String english, String japanese});

const Map<String, _PageTranslation>
_pageTranslations = <String, _PageTranslation>{
  "每个账号最多 10 个自定义字段。": (
    english: "Each account supports at most 10 custom fields.",
    japanese: "追加項目は1アカウントにつき最大10件です。",
  ),
  "申请显示敏感字段": (english: "Request sensitive field", japanese: "機密項目の表示を申請"),
  "字段名称": (english: "Field name", japanese: "項目名"),
  "字段类型": (english: "Field type", japanese: "項目タイプ"),
  "字段值": (english: "Field value", japanese: "項目値"),
  "敏感文本": (english: "Sensitive text", japanese: "機密テキスト"),
  "普通文本": (english: "Text", japanese: "通常のテキスト"),
  "日期": (english: "Date", japanese: "日付"),
  "数字": (english: "Number", japanese: "数値"),
  "留空保留已有值；输入可直接替换": (
    english: "Leave unchanged to keep the value; enter text to replace it",
    japanese: "変更しなければ既存値を保持します。入力すると置き換えます",
  ),
  "不建议保存私钥、助记词、支付密码、CVV、完整银行卡资料或验证码恢复码。": (
    english:
        "Do not use these fields for private keys, seed phrases, payment passwords, CVVs, full card details or recovery codes.",
    japanese: "秘密鍵、シードフレーズ、支払い用パスワード、CVV、完全なカード情報、リカバリーコードの保存は推奨しません。",
  ),
  "上移": (english: "Move up", japanese: "上へ"),
  "下移": (english: "Move down", japanese: "下へ"),

  '请选择一个 XLSX、DOCX、CSV、TSV 或 TXT 文件。': (
    english: 'Choose one XLSX, DOCX, CSV, TSV, or TXT file.',
    japanese: 'XLSX、DOCX、CSV、TSV、TXTのいずれか1ファイルを選択してください。',
  ),
  '正在处理另一个请求，请稍后再试。': (
    english: 'Another request is being processed. Try again shortly.',
    japanese: '別の処理を実行中です。少し待ってからもう一度お試しください。',
  ),
  '手机连接尚未建立，请重新连接后再试。': (
    english: 'The phone connection is not ready. Reconnect and try again.',
    japanese: 'スマートフォンとの接続が確立していません。再接続してからお試しください。',
  ),
  '无法读取所选文件。': (
    english: 'The selected file could not be read.',
    japanese: '選択したファイルを読み取れませんでした。',
  ),
  '浏览器无法读取所选文件（FILE_READER_ERROR）。请重新选择本地文件；若仍失败，请刷新网页并重新连接手机。': (
    english:
        'The browser could not read the selected file (FILE_READER_ERROR). Choose the local file again; if it still fails, refresh the page and reconnect the phone.',
    japanese:
        'ブラウザが選択したファイルを読み取れませんでした（FILE_READER_ERROR）。ローカルファイルを選び直し、再び失敗する場合はページを更新してスマートフォンへ再接続してください。',
  ),
  '浏览器返回了不支持的文件结果（FILE_READER_RESULT_TYPE）。请刷新网页后重新选择文件。': (
    english:
        'The browser returned an unsupported file result (FILE_READER_RESULT_TYPE). Refresh the page and choose the file again.',
    japanese:
        'ブラウザが未対応のファイル結果を返しました（FILE_READER_RESULT_TYPE）。ページを更新してファイルを選び直してください。',
  ),
  '文件上传或手机端解析未完成（BATCH_UPLOAD_FAILED）。请确认手机临时网页连接仍在运行，再重新选择文件。': (
    english:
        'The upload or phone-side parse did not finish (BATCH_UPLOAD_FAILED). Confirm that the temporary phone connection is still running, then choose the file again.',
    japanese:
        'アップロードまたはスマートフォン側の解析が完了しませんでした（BATCH_UPLOAD_FAILED）。一時接続が動作中であることを確認して、ファイルを選び直してください。',
  ),
  '已接收文件，正在读取…': (
    english: 'File received. Reading it now…',
    japanese: 'ファイルを受け取りました。読み込んでいます…',
  ),
  '手机端拒绝接收该批量文件。': (
    english: 'The phone rejected this batch file.',
    japanese: 'スマートフォンがこの一括ファイルを拒否しました。',
  ),
  '批量文件传输未完成，请重新选择文件。': (
    english: 'The batch file transfer did not finish. Choose the file again.',
    japanese: '一括ファイルの転送が完了しませんでした。ファイルをもう一度選択してください。',
  ),
  '手机已解锁，连接已恢复；未提交的网页内容仍保留。': (
    english:
        'The phone is unlocked and the connection has resumed. Unsubmitted page contents were preserved.',
    japanese: 'スマートフォンのロックが解除され、接続が復帰しました。未送信のページ内容は保持されています。',
  ),
  '手机锁定后权威批量预览已失效；网页选择仍保留，请重新选择文件生成预览。': (
    english:
        'The authoritative batch preview expired while the phone was locked. Your page selections remain visible; choose the file again to rebuild the preview.',
    japanese:
        'スマートフォンのロック中に正式な一括プレビューが失効しました。ページ上の選択内容は表示されたままです。ファイルをもう一度選択してプレビューを再作成してください。',
  ),
  '等待手机解锁': (english: 'Waiting for phone unlock', japanese: 'スマートフォンのロック解除待ち'),
  '页面已隐藏，临时密码已立即清除。': (
    english:
        'The page was hidden, so the temporary password was cleared immediately.',
    japanese: 'ページが非表示になったため、一時パスワードを直ちに消去しました。',
  ),
  '页面已离开，本地会话数据已清空。': (
    english: 'You left the page. Local session data has been cleared.',
    japanese: 'ページから移動したため、ローカルセッションのデータを消去しました。',
  ),
  '正在建立加密会话…': (
    english: 'Establishing an encrypted session…',
    japanese: '暗号化セッションを確立しています…',
  ),
  '正在连接手机（HELLO：读取本次会话信息）…': (
    english: 'Connecting to the phone (HELLO: reading session information)…',
    japanese: 'スマートフォンに接続しています（HELLO：セッション情報を取得中）…',
  ),
  '正在连接手机（LOCAL_CODE：校验连接码格式）…': (
    english:
        'Connecting to the phone (LOCAL_CODE: checking the connection code)…',
    japanese: 'スマートフォンに接続しています（LOCAL_CODE：接続コードを確認中）…',
  ),
  '正在连接手机（FINISH：提交一次性配对）…': (
    english: 'Connecting to the phone (FINISH: submitting one-time pairing)…',
    japanese: 'スマートフォンに接続しています（FINISH：ワンタイムペアリングを送信中）…',
  ),
  '正在连接手机（CONFIRM：确认加密通道）…': (
    english:
        'Connecting to the phone (CONFIRM: verifying the encrypted channel)…',
    japanese: 'スマートフォンに接続しています（CONFIRM：暗号化チャネルを確認中）…',
  ),
  '已连接手机': (english: 'Connected to phone', japanese: 'スマートフォンに接続済み'),
  '正在连接手机（INITIAL_SYNC：读取允许显示的数据）…': (
    english: 'Connecting to the phone (INITIAL_SYNC: loading permitted data)…',
    japanese: 'スマートフォンに接続しています（INITIAL_SYNC：表示を許可されたデータを取得中）…',
  ),
  '已与手机中的当前数据同步。': (
    english: 'Synced with the current data on your phone.',
    japanese: 'スマートフォンの最新データと同期しました。',
  ),
  '等待连接': (english: 'Waiting to connect', japanese: '接続待ち'),
  '连接码格式不正确（LOCAL_CODE）。请输入手机显示的 16 位连接码；可保留或省略连字符。': (
    english:
        'The connection code format is invalid (LOCAL_CODE). Enter the 16-character code shown on your phone, with or without hyphens.',
    japanese:
        '接続コードの形式が正しくありません（LOCAL_CODE）。スマートフォンに表示された16文字のコードを入力してください。ハイフンはあってもなくても構いません。',
  ),
  '已主动断开。请关闭此标签页。': (
    english: 'Disconnected. Close this tab.',
    japanese: '切断しました。このタブを閉じてください。',
  ),
  '选择“替换密码”后必须输入新密码。': (
    english: 'Enter a new password when Replace password is selected.',
    japanese: '「パスワードを置き換える」を選択した場合は、新しいパスワードを入力してください。',
  ),
  '账号已保存到手机。': (
    english: 'The account was saved to your phone.',
    japanese: 'アカウントをスマートフォンに保存しました。',
  ),
  '账号修改已保存到手机。': (
    english: 'The account changes were saved to your phone.',
    japanese: 'アカウントの変更をスマートフォンに保存しました。',
  ),
  '订阅已保存到手机。': (
    english: 'The subscription was saved to your phone.',
    japanese: 'サブスクリプションをスマートフォンに保存しました。',
  ),
  '订阅修改已保存到手机。': (
    english: 'The subscription changes were saved to your phone.',
    japanese: 'サブスクリプションの変更をスマートフォンに保存しました。',
  ),
  '等待手机确认；不要关闭手机页面。': (
    english:
        'Waiting for confirmation on your phone. Keep the phone page open.',
    japanese: 'スマートフォンでの確認を待っています。スマートフォンの画面を閉じないでください。',
  ),
  '手机数据已变化，已为你刷新；请核对后重试。': (
    english:
        'Phone data changed, so the page was refreshed. Review it and try again.',
    japanese: 'スマートフォンのデータが変更されたため、ページを更新しました。内容を確認してからもう一度お試しください。',
  ),
  '写入结果无法确认，请立即在手机端核对后再继续。': (
    english:
        'The save result could not be confirmed. Check it on your phone before continuing.',
    japanese: '保存結果を確認できません。続行する前にスマートフォンで確認してください。',
  ),
  '操作未完成，请检查输入。': (
    english: 'The operation was not completed. Check your entries.',
    japanese: '操作を完了できませんでした。入力内容を確認してください。',
  ),
  '连接中断，刚才的写入结果可能未知；请在手机解锁后核对。': (
    english:
        'The connection was interrupted, so the last save result may be unknown. Unlock your phone and verify it.',
    japanese: '接続が中断されたため、直前の保存結果を確認できない可能性があります。スマートフォンのロックを解除して確認してください。',
  ),
  '手机已确认，操作已完成。': (
    english: 'Confirmed on your phone. The operation is complete.',
    japanese: 'スマートフォンで確認され、操作が完了しました。',
  ),
  '该账号没有保存密码。': (
    english: 'No password is stored for this account.',
    japanese: 'このアカウントにはパスワードが保存されていません。',
  ),
  '手机确认未通过。': (
    english: 'The request was not approved on your phone.',
    japanese: 'スマートフォンで承認されませんでした。',
  ),
  '手机确认已超时。': (
    english: 'Phone confirmation timed out.',
    japanese: 'スマートフォンでの確認がタイムアウトしました。',
  ),
  '仅显示本次会话创建的记录': (
    english: 'Show only records created in this session',
    japanese: 'このセッションで作成した記録のみ表示',
  ),
  '显示历史摘要': (english: 'Show history summaries', japanese: '履歴の概要を表示'),
  '显示历史详情（历史密码不批量传输）': (
    english:
        'Show history details (historical passwords are not transferred in bulk)',
    japanese: '履歴の詳細を表示（過去のパスワードは一括送信されません）',
  ),
  '权限由手机端决定': (
    english: 'Permissions are controlled on your phone',
    japanese: '権限はスマートフォン側で管理されます',
  ),
  '允许编辑历史记录': (english: 'History editing is allowed', japanese: '履歴を編集できます'),
  '历史记录只读': (english: 'History is read-only', japanese: '履歴は読み取り専用です'),
  '可向手机申请临时显示历史密码': (
    english: 'You may request temporary access to a historical password',
    japanese: '過去のパスワードの一時表示をスマートフォンに申請できます',
  ),
  '不允许显示历史密码': (
    english: 'Historical passwords cannot be displayed',
    japanese: '過去のパスワードは表示できません',
  ),
  '当前权限范围内没有账号。': (
    english: 'No accounts are available within the current permissions.',
    japanese: '現在の権限で表示できるアカウントはありません。',
  ),
  '未命名账号': (english: 'Unnamed account', japanese: '名前のないアカウント'),
  '本次': (english: 'This session', japanese: '今回'),
  '历史': (english: 'History', japanese: '履歴'),
  '分类': (english: 'Category', japanese: 'カテゴリー'),
  'AI工具': (english: 'AI tools', japanese: 'AIツール'),
  '影音娱乐': (english: 'Entertainment', japanese: '動画・音楽'),
  '购物': (english: 'Shopping', japanese: 'ショッピング'),
  '社交': (english: 'Social', japanese: 'ソーシャル'),
  '办公': (english: 'Productivity', japanese: '仕事効率化'),
  '云服务': (english: 'Cloud services', japanese: 'クラウドサービス'),
  '金融': (english: 'Finance', japanese: '金融'),
  '保险': (english: 'Insurance', japanese: '保険'),
  '其他': (english: 'Other', japanese: 'その他'),
  '登录账号': (english: 'Sign-in ID', japanese: 'ログインID'),
  '用户名': (english: 'Username', japanese: 'ユーザー名'),
  '绑定手机': (english: 'Linked phone', japanese: '連携済み電話番号'),
  '绑定邮箱': (english: 'Linked email', japanese: '連携済みメール'),
  '网站': (english: 'Website', japanese: 'ウェブサイト'),
  '备注': (english: 'Notes', japanese: 'メモ'),
  '订阅数': (english: 'Subscriptions', japanese: 'サブスクリプション数'),
  '编辑': (english: 'Edit', japanese: '編集'),
  '申请删除': (english: 'Request deletion', japanese: '削除を申請'),
  '删除': (english: 'Delete', japanese: '削除'),
  '显示本次密码 30 秒': (
    english: 'Show this-session password for 30 seconds',
    japanese: '今回のパスワードを30秒間表示',
  ),
  '向手机申请显示密码': (
    english: 'Request password display on phone',
    japanese: 'パスワード表示をスマートフォンに申請',
  ),
  '当前权限范围内没有订阅。': (
    english: 'No subscriptions are available within the current permissions.',
    japanese: '現在の権限で表示できるサブスクリプションはありません。',
  ),
  '未命名订阅': (english: 'Unnamed subscription', japanese: '名前のないサブスクリプション'),
  '首次订阅': (english: 'Started', japanese: '初回登録日'),
  '下次续费': (english: 'Next renewal', japanese: '次回更新日'),
  '状态': (english: 'Status', japanese: 'ステータス'),
  '方案': (english: 'Plan', japanese: 'プラン'),
  '金额': (english: 'Amount', japanese: '金額'),
  '货币': (english: 'Currency', japanese: '通貨'),
  '周期': (english: 'Billing cycle', japanese: '請求周期'),
  '自动续费': (english: 'Auto-renew', japanese: '自動更新'),
  '支付方式': (english: 'Payment method', japanese: '支払い方法'),
  '提前提醒': (english: 'Reminder lead time', japanese: '事前通知'),
  '提醒已启用': (english: 'Reminders enabled', japanese: '通知を有効化'),
  '账号': (english: 'account', japanese: 'アカウント'),
  '订阅': (english: 'subscription', japanese: 'サブスクリプション'),
  '手机已确认。': (english: 'Confirmed on your phone.', japanese: 'スマートフォンで確認されました。'),
  '编辑账号': (english: 'Edit account', japanese: 'アカウントを編集'),
  '新增账号': (english: 'Add account', japanese: 'アカウントを追加'),
  '编辑订阅': (english: 'Edit subscription', japanese: 'サブスクリプションを編集'),
  '新增订阅': (english: 'Add subscription', japanese: 'サブスクリプションを追加'),
  '批量迁移': (english: 'Batch migration', japanese: '一括移行'),
  '单条录入': (english: 'Single entry', japanese: '1件ずつ入力'),
  '手机端批量导入尚不可用。': (
    english: 'Batch import is not available on the phone.',
    japanese: 'スマートフォン側で一括インポートを利用できません。',
  ),
  '为防止通过重复结果探测隐藏历史，请先在手机为本次连接启用历史摘要或详情；也可改用手机迁移中心。': (
    english:
        'To prevent hidden-history probing through duplicate results, enable history summaries or details for this connection on your phone, or use the phone migration center.',
    japanese:
        '重複結果から非表示の履歴を推測されないよう、スマートフォンで今回の接続に履歴の概要または詳細を許可するか、スマートフォンの移行センターを使用してください。',
  ),
  '请选择一个 CSV、TSV 或 TXT 文件。': (
    english: 'Choose one CSV, TSV, or TXT file.',
    japanese: 'CSV、TSV、TXTファイルを1つ選択してください。',
  ),
  '批量文件不能超过 10 MiB。': (
    english: 'The batch file cannot exceed 10 MiB.',
    japanese: '一括ファイルは10 MiB以下にしてください。',
  ),
  '粘贴内容为空。': (
    english: 'The pasted content is empty.',
    japanese: '貼り付けた内容が空です。',
  ),
  '正在由手机生成权威预览…': (
    english: 'The phone is building the authoritative preview…',
    japanese: 'スマートフォンで正式なプレビューを作成しています…',
  ),
  '权威预览已生成。密码始终遮挡。': (
    english: 'The authoritative preview is ready. Passwords remain masked.',
    japanese: '正式なプレビューを作成しました。パスワードは常にマスクされます。',
  ),
  '账号文件': (english: 'Account file', japanese: 'アカウントファイル'),
  '订阅文件': (english: 'Subscription file', japanese: 'サブスクリプションファイル'),
  '未加入': (english: 'Not added', japanese: '未追加'),
  '当前编辑': (english: 'Editing now', japanese: '編集中'),
  '编辑此文件': (english: 'Edit this file', japanese: 'このファイルを編集'),
  '移除此文件': (english: 'Remove this file', japanese: 'このファイルを削除'),
  '已切换当前编辑文件。': (
    english: 'The active file was changed.',
    japanese: '編集対象のファイルを切り替えました。',
  ),
  '已从计划移除该文件。': (
    english: 'The file was removed from the plan.',
    japanese: '計画からこのファイルを削除しました。',
  ),
  '定义本次 account_key': (
    english: 'Defines an account_key in this plan',
    japanese: '今回の account_key を定義',
  ),
  '已关联本次账号': (
    english: 'Linked to an account in this plan',
    japanese: '今回のアカウントに関連付け済み',
  ),
  '缺少匹配 account_key': (
    english: 'No matching account_key',
    japanese: '一致する account_key がありません',
  ),
  '记录数': (english: 'Rows', japanese: '行数'),
  '请先应用当前映射与编辑，再切换文件。': (
    english: 'Apply the current mapping and edits before switching files.',
    japanese: 'ファイルを切り替える前に、現在のマッピングと編集を適用してください。',
  ),
  '未包含密码': (english: 'No password', japanese: 'パスワードなし'),
  '将加密导入': (english: 'Encrypted on import', japanese: '暗号化してインポート'),
  '已按规则排除': (english: 'Excluded by policy', japanese: 'ポリシーにより除外'),
  '订阅草稿': (english: 'Subscription draft', japanese: 'サブスクリプション下書き'),
  '跳过': (english: 'Skip', japanese: 'スキップ'),
  '只补充空字段': (english: 'Fill empty fields only', japanese: '空のフィールドのみ補完'),
  '仍创建另一条': (english: 'Create another record', japanese: '別の記録として作成'),
  '从本次导入移除': (english: 'Remove from this import', japanese: '今回のインポートから除外'),
  '忽略此列': (english: 'Ignore this column', japanese: 'この列を無視'),
  '没有可预览的记录。': (
    english: 'There are no records to preview.',
    japanese: 'プレビューできる記録がありません。',
  ),
  '至少选择一条可导入记录。': (
    english: 'Select at least one record to import.',
    japanese: 'インポートする記録を1件以上選択してください。',
  ),
  '请先勾选最终确认。': (
    english: 'Complete the final confirmation first.',
    japanese: '先に最終確認をオンにしてください。',
  ),
  '正在手机端重新验证并一次提交…': (
    english: 'The phone is revalidating and committing in one operation…',
    japanese: 'スマートフォンで再検証し、1回の操作でコミットしています…',
  ),
  '批量导入已提交到手机。': (
    english: 'The batch import was committed on the phone.',
    japanese: '一括インポートをスマートフォンにコミットしました。',
  ),
  '手机数据已变化，权威预览已失效；请重新生成。': (
    english:
        'Phone data changed, so the authoritative preview expired. Build it again.',
    japanese: 'スマートフォンのデータが変更されたため、正式なプレビューは無効です。再作成してください。',
  ),
  '批量迁移内存已清空。': (
    english: 'Batch migration memory was cleared.',
    japanese: '一括移行のメモリを消去しました。',
  ),
  '可导入': (english: 'Ready', japanese: 'インポート可能'),
  '阻断': (english: 'Blocked', japanese: 'ブロックあり'),
  '选择关联账号': (english: 'Choose a linked account', japanese: '関連アカウントを選択'),
  '仅填充空白字段的默认值': (
    english: 'Default value for blank fields only',
    japanese: '空欄フィールドだけに適用する既定値',
  ),
  '添加批量默认值': (english: 'Add batch default', japanese: '一括既定値を追加'),
  '应用映射与编辑并重新预览': (
    english: 'Apply mapping and edits, then rebuild preview',
    japanese: 'マッピングと編集を適用してプレビューを再作成',
  ),
  '已设置默认值': (english: 'Default set', japanese: '既定値を設定しました'),
  '只填空白字段': (english: 'blank fields only', japanese: '空欄フィールドのみ'),
  '正在手机端重建权威预览…': (
    english: 'The phone is rebuilding the authoritative preview…',
    japanese: 'スマートフォンで正式なプレビューを再作成しています…',
  ),
  '映射与编辑已由手机重建并重新验证。': (
    english: 'The phone rebuilt and revalidated the mapping and edits.',
    japanese: 'スマートフォンでマッピングと編集を再構築し、再検証しました。',
  ),
  '编辑未通过权威重建，本次批量内存已清空。': (
    english:
        'The authoritative rebuild rejected the edits. Batch memory was cleared.',
    japanese: '正式な再構築で編集が拒否されたため、一括移行メモリを消去しました。',
  ),
  '正式订阅': (english: 'formal subscriptions', japanese: '正式なサブスクリプション'),
  '待完善订阅': (english: 'pending subscriptions', japanese: '要入力のサブスクリプション'),
  '不支持': (english: 'unsupported', japanese: '未対応'),
  'accountKey': (english: 'Account key', japanese: 'アカウントキー'),
  'platformName': (english: 'Platform', japanese: 'プラットフォーム'),
  'loginAccount': (english: 'Sign-in ID', japanese: 'ログインID'),
  'phone': (english: 'Phone', japanese: '電話番号'),
  'email': (english: 'Email', japanese: 'メール'),
  'url': (english: 'URL', japanese: 'URL'),
  'notes': (english: 'Notes', japanese: 'メモ'),
  'planName': (english: 'Plan', japanese: 'プラン'),
  'amount': (english: 'Amount', japanese: '金額'),
  'currency': (english: 'Currency', japanese: '通貨'),
  'billingCycle': (english: 'Billing cycle', japanese: '請求周期'),
  'subscriptionStartDate': (
    english: 'Subscription start date',
    japanese: '契約開始日',
  ),
  'nextRenewalDate': (english: 'Next renewal', japanese: '次回更新日'),
  'autoRenew': (english: 'Auto-renew', japanese: '自動更新'),
  'paymentMethod': (english: 'Payment method', japanese: '支払方法'),
  'reminderDays': (english: 'Reminder days', japanese: '通知日数'),
  '不关联账号 · 独立订阅': (
    english: 'No linked account · Standalone subscription',
    japanese: 'アカウントに関連付けない · 単独のサブスクリプション',
  ),
  '密码显示时间已结束。': (
    english: 'The password display period has ended.',
    japanese: 'パスワードの表示時間が終了しました。',
  ),
  '手机端会话时限已到，页面数据已清空。': (
    english: 'The phone session expired. Page data has been cleared.',
    japanese: 'スマートフォン側のセッション期限が切れたため、ページのデータを消去しました。',
  ),
  '本次连接已达到 30 分钟绝对上限，页面数据已清空。': (
    english:
        'This connection reached the 30-minute limit. Page data has been cleared.',
    japanese: 'この接続は30分の上限に達したため、ページのデータを消去しました。',
  ),
  '网页已达到手机设置的无操作时限，页面数据已清空。': (
    english:
        'The inactivity limit set on your phone was reached. Page data has been cleared.',
    japanese: 'スマートフォンで設定した無操作時間を超えたため、ページのデータを消去しました。',
  ),
  '连接已结束。若刚才有写入，请在手机解锁后核对结果。': (
    english:
        'The connection ended. If you just saved something, unlock your phone and verify the result.',
    japanese: '接続が終了しました。直前に保存した場合は、スマートフォンのロックを解除して結果を確認してください。',
  ),
  '已断开': (english: 'Disconnected', japanese: '切断済み'),
  '天': (english: 'day', japanese: '日'),
  '周': (english: 'week', japanese: '週'),
  '月': (english: 'month', japanese: 'か月'),
  '年': (english: 'year', japanese: '年'),
  '是': (english: 'Yes', japanese: 'はい'),
  '否': (english: 'No', japanese: 'いいえ'),
  '正常': (english: 'Active', japanese: '有効'),
  '暂停': (english: 'Paused', japanese: '一時停止'),
  '已取消': (english: 'Canceled', japanese: '解約済み'),
  '已到期': (english: 'Expired', japanese: '期限切れ'),
  '记录已发生变化，请在网页刷新后重新提交。': (
    english: 'The record changed. Refresh the page and submit again.',
    japanese: '記録が変更されました。ページを更新してからもう一度送信してください。',
  ),
  '手机端已拒绝。': (english: 'Rejected on your phone.', japanese: 'スマートフォンで拒否されました。'),
  '网页会话已结束。': (
    english: 'The web session has ended.',
    japanese: 'ウェブセッションは終了しました。',
  ),
  '客户端地址与已确认会话不一致。': (
    english: 'The client address does not match the confirmed session.',
    japanese: 'クライアントのアドレスが確認済みセッションと一致しません。',
  ),
  '手机保险库状态已变化。': (
    english: 'The vault state changed on your phone.',
    japanese: 'スマートフォンの保管庫の状態が変わりました。',
  ),
  '本会话中没有该操作结果。': (
    english: 'No result for this operation exists in this session.',
    japanese: 'このセッションには該当する操作結果がありません。',
  ),
  '提交内容无效。': (
    english: 'The submitted content is invalid.',
    japanese: '送信内容が無効です。',
  ),
  '手机数据已变化，请刷新网页后再操作。': (
    english: 'Phone data changed. Refresh the page before continuing.',
    japanese: 'スマートフォンのデータが変更されました。ページを更新してから操作してください。',
  ),
  '账号记录不存在。': (
    english: 'The account record does not exist.',
    japanese: 'アカウント記録が存在しません。',
  ),
  '订阅记录不存在。': (
    english: 'The subscription record does not exist.',
    japanese: 'サブスクリプション記録が存在しません。',
  ),
  '确认结果不存在或已过期。': (
    english: 'The confirmation result does not exist or has expired.',
    japanese: '確認結果が存在しないか、有効期限が切れています。',
  ),
  '关联账号不存在。': (
    english: 'The linked account does not exist.',
    japanese: '関連付けたアカウントが存在しません。',
  ),
  '关联账号不在本会话可见范围内。': (
    english: 'The linked account is outside this session scope.',
    japanese: '関連付けたアカウントはこのセッションの表示範囲外です。',
  ),
  '订阅周期或状态无效。': (
    english: 'The billing cycle or status is invalid.',
    japanese: '請求周期またはステータスが無効です。',
  ),
  '密码修改方式无效。': (
    english: 'The password update method is invalid.',
    japanese: 'パスワードの更新方法が無効です。',
  ),
  '账号未能保存。': (
    english: 'The account could not be saved.',
    japanese: 'アカウントを保存できませんでした。',
  ),
  '账号修改未能保存。': (
    english: 'The account changes could not be saved.',
    japanese: 'アカウントの変更を保存できませんでした。',
  ),
  '账号删除结果未确认。': (
    english: 'The account deletion result could not be confirmed.',
    japanese: 'アカウントの削除結果を確認できませんでした。',
  ),
  '订阅未能保存。': (
    english: 'The subscription could not be saved.',
    japanese: 'サブスクリプションを保存できませんでした。',
  ),
  '订阅修改未能保存。': (
    english: 'The subscription changes could not be saved.',
    japanese: 'サブスクリプションの変更を保存できませんでした。',
  ),
  '订阅删除结果未确认。': (
    english: 'The subscription deletion result could not be confirmed.',
    japanese: 'サブスクリプションの削除結果を確認できませんでした。',
  ),
  '保存结果无法唯一确认，请在手机端核对。': (
    english: 'The save result is uncertain. Check it on your phone.',
    japanese: '保存結果を一意に確認できません。スマートフォンで確認してください。',
  ),
  '手机保险库状态在写入期间发生变化，请解锁后核对结果。': (
    english:
        'The vault state changed while saving. Unlock your phone and verify the result.',
    japanese: '保存中にスマートフォンの保管庫の状態が変わりました。ロックを解除して結果を確認してください。',
  ),
  '本会话未允许编辑历史账号。': (
    english: 'This session does not allow editing historical accounts.',
    japanese: 'このセッションでは履歴のアカウントを編集できません。',
  ),
  '本会话未允许编辑历史订阅。': (
    english: 'This session does not allow editing historical subscriptions.',
    japanese: 'このセッションでは履歴のサブスクリプションを編集できません。',
  ),
  '不支持的网页操作。': (
    english: 'This web operation is not supported.',
    japanese: 'このウェブ操作には対応していません。',
  ),
  '该历史账号不在本会话可见范围内。': (
    english: 'This historical account is outside the visible session scope.',
    japanese: 'この履歴アカウントはセッションの表示範囲外です。',
  ),
  '该历史订阅不在本会话可见范围内。': (
    english:
        'This historical subscription is outside the visible session scope.',
    japanese: 'この履歴サブスクリプションはセッションの表示範囲外です。',
  ),
  '本会话未允许查看历史密码。': (
    english: 'This session does not allow viewing historical passwords.',
    japanese: 'このセッションでは過去のパスワードを表示できません。',
  ),
  '本次新建账号的密码已随详情提供。': (
    english:
        'The password for an account created in this session is already included in its details.',
    japanese: '今回作成したアカウントのパスワードは、すでに詳細に含まれています。',
  ),
  '手机保险库在写入期间结束了旧网页会话；请在手机端核对结果。': (
    english:
        'The phone vault ended the previous web session while saving. Verify the result on your phone.',
    japanese: '保存中にスマートフォンの保管庫が以前のウェブセッションを終了しました。スマートフォンで結果を確認してください。',
  ),
  '旧网页会话已结束。': (
    english: 'The previous web session has ended.',
    japanese: '以前のウェブセッションは終了しました。',
  ),
  '连接码格式不正确（LOCAL_CODE）。请输入手机显示的 8 位大写英文字母，不要输入数字。': (
    english:
        'The connection code format is invalid (LOCAL_CODE). Enter the 8 uppercase English letters shown on your phone; do not enter digits.',
    japanese:
        '接続コードの形式が正しくありません（LOCAL_CODE）。スマートフォンに表示された英大文字8文字を入力し、数字は入力しないでください。',
  ),
  '手机暂时锁定，连接仍保留；请先解锁同一个保险库，再点击“刷新”或重新提交。': (
    english:
        'The phone is locked, but the connection is being kept. Unlock the same vault, then click Refresh or submit again.',
    japanese:
        'スマートフォンはロックされていますが、接続は維持されています。同じ保管庫をアンロックしてから、「更新」を押すか再送信してください。',
  ),
  '请求已发送到手机。请在卡坞“电脑临时录入”页面弹窗中点击“批准本次操作”。': (
    english:
        'The request was sent to your phone. In Cardock, tap Approve this action in the dialog on the Temporary PC Entry page.',
    japanese:
        'リクエストをスマートフォンに送信しました。Cardockの「PCから一時入力」ページに表示されるダイアログで「今回の操作を許可」を押してください。',
  ),
  '先选择文件并完成手机端权威预览。': (
    english:
        'Choose a file and complete the authoritative phone preview first.',
    japanese: 'まずファイルを選択し、スマートフォン側の正式なプレビューを完了してください。',
  ),
  '订阅必须关联账号，但本次连接没有获准显示可选账号。请在手机重新开启连接并选择“历史摘要”或“历史详情”，或在同一批次加入账号文件。': (
    english:
        'A subscription must be linked to an account, but this session is not allowed to show any account choices. Start a new session on the phone with History summary or History details, or add an account file to the same batch.',
    japanese:
        'サブスクリプションにはアカウントの関連付けが必要ですが、このセッションでは選択可能なアカウントを表示できません。スマートフォンで「履歴の概要」または「履歴の詳細」を選んで新しいセッションを開始するか、同じ一括処理にアカウントファイルを追加してください。',
  ),
  '请先在表格“处理方式”列选择关联账号；只有一个可选账号时会自动关联。': (
    english:
        'Choose a linked account in the table Action column first. If there is only one choice, it is linked automatically.',
    japanese: 'まず表の「処理方法」列で関連付けるアカウントを選択してください。候補が1件だけの場合は自動で関連付けます。',
  ),
  '请至少选择一条可导入记录。': (
    english: 'Select at least one importable record.',
    japanese: 'インポート可能な記録を1件以上選択してください。',
  ),
  '点击后会在手机弹出批准框；请拿起手机点击“批准本次操作”。': (
    english:
        'After you click, an approval dialog appears on the phone. Pick up the phone and tap Approve this action.',
    japanese: 'クリックするとスマートフォンに承認ダイアログが表示されます。スマートフォンを手に取り、「今回の操作を許可」を押してください。',
  ),
  '本次连接没有获准显示可关联账号': (
    english: 'This session is not allowed to show linkable accounts',
    japanese: 'このセッションでは関連付け可能なアカウントを表示できません',
  ),
  '所选连接时间已到，页面数据已清空。': (
    english:
        'The selected connection duration has ended. Page data was cleared.',
    japanese: '選択した接続時間が終了したため、ページのデータを消去しました。',
  ),
};

_PageLanguage _pageLanguageFromCode(String? code) => switch (code) {
  'en' => _PageLanguage.english,
  'ja' => _PageLanguage.japanese,
  _ => _PageLanguage.simplifiedChinese,
};

String _tr(_PageLanguage language, String chinese) {
  final translation = _pageTranslations[chinese];
  if (translation == null) return chinese;
  return switch (language) {
    _PageLanguage.simplifiedChinese => chinese,
    _PageLanguage.english => translation.english,
    _PageLanguage.japanese => translation.japanese,
  };
}

Future<void> main() async {
  _TemporaryWebClient().initialize();
}

final class _TemporaryWebClient {
  _PageLanguage _language = _pageLanguageFromCode(
    Uri.base.queryParameters['lang'],
  );
  final FormElement _pairingForm = _element<FormElement>('pairing-form');
  final InputElement _connectionCode = _element<InputElement>(
    'connection-code',
  );
  final ButtonElement _pairButton = _element<ButtonElement>('pair-button');
  final HtmlElement _pairingPanel = _element<HtmlElement>('pairing-panel');
  final HtmlElement _workspace = _element<HtmlElement>('workspace');
  final HtmlElement _connectionStatus = _element<HtmlElement>(
    'connection-status',
  );
  final HtmlElement _scopeDescription = _element<HtmlElement>(
    'scope-description',
  );
  final HtmlElement _message = _element<HtmlElement>('message');
  final HtmlElement _accountList = _element<HtmlElement>('account-list');
  final HtmlElement _subscriptionList = _element<HtmlElement>(
    'subscription-list',
  );
  final HtmlElement _accountEditor = _element<HtmlElement>('account-editor');
  final HtmlElement _subscriptionEditor = _element<HtmlElement>(
    'subscription-editor',
  );
  final List<Map<String, Object?>> _editingCustomFields = [];
  final FormElement _accountForm = _element<FormElement>('account-form');
  final FormElement _subscriptionForm = _element<FormElement>(
    'subscription-form',
  );
  final HtmlElement _singleEntryGrid = _element<HtmlElement>(
    'single-entry-grid',
  );
  final HtmlElement _batchImportPanel = _element<HtmlElement>(
    'batch-import-panel',
  );
  final HtmlElement _batchSummary = _element<HtmlElement>('batch-summary');
  final HtmlElement _batchMapping = _element<HtmlElement>('batch-mapping');
  final HtmlElement _batchDocumentSlots = _element<HtmlElement>(
    'batch-document-slots',
  );
  final HtmlElement _batchTableRegion = _element<HtmlElement>(
    'batch-table-region',
  );
  final HtmlElement _batchCommitGuidance = _element<HtmlElement>(
    'batch-commit-guidance',
  );
  final DialogElement _phoneApprovalDialog = _element<DialogElement>(
    'phone-approval-dialog',
  );
  final TableSectionElement _batchTableBody = _element<TableSectionElement>(
    'batch-table-body',
  );
  final FileUploadInputElement _batchFileInput =
      _element<FileUploadInputElement>('batch-file-input');
  final TextAreaElement _batchPasteInput = _element<TextAreaElement>(
    'batch-paste-input',
  );
  final Random _random = Random.secure();

  TrustedLanBrowserPairing? _pairing;
  TrustedLanSecureChannel? _channel;
  Future<void> _commandTail = Future<void>.value();
  Map<String, Object?> _snapshot = const <String, Object?>{};
  Timer? _connectionExpiryTimer;
  Timer? _secretTimer;
  bool _phoneUnlockRequired = false;
  bool _refreshAfterPhoneUnlock = false;
  int _revision = -1;
  bool _working = false;
  bool _ended = false;
  Map<String, Object?>? _batchPreview;
  List<Map<String, Object?>> _batchDocuments = <Map<String, Object?>>[];
  String? _activeBatchDocumentKind;
  List<Map<String, Object?>> _batchRows = <Map<String, Object?>>[];
  final Set<String> _batchSelectedIds = <String>{};
  final Map<String, String> _batchDuplicateResolutions = <String, String>{};
  final Map<String, String> _batchSubscriptionTargets = <String, String>{};
  final Map<int, String?> _batchMappingOverrides = <int, String?>{};
  final Map<String, Map<String, String>> _batchRowPatches =
      <String, Map<String, String>>{};
  final Map<String, String> _batchDefaultValues = <String, String>{};
  String? _batchPreviewToken;
  bool _batchPreviewNeedsReupload = false;
  int _batchPage = 0;
  static const int _batchPageSize = 25;

  void initialize() {
    _applyStaticTranslations();
    _connectionCode.onInput.listen((_) {
      final normalized = (_connectionCode.value ?? '').toUpperCase().replaceAll(
        RegExp('[^A-Z]'),
        '',
      );
      _connectionCode.value = normalized.length <= 8
          ? normalized
          : normalized.substring(0, 8);
    });
    _pairingForm.onSubmit.listen((event) {
      event.preventDefault();
      unawaited(_connect());
    });
    _element<ButtonElement>('refresh-button').onClick.listen((_) {
      unawaited(_refresh());
    });
    _element<ButtonElement>('disconnect-button').onClick.listen((_) {
      unawaited(_disconnect());
    });
    _element<ButtonElement>('single-entry-tab').onClick.listen((_) {
      _showBatchImport(false);
    });
    _element<ButtonElement>('batch-import-tab').onClick.listen((_) {
      _showBatchImport(true);
    });
    _batchFileInput.onClick.listen((_) => _batchFileInput.value = '');
    _batchFileInput.onChange.listen((_) {
      final files = _batchFileInput.files;
      if (files != null && files.length == 1) {
        unawaited(_loadBatchFile(files.single));
      }
    });
    final dropZone = _element<HtmlElement>('batch-drop-zone');
    dropZone.onClick.listen((event) {
      final target = event.target;
      if (target == _batchFileInput ||
          (target is Element && target.closest('#batch-file-button') != null)) {
        return;
      }
      _batchFileInput.value = '';
      _batchFileInput.click();
    });
    dropZone.onDragOver.listen((event) {
      event.preventDefault();
      event.dataTransfer.dropEffect = 'copy';
      dropZone.classes.add('drag-over');
    });
    dropZone.onDragLeave.listen((_) => dropZone.classes.remove('drag-over'));
    dropZone.onDrop.listen((event) {
      event.preventDefault();
      dropZone.classes.remove('drag-over');
      final files = event.dataTransfer.files;
      if (files != null && files.length == 1) {
        unawaited(_loadBatchFile(files.single));
      } else {
        _showBatchSummary('请选择一个 XLSX、DOCX、CSV、TSV 或 TXT 文件。', error: true);
      }
    });
    dropZone.onKeyDown.listen((event) {
      if (event.key == 'Enter' || event.key == ' ') {
        event.preventDefault();
        _batchFileInput.click();
      }
    });
    _element<ButtonElement>('batch-paste-button').onClick.listen((_) {
      unawaited(_loadBatchPaste());
    });
    _element<ButtonElement>('batch-clear-button').onClick.listen((_) async {
      await _clearBatchImportEverywhere();
      if (!_ended) _showBatchSummary('批量迁移内存已清空。');
    });
    _element<ButtonElement>('download-custom-fields-template').onClick.listen((
      _,
    ) {
      _downloadTemplate(account: true, customFields: true);
    });
    _element<ButtonElement>('add-custom-field').onClick.listen((_) {
      if (_editingCustomFields.length >= 10) {
        _showMessage('每个账号最多 10 个自定义字段。', error: true);
        return;
      }
      _editingCustomFields.add({
        'id':
            'web-${DateTime.now().microsecondsSinceEpoch}-${_editingCustomFields.length}',
        'name': '',
        'type': 'text',
        'value': '',
        'order': _editingCustomFields.length,
        'revision': 0,
      });
      _renderCustomFieldEditor();
    });
    _element<ButtonElement>('download-account-template').onClick.listen((_) {
      _downloadTemplate(account: true);
    });
    _element<ButtonElement>('download-subscription-template').onClick.listen((
      _,
    ) {
      _downloadTemplate(account: false);
    });
    _element<ButtonElement>('batch-previous-page').onClick.listen((_) {
      if (_batchPage > 0) {
        _batchPage -= 1;
        _renderBatchTable();
      }
    });
    _element<ButtonElement>('batch-next-page').onClick.listen((_) {
      if ((_batchPage + 1) * _batchPageSize < _batchRows.length) {
        _batchPage += 1;
        _renderBatchTable();
      }
    });
    _input('batch-select-all').onChange.listen((_) {
      _setBatchPageSelected(_input('batch-select-all').checked ?? false);
    });
    _element<ButtonElement>('batch-delete-selected').onClick.listen((_) {
      _removeSelectedBatchRows();
    });
    _input('batch-final-confirm').onChange.listen((_) {
      _syncBatchCommitButton();
    });
    _element<ButtonElement>('batch-commit-button').onClick.listen((_) {
      unawaited(_commitBatchImport());
    });
    _element<ButtonElement>('phone-approval-dialog-close').onClick.listen((_) {
      _closePhoneApprovalPrompt();
    });
    _element<ButtonElement>('new-account-button').onClick.listen((_) {
      _openAccountEditor();
    });
    _element<ButtonElement>('cancel-account-button').onClick.listen((_) {
      _closeAccountEditor();
    });
    _element<ButtonElement>('new-subscription-button').onClick.listen((_) {
      _openSubscriptionEditor();
    });
    _element<ButtonElement>('cancel-subscription-button').onClick.listen((_) {
      _closeSubscriptionEditor();
    });
    _accountForm.onSubmit.listen((event) {
      event.preventDefault();
      unawaited(_saveAccount());
    });
    _subscriptionForm.onSubmit.listen((event) {
      event.preventDefault();
      unawaited(_saveSubscription());
    });
    _element<SelectElement>('account-password-mode').onChange.listen((_) {
      _syncPasswordMode();
    });
    _select('subscription-currency').onChange.listen((_) {
      _syncSubscriptionCurrencyInput();
    });
    _syncSubscriptionCurrencyInput();
    document.onVisibilityChange.listen((_) {
      if (document.visibilityState != 'visible') {
        _clearCustomFieldValues();
        _clearTemporarySecret(message: '页面已隐藏，临时密码已立即清除。');
        _clearBatchImportMemory();
        return;
      }
      _clearTemporarySecret();
    });
    window.onBeforeUnload.listen((_) => _clearSensitivePageState());
    window.onPageHide.listen((_) {
      unawaited(_endPage('页面已离开，本地会话数据已清空。'));
    });
    _syncBatchCommitButton();
  }

  void _applyStaticTranslations() {
    document.documentElement?.attributes['lang'] = switch (_language) {
      _PageLanguage.simplifiedChinese => 'zh-CN',
      _PageLanguage.english => 'en',
      _PageLanguage.japanese => 'ja',
    };
    for (final element in document.querySelectorAll('[data-i18n]')) {
      element.attributes.putIfAbsent('data-zh', () => element.text ?? '');
      final value = switch (_language) {
        _PageLanguage.simplifiedChinese => element.attributes['data-zh'],
        _PageLanguage.english => element.attributes['data-en'],
        _PageLanguage.japanese => element.attributes['data-ja'],
      };
      if (value != null) element.text = value;
    }
    for (final input in document.querySelectorAll('[data-i18n-placeholder]')) {
      input.attributes.putIfAbsent(
        'data-placeholder-zh',
        () => input.attributes['placeholder'] ?? '',
      );
      final value = switch (_language) {
        _PageLanguage.simplifiedChinese =>
          input.attributes['data-placeholder-zh'],
        _PageLanguage.english => input.attributes['data-placeholder-en'],
        _PageLanguage.japanese => input.attributes['data-placeholder-ja'],
      };
      if (value != null) input.attributes['placeholder'] = value;
    }
    for (final option in document.querySelectorAll('[data-i18n-option]')) {
      option.attributes.putIfAbsent(
        'data-label-zh',
        () => option.attributes['label'] ?? option.attributes['value'] ?? '',
      );
      option.attributes.putIfAbsent(
        'data-value-zh',
        () => option.attributes['value'] ?? '',
      );
      final label = switch (_language) {
        _PageLanguage.simplifiedChinese => option.attributes['data-label-zh'],
        _PageLanguage.english => option.attributes['data-label-en'],
        _PageLanguage.japanese => option.attributes['data-label-ja'],
      };
      final value = switch (_language) {
        _PageLanguage.simplifiedChinese => option.attributes['data-value-zh'],
        _PageLanguage.english => option.attributes['data-value-en'],
        _PageLanguage.japanese => option.attributes['data-value-ja'],
      };
      if (label != null) option.attributes['label'] = label;
      if (value != null) option.attributes['value'] = value;
    }
    for (final element in document.querySelectorAll('[data-aria-label-en]')) {
      final value = switch (_language) {
        _PageLanguage.english => element.attributes['data-aria-label-en'],
        _PageLanguage.japanese => element.attributes['data-aria-label-ja'],
        _ => element.attributes['aria-label'],
      };
      if (value != null) element.attributes['aria-label'] = value;
    }
  }

  void _applyResponseLocale(Map<String, Object?> response) {
    final next = _pageLanguageFromCode(response['locale'] as String?);
    if (next == _language || response['locale'] == null) return;
    final accountCategory = _accountEditor.hidden
        ? null
        : _canonicalAccountCategory(_input('account-category').value);
    _language = next;
    _applyStaticTranslations();
    if (_snapshot.isNotEmpty) _render();
    if (!_accountEditor.hidden) {
      _input('account-category').value = accountCategory == null
          ? ''
          : _displayAccountCategory(accountCategory);
      _element<HtmlElement>(
        'account-editor-title',
      ).text = (_input('account-id').value ?? '').isEmpty
          ? _text('新增账号')
          : _text('编辑账号');
    }
    if (!_subscriptionEditor.hidden) {
      _element<HtmlElement>(
        'subscription-editor-title',
      ).text = (_input('subscription-id').value ?? '').isEmpty
          ? _text('新增订阅')
          : _text('编辑订阅');
    }
  }

  String _text(String chinese) => _tr(_language, chinese);

  String _localizedMessage(String message) {
    final exact = _text(message);
    if (exact != message || _language == _PageLanguage.simplifiedChinese) {
      return exact;
    }

    final passwordMatch = RegExp(
      r'^密码（(\d+) 秒后清除）：([\s\S]*)$',
    ).firstMatch(message);
    if (passwordMatch != null) {
      final seconds = passwordMatch.group(1)!;
      final password = passwordMatch.group(2)!;
      return switch (_language) {
        _PageLanguage.english =>
          'Password (cleared in $seconds seconds): $password',
        _PageLanguage.japanese => 'パスワード（$seconds秒後に消去）：$password',
        _ => message,
      };
    }

    final limitMatch = RegExp(
      r'^免费版(账户|订阅)数量已达上限（(账户|订阅)\s+(\d+)/(\d+)）；请在手机设置中解锁完整版后重试。$',
    ).firstMatch(message);
    if (limitMatch != null && limitMatch.group(1) == limitMatch.group(2)) {
      final type = limitMatch.group(1) == '账户' ? _text('账号') : _text('订阅');
      final current = limitMatch.group(3)!;
      final maximum = limitMatch.group(4)!;
      return switch (_language) {
        _PageLanguage.english =>
          'The Free Version $type limit has been reached ($current/$maximum). Unlock Full Version in Cardock settings on your phone and try again.',
        _PageLanguage.japanese =>
          '無料版の$type数が上限に達しました（$current/$maximum）。スマートフォンのCardock設定で完全版を有効にしてから、もう一度お試しください。',
        _ => message,
      };
    }

    if (RegExp(r'^.+ 格式无效。$').hasMatch(message)) {
      return switch (_language) {
        _PageLanguage.english =>
          'One of the submitted fields has an invalid format.',
        _PageLanguage.japanese => '入力内容の形式が正しくありません。',
        _ => message,
      };
    }
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(message)) {
      return switch (_language) {
        _PageLanguage.english =>
          'The request could not be completed. Check the submitted fields.',
        _PageLanguage.japanese => 'リクエストを完了できませんでした。入力内容を確認してください。',
        _ => message,
      };
    }
    return message;
  }

  Future<void> _connect() async {
    if (_working || _ended) return;
    final code = _connectionCode.value?.trim() ?? '';
    if (code.isEmpty) return;
    var stage = 'HELLO';
    _setWorking(true);
    _setStatus('正在建立加密会话…', 'status-waiting');
    _showMessage('正在连接手机（HELLO：读取本次会话信息）…');
    try {
      final helloResponse = await _jsonRequest('GET', '/api/pairing/hello');
      final phoneHello = TrustedLanPhoneHello.fromJson(
        _requiredMap(helloResponse, 'hello'),
      );
      stage = 'LOCAL_CODE';
      _showMessage('正在连接手机（LOCAL_CODE：校验连接码格式）…');
      final pairing = await TrustedLanBrowserPairing.start(
        phoneHello: phoneHello,
        connectionCode: code,
      );
      _pairing = pairing;
      stage = 'FINISH';
      _showMessage('正在连接手机（FINISH：提交一次性配对）…');
      final finishResponse = await _jsonRequest(
        'POST',
        '/api/pairing/finish',
        body: <String, Object?>{'hello': pairing.hello.toJson()},
      );
      stage = 'CONFIRM';
      _showMessage('正在连接手机（CONFIRM：确认加密通道）…');
      final confirmation = TrustedLanPhoneConfirmation.fromJson(
        _requiredMap(finishResponse, 'confirmation'),
      );
      final channel = await pairing.finish(confirmation);
      _pairing = null;
      _channel = channel;
      _connectionCode.value = '';
      _pairingPanel.hidden = true;
      _workspace.hidden = false;
      _setStatus('已连接手机', 'status-connected');
      stage = 'INITIAL_SYNC';
      _showMessage('正在连接手机（INITIAL_SYNC：读取允许显示的数据）…');
      await _refreshWithoutWorkingGuard();
      _showMessage('已与手机中的当前数据同步。');
    } on TrustedLanPairingException catch (error, stackTrace) {
      if (stage == 'LOCAL_CODE' &&
          error.failure == TrustedLanPairingFailure.invalidConnectionCode) {
        _pairing?.cancel();
        _pairing = null;
        _setStatus('等待连接', 'status-waiting');
        _showMessage(
          '连接码格式不正确（LOCAL_CODE）。请输入手机显示的 8 位大写英文字母，不要输入数字。',
          error: true,
        );
      } else {
        await _endPage(
          _connectionFailureMessage(_language, stage, error, stackTrace),
        );
      }
    } on Object catch (error, stackTrace) {
      await _endPage(
        _connectionFailureMessage(_language, stage, error, stackTrace),
      );
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _refresh() async {
    if (_channel == null || _working) return;
    _setWorking(true);
    try {
      final response = await _command(<String, Object?>{'action': 'snapshot'});
      if (_isPhoneUnlockRequiredResponse(response)) return;
      if (response['status'] != 'ok') {
        throw StateError('Snapshot rejected.');
      }
      _applyResponseLocale(response);
      _snapshot = _requiredMap(response, 'data');
      _revision = _requiredInt(_snapshot, 'revision');
      _applySessionTimeouts(_snapshot['timeouts']);
      _render();
      if (_refreshAfterPhoneUnlock) {
        _finishPhoneUnlockRefresh();
      } else {
        _showMessage('已与手机中的当前数据同步。');
      }
    } on Object {
      await _handleChannelFailure();
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _disconnect() async {
    if (_ended) return;
    try {
      if (_channel != null) {
        await _command(<String, Object?>{'action': 'disconnect'});
      }
    } on Object {
      // The phone may close the listener immediately after acknowledging.
    } finally {
      await _endPage('已主动断开。请关闭此标签页。');
    }
  }

  Future<Map<String, Object?>> _command(Map<String, Object?> command) async {
    final previous = _commandTail;
    final completer = Completer<void>();
    _commandTail = completer.future;
    await previous.catchError((Object _) {});
    Uint8List? plaintext;
    Uint8List? responsePlaintext;
    try {
      final channel = _channel;
      if (channel == null || _ended) throw StateError('Session ended.');
      plaintext = Uint8List.fromList(utf8.encode(jsonEncode(command)));
      final frame = await channel.encrypt(plaintext);
      final response = await _jsonRequest(
        'POST',
        '/api/message',
        body: <String, Object?>{'frame': frame.toJson()},
      );
      final encryptedResponse = TrustedLanEncryptedFrame.fromJson(
        _requiredMap(response, 'frame'),
      );
      responsePlaintext = await channel.decrypt(encryptedResponse);
      final decoded = _stringMap(
        jsonDecode(utf8.decode(responsePlaintext, allowMalformed: false)),
      );
      _observeVaultAccess(decoded);
      return decoded;
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      responsePlaintext?.fillRange(0, responsePlaintext.length, 0);
      completer.complete();
    }
  }

  bool _isPhoneUnlockRequiredResponse(Map<String, Object?> response) =>
      response['status'] == 'phoneUnlockRequired' ||
      response['vaultAccess'] == 'locked';

  void _observeVaultAccess(Map<String, Object?> response) {
    if (_isPhoneUnlockRequiredResponse(response)) {
      _phoneUnlockRequired = true;
      _clearCustomFieldValues();
      _refreshAfterPhoneUnlock = false;
      if (_batchPreviewToken != null) _batchPreviewNeedsReupload = true;
      _setStatus('等待手机解锁', 'status-waiting');
      _closePhoneApprovalPrompt();
      _showMessage('手机暂时锁定，连接仍保留；请先解锁同一个保险库，再点击“刷新”或重新提交。');
      if (_batchPreviewNeedsReupload) {
        _showBatchSummary('手机锁定后权威批量预览已失效；网页选择仍保留，请重新选择文件生成预览。', error: true);
      }
      _syncBatchCommitButton();
      return;
    }
    if (response['vaultAccess'] == 'ready' && _phoneUnlockRequired) {
      _phoneUnlockRequired = false;
      _refreshAfterPhoneUnlock = true;
      _setStatus('已连接手机', 'status-connected');
    }
  }

  void _finishPhoneUnlockRefresh() {
    if (!_refreshAfterPhoneUnlock) return;
    _refreshAfterPhoneUnlock = false;
    _showMessage('手机已解锁，连接已恢复；未提交的网页内容仍保留。');
    if (_batchPreviewNeedsReupload) {
      _showBatchSummary('手机锁定后权威批量预览已失效；网页选择仍保留，请重新选择文件生成预览。', error: true);
    }
  }

  Future<Map<String, Object?>> _mutation(
    String action,
    Map<String, Object?> body,
  ) => _command(<String, Object?>{
    'action': action,
    'requestId': _requestId(),
    'expectedRevision': _revision,
    'body': body,
  });

  void _showBatchImport(bool value) {
    if (value && _snapshot['batchImportAvailable'] != true) {
      _showMessage('手机端批量导入尚不可用。', error: true);
      return;
    }
    _batchImportPanel.hidden = !value;
    _singleEntryGrid.hidden = value;
    if (value) {
      _accountEditor.hidden = true;
      _subscriptionEditor.hidden = true;
      _clearPasswordInputs();
    }
    final singleTab = _element<ButtonElement>('single-entry-tab');
    final batchTab = _element<ButtonElement>('batch-import-tab');
    singleTab.classes.toggle('active', !value);
    batchTab.classes.toggle('active', value);
    singleTab.attributes['aria-selected'] = (!value).toString();
    batchTab.attributes['aria-selected'] = value.toString();
  }

  Future<void> _loadBatchFile(File file) async {
    if (_working) {
      _showBatchSummary('正在处理另一个请求，请稍后再试。', error: true);
      return;
    }
    if (_channel == null) {
      _showBatchSummary('手机连接尚未建立，请重新连接后再试。', error: true);
      return;
    }
    _showBatchSummary('已接收文件，正在读取…');
    final lowerName = file.name.toLowerCase();
    if (!(lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.docx') ||
        lowerName.endsWith('.csv') ||
        lowerName.endsWith('.tsv') ||
        lowerName.endsWith('.txt'))) {
      _showBatchSummary('请选择一个 XLSX、DOCX、CSV、TSV 或 TXT 文件。', error: true);
      _batchFileInput.value = '';
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      _showBatchSummary('批量文件不能超过 10 MiB。', error: true);
      _batchFileInput.value = '';
      return;
    }
    final reader = FileReader()..readAsArrayBuffer(file);
    try {
      await Future.any<void>(<Future<void>>[
        reader.onLoad.first.then((_) {}),
        reader.onError.first.then(
          (_) => throw const FormatException('file_read_failed'),
        ),
        reader.onAbort.first.then(
          (_) => throw const FormatException('file_read_aborted'),
        ),
      ]);
    } on Object {
      _showBatchSummary(
        '浏览器无法读取所选文件（FILE_READER_ERROR）。请重新选择本地文件；若仍失败，请刷新网页并重新连接手机。',
        error: true,
      );
      _batchFileInput.value = '';
      return;
    }
    final result = reader.result;
    late final Uint8List bytes;
    if (result is ByteBuffer) {
      final view = Uint8List.view(result);
      bytes = Uint8List.fromList(view);
      view.fillRange(0, view.length, 0);
    } else if (result is Uint8List) {
      bytes = Uint8List.fromList(result);
      result.fillRange(0, result.length, 0);
    } else {
      _showBatchSummary(
        '浏览器返回了不支持的文件结果（FILE_READER_RESULT_TYPE）。请刷新网页后重新选择文件。',
        error: true,
      );
      _batchFileInput.value = '';
      return;
    }
    await _requestBatchPreview(file.name, bytes);
  }

  Future<void> _loadBatchPaste() async {
    final value = _batchPasteInput.value ?? '';
    if (value.trim().isEmpty) {
      _showBatchSummary('粘贴内容为空。', error: true);
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(value));
    if (bytes.length > 10 * 1024 * 1024) {
      bytes.fillRange(0, bytes.length, 0);
      _showBatchSummary('批量文件不能超过 10 MiB。', error: true);
      return;
    }
    await _requestBatchPreview('pasted-table.txt', bytes);
  }

  Future<void> _requestBatchPreview(String fileName, Uint8List bytes) async {
    if (_working || _channel == null) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    if (bytes.isEmpty) {
      _showBatchSummary('粘贴内容为空。', error: true);
      return;
    }
    const chunkSize = 192 * 1024;
    final totalChunks = (bytes.length + chunkSize - 1) ~/ chunkSize;
    final sessionId = _requestId();
    final documentKindsBeforeUpload = _batchDocuments
        .map((document) => document['kind'])
        .whereType<String>()
        .toSet();
    _setWorking(true);
    _showBatchSummary('正在由手机生成权威预览…');
    String? rejectedMessage;
    try {
      var response =
          await _mutation('batchImportUploadStart', <String, Object?>{
            'sessionId': sessionId,
            'fileName': fileName,
            'sourceId': _select('batch-source').value ?? 'auto',
            'totalBytes': bytes.length,
            'totalChunks': totalChunks,
          });
      if (_isPhoneUnlockRequiredResponse(response)) return;
      if (response['status'] != 'ok' || response['nextSequence'] != 0) {
        rejectedMessage = _batchRejectionMessage(response, '手机端拒绝接收该批量文件。');
        throw StateError('batch_upload_start_rejected');
      }
      for (var sequence = 0; sequence < totalChunks; sequence += 1) {
        final start = sequence * chunkSize;
        final end = min(start + chunkSize, bytes.length);
        final chunk = Uint8List.sublistView(bytes, start, end);
        response = await _mutation('batchImportUploadChunk', <String, Object?>{
          'sessionId': sessionId,
          'sequence': sequence,
          'totalChunks': totalChunks,
          'contentBase64': base64Encode(chunk),
        });
        if (_isPhoneUnlockRequiredResponse(response)) return;
        if (response['status'] != 'ok' ||
            response['nextSequence'] != sequence + 1) {
          rejectedMessage = _batchRejectionMessage(
            response,
            '批量文件传输未完成，请重新选择文件。',
          );
          throw StateError('batch_upload_chunk_rejected');
        }
      }
      response = await _mutation('batchImportUploadFinish', <String, Object?>{
        'sessionId': sessionId,
        'totalChunks': totalChunks,
      });
      if (_isPhoneUnlockRequiredResponse(response)) return;
      final status = response['status'];
      if (status == 'ok') {
        _acceptBatchPreview(
          _requiredMap(response, 'data'),
          resetActiveDocumentIfPreviouslyPresent: documentKindsBeforeUpload,
        );
        _showBatchSummary('权威预览已生成。密码始终遮挡。');
      } else if (status == 'conflict') {
        _clearBatchImportMemory();
        _showBatchSummary('手机数据已变化，权威预览已失效；请重新生成。', error: true);
        await _refreshWithoutWorkingGuard();
      } else {
        _showBatchSummary(
          _batchRejectionMessage(response, '手机端批量导入尚不可用。'),
          error: true,
        );
      }
    } on Object {
      try {
        await _mutation('batchImportClear', const <String, Object?>{});
      } on Object {
        // Session teardown also clears every partial upload buffer.
      }
      _showBatchSummary(
        rejectedMessage ??
            '文件上传或手机端解析未完成（BATCH_UPLOAD_FAILED）。请确认手机临时网页连接仍在运行，再重新选择文件。',
        error: true,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      _batchPasteInput.value = '';
      _batchFileInput.value = '';
      _setWorking(false);
    }
  }

  void _acceptBatchPreview(
    Map<String, Object?> preview, {
    Set<String> resetDocumentKinds = const <String>{},
    Set<String> resetActiveDocumentIfPreviouslyPresent = const <String>{},
  }) {
    final rows = _objectList(preview['rows']);
    final documents = _objectList(preview['documents'] ?? const <Object?>[]);
    if (rows.length > 5000) {
      throw const FormatException('Too many preview rows.');
    }
    if (documents.length > 2) {
      throw const FormatException('Too many batch documents.');
    }
    final validatedDocuments = <Map<String, Object?>>[
      for (final document in documents) _validatedBatchDocument(document),
    ];
    if (validatedDocuments.map((item) => item['kind']).toSet().length !=
        validatedDocuments.length) {
      throw const FormatException('Duplicate batch document kind.');
    }
    final activeKind = _safeOptionalPreviewText(
      preview['activeDocumentKind'],
      32,
    );
    if (activeKind != null &&
        !validatedDocuments.any((item) => item['kind'] == activeKind)) {
      throw const FormatException('Invalid active batch document.');
    }
    final validatedRows = <Map<String, Object?>>[
      for (final row in rows) _validatedBatchRow(row),
    ];
    final effectiveResetKinds = <String>{...resetDocumentKinds};
    if (activeKind != null &&
        resetActiveDocumentIfPreviouslyPresent.contains(activeKind)) {
      effectiveResetKinds.add(activeKind);
    }
    final decisions = reconcileTemporaryWebBatchDecisions(
      previousRows: _batchDecisionRows(_batchRows),
      previousSelectedRowIds: _batchSelectedIds,
      previousDuplicateResolutions: _batchDuplicateResolutions,
      previousSubscriptionTargets: _batchSubscriptionTargets,
      rows: _batchDecisionRows(validatedRows),
      resetDocumentKinds: effectiveResetKinds,
    );

    _batchPreview = preview;
    _batchDocuments = validatedDocuments;
    _activeBatchDocumentKind = activeKind;
    _batchPreviewToken = _requireBatchText(
      preview,
      'previewToken',
      maximumLength: 256,
    );
    _batchPreviewNeedsReupload = false;
    _batchRows = validatedRows;
    _batchSelectedIds
      ..clear()
      ..addAll(decisions.selectedRowIds);
    _batchDuplicateResolutions
      ..clear()
      ..addAll(decisions.duplicateResolutions);
    _batchSubscriptionTargets
      ..clear()
      ..addAll(decisions.subscriptionTargets);
    _batchMappingOverrides.clear();
    _batchRowPatches.clear();
    _batchDefaultValues.clear();
    _batchPage = 0;
    _input('batch-final-confirm').checked = false;
    _renderBatchDocuments();
    _renderBatchMapping(preview);
    _renderBatchTable();
    _batchTableRegion.hidden = _batchRows.isEmpty;
  }

  Iterable<TemporaryWebBatchDecisionRow> _batchDecisionRows(
    Iterable<Map<String, Object?>> rows,
  ) sync* {
    for (final row in rows) {
      final targetOptions = row['subscriptionTargetOptions'];
      yield TemporaryWebBatchDecisionRow(
        id: row['id']! as String,
        kind: row['kind']! as String,
        canImport: row['canImport'] == true,
        hasDuplicate: row['duplicateDescription'] != null,
        duplicateContext: row['duplicateDescription'] as String? ?? '',
        defaultResolution: row['defaultResolution'] as String? ?? 'skip',
        subscriptionTargetRequired: row['subscriptionTargetRequired'] == true,
        subscriptionTargetIds: targetOptions is Map<String, String>
            ? targetOptions.keys.toSet()
            : const <String>{},
      );
    }
  }

  Map<String, Object?> _validatedBatchDocument(Map<String, Object?> document) {
    final kind = _requireBatchText(document, 'kind', maximumLength: 32);
    final fileName = _requireBatchText(
      document,
      'fileName',
      maximumLength: 255,
    );
    final sourceLabel = _requireBatchText(
      document,
      'sourceLabel',
      maximumLength: 512,
    );
    final detectedFormat = _requireBatchText(
      document,
      'detectedFormat',
      maximumLength: 512,
    );
    final rowCount = document['rowCount'];
    if (!const <String>{'account', 'subscription'}.contains(kind) ||
        rowCount is! int ||
        rowCount < 0 ||
        rowCount > 5000) {
      throw const FormatException('Invalid batch document.');
    }
    return <String, Object?>{
      'kind': kind,
      'fileName': fileName,
      'sourceLabel': sourceLabel,
      'detectedFormat': detectedFormat,
      'rowCount': rowCount,
    };
  }

  Map<String, Object?> _validatedBatchRow(Map<String, Object?> row) {
    final id = _requireBatchText(row, 'id', maximumLength: 128);
    final kind = _requireBatchText(row, 'kind', maximumLength: 32);
    final title = _requireBatchText(row, 'title', maximumLength: 512);
    final subtitle = row['subtitle'];
    final passwordStatus = _requireBatchText(
      row,
      'passwordStatus',
      maximumLength: 32,
    );
    if (!const <String>{'account', 'subscription'}.contains(kind) ||
        !const <String>{
          'absent',
          'encryptedForImport',
          'excluded',
        }.contains(passwordStatus) ||
        subtitle is! String ||
        subtitle.runes.length > 1024) {
      throw const FormatException('Invalid batch preview row.');
    }
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'title': title,
      'subtitle': subtitle,
      'passwordStatus': passwordStatus,
      'issue': _safeOptionalPreviewText(row['issue'], 1024),
      'duplicateDescription': _safeOptionalPreviewText(
        row['duplicateDescription'],
        1024,
      ),
      'defaultResolution':
          _safeOptionalPreviewText(row['defaultResolution'], 32) ?? 'skip',
      'subscriptionTargetOptions': _validatedBatchStringMap(
        row['subscriptionTargetOptions'],
      ),
      'subscriptionTargetRequired': row['subscriptionTargetRequired'] == true,
      'canImport': row['canImport'] == true,
      'originalRowNumber': row['originalRowNumber'] is int
          ? row['originalRowNumber']
          : 0,
      'fields': _validatedBatchStringMap(row['fields']),
      'accountKeyAssociation': _validatedBatchAssociation(
        row['accountKeyAssociation'],
      ),
    };
  }

  String? _validatedBatchAssociation(Object? value) {
    final association = _safeOptionalPreviewText(value, 64);
    if (association == null) return null;
    if (!const <String>{
      'definesImportedAccountKey',
      'linkedToImportedAccount',
      'missingImportedAccountKey',
    }.contains(association)) {
      throw const FormatException('Invalid account key association.');
    }
    return association;
  }

  Map<String, String> _validatedBatchStringMap(Object? value) {
    final source = _stringMap(value ?? const <String, Object?>{});
    if (source.length > 5000) {
      throw const FormatException('Too many batch options.');
    }
    final result = <String, String>{};
    for (final entry in source.entries) {
      final label = entry.value;
      if (entry.key.runes.length > 256 ||
          label is! String ||
          label.runes.length > 512) {
        throw const FormatException('Invalid batch option.');
      }
      result[entry.key] = label;
    }
    return result;
  }

  String _requireBatchText(
    Map<String, Object?> source,
    String key, {
    required int maximumLength,
  }) {
    final value = source[key];
    if (value is! String ||
        value.isEmpty ||
        value.runes.length > maximumLength) {
      throw const FormatException('Invalid batch preview text.');
    }
    return value;
  }

  String? _safeOptionalPreviewText(Object? value, int maximumLength) {
    if (value == null) return null;
    if (value is! String || value.runes.length > maximumLength) {
      throw const FormatException('Invalid batch preview text.');
    }
    return value;
  }

  void _renderBatchDocuments() {
    _batchDocumentSlots.children.clear();
    for (final kind in const <String>['account', 'subscription']) {
      final document = _batchDocuments
          .where((candidate) => candidate['kind'] == kind)
          .firstOrNull;
      final active = document != null && _activeBatchDocumentKind == kind;
      final slot = DivElement()..classes.add('batch-document-slot');
      if (active) slot.classes.add('active');
      slot.append(
        HeadingElement.h3()..text = _text(kind == 'account' ? '账号文件' : '订阅文件'),
      );
      if (document == null) {
        slot.append(ParagraphElement()..text = _text('未加入'));
      } else {
        slot
          ..append(ParagraphElement()..text = document['fileName']! as String)
          ..append(
            ParagraphElement()
              ..text =
                  '${document['sourceLabel']} · ${document['detectedFormat']}',
          )
          ..append(
            ParagraphElement()
              ..text = '${_text('记录数')} ${document['rowCount']}',
          );
        final actions = DivElement()..classes.add('slot-actions');
        if (active) {
          actions.append(SpanElement()..text = _text('当前编辑'));
        } else {
          actions.append(
            _button('编辑此文件', () {
              unawaited(_activateBatchDocument(kind));
            }),
          );
        }
        actions.append(
          _button('移除此文件', () {
            unawaited(_removeBatchDocument(kind));
          }, danger: true),
        );
        slot.append(actions);
      }
      _batchDocumentSlots.append(slot);
    }
  }

  Future<void> _activateBatchDocument(String kind) async {
    if (_working || _batchPreviewToken == null) return;
    if (_batchMappingOverrides.isNotEmpty ||
        _batchRowPatches.isNotEmpty ||
        _batchDefaultValues.isNotEmpty) {
      _showBatchSummary('请先应用当前映射与编辑，再切换文件。', error: true);
      return;
    }
    await _reviseBatchDocument(
      activateDocumentKind: kind,
      successMessage: '已切换当前编辑文件。',
    );
  }

  Future<void> _removeBatchDocument(String kind) => _reviseBatchDocument(
    removeDocumentKind: kind,
    successMessage: '已从计划移除该文件。',
  );

  Future<void> _reviseBatchDocument({
    String? activateDocumentKind,
    String? removeDocumentKind,
    required String successMessage,
  }) async {
    final token = _batchPreviewToken;
    if (_working || token == null) return;
    _setWorking(true);
    try {
      final response = await _mutation('batchImportRevise', <String, Object?>{
        'previewToken': token,
        'mappingOverrides': const <String, Object?>{},
        'rowPatches': const <String, Object?>{},
        'defaultValues': const <String, Object?>{},
        'activateDocumentKind': ?activateDocumentKind,
        'removeDocumentKind': ?removeDocumentKind,
      });
      if (_isPhoneUnlockRequiredResponse(response)) return;
      if (response['status'] != 'ok') {
        throw const FormatException('Document revision rejected.');
      }
      _acceptBatchPreview(
        _stringMap(response['data']),
        resetDocumentKinds: removeDocumentKind == null
            ? const <String>{}
            : <String>{removeDocumentKind},
      );
      _showBatchSummary(successMessage);
    } on Object {
      await _clearBatchImportEverywhere();
      _showBatchSummary('编辑未通过权威重建，本次批量内存已清空。', error: true);
    } finally {
      _setWorking(false);
    }
  }

  void _renderBatchMapping(Map<String, Object?> preview) {
    _batchMapping.children.clear();
    final source = _safeOptionalPreviewText(preview['sourceLabel'], 512) ?? '';
    final format =
        _safeOptionalPreviewText(preview['detectedFormat'], 512) ?? '';
    if (source.isNotEmpty || format.isNotEmpty) {
      _batchMapping.append(
        DivElement()
          ..classes.add('batch-summary')
          ..text = '$source · $format',
      );
    }
    for (final mapping in _objectList(preview['mappings'])) {
      final row = DivElement()..classes.add('mapping-row');
      final sourceLabel = _requireBatchText(
        mapping,
        'sourceLabel',
        maximumLength: 512,
      );
      row.append(SpanElement()..text = sourceLabel);
      if (mapping['excludedAsSensitive'] == true) {
        row.classes.add('sensitive');
        row.append(SpanElement()..text = _text('已按规则排除'));
      } else {
        final columnIndex = mapping['columnIndex'];
        if (columnIndex is! int || columnIndex < 0 || columnIndex > 255) {
          throw const FormatException('Invalid mapping column.');
        }
        final select = SelectElement()
          ..append(
            OptionElement(
              value: 'ignore',
              data: _text('忽略此列'),
              selected: mapping['targetField'] == null,
            ),
          );
        for (final target in _stringList(mapping['availableTargets'])) {
          select.append(
            OptionElement(
              value: target,
              data: _text(target),
              selected: mapping['targetField'] == target,
            ),
          );
        }
        select.onChange.listen((_) {
          final value = select.value ?? 'ignore';
          _batchMappingOverrides[columnIndex] = value == 'ignore'
              ? null
              : value;
        });
        row.append(select);
      }
      _batchMapping.append(row);
    }
    final controls = DivElement()..classes.add('batch-mapping-controls');
    final defaultField = SelectElement();
    final kind = _activeBatchDocumentKind;
    final defaultFields = kind == 'subscription'
        ? const <String>[
            'currency',
            'billingCycle',
            'subscriptionStartDate',
            'autoRenew',
            'paymentMethod',
            'reminderDays',
          ]
        : const <String>['platformName', 'phone', 'email', 'url', 'notes'];
    for (final field in defaultFields) {
      defaultField.append(OptionElement(value: field, data: _text(field)));
    }
    final defaultValue = InputElement()
      ..classes.add('batch-default-value')
      ..placeholder = _text('仅填充空白字段的默认值');
    controls
      ..append(defaultField)
      ..append(defaultValue)
      ..append(
        _button('添加批量默认值', () {
          final field = defaultField.value ?? '';
          final value = defaultValue.value ?? '';
          if (field.isEmpty || value.isEmpty) return;
          _batchDefaultValues[field] = value;
          defaultValue.value = '';
          _showBatchSummary(
            '${_text('已设置默认值')}：${_text(field)}（${_text('只填空白字段')}）',
          );
        }),
      )
      ..append(
        _button('应用映射与编辑并重新预览', () {
          unawaited(_reviseBatchPreview());
        }, primary: true),
      );
    _batchMapping.append(controls);
  }

  Future<void> _reviseBatchPreview() async {
    final token = _batchPreviewToken;
    if (_working || token == null) return;
    _setWorking(true);
    _showBatchSummary('正在手机端重建权威预览…');
    try {
      final response = await _mutation('batchImportRevise', <String, Object?>{
        'previewToken': token,
        'mappingOverrides': <String, Object?>{
          for (final entry in _batchMappingOverrides.entries)
            entry.key.toString(): entry.value ?? 'ignore',
        },
        'rowPatches': <String, Object?>{
          for (final entry in _batchRowPatches.entries)
            entry.key: <String, Object?>{...entry.value},
        },
        'defaultValues': <String, Object?>{..._batchDefaultValues},
      });
      if (_isPhoneUnlockRequiredResponse(response)) return;
      if (response['status'] != 'ok') {
        throw const FormatException('Revision rejected.');
      }
      _acceptBatchPreview(_stringMap(response['data']));
      _showBatchSummary('映射与编辑已由手机重建并重新验证。');
    } on Object {
      await _clearBatchImportEverywhere();
      _showBatchSummary('编辑未通过权威重建，本次批量内存已清空。', error: true);
    } finally {
      _setWorking(false);
    }
  }

  void _renderBatchTable() {
    _batchTableBody.children.clear();
    if (_batchRows.isEmpty) {
      _showBatchSummary('没有可预览的记录。');
      _batchTableRegion.hidden = true;
      _syncBatchCommitButton();
      return;
    }
    final maximumPage = (_batchRows.length - 1) ~/ _batchPageSize;
    if (_batchPage > maximumPage) _batchPage = maximumPage;
    final start = _batchPage * _batchPageSize;
    final end = min(start + _batchPageSize, _batchRows.length);
    final visible = _batchRows.sublist(start, end);
    for (var index = 0; index < visible.length; index += 1) {
      final row = visible[index];
      final id = row['id']! as String;
      final requiresSubscriptionTarget =
          row['kind'] == 'subscription' &&
          row['subscriptionTargetRequired'] == true;
      final missingSubscriptionTarget =
          requiresSubscriptionTarget &&
          !_batchSubscriptionTargets.containsKey(id);
      final tableRow = TableRowElement()
        ..tabIndex = 0
        ..attributes['data-row-id'] = id;
      final checkbox = CheckboxInputElement()
        ..checked = _batchSelectedIds.contains(id)
        ..disabled = missingSubscriptionTarget;
      checkbox.onChange.listen((_) {
        _setBatchRowSelected(id, checkbox.checked ?? false);
      });
      tableRow.append(TableCellElement()..append(checkbox));
      tableRow.append(
        TableCellElement()
          ..text = (row['originalRowNumber'] as int? ?? 0).toString(),
      );
      final statusCell = TableCellElement()
        ..append(
          DivElement()..text = _text(row['canImport'] == true ? '可导入' : '阻断'),
        );
      final association = row['accountKeyAssociation'] as String?;
      if (association != null) {
        statusCell.append(
          DivElement()
            ..classes.add('batch-record-subtitle')
            ..text = _text(switch (association) {
              'definesImportedAccountKey' => '定义本次 account_key',
              'linkedToImportedAccount' => '已关联本次账号',
              _ => '缺少匹配 account_key',
            }),
        );
      }
      tableRow.append(statusCell);
      tableRow.append(
        TableCellElement()
          ..text = _text(row['kind'] == 'subscription' ? '订阅草稿' : '账号'),
      );
      final fields = row['fields']! as Map<String, String>;
      final isSubscription = row['kind'] == 'subscription';
      tableRow
        ..append(
          _batchEditableFieldCell(
            id,
            isSubscription ? 'planName' : 'platformName',
            fields,
          ),
        )
        ..append(
          _batchEditableFieldCell(
            id,
            isSubscription ? 'accountKey' : 'loginAccount',
            fields,
          ),
        )
        ..append(
          _batchEditableFieldCell(
            id,
            isSubscription ? 'amount' : 'email',
            fields,
          ),
        )
        ..append(
          _batchEditableFieldCell(
            id,
            isSubscription ? 'currency' : 'phone',
            fields,
          ),
        );
      if (isSubscription) {
        tableRow.append(_batchEditableFieldCell(id, 'billingCycle', fields));
      } else {
        tableRow.append(
          TableCellElement()..append(
            DivElement()
              ..classes.add('batch-password-status')
              ..text = _text(switch (row['passwordStatus']) {
                'encryptedForImport' => '将加密导入',
                'excluded' => '已按规则排除',
                _ => '未包含密码',
              }),
          ),
        );
      }
      tableRow.append(
        isSubscription
            ? _batchEditableFieldCell(id, 'subscriptionStartDate', fields)
            : (TableCellElement()..text = '—'),
      );
      tableRow
        ..append(
          _batchEditableFieldCell(
            id,
            isSubscription ? 'nextRenewalDate' : 'url',
            fields,
          ),
        )
        ..append(_batchEditableFieldCell(id, 'notes', fields));
      if (isSubscription) {
        tableRow
          ..append(_batchEditableFieldCell(id, 'autoRenew', fields))
          ..append(
            _batchCompositeFieldCell(id, fields, const <String>[
              'paymentMethod',
              'reminderDays',
            ]),
          );
      } else {
        tableRow
          ..append(
            TableCellElement()
              ..text = fields['brandSuggestion']?.isNotEmpty == true
                  ? fields['brandSuggestion']!
                  : '—',
          )
          ..append(TableCellElement()..text = '—');
      }
      final resolutionCell = TableCellElement();
      if (row['kind'] == 'subscription' &&
          row['subscriptionTargetRequired'] == true) {
        final options =
            row['subscriptionTargetOptions']! as Map<String, String>;
        final select = SelectElement()
          ..append(
            OptionElement(
              value: '',
              data: _text('选择关联账号'),
              selected: !_batchSubscriptionTargets.containsKey(id),
            ),
          );
        for (final option in options.entries) {
          select.append(
            OptionElement(
              value: option.key,
              data: option.value,
              selected: _batchSubscriptionTargets[id] == option.key,
            ),
          );
        }
        select.disabled = options.isEmpty;
        select.onChange.listen((_) {
          final value = select.value ?? '';
          if (value.isEmpty) {
            _batchSubscriptionTargets.remove(id);
            _batchSelectedIds.remove(id);
          } else {
            _batchSubscriptionTargets[id] = value;
            _batchSelectedIds.add(id);
          }
          _syncBatchCommitButton();
        });
        resolutionCell.append(select);
        if (options.isEmpty) {
          resolutionCell.append(
            DivElement()
              ..classes.add('batch-record-subtitle')
              ..text = _text('本次连接没有获准显示可关联账号'),
          );
        }
      } else if (row['duplicateDescription'] != null) {
        final select = SelectElement();
        for (final option in const <(String, String)>[
          ('skip', '跳过'),
          ('fillEmptyFieldsOnly', '只补充空字段'),
          ('importAsNew', '仍创建另一条'),
        ]) {
          select.append(
            OptionElement(
              value: option.$1,
              data: _text(option.$2),
              selected: _batchDuplicateResolutions[id] == option.$1,
            ),
          );
        }
        select.onChange.listen((_) {
          _batchDuplicateResolutions[id] = select.value ?? 'skip';
        });
        resolutionCell.append(select);
      } else {
        resolutionCell.text = '—';
      }
      tableRow.append(resolutionCell);
      tableRow.append(
        TableCellElement()..append(
          _button('从本次导入移除', () {
            _batchRows.removeWhere((candidate) => candidate['id'] == id);
            _batchSelectedIds.remove(id);
            _batchDuplicateResolutions.remove(id);
            _batchSubscriptionTargets.remove(id);
            _renderBatchTable();
          }, danger: true),
        ),
      );
      tableRow.onKeyDown.listen((event) {
        if (event.key == ' ') {
          event.preventDefault();
          _setBatchRowSelected(id, !_batchSelectedIds.contains(id));
          _renderBatchTable();
        } else if (event.key == 'Delete') {
          event.preventDefault();
          _batchRows.removeWhere((candidate) => candidate['id'] == id);
          _batchSelectedIds.remove(id);
          _batchDuplicateResolutions.remove(id);
          _batchSubscriptionTargets.remove(id);
          _renderBatchTable();
        } else if (event.key == 'ArrowDown' || event.key == 'ArrowUp') {
          event.preventDefault();
          final next = index + (event.key == 'ArrowDown' ? 1 : -1);
          final renderedRows = _batchTableBody.querySelectorAll('tr');
          if (next >= 0 && next < renderedRows.length) {
            renderedRows[next].focus();
          }
        }
      });
      _batchTableBody.append(tableRow);
    }
    _element<HtmlElement>('batch-page-status').text =
        '${_batchPage + 1} / ${maximumPage + 1}';
    _element<ButtonElement>('batch-previous-page').disabled =
        _working || _batchPage == 0;
    _element<ButtonElement>('batch-next-page').disabled =
        _working || _batchPage >= maximumPage;
    _input('batch-select-all').checked = visible.every(
      (row) => _batchSelectedIds.contains(row['id']),
    );
    _batchTableRegion.hidden = false;
    _syncBatchCommitButton();
  }

  TableCellElement _batchEditableFieldCell(
    String rowId,
    String field,
    Map<String, String> fields,
  ) {
    final rowKind = rowId.startsWith('subscription-row-')
        ? 'subscription'
        : 'account';
    if (_activeBatchDocumentKind != null &&
        _activeBatchDocumentKind != rowKind) {
      return TableCellElement()..append(
        SpanElement()
          ..text = fields[field]?.isNotEmpty == true ? fields[field]! : '—',
      );
    }
    final input = InputElement()
      ..classes.add('batch-cell-input')
      ..value = _batchRowPatches[rowId]?[field] ?? fields[field] ?? ''
      ..attributes['aria-label'] = _text(field);
    input.onInput.listen((_) {
      (_batchRowPatches[rowId] ??= <String, String>{})[field] =
          input.value ?? '';
    });
    input.onKeyDown.listen((event) {
      if (event.key != 'Enter') return;
      event.preventDefault();
      final inputs = document.querySelectorAll('.batch-cell-input');
      final current = inputs.indexOf(input);
      if (current >= 0 && current + 1 < inputs.length) {
        inputs[current + 1].focus();
      }
    });
    return TableCellElement()..append(input);
  }

  TableCellElement _batchCompositeFieldCell(
    String rowId,
    Map<String, String> fields,
    List<String> names,
  ) {
    final cell = TableCellElement();
    for (final field in names) {
      cell.append(
        _batchEditableFieldCell(rowId, field, fields).children.single,
      );
    }
    return cell;
  }

  void _setBatchRowSelected(String id, bool selected) {
    final row = _batchRows
        .where((candidate) => candidate['id'] == id)
        .firstOrNull;
    final missingSubscriptionTarget =
        row?['kind'] == 'subscription' &&
        row?['subscriptionTargetRequired'] == true &&
        !_batchSubscriptionTargets.containsKey(id);
    if (selected && missingSubscriptionTarget) {
      _batchSelectedIds.remove(id);
      _syncBatchCommitButton();
      return;
    }
    if (selected) {
      _batchSelectedIds.add(id);
    } else {
      _batchSelectedIds.remove(id);
    }
    _syncBatchCommitButton();
  }

  void _setBatchPageSelected(bool selected) {
    final start = _batchPage * _batchPageSize;
    final end = min(start + _batchPageSize, _batchRows.length);
    for (final row in _batchRows.sublist(start, end)) {
      final id = row['id']! as String;
      final missingSubscriptionTarget =
          row['kind'] == 'subscription' &&
          row['subscriptionTargetRequired'] == true &&
          !_batchSubscriptionTargets.containsKey(id);
      _setBatchRowSelected(id, selected && !missingSubscriptionTarget);
    }
    _renderBatchTable();
  }

  void _removeSelectedBatchRows() {
    _batchRows.removeWhere(
      (row) => _batchSelectedIds.contains(row['id']! as String),
    );
    _batchSelectedIds.clear();
    _batchDuplicateResolutions.removeWhere(
      (id, _) => !_batchRows.any((row) => row['id'] == id),
    );
    _batchSubscriptionTargets.removeWhere(
      (id, _) => !_batchRows.any((row) => row['id'] == id),
    );
    _renderBatchTable();
  }

  Future<void> _commitBatchImport() async {
    if (_working || _channel == null || _batchPreviewToken == null) return;
    if (_batchPreviewNeedsReupload || _phoneUnlockRequired) {
      _showBatchSummary('手机锁定后权威批量预览已失效；网页选择仍保留，请重新选择文件生成预览。', error: true);
      return;
    }
    if (_batchSelectedIds.isEmpty) {
      _showBatchSummary('至少选择一条可导入记录。', error: true);
      return;
    }
    if (_input('batch-final-confirm').checked != true) {
      _showBatchSummary('请先勾选最终确认。', error: true);
      return;
    }
    _setWorking(true);
    _showBatchSummary('正在手机端重新验证并一次提交…');
    try {
      final response = await _mutation('batchImportCommit', <String, Object?>{
        'previewToken': _batchPreviewToken,
        'selectedRowIds': _batchSelectedIds.toList(growable: false),
        'duplicateResolutions': <String, Object?>{
          for (final id in _batchSelectedIds)
            id: _batchDuplicateResolutions[id] ?? 'skip',
        },
        'subscriptionAccountTargets': <String, Object?>{
          for (final entry in _batchSubscriptionTargets.entries)
            if (_batchSelectedIds.contains(entry.key)) entry.key: entry.value,
        },
      });
      if (_isPhoneUnlockRequiredResponse(response)) return;
      final status = response['status'];
      if (status == 'pendingPhoneApproval') {
        _showMessage('请求已发送到手机。请在卡坞“电脑临时录入”页面弹窗中点击“批准本次操作”。');
        _showPhoneApprovalPrompt();
        await _waitForBatchApproval(response['approvalId']! as String);
      } else if (status == 'conflict') {
        _clearBatchImportMemory();
        _showBatchSummary('手机数据已变化，权威预览已失效；请重新生成。', error: true);
        await _refreshWithoutWorkingGuard();
      } else {
        _showBatchSummary(
          response['message'] as String? ?? '操作未完成，请检查输入。',
          error: true,
        );
      }
    } on Object {
      _showBatchSummary('写入结果无法确认，请立即在手机端核对后再继续。', error: true);
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _waitForBatchApproval(String approvalId) async {
    for (var attempt = 0; attempt < 125 && !_ended; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final response = await _command(<String, Object?>{
        'action': 'approvalResult',
        'approvalId': approvalId,
      });
      if (_isPhoneUnlockRequiredResponse(response)) {
        _closePhoneApprovalPrompt();
        return;
      }
      final status = response['status'];
      if (status == 'pendingPhoneApproval') continue;
      _closePhoneApprovalPrompt();
      if (status == 'committed') {
        final accounts = response['importedAccounts'] as int? ?? 0;
        final formalSubscriptions =
            response['formalSubscriptions'] as int? ?? 0;
        final pendingSubscriptions =
            response['pendingSubscriptionDrafts'] as int? ?? 0;
        final unsupported = response['unsupportedRecords'] as int? ?? 0;
        final merged = response['mergedRecords'] as int? ?? 0;
        final skipped = response['skippedRecords'] as int? ?? 0;
        _clearBatchImportMemory();
        _showBatchSummary(
          '${_text('批量导入已提交到手机。')} '
          '${_text('账号')} $accounts · '
          '${_text('正式订阅')} $formalSubscriptions · '
          '${_text('待完善订阅')} $pendingSubscriptions · '
          '${_text('只补充空字段')} $merged · '
          '${_text('跳过')} $skipped · '
          '${_text('不支持')} $unsupported',
        );
        await _refreshWithoutWorkingGuard();
      } else {
        _clearBatchImportMemory();
        _showBatchSummary(
          response['message'] as String? ?? '手机确认未通过。',
          error: true,
        );
      }
      return;
    }
    _closePhoneApprovalPrompt();
    _clearBatchImportMemory();
    _showBatchSummary('手机确认已超时。', error: true);
  }

  void _downloadTemplate({required bool account, bool customFields = false}) {
    final headers = customFields
        ? const [
            'account_key',
            'field_order',
            'field_name',
            'field_type',
            'field_value',
          ]
        : _templateHeaders(account: account);
    final languageCode = switch (_language) {
      _PageLanguage.simplifiedChinese => 'zh',
      _PageLanguage.english => 'en',
      _PageLanguage.japanese => 'ja',
    };
    final format = _select('batch-template-format').value ?? 'xlsx';
    late final Uint8List bytes;
    late final String mimeType;
    late final String extension;
    switch (format) {
      case 'docx':
        bytes = _buildDocxTemplate(headers);
        mimeType =
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        extension = 'docx';
      case 'tsv':
        bytes = _utf8Bom('${headers.join('\t')}\r\n');
        mimeType = 'text/tab-separated-values;charset=utf-8';
        extension = 'tsv';
      case 'txt':
        bytes = _utf8Bom('${headers.join('\t')}\r\n');
        mimeType = 'text/plain;charset=utf-8';
        extension = 'txt';
      case 'csv':
        bytes = _utf8Bom('${headers.map(_csvCell).join(',')}\r\n');
        mimeType = 'text/csv;charset=utf-8';
        extension = 'csv';
      default:
        bytes = _buildXlsxTemplate(headers);
        mimeType =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        extension = 'xlsx';
    }
    final blob = Blob(<Object>[bytes], mimeType);
    final url = Url.createObjectUrlFromBlob(blob);
    final anchor = AnchorElement(href: url)
      ..download = customFields
          ? 'cardock-account-custom-fields-template-$languageCode.$extension'
          : account
          ? 'cardock-accounts-template-$languageCode.$extension'
          : 'cardock-subscriptions-template-$languageCode.$extension'
      ..style.display = 'none';
    document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Url.revokeObjectUrl(url);
    bytes.fillRange(0, bytes.length, 0);
  }

  List<String> _templateHeaders({required bool account}) =>
      switch ((_language, account)) {
        (_PageLanguage.simplifiedChinese, true) => const <String>[
          '账号关联标识',
          '平台名称',
          '登录账号',
          '手机号',
          '邮箱',
          '密码',
          '网址',
          '备注',
        ],
        (_PageLanguage.simplifiedChinese, false) => const <String>[
          '账号关联标识',
          '方案名称',
          '金额',
          '币种',
          '计费周期',
          '首次订阅日期',
          '下次续费日期',
          '自动续费',
          '支付方式',
          '提前提醒天数',
          '备注',
        ],
        (_PageLanguage.english, true) => const <String>[
          'Account Link Key',
          'Platform Name',
          'Login Username',
          'Phone',
          'Email',
          'Password',
          'Website',
          'Notes',
        ],
        (_PageLanguage.english, false) => const <String>[
          'Account Link Key',
          'Plan Name',
          'Amount',
          'Currency',
          'Billing Cycle',
          'Subscription Start Date',
          'Next Renewal Date',
          'Auto Renew',
          'Payment Method',
          'Reminder Days',
          'Notes',
        ],
        (_PageLanguage.japanese, true) => const <String>[
          'アカウント連携キー',
          'サービス名',
          'ログイン名',
          '電話番号',
          'メールアドレス',
          'パスワード',
          'ウェブサイト',
          'メモ',
        ],
        (_PageLanguage.japanese, false) => const <String>[
          'アカウント連携キー',
          'プラン名',
          '金額',
          '通貨',
          '請求周期',
          '初回購読日',
          '次回更新日',
          '自動更新',
          '支払方法',
          '事前通知日数',
          'メモ',
        ],
      };

  Uint8List _utf8Bom(String contents) =>
      Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(contents)]);

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  Uint8List _buildXlsxTemplate(List<String> headers) {
    final contentTypesNamespace = _officeNamespace(
      'schemas.openxmlformats.org/package/2006/content-types',
    );
    final packageRelationshipsNamespace = _officeNamespace(
      'schemas.openxmlformats.org/package/2006/relationships',
    );
    final spreadsheetNamespace = _officeNamespace(
      'schemas.openxmlformats.org/spreadsheetml/2006/main',
    );
    final officeRelationshipsNamespace = _officeNamespace(
      'schemas.openxmlformats.org/officeDocument/2006/relationships',
    );
    final headerCells = <String>[];
    final blankCells = <String>[];
    for (var index = 0; index < headers.length; index += 1) {
      final column = _xlsxColumnName(index);
      headerCells.add(
        '<c r="${column}1" s="1" t="inlineStr"><is><t>${_xmlEscape(headers[index])}</t></is></c>',
      );
      blankCells.add(
        '<c r="${column}2" s="2" t="inlineStr"><is><t></t></is></c>',
      );
    }
    final lastColumn = _xlsxColumnName(headers.length - 1);
    return _zipXml(<String, String>{
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="$contentTypesNamespace">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '</Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="$packageRelationshipsNamespace">'
          '<Relationship Id="rId1" Type="$officeRelationshipsNamespace/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
      'xl/workbook.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="$spreadsheetNamespace" xmlns:r="$officeRelationshipsNamespace">'
          '<sheets><sheet name="Cardock" sheetId="1" r:id="rId1"/></sheets>'
          '</workbook>',
      'xl/_rels/workbook.xml.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="$packageRelationshipsNamespace">'
          '<Relationship Id="rId1" Type="$officeRelationshipsNamespace/worksheet" Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" Type="$officeRelationshipsNamespace/styles" Target="styles.xml"/>'
          '</Relationships>',
      'xl/styles.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<styleSheet xmlns="$spreadsheetNamespace">'
          '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
          '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
          '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
          '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
          '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
          '</styleSheet>',
      'xl/worksheets/sheet1.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<worksheet xmlns="$spreadsheetNamespace">'
          '<dimension ref="A1:${lastColumn}2"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
          '<cols><col min="1" max="${headers.length}" width="20" customWidth="1" style="2"/></cols>'
          '<sheetData><row r="1">${headerCells.join()}</row><row r="2">${blankCells.join()}</row></sheetData>'
          '<autoFilter ref="A1:${lastColumn}1"/>'
          '</worksheet>',
    });
  }

  Uint8List _buildDocxTemplate(List<String> headers) {
    final contentTypesNamespace = _officeNamespace(
      'schemas.openxmlformats.org/package/2006/content-types',
    );
    final packageRelationshipsNamespace = _officeNamespace(
      'schemas.openxmlformats.org/package/2006/relationships',
    );
    final officeRelationshipsNamespace = _officeNamespace(
      'schemas.openxmlformats.org/officeDocument/2006/relationships',
    );
    final wordNamespace = _officeNamespace(
      'schemas.openxmlformats.org/wordprocessingml/2006/main',
    );
    String cell(String value, {bool bold = false}) =>
        '<w:tc><w:tcPr><w:tcW w:w="1800" w:type="dxa"/></w:tcPr><w:p><w:r>${bold ? '<w:rPr><w:b/></w:rPr>' : ''}<w:t xml:space="preserve">${_xmlEscape(value)}</w:t></w:r></w:p></w:tc>';
    final headerRow = headers.map((value) => cell(value, bold: true)).join();
    final blankRow = headers.map((_) => cell('')).join();
    return _zipXml(<String, String>{
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="$contentTypesNamespace">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '</Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="$packageRelationshipsNamespace">'
          '<Relationship Id="rId1" Type="$officeRelationshipsNamespace/officeDocument" Target="word/document.xml"/>'
          '</Relationships>',
      'word/document.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="$wordNamespace"><w:body>'
          '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblLayout w:type="autofit"/></w:tblPr>'
          '<w:tr>$headerRow</w:tr><w:tr>$blankRow</w:tr></w:tbl>'
          '<w:sectPr><w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720"/></w:sectPr>'
          '</w:body></w:document>',
    });
  }

  Uint8List _zipXml(Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final content = Uint8List.fromList(utf8.encode(entry.value));
      archive.addFile(ArchiveFile(entry.key, content.length, content));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  String _xlsxColumnName(int index) {
    var value = index + 1;
    final output = StringBuffer();
    while (value > 0) {
      value -= 1;
      output.writeCharCode(0x41 + value % 26);
      value ~/= 26;
    }
    return output.toString().split('').reversed.join();
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _officeNamespace(String suffix) =>
      '${String.fromCharCodes(const <int>[104, 116, 116, 112, 58, 47, 47])}$suffix';

  void _showBatchSummary(String message, {bool error = false}) {
    _batchSummary
      ..text = _localizedMessage(message)
      ..classes.toggle('error', error);
  }

  void _syncBatchCommitButton() {
    final unresolvedSubscriptionRows = _batchRows.where(
      (row) =>
          row['kind'] == 'subscription' &&
          row['subscriptionTargetRequired'] == true &&
          !_batchSubscriptionTargets.containsKey(row['id']),
    );
    final hasUnresolvedSubscription = unresolvedSubscriptionRows.isNotEmpty;
    final hasAnySubscriptionTargetOption = unresolvedSubscriptionRows.any(
      (row) =>
          (row['subscriptionTargetOptions'] as Map<String, String>).isNotEmpty,
    );
    final guidance = switch ((
      _batchPreviewToken,
      hasUnresolvedSubscription,
      hasAnySubscriptionTargetOption,
      _batchSelectedIds.isEmpty,
      _input('batch-final-confirm').checked == true,
    )) {
      (null, _, _, _, _) => '先选择文件并完成手机端权威预览。',
      (_, true, false, _, _) =>
        '订阅必须关联账号，但本次连接没有获准显示可选账号。请在手机重新开启连接并选择“历史摘要”或“历史详情”，或在同一批次加入账号文件。',
      (_, true, true, _, _) => '请先在表格“处理方式”列选择关联账号；只有一个可选账号时会自动关联。',
      (_, false, _, true, _) => '请至少选择一条可导入记录。',
      (_, false, _, false, false) => '请先勾选最终确认。',
      _ => '点击后会在手机弹出批准框；请拿起手机点击“批准本次操作”。',
    };
    _batchCommitGuidance
      ..text = _localizedMessage(guidance)
      ..classes.toggle(
        'error',
        hasUnresolvedSubscription ||
            (_batchPreviewToken != null && _batchSelectedIds.isEmpty),
      );
    _element<ButtonElement>('batch-commit-button').disabled =
        _working ||
        _ended ||
        _phoneUnlockRequired ||
        _batchPreviewNeedsReupload ||
        _batchPreviewToken == null ||
        _batchSelectedIds.isEmpty ||
        _input('batch-final-confirm').checked != true;
    _element<ButtonElement>('batch-import-tab').disabled =
        _working || _ended || _snapshot['batchImportAvailable'] != true;
  }

  void _clearBatchImportMemory() {
    _batchPreview?.clear();
    _batchPreview = null;
    for (final row in _batchRows) {
      row.clear();
    }
    _batchRows = <Map<String, Object?>>[];
    _batchSelectedIds.clear();
    _batchDuplicateResolutions.clear();
    _batchSubscriptionTargets.clear();
    _batchMappingOverrides.clear();
    _batchRowPatches.clear();
    _batchDefaultValues.clear();
    _batchDocuments.clear();
    _activeBatchDocumentKind = null;
    _batchPreviewToken = null;
    _batchPreviewNeedsReupload = false;
    _batchPage = 0;
    _batchFileInput.value = '';
    _batchPasteInput.value = '';
    _input('batch-final-confirm').checked = false;
    _batchMapping.children.clear();
    _batchDocumentSlots.children.clear();
    _batchTableBody.children.clear();
    _batchTableRegion.hidden = true;
    _syncBatchCommitButton();
  }

  Future<void> _clearBatchImportEverywhere() async {
    try {
      if (_channel != null && !_ended) {
        await _mutation('batchImportClear', const <String, Object?>{});
      }
    } on Object {
      // Session teardown also clears the authoritative in-memory port.
    } finally {
      _clearBatchImportMemory();
    }
  }

  Future<void> _saveAccount() async {
    if (_working || _channel == null) return;
    final id = _input('account-id').value ?? '';
    final passwordMode = _select('account-password-mode').value ?? 'preserve';
    final password = _input('account-password').value ?? '';
    if (id.isNotEmpty && passwordMode == 'replace' && password.isEmpty) {
      _showMessage('选择“替换密码”后必须输入新密码。', error: true);
      return;
    }
    final body = <String, Object?>{
      if (id.isNotEmpty) 'id': id,
      'platformName': _input('account-platform').value ?? '',
      'category': _canonicalAccountCategory(_input('account-category').value),
      'loginAccount': _emptyToNull(_input('account-login').value),
      'username': _emptyToNull(_input('account-username').value),
      'boundPhone': _emptyToNull(_input('account-phone').value),
      'boundEmail': _emptyToNull(_input('account-email').value),
      'website': _emptyToNull(_input('account-website').value),
      'notes': _emptyToNull(_textArea('account-notes').value),
      'customFields': [
        for (final field in _editingCustomFields)
          Map<String, Object?>.of(field),
      ],
      'password': _emptyToNull(password),
      'passwordMode': id.isEmpty ? 'replace' : passwordMode,
    };
    await _runMutation(
      id.isEmpty ? 'addAccount' : 'updateAccount',
      body,
      successMessage: id.isEmpty ? '账号已保存到手机。' : '账号修改已保存到手机。',
      afterSuccess: _closeAccountEditor,
    );
  }

  Future<void> _saveSubscription() async {
    if (_working || _channel == null) return;
    final id = _input('subscription-id').value ?? '';
    final body = <String, Object?>{
      if (id.isNotEmpty) 'id': id,
      'accountId': _emptyToNull(_select('subscription-account').value),
      'serviceName': _input('subscription-service').value ?? '',
      'planName': _emptyToNull(_input('subscription-plan').value),
      'amount': _emptyToNull(_input('subscription-amount').value),
      'currency': _subscriptionCurrencyValue(),
      'firstSubscribedOn': _input('subscription-first-date').value ?? '',
      'nextRenewalOn': _input('subscription-next-date').value ?? '',
      'cycleCount':
          int.tryParse(_input('subscription-cycle-count').value ?? '') ?? 1,
      'cycleUnit': _select('subscription-cycle-unit').value ?? 'month',
      'autoRenew': _input('subscription-auto-renew').checked ?? false,
      'paymentMethod': _emptyToNull(_input('subscription-payment').value),
      'reminderDaysBefore':
          int.tryParse(_input('subscription-reminder-days').value ?? '') ?? 7,
      'reminderEnabled':
          _input('subscription-reminder-enabled').checked ?? false,
      'status': _select('subscription-status').value ?? 'active',
    };
    await _runMutation(
      id.isEmpty ? 'addSubscription' : 'updateSubscription',
      body,
      successMessage: id.isEmpty ? '订阅已保存到手机。' : '订阅修改已保存到手机。',
      afterSuccess: _closeSubscriptionEditor,
    );
  }

  Future<void> _runMutation(
    String action,
    Map<String, Object?> body, {
    required String successMessage,
    void Function()? afterSuccess,
  }) async {
    if (_working) return;
    _setWorking(true);
    try {
      final response = await _mutation(action, body);
      final status = response['status'];
      if (_isPhoneUnlockRequiredResponse(response)) {
        // The encrypted channel and every unsubmitted browser field remain.
      } else if (status == 'committed') {
        afterSuccess?.call();
        _showMessage(successMessage);
        await _refreshWithoutWorkingGuard();
      } else if (status == 'pendingPhoneApproval') {
        _showMessage('请求已发送到手机。请在卡坞“电脑临时录入”页面弹窗中点击“批准本次操作”。');
        _showPhoneApprovalPrompt();
        await _waitForApproval(response['approvalId']! as String);
      } else if (status == 'conflict') {
        _showMessage('手机数据已变化，已为你刷新；请核对后重试。', error: true);
        await _refreshWithoutWorkingGuard();
      } else if (status == 'resultUnknown') {
        _showMessage('写入结果无法确认，请立即在手机端核对后再继续。', error: true);
      } else {
        _showMessage(
          response['message'] as String? ?? '操作未完成，请检查输入。',
          error: true,
        );
      }
    } on Object {
      _showMessage('连接中断，刚才的写入结果可能未知；请在手机解锁后核对。', error: true);
      await _handleChannelFailure();
    } finally {
      _setWorking(false);
      if (!_phoneUnlockRequired) _clearPasswordInputs();
    }
  }

  Future<void> _waitForApproval(String approvalId) async {
    for (var attempt = 0; attempt < 125 && !_ended; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final response = await _command(<String, Object?>{
        'action': 'approvalResult',
        'approvalId': approvalId,
      });
      if (_isPhoneUnlockRequiredResponse(response)) {
        _closePhoneApprovalPrompt();
        return;
      }
      final status = response['status'];
      if (status == 'pendingPhoneApproval') continue;
      _closePhoneApprovalPrompt();
      if (status == 'committed') {
        _closeAccountEditor();
        _showMessage('手机已确认，操作已完成。');
        await _refreshWithoutWorkingGuard();
      } else if (status == 'approved') {
        final password =
            (response['secret'] ?? response['password']) as String?;
        final visibleForMilliseconds =
            response['visibleForMilliseconds'] as int?;
        if (password == null) {
          _showMessage('该账号没有保存密码。');
        } else if (visibleForMilliseconds == null ||
            visibleForMilliseconds <= 0 ||
            visibleForMilliseconds > 30000) {
          throw const FormatException('Password display lifetime is invalid.');
        } else {
          _showTemporarySecret(
            password,
            Duration(milliseconds: visibleForMilliseconds),
          );
        }
      } else {
        _showMessage(response['message'] as String? ?? '手机确认未通过。', error: true);
      }
      return;
    }
    _closePhoneApprovalPrompt();
    _showMessage('手机确认已超时。', error: true);
  }

  Future<void> _refreshWithoutWorkingGuard() async {
    final response = await _command(<String, Object?>{'action': 'snapshot'});
    if (_isPhoneUnlockRequiredResponse(response)) return;
    if (response['status'] != 'ok') throw StateError('Snapshot rejected.');
    _applyResponseLocale(response);
    _snapshot = _requiredMap(response, 'data');
    _revision = _requiredInt(_snapshot, 'revision');
    _applySessionTimeouts(_snapshot['timeouts']);
    _render();
    _finishPhoneUnlockRefresh();
  }

  void _render() {
    final historyMode = _snapshot['historyMode'] as String? ?? '';
    final allowEdit = _snapshot['allowHistoryEditing'] == true;
    final allowPassword = _snapshot['allowHistoricalPasswordReveal'] == true;
    _scopeDescription.text = <String>[
      switch (historyMode) {
        'currentSessionOnly' => _text('仅显示本次会话创建的记录'),
        'summary' => _text('显示历史摘要'),
        'details' => _text('显示历史详情（历史密码不批量传输）'),
        _ => _text('权限由手机端决定'),
      },
      allowEdit ? _text('允许编辑历史记录') : _text('历史记录只读'),
      allowPassword ? _text('可向手机申请临时显示历史密码') : _text('不允许显示历史密码'),
    ].join(' · ');
    _renderAccounts(_objectList(_snapshot['accounts']));
    _renderSubscriptions(_objectList(_snapshot['subscriptions']));
    _populateCategoryChoices();
    _populateAccountChoices();
    _syncBatchCommitButton();
  }

  void _populateCategoryChoices() {
    final dataList = _element<HtmlElement>('account-category-options');
    dataList.children.clear();
    for (final category in _stringList(_snapshot['accountCategories'])) {
      final displayCategory = _displayAccountCategory(category);
      dataList.append(
        OptionElement(data: displayCategory, value: displayCategory),
      );
    }
  }

  void _renderAccounts(List<Map<String, Object?>> accounts) {
    _accountList.children.clear();
    if (accounts.isEmpty) {
      _accountList.append(_empty('当前权限范围内没有账号。'));
      return;
    }
    for (final account in accounts) {
      final card = DivElement()..classes.add('record');
      final title = HeadingElement.h3()
        ..append(Text(account['platformName'] as String? ?? _text('未命名账号')));
      title.append(
        SpanElement()
          ..classes.add('tag')
          ..text = account['isCurrentSession'] == true
              ? _text('本次')
              : _text('历史'),
      );
      card.append(title);
      final details = DListElement();
      _detail(details, '分类', _displayAccountCategoryValue(account['category']));
      _detail(details, '登录账号', account['loginAccount']);
      _detail(details, '用户名', account['username']);
      _detail(details, '绑定手机', account['boundPhone']);
      _detail(details, '绑定邮箱', account['boundEmail']);
      _detail(details, '网站', account['website']);
      _detail(details, '备注', account['notes']);
      _detail(details, '订阅数', account['subscriptionCount']);
      card.append(details);
      final actions = DivElement()..classes.add('record-actions');
      final hasDetails = account.containsKey('loginAccount');
      if (account['canEdit'] == true && hasDetails) {
        actions.append(
          _button('编辑', () => _openAccountEditor(account: account)),
        );
      }
      actions.append(
        _button(
          account['deleteNeedsPhoneApproval'] == true ? '申请删除' : '删除',
          () => unawaited(
            _deleteRecord('deleteAccount', account['id']! as String),
          ),
          danger: true,
        ),
      );
      final password = account['password'] as String?;
      if (password != null) {
        actions.append(
          _button('显示本次密码 30 秒', () => _showTemporarySecret(password)),
        );
      } else if (account['isCurrentSession'] != true &&
          account['hasPassword'] == true &&
          _snapshot['allowHistoricalPasswordReveal'] == true) {
        actions.append(
          _button(
            '向手机申请显示密码',
            () =>
                unawaited(_requestHistoricalPassword(account['id']! as String)),
          ),
        );
      }
      for (final field in _objectList(account['customFields'])) {
        final name = field['name'] as String? ?? '';
        if (field['type'] == 'sensitive_text') {
          _detail(details, name, '••••••', translateLabel: false);
          actions.append(
            _button(
              '${_text('申请显示敏感字段')} · $name',
              () => unawaited(
                _runMutation('requestCustomField', {
                  'id': account['id'],
                  'fieldId': field['id'],
                }, successMessage: '手机已确认。'),
              ),
            ),
          );
        } else {
          _detail(details, name, field['value'], translateLabel: false);
        }
      }
      card.append(actions);
      _accountList.append(card);
    }
  }

  void _renderSubscriptions(List<Map<String, Object?>> subscriptions) {
    _subscriptionList.children.clear();
    if (subscriptions.isEmpty) {
      _subscriptionList.append(_empty('当前权限范围内没有订阅。'));
      return;
    }
    for (final subscription in subscriptions) {
      final card = DivElement()..classes.add('record');
      final title = HeadingElement.h3()
        ..append(
          Text(subscription['serviceName'] as String? ?? _text('未命名订阅')),
        );
      title.append(
        SpanElement()
          ..classes.add('tag')
          ..text = subscription['isCurrentSession'] == true
              ? _text('本次')
              : _text('历史'),
      );
      card.append(title);
      final details = DListElement();
      _detail(
        details,
        '首次订阅',
        _localizedRecordDateValue(subscription['firstSubscribedOn']),
      );
      _detail(
        details,
        '下次续费',
        _localizedRecordDateValue(subscription['nextRenewalOn']),
      );
      _detail(details, '状态', _statusText(subscription['status']));
      _detail(details, '方案', subscription['planName']);
      _detail(details, '金额', subscription['amount']);
      _detail(details, '货币', subscription['currency']);
      _detail(details, '周期', _cycleText(subscription));
      _detail(details, '自动续费', _yesNo(subscription['autoRenew']));
      _detail(details, '支付方式', subscription['paymentMethod']);
      _detail(
        details,
        '提前提醒',
        _localizedDaysBeforeValue(subscription['reminderDaysBefore']),
      );
      _detail(details, '提醒已启用', _yesNo(subscription['reminderEnabled']));
      card.append(details);
      final actions = DivElement()..classes.add('record-actions');
      final hasDetails = subscription.containsKey('firstSubscribedOn');
      if (subscription['canEdit'] == true && hasDetails) {
        actions.append(
          _button(
            '编辑',
            () => _openSubscriptionEditor(subscription: subscription),
          ),
        );
      }
      actions.append(
        _button(
          subscription['deleteNeedsPhoneApproval'] == true ? '申请删除' : '删除',
          () => unawaited(
            _deleteRecord('deleteSubscription', subscription['id']! as String),
          ),
          danger: true,
        ),
      );
      card.append(actions);
      _subscriptionList.append(card);
    }
  }

  Future<void> _deleteRecord(String action, String id) async {
    final label = action == 'deleteAccount' ? _text('账号') : _text('订阅');
    final confirmation = switch (_language) {
      _PageLanguage.simplifiedChinese => '确定要删除这条$label记录吗？历史记录还需在手机端确认。',
      _PageLanguage.english =>
        'Delete this $label record? Historical records also require confirmation on your phone.',
      _PageLanguage.japanese => 'この$label記録を削除しますか？履歴の記録はスマートフォンでの確認も必要です。',
    };
    if (window.confirm(confirmation) != true) {
      return;
    }
    await _runMutation(
      action,
      <String, Object?>{'id': id},
      successMessage: switch (_language) {
        _PageLanguage.simplifiedChinese => '$label已删除。',
        _PageLanguage.english => 'The $label was deleted.',
        _PageLanguage.japanese => '$labelを削除しました。',
      },
    );
  }

  Future<void> _requestHistoricalPassword(String id) async {
    await _runMutation('requestHistoricalPassword', <String, Object?>{
      'id': id,
    }, successMessage: '手机已确认。');
  }

  void _openAccountEditor({Map<String, Object?>? account}) {
    _closeSubscriptionEditor();
    _accountForm.reset();
    final editing = account != null;
    _element<HtmlElement>('account-editor-title').text = editing
        ? _text('编辑账号')
        : _text('新增账号');
    _input('account-id').value = account?['id'] as String? ?? '';
    _input('account-platform').value =
        account?['platformName'] as String? ?? '';
    _input('account-category').value = _displayAccountCategoryValue(
      account?['category'],
    );
    _input('account-login').value = account?['loginAccount'] as String? ?? '';
    _input('account-username').value = account?['username'] as String? ?? '';
    _input('account-phone').value = account?['boundPhone'] as String? ?? '';
    _input('account-email').value = account?['boundEmail'] as String? ?? '';
    _input('account-website').value = account?['website'] as String? ?? '';
    _textArea('account-notes').value = account?['notes'] as String? ?? '';
    _editingCustomFields.clear();
    _editingCustomFields.addAll([
      for (final field in _objectList(account?['customFields']))
        Map<String, Object?>.of(field),
    ]);
    _renderCustomFieldEditor();
    _input('account-password').value = '';
    _select('account-password-mode').value = 'preserve';
    _element<HtmlElement>('password-mode-label').hidden = !editing;
    _syncPasswordMode();
    _accountEditor.hidden = false;
    _accountEditor.scrollIntoView();
  }

  void _closeAccountEditor() {
    _editingCustomFields.clear();
    _element<HtmlElement>('account-custom-fields').children.clear();
    _accountForm.reset();
    _clearPasswordInputs();
    _accountEditor.hidden = true;
  }

  void _clearCustomFieldValues() {
    for (final field in _editingCustomFields) {
      if (field['type'] == 'sensitive_text' &&
          field['valueState'] != 'redacted') {
        field['value'] = '';
      }
    }
    for (final input in document.querySelectorAll('[data-custom-sensitive]')) {
      if (input is InputElement) input.value = '';
    }
  }

  void _renderCustomFieldEditor() {
    final host = _element<HtmlElement>('account-custom-fields');
    host.children.clear();
    for (var index = 0; index < _editingCustomFields.length; index++) {
      final field = _editingCustomFields[index];
      field['order'] = index;
      final box = DivElement()..classes.add('record');
      final name = InputElement()
        ..value = field['name'] as String? ?? ''
        ..maxLength = 100
        ..placeholder = _text('字段名称')
        ..required = true;
      name.onInput.listen((_) => field['name'] = name.value ?? '');
      final type = SelectElement();
      for (final code in ['text', 'sensitive_text', 'url', 'date', 'number']) {
        type.append(
          OptionElement(
            data: _text(switch (code) {
              'sensitive_text' => '敏感文本',
              'url' => '网址',
              'date' => '日期',
              'number' => '数字',
              _ => '普通文本',
            }),
            value: code,
          ),
        );
      }
      type.value = field['type'] as String? ?? 'text';
      type.onChange.listen((_) {
        if (field['valueState'] == 'redacted') field['value'] = '';
        field.remove('valueState');
        field['type'] = type.value;
        _renderCustomFieldEditor();
      });
      final input =
          InputElement(
              type: type.value == 'sensitive_text' ? 'password' : 'text',
            )
            ..value = field['value'] as String? ?? ''
            ..maxLength = 10000
            ..autocomplete = 'off'
            ..spellcheck = false;
      if (type.value == 'sensitive_text') {
        input.dataset['customSensitive'] = 'true';
      }
      if (field['valueState'] == 'redacted') {
        input.placeholder = _text('留空保留已有值；输入可直接替换');
      }
      input.onInput.listen((_) {
        field['value'] = input.value ?? '';
        field.remove('valueState');
      });
      box.append(
        LabelElement()
          ..text = _text('字段名称')
          ..append(name),
      );
      box.append(
        LabelElement()
          ..text = _text('字段类型')
          ..append(type),
      );
      box.append(
        LabelElement()
          ..text = _text('字段值')
          ..append(input),
      );
      if (type.value == 'sensitive_text') {
        box.append(
          ParagraphElement()
            ..text = _text('不建议保存私钥、助记词、支付密码、CVV、完整银行卡资料或验证码恢复码。'),
        );
      }
      box.append(
        _button('上移', () {
          if (index > 0) {
            _editingCustomFields.removeAt(index);
            _editingCustomFields.insert(index - 1, field);
            _renderCustomFieldEditor();
          }
        }),
      );
      box.append(
        _button('下移', () {
          if (index + 1 < _editingCustomFields.length) {
            _editingCustomFields.removeAt(index);
            _editingCustomFields.insert(index + 1, field);
            _renderCustomFieldEditor();
          }
        }),
      );
      box.append(
        _button('删除', () {
          _editingCustomFields.removeAt(index);
          _renderCustomFieldEditor();
        }),
      );
      host.append(box);
    }
  }

  void _syncPasswordMode() {
    final editing = (_input('account-id').value ?? '').isNotEmpty;
    final mode = _select('account-password-mode').value;
    final password = _input('account-password');
    password.disabled = editing && mode != 'replace';
    password.required = editing && mode == 'replace';
    if (password.disabled == true) password.value = '';
  }

  void _openSubscriptionEditor({Map<String, Object?>? subscription}) {
    _closeAccountEditor();
    _subscriptionForm.reset();
    _populateAccountChoices();
    final editing = subscription != null;
    _element<HtmlElement>('subscription-editor-title').text = editing
        ? _text('编辑订阅')
        : _text('新增订阅');
    _input('subscription-id').value = subscription?['id'] as String? ?? '';
    _select('subscription-account').value =
        subscription?['accountId'] as String? ??
        _select('subscription-account').options.first.value;
    _input('subscription-service').value =
        subscription?['serviceName'] as String? ?? '';
    _input('subscription-plan').value =
        subscription?['planName'] as String? ?? '';
    _input('subscription-amount').value =
        subscription?['amount'] as String? ?? '';
    _setSubscriptionCurrency(subscription?['currency'] as String? ?? 'CNY');
    final today = DateTime.now();
    _input('subscription-first-date').value =
        subscription?['firstSubscribedOn'] as String? ?? _date(today);
    _input('subscription-next-date').value =
        subscription?['nextRenewalOn'] as String? ??
        _date(
          advanceSubscriptionDate(
            today,
            count: 1,
            unit: SubscriptionCycleUnit.month,
          ),
        );
    _input('subscription-cycle-count').value =
        (subscription?['cycleCount'] as int? ?? 1).toString();
    _select('subscription-cycle-unit').value =
        subscription?['cycleUnit'] as String? ?? 'month';
    _select('subscription-status').value =
        subscription?['status'] as String? ?? 'active';
    _input('subscription-payment').value =
        subscription?['paymentMethod'] as String? ?? '';
    _input('subscription-reminder-days').value =
        (subscription?['reminderDaysBefore'] as int? ?? 7).toString();
    _input('subscription-auto-renew').checked =
        subscription?['autoRenew'] as bool? ?? true;
    _input('subscription-reminder-enabled').checked =
        subscription?['reminderEnabled'] as bool? ?? true;
    _subscriptionEditor.hidden = false;
    _subscriptionEditor.scrollIntoView();
  }

  void _closeSubscriptionEditor() {
    _subscriptionForm.reset();
    _syncSubscriptionCurrencyInput();
    _subscriptionEditor.hidden = true;
  }

  void _setSubscriptionCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    final currency = normalized.isEmpty ? 'CNY' : normalized;
    final select = _select('subscription-currency');
    final customInput = _input('subscription-custom-currency');
    if (subscriptionCurrencies.contains(currency)) {
      select.value = currency;
      customInput.value = '';
    } else {
      select.value = _customCurrencyValue;
      customInput.value = currency;
    }
    _syncSubscriptionCurrencyInput();
  }

  void _syncSubscriptionCurrencyInput() {
    final usesCustom =
        _select('subscription-currency').value == _customCurrencyValue;
    final customLabel = _element<HtmlElement>(
      'subscription-custom-currency-label',
    );
    final customInput = _input('subscription-custom-currency');
    customLabel.hidden = !usesCustom;
    customInput.disabled = !usesCustom;
    customInput.required = usesCustom;
    if (!usesCustom) customInput.value = '';
  }

  String _subscriptionCurrencyValue() {
    final selected = _select('subscription-currency').value ?? 'CNY';
    if (selected != _customCurrencyValue) return selected;
    return (_input('subscription-custom-currency').value ?? '')
        .trim()
        .toUpperCase();
  }

  void _populateAccountChoices() {
    final select = _select('subscription-account');
    final selected = select.value;
    select.children.clear();
    select.append(
      OptionElement(
        data: _text('不关联账号 · 独立订阅'),
        value: '',
        selected: selected == null || selected.isEmpty,
      ),
    );
    for (final account in _objectList(_snapshot['accounts'])) {
      select.append(
        OptionElement(
          data: account['platformName'] as String? ?? _text('未命名账号'),
          value: account['id'] as String? ?? '',
          selected: account['id'] == selected,
        ),
      );
    }
  }

  void _showTemporarySecret(
    String password, [
    Duration visibleFor = const Duration(seconds: 30),
  ]) {
    _clearTemporarySecret();
    _secretVisible = true;
    _showMessage('密码（${visibleFor.inSeconds} 秒后清除）：$password');
    _secretTimer = Timer(visibleFor, () {
      _secretTimer = null;
      if (!_secretVisible) return;
      _secretVisible = false;
      _showMessage('密码显示时间已结束。');
    });
  }

  bool _secretVisible = false;

  void _clearTemporarySecret({String? message}) {
    final wasVisible = _secretVisible;
    _secretTimer?.cancel();
    _secretTimer = null;
    _secretVisible = false;
    if (!wasVisible) return;
    _message
      ..text = ''
      ..classes.remove('error');
    if (message != null) _showMessage(message);
  }

  void _applySessionTimeouts(Object? value) {
    final timeouts = _stringMap(value);
    final connectionDurationMilliseconds = _requiredInt(
      timeouts,
      'connectionDurationMilliseconds',
    );
    final connectionRemainingMilliseconds = _requiredInt(
      timeouts,
      'connectionRemainingMilliseconds',
    );
    if (connectionDurationMilliseconds <= 0 ||
        connectionRemainingMilliseconds <= 0) {
      unawaited(_endPage('所选连接时间已到，页面数据已清空。'));
      return;
    }
    _connectionExpiryTimer?.cancel();
    _connectionExpiryTimer = Timer(
      Duration(milliseconds: connectionRemainingMilliseconds),
      () => unawaited(_endPage('所选连接时间已到，页面数据已清空。')),
    );
  }

  Future<void> _handleChannelFailure() async {
    await _endPage('连接已结束。若刚才有写入，请在手机解锁后核对结果。');
  }

  Future<void> _endPage(String message) async {
    if (_ended) {
      return;
    }
    _ended = true;
    final channel = _channel;
    _channel = null;
    _pairing?.cancel();
    _pairing = null;
    _connectionExpiryTimer?.cancel();
    _connectionExpiryTimer = null;
    _clearSensitivePageState();
    _workspace.hidden = true;
    _pairingPanel.hidden = false;
    _pairButton.disabled = true;
    _setStatus('已断开', 'status-error');
    _showMessage(message, error: true);
    if (channel != null) {
      try {
        await channel.destroy();
      } on Object {
        // Page data and local references were already synchronously cleared.
      }
    }
  }

  void _clearSensitivePageState() {
    _phoneUnlockRequired = false;
    _refreshAfterPhoneUnlock = false;
    _clearTemporarySecret();
    _closePhoneApprovalPrompt();
    _clearBatchImportMemory();
    _snapshot = const <String, Object?>{};
    _revision = -1;
    _accountList.children.clear();
    _subscriptionList.children.clear();
    _editingCustomFields.clear();
    _element<HtmlElement>('account-custom-fields').children.clear();
    _accountForm.reset();
    _subscriptionForm.reset();
    _syncSubscriptionCurrencyInput();
    _connectionCode.value = '';
    _clearPasswordInputs();
    _scopeDescription.text = '';
    _message
      ..text = ''
      ..classes.remove('error');
  }

  void _clearPasswordInputs() {
    _clearCustomFieldValues();
    _input('account-password').value = '';
  }

  void _setWorking(bool value) {
    _working = value;
    for (final element in document.querySelectorAll('button')) {
      if (element is ButtonElement &&
          element.id != 'disconnect-button' &&
          element.id != 'phone-approval-dialog-close') {
        element.disabled = value || _ended;
      }
    }
    _syncBatchCommitButton();
  }

  void _setStatus(String text, String className) {
    _connectionStatus
      ..text = _localizedMessage(text)
      ..classes.removeWhere((name) => name.startsWith('status-'))
      ..classes.add(className);
  }

  void _showMessage(String text, {bool error = false}) {
    _message
      ..text = _localizedMessage(text)
      ..classes.toggle('error', error);
  }

  void _showPhoneApprovalPrompt() {
    if (_phoneApprovalDialog.open == true) return;
    try {
      _phoneApprovalDialog.showModal();
    } on Object {
      // The inline message remains the accessible fallback.
    }
  }

  void _closePhoneApprovalPrompt() {
    if (_phoneApprovalDialog.open == true) _phoneApprovalDialog.close();
  }

  ButtonElement _button(
    String label,
    void Function() onClick, {
    bool danger = false,
    bool primary = false,
  }) {
    final button = ButtonElement()
      ..type = 'button'
      ..text = _text(label);
    if (danger) button.classes.add('danger');
    if (primary) button.classes.add('primary');
    button.onClick.listen((_) => onClick());
    return button;
  }

  HtmlElement _empty(String text) => DivElement()
    ..classes.add('empty')
    ..text = _text(text);

  void _detail(
    DListElement list,
    String label,
    Object? value, {
    bool translateLabel = true,
  }) {
    if (value == null || value == '') return;
    list
      ..append(Element.tag('dt')..text = translateLabel ? _text(label) : label)
      ..append(Element.tag('dd')..text = value.toString());
  }

  String _displayAccountCategory(String value) =>
      accountCategories.contains(value) ? _text(value) : value;

  String _displayAccountCategoryValue(Object? value) => value is String
      ? _displayAccountCategory(value)
      : value?.toString() ?? '';

  String? _canonicalAccountCategory(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final folded = normalized.toLowerCase();
    for (final category in accountCategories) {
      final translation = _pageTranslations[category];
      if (folded == category.toLowerCase() ||
          folded == translation?.english.toLowerCase() ||
          normalized == translation?.japanese) {
        return category;
      }
    }
    return normalized;
  }

  String? _cycleText(Map<String, Object?> subscription) {
    final count = subscription['cycleCount'];
    final unit = subscription['cycleUnit'];
    if (count is! int || unit is! String) return null;
    final cycleUnit = switch (unit) {
      'day' => SubscriptionCycleUnit.day,
      'week' => SubscriptionCycleUnit.week,
      'month' => SubscriptionCycleUnit.month,
      'year' => SubscriptionCycleUnit.year,
      _ => null,
    };
    return cycleUnit == null
        ? null
        : _localizedSubscriptionCycle(cycleUnit, count);
  }

  // Browser-safe parity with the records localization helpers. Importing the
  // app localization module would pull dart:io into this dart2js entrypoint.
  String _localizedSubscriptionCycle(SubscriptionCycleUnit unit, int count) {
    if (_language == _PageLanguage.simplifiedChinese) {
      if (count == 1) return '每${unit.label}';
      return unit == SubscriptionCycleUnit.month
          ? '每$count个月'
          : '每$count${unit.label}';
    }
    if (_language == _PageLanguage.japanese) {
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

  String? _localizedRecordDateValue(Object? value) {
    if (value == null || value == '') return null;
    final parsed = switch (value) {
      DateTime date => date,
      String text => DateTime.tryParse(text),
      _ => null,
    };
    if (parsed == null) return value.toString();
    final date = DateTime(parsed.year, parsed.month, parsed.day);
    if (_language == _PageLanguage.english) {
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

  String? _localizedDaysBeforeValue(Object? value) {
    if (value is! int) return value?.toString();
    return switch (_language) {
      _PageLanguage.simplifiedChinese => '提前$value天',
      _PageLanguage.english =>
        value == 1 ? '1 day before' : '$value days before',
      _PageLanguage.japanese => '$value日前',
    };
  }

  String? _yesNo(Object? value) => switch (value) {
    true => _text('是'),
    false => _text('否'),
    _ => null,
  };

  String? _statusText(Object? value) => switch (value) {
    'active' => _text('正常'),
    'paused' => _text('暂停'),
    'cancelled' => _text('已取消'),
    'expired' => _text('已到期'),
    null => null,
    _ => value.toString(),
  };

  String _requestId() {
    final bytes = Uint8List(18);
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = _random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _batchRejectionMessage(
    Map<String, Object?> response,
    String fallback,
  ) {
    final rawMessage = response['message'];
    final message =
        rawMessage is String &&
            rawMessage.isNotEmpty &&
            rawMessage.length <= 240
        ? rawMessage
        : fallback;
    final rawCode = response['errorCode'];
    if (rawCode is! String ||
        rawCode.isEmpty ||
        rawCode.length > 64 ||
        !RegExp(r'^[a-z0-9_]+$').hasMatch(rawCode)) {
      return message;
    }
    return '$message [$rawCode]';
  }

  String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}';
  }

  String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  InputElement _input(String id) => _element<InputElement>(id);
  SelectElement _select(String id) => _element<SelectElement>(id);
  TextAreaElement _textArea(String id) => _element<TextAreaElement>(id);
}

Future<Map<String, Object?>> _jsonRequest(
  String method,
  String path, {
  Map<String, Object?>? body,
}) async {
  final request = HttpRequest();
  final completer = Completer<Map<String, Object?>>();
  request
    ..open(method, path, async: true)
    ..responseType = 'text';
  if (body != null) {
    request.setRequestHeader('Content-Type', 'application/json');
  }
  request.onLoad.first.then((_) {
    if (completer.isCompleted) return;
    try {
      if (request.status != 200) {
        String? serverStatus;
        try {
          final decoded = _stringMap(jsonDecode(request.responseText ?? ''));
          final value = decoded['status'];
          if (value is String && value.length <= 64) serverStatus = value;
        } on Object {
          // A rejected response is allowed to omit a JSON body.
        }
        throw _LocalHttpRequestException(
          statusCode: request.status ?? 0,
          serverStatus: serverStatus,
        );
      }
      completer.complete(_stringMap(jsonDecode(request.responseText ?? '')));
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  });
  request.onError.first.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Local HTTP request failed.'));
    }
  });
  request.onTimeout.first.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Local HTTP request timed out.'));
    }
  });
  request.timeout = 15000;
  request.send(body == null ? null : jsonEncode(body));
  return completer.future;
}

String _connectionFailureMessage(
  _PageLanguage language,
  String stage,
  Object error, [
  StackTrace? stackTrace,
]) {
  final detailKey = switch (error) {
    _LocalHttpRequestException(:final serverStatus) => switch (serverStatus) {
      'pairingFailed' => '连接码未通过验证或本次配对已失效',
      'alreadyPaired' => '本次连接已被使用或不再接受配对',
      'sessionEnded' => '手机端已结束本次连接',
      'rejected' => '手机拒绝了不符合本次会话要求的请求',
      'invalidHost' => '浏览器地址与手机当前显示的地址不一致',
      _ => '手机未接受本次请求',
    },
    _ => '浏览器未能完成当前步骤',
  };
  final category = switch (error) {
    TrustedLanPairingException(:final failure) => 'PAIRING_${failure.name}',
    UnsupportedError() => 'UNSUPPORTED',
    StateError() => 'STATE',
    ArgumentError() => 'ARGUMENT',
    FormatException() => 'FORMAT',
    _LocalHttpRequestException() => 'HTTP',
    _ => 'UNEXPECTED',
  };
  final diagnostic = _includePairingDiagnostics
      ? '/${_safeDiagnosticText(error, stackTrace)}'
      : '';
  final detail = switch ((language, detailKey)) {
    (_PageLanguage.english, '连接码未通过验证或本次配对已失效') =>
      'The connection code was not accepted, or the pairing session has expired',
    (_PageLanguage.english, '本次连接已被使用或不再接受配对') =>
      'This connection has already been used or is no longer accepting pairing',
    (_PageLanguage.english, '手机端已结束本次连接') => 'The phone ended this connection',
    (_PageLanguage.english, '手机拒绝了不符合本次会话要求的请求') =>
      'The phone rejected a request that did not meet the session requirements',
    (_PageLanguage.english, '浏览器地址与手机当前显示的地址不一致') =>
      'The browser address does not match the address shown on the phone',
    (_PageLanguage.english, '手机未接受本次请求') =>
      'The phone did not accept the request',
    (_PageLanguage.english, _) => 'The browser could not complete this step',
    (_PageLanguage.japanese, '连接码未通过验证或本次配对已失效') =>
      '接続コードが承認されなかったか、ペアリングの有効期限が切れました',
    (_PageLanguage.japanese, '本次连接已被使用或不再接受配对') =>
      'この接続はすでに使用されたか、ペアリングを受け付けていません',
    (_PageLanguage.japanese, '手机端已结束本次连接') => 'スマートフォン側でこの接続が終了しました',
    (_PageLanguage.japanese, '手机拒绝了不符合本次会话要求的请求') =>
      'セッションの要件を満たさないリクエストがスマートフォンで拒否されました',
    (_PageLanguage.japanese, '浏览器地址与手机当前显示的地址不一致') =>
      'ブラウザのアドレスがスマートフォンに表示されたアドレスと一致しません',
    (_PageLanguage.japanese, '手机未接受本次请求') => 'スマートフォンでリクエストが受け付けられませんでした',
    (_PageLanguage.japanese, _) => 'ブラウザでこの手順を完了できませんでした',
    _ => detailKey,
  };
  return switch (language) {
    _PageLanguage.simplifiedChinese =>
      '$detail（$stage/$category$diagnostic）。本次页面已安全断开；请回到手机重新开启连接，刷新本页后输入新码。',
    _PageLanguage.english =>
      '$detail ($stage/$category$diagnostic). This page has been safely disconnected. Start a new connection on your phone, refresh this page, and enter the new code.',
    _PageLanguage.japanese =>
      '$detail（$stage/$category$diagnostic）。このページは安全に切断されました。スマートフォンで新しい接続を開始し、このページを更新して新しいコードを入力してください。',
  };
}

String _safeDiagnosticText(Object error, StackTrace? stackTrace) {
  final text = '$error ${stackTrace ?? ''}'
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();
  return text.length <= 600 ? text : '${text.substring(0, 600)}…';
}

final class _LocalHttpRequestException implements Exception {
  const _LocalHttpRequestException({
    required this.statusCode,
    required this.serverStatus,
  });

  final int statusCode;
  final String? serverStatus;

  @override
  String toString() =>
      '_LocalHttpRequestException(statusCode: $statusCode, '
      'serverStatus: ${serverStatus ?? 'unknown'})';
}

T _element<T extends Element>(String id) {
  final value = document.getElementById(id);
  if (value is! T) throw StateError('Missing page element: $id');
  return value;
}

Map<String, Object?> _requiredMap(Map<String, Object?> source, String key) =>
    _stringMap(source[key]);

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw const FormatException('Invalid JSON key.');
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List<Object?>) throw const FormatException('Expected a list.');
  return <Map<String, Object?>>[for (final item in value) _stringMap(item)];
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) throw const FormatException('Expected a list.');
  return <String>[
    for (final item in value)
      if (item is String)
        item
      else
        throw const FormatException('Expected text.'),
  ];
}

int _requiredInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! int) throw const FormatException('Expected an integer.');
  return value;
}
