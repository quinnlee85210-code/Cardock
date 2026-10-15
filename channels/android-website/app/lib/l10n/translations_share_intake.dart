const Map<String, String> shareIntakeEnglishTranslations = <String, String>{
  '从其他应用分享文字': 'Share text from another app',
  'Android 可分享普通文字或 http(s) 链接；解锁后在本机核对候选':
      'On Android, share plain text or an http(s) link and review candidates after unlocking',
  'Android“分享至Cardock”': 'Android “Share to Cardock”',
  '在其他 Android 应用的分享菜单中选择“分享至Cardock”。Cardock 只接受单条 text/plain 普通文字和 http(s) 链接；图片、PDF、附件、HTML、文件 URI 和可执行内容都会拒绝。\n\n原文只在进程内存中保留最多 5 分钟。必须先解锁真实库或诱饵库，确认候选并选择当前库中的已有账号后，才能保存为待完善订阅草稿。不会打开网址、联网抓取、上传、自动新建账号或正式订阅。':
      'Choose “Share to Cardock” from another Android app. Cardock accepts only one text/plain item containing ordinary text or an http(s) link. Images, PDFs, attachments, HTML, file URIs, and executable content are rejected.\n\nThe original text remains only in process memory for up to 5 minutes. Unlock the real or decoy vault, review candidates, and select an existing account in that vault before saving an incomplete subscription draft. Cardock does not open links, fetch from the network, upload, create an account, or create a formal subscription automatically.',
  '从分享内容整理订阅': 'Organize a subscription from shared text',
  '取消并清除': 'Cancel and clear',
  '只在本机内存中解析，不上传、不联网打开网址。只有点按保存后，所选结构化字段才会进入当前解锁保险库的待完善草稿。':
      'Parsing happens only in memory on this device. Nothing is uploaded and links are not opened. Only after you tap Save are selected structured fields added to an incomplete draft in the currently unlocked vault.',
  '原始分享内容': 'Original shared content',
  '默认收起；离开、锁定、过期或保存后清除':
      'Collapsed by default; cleared on exit, lock, expiry, or save',
  '标题': 'Title',
  '主题': 'Subject',
  '正文': 'Body',
  '候选字段': 'Candidate fields',
  '候选只作为本机建议；你可以编辑、清空或保持留空。':
      'Candidates are on-device suggestions only. You can edit, clear, or leave them blank.',
  '检测到多个候选的字段没有自动选定；请点选、手工编辑、清空或保持留空。':
      'Fields with multiple candidates were not selected automatically. Choose one, edit manually, clear it, or leave it blank.',
  '平台或服务名（仅用于核对）': 'Platform or service (review only)',
  '不会新建或修改账号；保存时以你选择的已有账号为准。':
      'No account is created or changed. Saving uses the existing account you select.',
  '套餐名称（可留空）': 'Plan name (optional)',
  '金额（可留空）': 'Amount (optional)',
  '币种': 'Currency',
  '币种必须为 3 位字母代码': 'Currency must be a 3-letter code',
  '计费周期数量': 'Billing interval',
  '计费周期单位': 'Billing unit',
  '清空计费周期': 'Clear billing cycle',
  '计费周期数量和单位必须同时填写，数量为 1 到 120。':
      'Enter both the billing interval and unit, with an interval from 1 to 120.',
  '计费周期数量和单位必须同时填写或同时留空。':
      'Enter both the billing interval and unit, or leave both blank.',
  '下次续费日期（可留空）': 'Next renewal date (optional)',
  '清空日期': 'Clear date',
  '选择日期': 'Choose date',
  '自动续费（可留空）': 'Auto-renew (optional)',
  '留空': 'Leave blank',
  '检测到互相冲突的自动续费候选，请明确选择或留空。':
      'Conflicting auto-renew candidates were found. Choose explicitly or leave this blank.',
  '网页地址（仅用于核对）': 'Web address (review only)',
  '只接受 http(s)；Cardock 不会打开、抓取或保存为新账号网址。':
      'Only http(s) is accepted. Cardock does not open, fetch, or save it as a new account URL.',
  '只接受有效的 http(s) 网页地址': 'Enter a valid http(s) web address only',
  '关联当前保险库中的已有账号': 'Link an existing account in the current vault',
  '关联已有账号（保存草稿必选）': 'Existing account (required to save)',
  '草稿只写入这个账号所在的当前真实库或诱饵库，不会跨库。':
      'The draft is written only to the current real or decoy vault containing this account. It never crosses vaults.',
  '尚未选择已有账号': 'No existing account selected',
  '当前保险库没有已有账号；本次只能取消或清除，不会自动创建账号。':
      'This vault has no existing accounts. You can only cancel or clear this share; no account is created automatically.',
  '请先选择当前保险库中的已有账号。': 'Select an existing account in the current vault first.',
  '请选择当前保险库中的已有账号；分享草稿未保存。':
      'Select an existing account in the current vault. The shared draft was not saved.',
  '分享中的订阅字段无效；原文未保存。':
      'The subscription fields from the share are invalid. The original text was not saved.',
  '待完善订阅草稿未能写入当前本机加密库。':
      'The incomplete subscription draft could not be written to the current local encrypted vault.',
  '待完善订阅草稿未能保存。': 'The incomplete subscription draft could not be saved.',
  '清除本次内容': 'Clear this share',
  '保存待完善草稿': 'Save incomplete draft',
  '正在保存…': 'Saving…',
  '待完善订阅草稿已加密保存到当前保险库。':
      'The incomplete subscription draft was encrypted and saved to the current vault.',
  '分享内容已过期并从内存中清除。': 'The shared content expired and was cleared from memory.',
  '分享的文字过长，未交给 Cardock 处理。':
      'The shared text is too long and was not handed to Cardock.',
  '这项分享不是受支持的纯文本或 http(s) 链接。':
      'This share is not supported plain text or an http(s) link.',
};

const Map<String, String> shareIntakeJapaneseTranslations = <String, String>{
  '从其他应用分享文字': 'ほかのアプリからテキストを共有',
  'Android 可分享普通文字或 http(s) 链接；解锁后在本机核对候选':
      'Android から通常のテキストまたは http(s) リンクを共有し、ロック解除後に端末上で候補を確認します',
  'Android“分享至Cardock”': 'Android「Cardock に共有」',
  '在其他 Android 应用的分享菜单中选择“分享至Cardock”。Cardock 只接受单条 text/plain 普通文字和 http(s) 链接；图片、PDF、附件、HTML、文件 URI 和可执行内容都会拒绝。\n\n原文只在进程内存中保留最多 5 分钟。必须先解锁真实库或诱饵库，确认候选并选择当前库中的已有账号后，才能保存为待完善订阅草稿。不会打开网址、联网抓取、上传、自动新建账号或正式订阅。':
      'ほかの Android アプリの共有メニューで「Cardock に共有」を選択します。Cardock が受け付けるのは、通常のテキストまたは http(s) リンクを含む 1 件の text/plain だけです。画像、PDF、添付ファイル、HTML、ファイル URI、実行可能な内容は拒否されます。\n\n原文はプロセスメモリ内に最大 5 分だけ保持されます。実保管庫またはおとり保管庫のロックを解除し、候補を確認して、その保管庫内の既存アカウントを選択してから未完成のサブスクリプション下書きを保存します。リンクを開く、ネットワークから取得する、アップロードする、アカウントや正式なサブスクリプションを自動作成することはありません。',
  '从分享内容整理订阅': '共有テキストからサブスクリプションを整理',
  '取消并清除': 'キャンセルして消去',
  '只在本机内存中解析，不上传、不联网打开网址。只有点按保存后，所选结构化字段才会进入当前解锁保险库的待完善草稿。':
      '解析はこの端末のメモリ内だけで行われます。アップロードもリンクを開くこともありません。「保存」をタップした場合だけ、選択した構造化フィールドが現在ロック解除中の保管庫の未完成下書きに入ります。',
  '原始分享内容': '共有された原文',
  '默认收起；离开、锁定、过期或保存后清除': '初期状態では折りたたみ。終了、ロック、期限切れ、保存時に消去',
  '标题': 'タイトル',
  '主题': '件名',
  '正文': '本文',
  '候选字段': '候補フィールド',
  '候选只作为本机建议；你可以编辑、清空或保持留空。': '候補は端末上の提案にすぎません。編集、消去、空欄のままにできます。',
  '检测到多个候选的字段没有自动选定；请点选、手工编辑、清空或保持留空。':
      '複数の候補があるフィールドは自動選択されていません。選択、手動編集、消去、または空欄のままにしてください。',
  '平台或服务名（仅用于核对）': 'プラットフォーム／サービス（確認用）',
  '不会新建或修改账号；保存时以你选择的已有账号为准。': 'アカウントの新規作成や変更は行いません。保存時は選択した既存アカウントを使用します。',
  '套餐名称（可留空）': 'プラン名（任意）',
  '金额（可留空）': '金額（任意）',
  '币种': '通貨',
  '币种必须为 3 位字母代码': '通貨は 3 文字のコードで入力してください',
  '计费周期数量': '請求間隔',
  '计费周期单位': '請求単位',
  '清空计费周期': '請求周期を消去',
  '计费周期数量和单位必须同时填写，数量为 1 到 120。': '請求間隔と単位を両方入力し、間隔は 1～120 にしてください。',
  '计费周期数量和单位必须同时填写或同时留空。': '請求間隔と単位は両方入力するか、両方空欄にしてください。',
  '下次续费日期（可留空）': '次回更新日（任意）',
  '清空日期': '日付を消去',
  '选择日期': '日付を選択',
  '自动续费（可留空）': '自動更新（任意）',
  '留空': '空欄',
  '检测到互相冲突的自动续费候选，请明确选择或留空。': '競合する自動更新候補が見つかりました。明示的に選択するか空欄にしてください。',
  '网页地址（仅用于核对）': 'Web アドレス（確認用）',
  '只接受 http(s)；Cardock 不会打开、抓取或保存为新账号网址。':
      'http(s) のみ受け付けます。Cardock は開く、取得する、新しいアカウント URL として保存することはありません。',
  '只接受有效的 http(s) 网页地址': '有効な http(s) Web アドレスだけを入力してください',
  '关联当前保险库中的已有账号': '現在の保管庫内の既存アカウントに関連付け',
  '关联已有账号（保存草稿必选）': '既存アカウント（保存に必須）',
  '草稿只写入这个账号所在的当前真实库或诱饵库，不会跨库。':
      '下書きはこのアカウントがある現在の実保管庫またはおとり保管庫にだけ書き込まれ、保管庫をまたぎません。',
  '尚未选择已有账号': '既存アカウントが未選択です',
  '当前保险库没有已有账号；本次只能取消或清除，不会自动创建账号。':
      '現在の保管庫に既存アカウントがありません。この共有はキャンセルまたは消去だけが可能で、アカウントは自動作成されません。',
  '请先选择当前保险库中的已有账号。': '先に現在の保管庫内の既存アカウントを選択してください。',
  '请选择当前保险库中的已有账号；分享草稿未保存。': '現在の保管庫内の既存アカウントを選択してください。共有下書きは保存されませんでした。',
  '分享中的订阅字段无效；原文未保存。': '共有内のサブスクリプション項目が無効です。原文は保存されませんでした。',
  '待完善订阅草稿未能写入当前本机加密库。': '未完成のサブスクリプション下書きを現在のローカル暗号化保管庫に書き込めませんでした。',
  '待完善订阅草稿未能保存。': '未完成のサブスクリプション下書きを保存できませんでした。',
  '清除本次内容': 'この共有を消去',
  '保存待完善草稿': '未完成の下書きを保存',
  '正在保存…': '保存中…',
  '待完善订阅草稿已加密保存到当前保险库。': '未完成のサブスクリプション下書きを暗号化して現在の保管庫に保存しました。',
  '分享内容已过期并从内存中清除。': '共有内容は期限切れとなり、メモリから消去されました。',
  '分享的文字过长，未交给 Cardock 处理。': '共有テキストが長すぎるため、Cardock には渡されませんでした。',
  '这项分享不是受支持的纯文本或 http(s) 链接。': 'この共有は対応しているプレーンテキストまたは http(s) リンクではありません。',
};
