typedef _SettingsTranslation = ({String en, String ja});

const Map<String, _SettingsTranslation>
_settingsTranslations = <String, _SettingsTranslation>{
  '免费版使用橙墨旧刊，其他桌面图标随完整版解锁。系统桌面可能需要几秒刷新；应用内 LOGO 跟随主题。': (
    en: 'Paper Archive is free. Other home screen icons unlock with Full Version. The system may take a few seconds to refresh; the in-app logo follows the theme.',
    ja: '無料版はペーパーアーカイブを使用します。他のホーム画面アイコンは完全版で利用できます。反映に数秒かかる場合があります。アプリ内のロゴはテーマに連動します。',
  ),
  '商店价格 {price} · 一次买断': (en: '{price} one-time purchase', ja: '{price}の買い切り'),
  '一次买断，价格以商店为准。没有订阅收费、自动续费、广告或基于用户数据的商业追踪。': (
    en: 'A one-time purchase at the price shown by the store, with no subscription fees, automatic renewals, ads, or commercial tracking based on your data.',
    ja: 'ストアに表示される価格での買い切りです。サブスクリプション料金、自動更新、広告、ユーザーデータに基づく商用トラッキングはありません。',
  ),
  '卡坞完整版一次买断，价格以商店显示为准。完成购买之后，无需订阅或额外付费。': (
    en: 'Cardock Full Version is a one-time purchase at the price shown by the store. After purchase, no subscription or additional payment is required.',
    ja: 'Cardock完全版はストアに表示される価格での買い切りです。購入後にサブスクリプションや追加料金は必要ありません。',
  ),
  '卡坞·Cardock：本地保存账号与订阅记录，免费开始使用；完整版一次买断，价格以商店为准，无广告、无订阅收费。': (
    en: 'Cardock keeps account and subscription records on your device. Start for free; unlock Full Version with a one-time purchase at the store price. No ads or subscription fees.',
    ja: 'Cardockはアカウントとサブスクリプションの記録を端末内に保存します。無料で使い始め、ストア価格の買い切りで完全版をアンロックできます。広告やサブスクリプション料金はありません。',
  ),

  '设置真实保险库密码恢复前请重新输入当前真实主密码。主密码和密保答案都不会保存。': (
    en: 'Re-enter the current real master password before setting up real-vault password recovery. Neither the master password nor the security answers are stored.',
    ja: '実際の保管庫のパスワード復旧を設定する前に、現在の実際のマスターパスワードを再入力してください。マスターパスワードと秘密の質問の答えは保存されません。',
  ),
  '管理诱饵保险库密码恢复需要真实主密码和当前诱饵密码双重授权；两者都不会保存。': (
    en: 'Managing decoy-vault password recovery requires both the real master password and current decoy password. Neither is stored.',
    ja: 'おとり保管庫のパスワード復旧を管理するには、実際のマスターパスワードと現在のおとりパスワードの両方が必要です。どちらも保存されません。',
  ),
  '此步骤不会打开诱饵库，也不会修改真实保险库。': (
    en: 'This step does not open the decoy vault or change the real vault.',
    ja: 'この操作でおとり保管庫が開いたり、実際の保管庫が変更されたりすることはありません。',
  ),
  '设置真实保险库密码恢复': (
    en: 'Set up real-vault password recovery',
    ja: '実際の保管庫のパスワード復旧を設定',
  ),
  '设置诱饵保险库密码恢复': (
    en: 'Set up decoy-vault password recovery',
    ja: 'おとり保管庫のパスワード復旧を設定',
  ),
  '真实保险库密码恢复已启用；请锁定后亲自验证入口和三道答案。': (
    en: 'Real-vault password recovery is enabled. Lock Cardock and personally verify the entry and all three answers.',
    ja: '実際の保管庫のパスワード復旧を有効にしました。Cardockをロックし、入口と3つの答えをご自身で確認してください。',
  ),
  '诱饵保险库密码恢复已启用；请锁定后亲自验证入口和三道答案。': (
    en: 'Decoy-vault password recovery is enabled. Lock Cardock and personally verify the entry and all three answers.',
    ja: 'おとり保管庫のパスワード復旧を有効にしました。Cardockをロックし、入口と3つの答えをご自身で確認してください。',
  ),
  '关闭真实保险库密码恢复？': (
    en: 'Turn off real-vault password recovery?',
    ja: '実際の保管庫のパスワード復旧をオフにしますか？',
  ),
  '关闭诱饵保险库密码恢复？': (
    en: 'Turn off decoy-vault password recovery?',
    ja: 'おとり保管庫のパスワード復旧をオフにしますか？',
  ),
  '关闭后，忘记真实主密码时只能依赖你单独保存的加密备份。业务数据和当前密码不会改变。': (
    en: 'After this is turned off, a separately stored encrypted backup will be your only fallback if you forget the real master password. App data and the current password will not change.',
    ja: 'オフにした後で実際のマスターパスワードを忘れた場合、別途保存した暗号化バックアップだけが回復手段になります。アプリデータと現在のパスワードは変更されません。',
  ),
  '关闭后，如果忘记诱饵密码，独立诱饵库内容将无法通过真实库备份恢复。现有内容和当前密码不会改变。': (
    en: 'After this is turned off, if you forget the decoy password, the separate decoy vault contents cannot be restored from a real-vault backup. Existing content and the current password will not change.',
    ja: 'オフにした後でおとりパスワードを忘れた場合、独立したおとり保管庫の内容を実際の保管庫のバックアップから復元することはできません。既存の内容と現在のパスワードは変更されません。',
  ),
  '管理诱饵保险库密码恢复需要真实主密码和当前诱饵密码双重授权。': (
    en: 'Managing decoy-vault password recovery requires both the real master password and current decoy password.',
    ja: 'おとり保管庫のパスワード復旧を管理するには、実際のマスターパスワードと現在のおとりパスワードの両方が必要です。',
  ),
  '真实保险库密码恢复已关闭。': (
    en: 'Real-vault password recovery is off.',
    ja: '実際の保管庫のパスワード復旧をオフにしました。',
  ),
  '诱饵保险库密码恢复已关闭。': (
    en: 'Decoy-vault password recovery is off.',
    ja: 'おとり保管庫のパスワード復旧をオフにしました。',
  ),
  '真实保险库密码恢复': (en: 'Real-vault password recovery', ja: '実際の保管庫のパスワード復旧'),
  '诱饵保险库密码恢复': (en: 'Decoy-vault password recovery', ja: 'おとり保管庫のパスワード復旧'),
  '未配置 · 独立三道密保 + 本机系统强认证': (
    en: 'Not configured · Separate set of three security questions + strong system authentication on this device',
    ja: '未設定 · 独立した3つの秘密の質問 + 端末の強力なシステム認証',
  ),
  '恢复不会显示旧密码。每次恢复都必须同时答对三题，并通过本机指纹或安全级人脸。请使用只有你知道且长期稳定的答案；两套保险库的三道问题组合不能完全相同。': (
    en: 'Recovery never reveals the old password. Every recovery attempt requires all three correct answers plus fingerprint or secure face authentication on this device. Use answers known only to you and stable over time. The two vaults cannot use exactly the same set of three questions.',
    ja: '復旧で以前のパスワードが表示されることはありません。復旧のたびに3問すべてへ正しく答え、この端末の指紋または安全な顔認証を完了する必要があります。自分だけが知り、長期間変わらない答えを使用してください。2つの保管庫で、まったく同じ3つの質問の組み合わせは使用できません。',
  ),
  '未完成表单暂时无法读取，已保存的记录不受影响。': (
    en: 'The unfinished form could not be read. Saved records are unaffected.',
    ja: '入力途中のフォームを読み込めませんでした。保存済みの記録には影響しません。',
  ),
  '未完成表单暂时无法加密保存，请保持此页面并重试。': (
    en: 'The unfinished form could not be saved securely. Keep this page open and try again.',
    ja: '入力途中のフォームを暗号化して保存できませんでした。この画面を開いたまま再試行してください。',
  ),
  '已恢复非精确提醒，系统可能延迟': (
    en: 'Inexact reminders restored; Android may delay delivery',
    ja: '非正確な通知を復元済み。システムにより遅延する場合があります',
  ),
  '检测到系统停止记录': (en: 'System stop detected', ja: 'システムによる停止を検出'),
  '系统曾在 {time} 停止卡坞，可能清除已安排的提醒。请允许自启动、关联启动和后台活动，并固定最近任务卡片。': (
    en: 'Android stopped Cardock at {time}, which may clear scheduled reminders. Allow auto-launch, secondary launch and background activity, and pin the app in recent tasks.',
    ja: 'システムが {time} に Cardock を停止しました。予定済みの通知が消去された可能性があります。自動起動・連携起動・バックグラウンド動作を許可し、最近のタスクに固定してください。',
  ),
  // Shared settings, product, and about copy.
  '设置': (en: 'Settings', ja: '設定'),
  '产品': (en: 'Product', ja: '製品'),
  '安全': (en: 'Security', ja: 'セキュリティ'),
  '外观': (en: 'Appearance', ja: '外観'),
  '显示偏好': (en: 'Display preferences', ja: '表示設定'),
  '加密数据': (en: 'Encrypted data', ja: '暗号化データ'),
  '提醒与订阅偏好': (
    en: 'Reminders and subscription defaults',
    ja: 'リマインダーとサブスクリプションの設定',
  ),
  '保存加密备份': (en: 'Save encrypted backup', ja: '暗号化バックアップを保存'),
  '选择加密备份': (en: 'Choose encrypted backup', ja: '暗号化バックアップを選択'),
  '解锁完整版': (en: 'Unlock Full Version', ja: '完全版をアンロック'),
  '解锁完整版 {price}': (
    en: 'Unlock Full Version for CN{price}',
    ja: 'CN{price}で完全版をアンロック',
  ),
  '{price} 一次买断': (en: 'CN{price} one-time purchase', ja: 'CN{price}の買い切り'),
  '卡坞完整版': (en: 'Cardock Full Version', ja: 'Cardock 完全版'),
  '完整版': (en: 'Full Version', ja: '完全版'),
  '免费版': (en: 'Free Version', ja: '無料版'),
  '永久完整版': (en: 'Full Version for life', ja: '永続ライセンスの完全版'),
  '一次买断，长期使用': (en: 'Buy once, use for life', ja: '買い切りで、ずっと使えます'),
  '一次买断 · 不是订阅': (
    en: 'One-time purchase · No subscription',
    ja: '買い切り · サブスクリプションではありません',
  ),
  '一次解锁，长期使用': (en: 'Unlock once, use for life', ja: '一度の購入で、ずっと使えます'),
  '选择适合你的版本': (en: 'Choose the version for you', ja: '自分に合うバージョンを選択'),
  '恢复购买': (en: 'Restore purchases', ja: '購入を復元'),
  '记录不设上限': (en: 'Unlimited records', ja: '記録数は無制限'),
  '订阅和账户数量无限制': (
    en: 'Unlimited subscriptions and accounts',
    ja: 'サブスクリプションとアカウントは無制限',
  ),
  '账号与订阅数量不再受免费额度限制，已有数据始终保留。': (
    en: 'Remove the Free Version limits on accounts and subscriptions. Your existing data is always kept.',
    ja: '無料版のアカウント数とサブスクリプション数の上限がなくなります。既存のデータはそのまま保持されます。',
  ),
  '最多 5 个订阅项': (en: 'Up to 5 subscriptions', ja: 'サブスクリプションは最大5件'),
  '最多 15 个账户条目': (en: 'Up to 15 account entries', ja: 'アカウントは最大15件'),
  '橙墨旧刊主题（免费）': (en: 'Paper Archive theme (free)', ja: 'ペーパーアーカイブテーマ（無料）'),
  '八套固定主题与自定义主题': (
    en: 'Eight preset themes and a custom theme',
    ja: '8種類のプリセットテーマとカスタムテーマ',
  ),
  '解锁七套高级固定主题与自定义主题': (
    en: 'Unlock seven premium preset themes and the custom theme',
    ja: '7種類のプレミアムテーマとカスタムテーマをアンロック',
  ),
  '不是订阅制，没有持续会员费用': (
    en: 'No subscription or recurring membership fee',
    ja: 'サブスクリプションではなく、継続料金もありません',
  ),
  '核心记录能力可以长期使用': (
    en: 'Core record keeping remains available',
    ja: '基本の記録機能は引き続き利用できます',
  ),
  '一杯饮品的价格，解锁不受数量限制的长期整理空间。': (
    en: 'For the price of a drink, unlock an organized space with no record limits.',
    ja: 'ドリンク1杯ほどの価格で、件数制限のない整理スペースをずっと利用できます。',
  ),
  '无需注册登录，不把保险库上传到公网或云端。': (
    en: 'No account required. Your vault is never uploaded to the public internet or cloud.',
    ja: '登録やログインは不要です。保管庫をインターネットやクラウドへアップロードしません。',
  ),
  '本地加密方式不变': (en: 'The same on-device encryption', ja: '端末内暗号化はそのまま'),
  '从瓷蓝晴光到曜石鎏金，并支持自定义配色。': (
    en: 'From Ceramic Blue to Obsidian Gold, plus your own color palette.',
    ja: 'セラミックブルーからオブシディアンゴールドまで、さらに配色をカスタマイズできます。',
  ),
  '无限记录、全套主题；继续保持本地加密与无需注册。': (
    en: 'Unlimited records and every theme, with the same on-device encryption and no sign-up.',
    ja: '記録数は無制限、すべてのテーマを利用可能。端末内暗号化と登録不要は変わりません。',
  ),
  '本地加密 · 无需注册账号 · 商店购买记录由应用商店托管 · 推广激活仅在本机离线验签。': (
    en: 'On-device encryption · No account required · Store purchases are managed by the app store · Promotional activation is verified offline on this device.',
    ja: '端末内暗号化 · アカウント登録不要 · 購入履歴はアプリストアが管理 · プロモーション認証はこの端末でオフライン検証',
  ),
  '已解锁完整版': (en: 'Full Version unlocked', ja: '完全版をアンロック済み'),
  '已解锁，所有数量限制与主题限制均已移除。': (
    en: 'Unlocked. All record and theme limits have been removed.',
    ja: 'アンロック済みです。件数とテーマの制限はすべて解除されています。',
  ),
  '已解锁完整版 · 感谢支持': (
    en: 'Full Version unlocked · Thank you for your support',
    ja: '完全版をアンロック済み · ご支援ありがとうございます',
  ),
  '感谢支持卡坞持续维护。': (
    en: 'Thank you for supporting continued Cardock development.',
    ja: 'Cardockの継続的な開発をご支援いただき、ありがとうございます。',
  ),
  '已通过推广激活解锁': (
    en: 'Unlocked with promotional activation',
    ja: 'プロモーション認証でアンロック済み',
  ),
  '已通过推广激活解锁，所有数量限制与主题限制均已移除。': (
    en: 'Unlocked with promotional activation. All record and theme limits have been removed.',
    ja: 'プロモーション認証でアンロック済みです。件数とテーマの制限はすべて解除されています。',
  ),
  '完整版权益已在本机通过 Ed25519 签名验证。': (
    en: 'Full Version access has been verified on this device with an Ed25519 signature.',
    ja: '完全版の権利は、この端末でEd25519署名により検証済みです。',
  ),
  '该主题为完整版专属': (
    en: 'This theme requires the Full Version',
    ja: 'このテーマは完全版限定です',
  ),
  '免费版账户数量已达上限': (
    en: 'You have reached the Free Version account limit',
    ja: '無料版のアカウント数上限に達しました',
  ),
  '免费版订阅数量已达上限': (
    en: 'You have reached the Free Version subscription limit',
    ja: '無料版のサブスクリプション数上限に達しました',
  ),
  '暂不': (en: 'Not now', ja: '今はしない'),
  '调试权益状态': (en: 'Debug entitlement state', ja: 'デバッグ用ライセンス状態'),
  '调试状态：免费。': (en: 'Debug state: Free.', ja: 'デバッグ状態：無料版。'),
  '调试状态：已购。': (en: 'Debug state: Purchased.', ja: 'デバッグ状態：購入済み。'),
  '仅调试构建可见，用于验证免费版与已购态。': (
    en: 'Visible only in debug builds for testing Free and purchased states.',
    ja: 'デバッグビルドでのみ表示され、無料版と購入済み状態の確認に使用します。',
  ),
  '关于卡坞·Cardock': (en: 'About Cardock', ja: 'Cardockについて'),
  '版本 {version}': (en: 'Version {version}', ja: 'バージョン {version}'),
  '本地存储与隐私边界': (en: 'On-device storage and privacy', ja: '端末内保存とプライバシー'),
  '账号与订阅数据默认加密保存在本机，不上传云端，也不进行云同步。卡坞不会申请通讯录、位置、外部存储或媒体读取权限，也不会扫描设备上的其他文件；导入或导出加密备份时，只会通过系统文件选择器处理你当次明确指定的文件。应用所需的 INTERNET 权限仅用于你主动开启“电脑临时录入”后，在自己的手机热点或可信 Wi-Fi 上提供短时局域网连接，不会连接公网、云端或中继，结束会话即停止。卡坞是一款真正属于你个人的本地工具，数据与使用方式的控制权始终在你手中。': (
    en: 'Account and subscription data is encrypted on this device by default. It is not uploaded to the cloud, and Cardock provides no cloud sync. Cardock does not request access to your contacts, location, external storage, or media, and it does not scan other files on your device. When you import or export an encrypted backup, the system file picker handles only the file you explicitly choose for that action. The INTERNET permission is used solely when you start Temporary PC Entry, providing a short-lived local connection over your own phone hotspot or trusted Wi-Fi. It does not connect to the public internet, cloud services, or a relay, and the connection stops when the session ends. Cardock is a genuinely personal, on-device tool: control over your data and how it is used remains with you.',
    ja: 'アカウントとサブスクリプションのデータは、既定で端末内に暗号化して保存されます。クラウドへアップロードせず、クラウド同期も行いません。Cardockは連絡先、位置情報、外部ストレージ、メディアへのアクセス権限を要求せず、端末内のほかのファイルを走査することもありません。暗号化バックアップを読み込む、または書き出す場合は、その操作でご自身が明示的に選んだファイルだけをシステムのファイル選択画面で処理します。INTERNET権限は、「PCから一時入力」を自分で開始したときに限り、ご自身のスマートフォンのテザリングまたは信頼できるWi-Fiで短時間のローカル接続を提供するために使用します。インターネット、クラウド、中継サービスへは接続せず、セッション終了時に接続も停止します。Cardockは本当にあなた個人のための端末内ツールであり、データと利用方法の主導権は常にあなたにあります。',
  ),
  '保险库如何加密': (en: 'How the vault is encrypted', ja: '保管庫の暗号化方式'),
  '每个保险库都会生成独立的随机 256 位数据密钥，并使用 AES-256-GCM 加密账号和订阅数据。它不仅隐藏内容，还会校验密文完整性；文件被篡改或损坏时，应用会拒绝把异常内容当作有效数据读取。主密码不会以明文保存，也不直接充当数据密钥。': (
    en: 'Each vault gets its own random 256-bit data key. Account and subscription data is encrypted with AES-256-GCM, which conceals the content and verifies ciphertext integrity. If a file is altered or damaged, Cardock refuses to read it as valid data. The master password is never stored in plain text and is not used directly as the data key.',
    ja: '保管庫ごとに独立したランダムな256ビットのデータキーを生成し、AES-256-GCMでアカウントとサブスクリプションを暗号化します。内容を隠すだけでなく暗号文の整合性も検証するため、ファイルが改ざん・破損している場合は有効なデータとして読み込みません。マスターパスワードを平文で保存したり、データキーとして直接使用したりすることもありません。',
  ),
  '主密码与密钥保护': (en: 'Master password and key protection', ja: 'マスターパスワードとキーの保護'),
  '主密码配合每次随机生成的盐，经 Argon2id 内存困难型算法派生密钥，再用于保护保险库的数据密钥。当前参数为 19 MiB 内存、2 次迭代、并行度 1。生物识别只调用系统认证并保护本机快速解锁材料；认证失败时仍需主密码。': (
    en: 'The master password and a fresh random salt are processed with the memory-hard Argon2id algorithm to derive a key that protects the vault data key. Current parameters are 19 MiB of memory, 2 iterations, and parallelism 1. Biometrics only invokes system authentication and protects local quick-unlock material; the master password is still required if authentication fails.',
    ja: 'マスターパスワードと毎回生成するランダムなソルトから、メモリハードなArgon2idでキーを導出し、保管庫のデータキーを保護します。現在のパラメータはメモリ19 MiB、反復2回、並列度1です。生体認証はシステム認証を呼び出し、端末内のクイックアンロック用データを保護するだけです。認証に失敗した場合はマスターパスワードが必要です。',
  ),
  '独立加密备份': (en: 'Independent encrypted backups', ja: '独立した暗号化バックアップ'),
  '.asmbackup 便携备份使用独立备份密码，并继续采用 Argon2id 与 AES-256-GCM 保护。备份文件由你自行离线保管；恢复时不会更改手机当前主密码。安装标识和推广激活码不进入备份，因此完整版权益不会随数据文件迁移到另一台设备。': (
    en: 'Portable .asmbackup files use a separate backup password and remain protected by Argon2id and AES-256-GCM. You keep the file offline yourself, and restoring it does not change the current master password on your phone. The installation ID and promotional activation code are not backed up, so Full Version access does not move to another device with the data file.',
    ja: 'ポータブルな.asmbackupは専用のバックアップパスワードを使用し、Argon2idとAES-256-GCMで保護されます。ファイルはご自身でオフライン保管し、復元してもスマートフォンの現在のマスターパスワードは変わりません。インストールIDとプロモーション認証コードはバックアップされないため、完全版の権利はデータファイルと一緒に別の端末へ移行しません。',
  ),
  '开源许可与品牌声明': (
    en: 'Open-source licenses and trademarks',
    ja: 'オープンソースライセンスと商標',
  ),
  '内置单色品牌识别图形部分来自 Simple Icons（CC0-1.0）。第三方名称与商标归各权利人所有，仅用于识别用户记录的平台，不代表授权、关联、赞助或背书；字母标是 Cardock 生成的非官方占位图形。': (
    en: 'Some built-in monochrome brand marks come from Simple Icons (CC0-1.0). Third-party names and trademarks belong to their respective owners and are used only to identify platforms in user records; they do not imply authorization, affiliation, sponsorship, or endorsement. Letter marks are unofficial placeholders generated by Cardock.',
    ja: '内蔵の単色ブランドアイコンの一部はSimple Icons（CC0-1.0）に由来します。第三者の名称および商標は各権利者に帰属し、ユーザー記録内のサービスを識別するためにのみ使用しています。認可、提携、スポンサー関係、推奨を示すものではありません。文字アイコンはCardockが生成した非公式のプレースホルダーです。',
  ),
  '开发者的话': (en: 'A Note from the Developer', ja: '開発者からのメッセージ'),
  '第一款作品 · 关于初心与维护': (
    en: 'My first app · Why it exists and how it will be maintained',
    ja: '初めてのアプリ · 開発の思いと今後の保守',
  ),
  '谢谢你选择卡坞': (
    en: 'Thank you for choosing Cardock',
    ja: 'Cardockを選んでいただき、ありがとうございます',
  ),
  '这是我完成的第一款正式 App，也是我准备认真维护下去的一款 App。': (
    en: 'This is the first app I have completed as a finished product, and one I intend to maintain with care.',
    ja: 'これは、私が初めて正式な形まで完成させたアプリであり、これからも丁寧に保守していきたいアプリです。',
  ),
  '第一款作品': (en: 'My first app', ja: '初めての作品'),
  '9.9 元一次买断': (en: 'CN¥9.9 one-time purchase', ja: 'CN¥9.9の買い切り'),
  '长期维护': (en: 'Ongoing maintenance', ja: '長期的な保守'),
  '为什么做卡坞': (en: 'Why I made Cardock', ja: 'Cardockを作った理由'),
  '账号、密码和订阅记录，都是非常私人的信息。': (
    en: 'Account details, passwords, and subscription records are all deeply personal information.',
    ja: 'アカウント、パスワード、サブスクリプションの記録は、どれも非常に個人的な情報です。',
  ),
  '我做卡坞，不是想再建立一个要求用户注册、同步和交出数据的平台，而是想做一件安静、可靠、真正留在你设备里的工具。': (
    en: 'I did not make Cardock to create yet another platform that asks you to register, sync, and hand over your data. I wanted to build a quiet, dependable tool that genuinely stays on your device.',
    ja: 'Cardockを作ったのは、登録や同期を求め、データを預けてもらう新たなプラットフォームを増やすためではありません。静かで信頼でき、本当にあなたの端末に留まる道具を作りたかったからです。',
  ),
  '卡坞是我完成的第一款正式 App。它不是一个做完就放下的试验项目，也不会因为使用者暂时不多就被随意搁置。': (
    en: 'Cardock is the first app I have completed as a finished product. It is not an experiment to be abandoned once built, nor will it be casually set aside just because its audience may be small for now.',
    ja: 'Cardockは、私が初めて正式な形まで完成させたアプリです。作って終わりの実験ではなく、利用者がまだ多くないという理由で簡単に放置することもありません。',
  ),
  '无论最终有多少人使用，我都会继续认真维护它，修复发现的问题，跟进必要的系统适配，并在不破坏本地、简洁和可靠这些原则的前提下，把它一点点做好。': (
    en: 'However many people ultimately use it, I will continue to maintain Cardock carefully, fix the issues I find, keep up with necessary system changes, and improve it step by step without compromising its on-device, simple, and dependable principles.',
    ja: '最終的な利用者数にかかわらず、見つかった問題を修正し、必要なOS対応を続けながら、端末内・シンプル・信頼できるという原則を損なわない範囲で、少しずつ丁寧に育てていきます。',
  ),
  '我会坚持的三件事': (en: 'Three commitments I will keep', ja: 'これからも守る三つのこと'),
  '认真维护': (en: 'Maintain it with care', ja: '丁寧に保守する'),
  '不会因为用户暂时不多，就停止修复已知问题和必要的系统适配。': (
    en: 'A smaller audience will not stop me from fixing known issues or completing necessary system compatibility work.',
    ja: '利用者がまだ多くないという理由で、既知の問題修正や必要なOS対応をやめることはありません。',
  ),
  '保持克制': (en: 'Stay focused', ja: '機能を増やしすぎない'),
  '只加入真正有价值的改进，不为了堆积功能让卡坞变得臃肿复杂。': (
    en: 'I will add improvements that provide real value, not pile on features that make Cardock bloated or complicated.',
    ja: '本当に価値のある改善だけを加え、機能を積み重ねるためにCardockを重く複雑にはしません。',
  ),
  '尊重购买': (en: 'Respect your purchase', ja: '購入を尊重する'),
  '9.9 元一次买断，不设置订阅、自动续费、广告或基于用户数据的商业追踪。': (
    en: 'A CN¥9.9 one-time purchase, with no subscriptions, automatic renewals, ads, or commercial tracking based on your data.',
    ja: 'CN¥9.9の買い切りで、サブスクリプション、自動更新、広告、ユーザーデータに基づく商用トラッキングは設けません。',
  ),
  '一次购买，就是最直接的支持': (
    en: 'A one-time purchase is the most direct support',
    ja: '一度の購入が、最も直接的な支えになります',
  ),
  '卡坞采用 9.9 元一次买断。完成购买之后，不需要再额外付费。': (
    en: 'Cardock is a CN¥9.9 one-time purchase. Once purchased, no additional payment is required.',
    ja: 'CardockはCN¥9.9の買い切りです。購入後に追加料金は必要ありません。',
  ),
  '对卡坞最有帮助的，是告诉我哪里不好用、提出真实的改进建议，或者把它推荐给同样重视本地与隐私的人。': (
    en: 'The most helpful things you can do are tell me what is difficult to use, share genuine improvement ideas, or recommend Cardock to someone who also values on-device tools and privacy.',
    ja: 'Cardockにとって最も助けになるのは、使いにくい点や率直な改善案を伝えていただくこと、または端末内保存とプライバシーを大切にする方へ紹介していただくことです。',
  ),
  '是否反馈或分享，都不会影响你获得的功能，也不会影响卡坞的后续维护。': (
    en: 'Whether or not you send feedback or share Cardock will not affect the features you receive or Cardock’s continued maintenance.',
    ja: 'フィードバックや紹介をするかどうかで、利用できる機能やCardockの今後の保守が変わることはありません。',
  ),
  '联系与反馈': (en: 'Contact and feedback', ja: 'お問い合わせとフィードバック'),
  '遇到问题或有改进建议，可以通过微信联系开发者。': (
    en: 'If you encounter a problem or have an improvement idea, you can contact the developer on WeChat.',
    ja: '問題が発生した場合や改善案がある場合は、WeChatで開発者に連絡できます。',
  ),
  '微信号': (en: 'WeChat ID', ja: 'WeChat ID'),
  '用于问题反馈、故障说明和改进建议。添加时请备注“卡坞反馈”。': (
    en: 'For problem reports, troubleshooting details, and improvement suggestions. When adding the contact, include “Cardock feedback” in your note.',
    ja: '問題報告、不具合の説明、改善提案にご利用ください。追加時のメモには「Cardock feedback」と記載してください。',
  ),
  '反馈时请勿发送主密码、备份密码、密码恢复答案、完整账号密码，或包含敏感信息的截图。开发者不会通过微信向你索取这些信息。': (
    en: 'Do not send your master password, backup password, password-recovery answers, complete account credentials, or screenshots containing sensitive information. The developer will never ask for this information over WeChat.',
    ja: 'マスターパスワード、バックアップ用パスワード、パスワード復旧の回答、完全なアカウント認証情報、機密情報を含むスクリーンショットは送らないでください。開発者がWeChatでこれらの情報を求めることはありません。',
  ),
  '复制微信号': (en: 'Copy WeChat ID', ja: 'WeChat IDをコピー'),
  '微信号已复制': (en: 'WeChat ID copied', ja: 'WeChat IDをコピーしました'),
  '复制失败，请稍后重试': (
    en: 'Could not copy. Please try again later.',
    ja: 'コピーできませんでした。しばらくしてからもう一度お試しください。',
  ),
  '隐私与安全说明': (en: 'Privacy and security information', ja: 'プライバシーとセキュリティ'),
  '复制推荐文案': (en: 'Copy recommendation', ja: '紹介文をコピー'),
  '卡坞·Cardock：一款本地保存账号与订阅记录的工具，9.9 元一次买断，无广告、无订阅。': (
    en: 'Cardock is an on-device tool for keeping account and subscription records. It is a CN¥9.9 one-time purchase, with no ads or subscription fees.',
    ja: '卡坞·Cardockは、アカウントとサブスクリプションの記録を端末内に保存するツールです。CN¥9.9の買い切りで、広告もサブスクリプション料金もありません。',
  ),
  '推荐文案已复制': (en: 'Recommendation copied', ja: '紹介文をコピーしました'),
  '谢谢你愿意使用卡坞。': (
    en: 'Thank you for using Cardock.',
    ja: 'Cardockを使っていただき、ありがとうございます。',
  ),
  '我会认真把它维护下去。': (
    en: 'I will continue to maintain it with care.',
    ja: 'これからも丁寧に保守していきます。',
  ),
  '—— 卡坞开发者': (en: '— The Cardock developer', ja: '—— Cardock開発者'),
  '推广激活': (en: 'Promotional activation', ja: 'プロモーション認証'),
  '其他激活方式': (en: 'Other activation methods', ja: 'その他の認証方法'),
  '已获得推广激活码': (
    en: 'I have a promotional activation code',
    ja: 'プロモーション認証コードを持っている',
  ),
  '如果你已获得开发者签发的推广激活码，可在此使用本机申请码完成离线激活。': (
    en: 'If you have a promotional activation code issued by the developer, use the device request code here to activate it offline.',
    ja: '開発者が発行したプロモーション認証コードをお持ちの場合は、ここで端末の申請コードを使ってオフライン認証できます。',
  ),
  '已通过购买解锁完整版': (
    en: 'Full Version unlocked with a purchase',
    ja: '購入により完全版をアンロック済み',
  ),
  '已通过推广激活解锁完整版': (
    en: 'Full Version unlocked with promotional activation',
    ja: 'プロモーション認証により完全版をアンロック済み',
  ),
  '本机申请码': (en: 'Device request code', ja: '端末の申請コード'),
  '本机申请码已复制。': (en: 'Device request code copied.', ja: '端末の申請コードをコピーしました。'),
  '暂不可用': (en: 'Unavailable', ja: '利用できません'),
  '准备中…': (en: 'Preparing…', ja: '準備中…'),
  '激活码': (en: 'Activation code', ja: '認証コード'),
  '粘贴开发者签发的激活码': (
    en: 'Paste the activation code issued by the developer',
    ja: '開発者が発行した認証コードを貼り付け',
  ),
  '激活完整版': (en: 'Activate Full Version', ja: '完全版を認証'),

  // Temporary PC entry.
  '电脑临时录入': (en: 'Temporary PC Entry', ja: 'PCから一時入力'),
  '仅真实保险库完整解锁且当前无其他写入时可开启；诱饵库和“仅查看订阅”模式不能开启。': (
    en: 'Available only when the real vault is fully unlocked and no other write is in progress. It cannot be started from the decoy vault or subscription-only mode.',
    ja: '実際の保管庫を完全にアンロックし、ほかの書き込み処理がない場合にのみ開始できます。おとり保管庫や「サブスクリプションのみ表示」モードでは開始できません。',
  ),
  '仅在你自己的手机热点或可信私有无线网络使用。应用不会访问公网、云或中继；不要在公共或陌生 Wi-Fi 开启。\n\n'
      '连接前建议先在电脑打开浏览器无痕/隐私窗口，以减少常规浏览记录和站点数据残留；无痕模式仍不能保证电脑绝对不留痕。\n\n'
      '普通锁屏、返回 Home、切换应用或接听来电时，电脑连接会继续保留；Android 会显示一条不含账号、密码或订阅内容的低敏前台服务通知。\n\n'
      '保险库锁定后，电脑仍可继续填写尚未提交的内容；保存或导入会暂停，需回到卡坞并解锁手机后继续。\n\n'
      '从最近任务划掉卡坞、强制停止、应用进程被系统终止、局域网地址变化或达到超时限制时，连接仍会结束。': (
    en: 'Use this only with your own phone hotspot or a trusted private Wi-Fi network. Cardock does not use the public internet, cloud services, or a relay. Do not enable it on public or unfamiliar Wi-Fi.\n\nBefore connecting, consider opening a private or incognito browser window on the PC to reduce ordinary history and site-data traces. Private browsing cannot guarantee that the PC leaves no trace.\n\nOrdinary screen locking, returning Home, switching apps, or taking a call keeps the PC connection alive. On Android, Cardock shows a low-sensitivity foreground-service notification that contains no account, password, or subscription details.\n\nIf the vault locks, you can keep typing unsubmitted content on the PC; saving or importing pauses until you return to Cardock and unlock the phone.\n\nSwiping Cardock away from Recents, force-stopping it, app process termination, a local-network address change, or a timeout still ends the connection.',
    ja: 'ご自身のスマートフォンのテザリング、または信頼できるプライベートWi-Fiでのみ使用してください。Cardockはインターネット、クラウド、中継サービスを利用しません。公共または不明なWi-Fiでは開始しないでください。\n\n接続前にPCのブラウザでシークレット／プライベートウィンドウを開くと、通常の閲覧履歴やサイトデータの残留を減らせます。ただし、PCに痕跡が一切残らないことを保証するものではありません。\n\n通常の画面ロック、ホーム画面への移動、アプリの切り替え、着信への応答では、PCとの接続は維持されます。Androidでは、アカウント、パスワード、サブスクリプションの内容を含まない機密性の低いフォアグラウンドサービス通知が表示されます。\n\n保管庫がロックされても、PCでは未送信の内容を引き続き入力できます。保存またはインポートは一時停止し、Cardockに戻ってスマートフォンをアンロックすると続行できます。\n\n最近使ったアプリからCardockをスワイプして終了する、強制停止する、アプリのプロセスが終了する、ローカルネットワークのアドレスが変わる、またはタイムアウトすると、接続は終了します。',
  ),
  '仅在你自己的手机热点或可信私有无线网络使用。应用不会访问公网、云或中继；不要在公共或陌生 Wi-Fi 开启。\n\n': (
    en: 'Use this only with your own phone hotspot or a trusted private Wi-Fi network. Cardock does not use the public internet, cloud services, or a relay. Do not enable it on public or unfamiliar Wi-Fi.\n\n',
    ja: 'ご自身のスマートフォンのテザリング、または信頼できるプライベートWi-Fiでのみ使用してください。Cardockはインターネット、クラウド、中継サービスを利用しません。公共または不明なWi-Fiでは開始しないでください。\n\n',
  ),
  '连接前建议先在电脑打开浏览器无痕/隐私窗口，以减少常规浏览记录和站点数据残留；无痕模式仍不能保证电脑绝对不留痕。\n\n': (
    en: 'Before connecting, consider opening a private or incognito browser window on the PC to reduce ordinary history and site-data traces. Private browsing cannot guarantee that the PC leaves no trace.\n\n',
    ja: '接続前にPCのブラウザでシークレット／プライベートウィンドウを開くと、通常の閲覧履歴やサイトデータの残留を減らせます。ただし、PCに痕跡が一切残らないことを保証するものではありません。\n\n',
  ),
  '普通锁屏、返回 Home、切换应用或接听来电时，电脑连接会继续保留；Android 会显示一条不含账号、密码或订阅内容的低敏前台服务通知。\n\n'
      '保险库锁定后，电脑仍可继续填写尚未提交的内容；保存或导入会暂停，需回到卡坞并解锁手机后继续。\n\n'
      '从最近任务划掉卡坞、强制停止、应用进程被系统终止、局域网地址变化或达到超时限制时，连接仍会结束。': (
    en: 'Ordinary screen locking, returning Home, switching apps, or taking a call keeps the PC connection alive. On Android, Cardock shows a low-sensitivity foreground-service notification that contains no account, password, or subscription details.\n\nIf the vault locks, you can keep typing unsubmitted content on the PC; saving or importing pauses until you return to Cardock and unlock the phone.\n\nSwiping Cardock away from Recents, force-stopping it, app process termination, a local-network address change, or a timeout still ends the connection.',
    ja: '通常の画面ロック、ホーム画面への移動、アプリの切り替え、着信への応答では、PCとの接続は維持されます。Androidでは、アカウント、パスワード、サブスクリプションの内容を含まない機密性の低いフォアグラウンドサービス通知が表示されます。\n\n保管庫がロックされても、PCでは未送信の内容を引き続き入力できます。保存またはインポートは一時停止し、Cardockに戻ってスマートフォンをアンロックすると続行できます。\n\n最近使ったアプリからCardockをスワイプして終了する、強制停止する、アプリのプロセスが終了する、ローカルネットワークのアドレスが変わる、またはタイムアウトすると、接続は終了します。',
  ),
  '连接地址': (en: 'Connection address', ja: '接続先アドレス'),
  '没有可用的可信局域网地址': (
    en: 'No trusted local-network address is available',
    ja: '利用できる信頼済みローカルネットワークアドレスがありません',
  ),
  '请先打开手机热点，或让手机与电脑连接同一个无线网络。': (
    en: 'Turn on your phone hotspot, or connect the phone and PC to the same Wi-Fi network.',
    ja: 'スマートフォンのテザリングをオンにするか、スマートフォンとPCを同じWi-Fiへ接続してください。',
  ),
  '重新检测': (en: 'Check again', ja: '再検出'),
  '开启后会自动分配临时端口': (
    en: 'A temporary port is assigned automatically when started',
    ja: '開始時に一時ポートを自動で割り当てます',
  ),
  '读取局域网地址失败：{error}': (
    en: 'Could not read local-network addresses: {error}',
    ja: 'ローカルネットワークアドレスを取得できませんでした：{error}',
  ),
  '网页可见范围': (en: 'Data visible on the web page', ja: 'Webページの表示範囲'),
  '仅本次': (en: 'Current session only', ja: '今回のみ'),
  '历史摘要': (en: 'History summary', ja: '履歴の概要'),
  '历史详情': (en: 'History details', ja: '履歴の詳細'),
  '只显示这次连接新建的记录（推荐）': (
    en: 'Show only records created in this session (recommended)',
    ja: 'この接続で作成した記録のみ表示（推奨）',
  ),
  '显示名称、分类、续费日期等摘要，不显示详情': (
    en: 'Show summaries such as name, category, and renewal date; hide details',
    ja: '名前、カテゴリ、更新日などの概要のみ表示し、詳細は表示しない',
  ),
  '显示历史详情，但旧密码仍默认隐藏': (
    en: 'Show historical details; existing passwords remain hidden by default',
    ja: '履歴の詳細を表示。既存のパスワードは引き続き初期状態で非表示',
  ),
  '允许编辑历史记录': (en: 'Allow editing historical records', ja: '履歴の編集を許可'),
  '仅“历史详情”可开启；删除历史记录仍须手机逐次确认': (
    en: 'Available only with Historical details. Deleting an existing record still requires confirmation on the phone each time.',
    ja: '「履歴の詳細」でのみ有効にできます。履歴の削除は、その都度スマートフォンでの確認が必要です。',
  ),
  '允许申请查看旧密码': (
    en: 'Allow requests to view existing passwords',
    ja: '既存パスワードの表示リクエストを許可',
  ),
  '每次仍须手机确认；网页只显示 30 秒': (
    en: 'Every request still requires phone confirmation; shown on the web page for only 30 seconds',
    ja: '毎回スマートフォンでの確認が必要です。Webページでの表示は30秒間のみです',
  ),
  '自动断开': (en: 'Automatic disconnect', ja: '自動切断'),
  '网页无操作时限': (en: 'Web inactivity timeout', ja: 'Webページの無操作タイムアウト'),
  '可选 1/5/10/30 分钟，默认 5 分钟；另有不可关闭的 30 分钟绝对上限': (
    en: 'Choose 1, 5, 10, or 30 minutes. The default is 5 minutes, with an additional non-disableable 30-minute absolute limit.',
    ja: '1／5／10／30分から選択できます。初期値は5分です。これとは別に、無効化できない30分の絶対上限があります。',
  ),
  '{minutes} 分钟': (en: '{minutes} min', ja: '{minutes}分'),
  '30 分钟（绝对上限仍生效）': (
    en: '30 min (absolute limit still applies)',
    ja: '30分（絶対上限は引き続き有効）',
  ),
  '开启本次临时连接': (en: 'Start this temporary connection', ja: '今回の一時接続を開始'),
  '正在开启…': (en: 'Starting…', ja: '開始しています…'),
  '正在分配地址…': (en: 'Assigning an address…', ja: 'アドレスを割り当てています…'),
  '正在开启临时服务': (en: 'Starting temporary service', ja: '一時サービスを開始中'),
  '等待电脑输入连接码': (
    en: 'Waiting for the connection code on the PC',
    ja: 'PCで接続コードが入力されるのを待っています',
  ),
  '电脑网页已连接': (en: 'PC web page connected', ja: 'PCのWebページが接続されました'),
  '会话已结束': (en: 'Session ended', ja: 'セッションは終了しました'),
  '手机局域网 IP': (en: 'Phone LAN IP', ja: 'スマートフォンのLAN IP'),
  '在电脑浏览器地址栏输入（无需输入 http://）': (
    en: 'Enter this in the PC browser address bar (http:// is not required)',
    ja: 'PCブラウザのアドレスバーに入力（http://は不要）',
  ),
  '一次性连接码': (en: 'One-time connection code', ja: 'ワンタイム接続コード'),
  '直接在网页输入；不使用二维码。连接成功后本码立即失效。': (
    en: 'Enter it directly on the web page. No QR code is used. The code expires as soon as the connection succeeds.',
    ja: 'Webページへ直接入力します。QRコードは使用しません。接続が完了すると、このコードは直ちに無効になります。',
  ),
  '连接码已复制；系统将在 60 秒后尽力清理剪贴板。': (
    en: 'Connection code copied. The system will attempt to clear the clipboard after 60 seconds.',
    ja: '接続コードをコピーしました。60秒後にクリップボードからの消去を試みます。',
  ),
  '连接码复制失败，请手动输入。': (
    en: 'Could not copy the connection code. Enter it manually.',
    ja: '接続コードをコピーできませんでした。手動で入力してください。',
  ),
  '已连接电脑：{client}': (en: 'Connected PC: {client}', ja: '接続中のPC：{client}'),
  '关闭标签页或断网后，手机约 {seconds} 秒内自动识别；需要立即结束请点“主动断开”。': (
    en: 'After the tab is closed or the network disconnects, the phone detects it within about {seconds} seconds. To end immediately, tap Disconnect now.',
    ja: 'タブを閉じるかネットワークが切断されると、スマートフォンが約{seconds}秒以内に検出します。すぐに終了する場合は「今すぐ切断」をタップしてください。',
  ),
  '网页无操作 {idle} 后断开 · 本次会话最长还剩 {absolute}': (
    en: 'Disconnect after {idle} of web inactivity · Up to {absolute} left in this session',
    ja: 'Webページが{idle}間操作されないと切断 · セッションの残り時間は最大{absolute}',
  ),
  '{mode} · {editing} · {passwords}': (
    en: '{mode} · {editing} · {passwords}',
    ja: '{mode} · {editing} · {passwords}',
  ),
  '允许历史编辑': (en: 'History editing allowed', ja: '履歴の編集可'),
  '历史编辑关闭': (en: 'History editing off', ja: '履歴の編集はオフ'),
  '可申请旧密码': (en: 'Existing passwords can be requested', ja: '既存パスワードをリクエスト可'),
  '旧密码关闭': (en: 'Existing passwords hidden', ja: '既存パスワードは非表示'),
  '主动断开': (en: 'Disconnect now', ja: '今すぐ切断'),
  '断开电脑网页？': (en: 'Disconnect the PC web page?', ja: 'PCのWebページを切断しますか？'),
  '断开后网页会立即失效，本次连接保存的记录会立刻按历史记录处理；以后再删除时需要手机确认。': (
    en: 'The web page will stop working immediately. Records saved during this connection become historical records at once, and deleting them later will require confirmation on the phone.',
    ja: 'Webページは直ちに無効になります。この接続中に保存した記録はすぐに履歴として扱われ、後から削除する際はスマートフォンでの確認が必要です。',
  ),
  '继续连接': (en: 'Keep connected', ja: '接続を続ける'),
  '断开': (en: 'Disconnect', ja: '切断'),
  '等待手机确认': (en: 'Waiting for phone confirmation', ja: 'スマートフォンでの確認待ち'),
  '确认删除历史账号': (en: 'Delete historical account?', ja: '履歴のアカウントを削除しますか？'),
  '确认删除历史订阅': (
    en: 'Delete historical subscription?',
    ja: '履歴のサブスクリプションを削除しますか？',
  ),
  '确认临时显示历史密码': (
    en: 'Show historical password temporarily?',
    ja: '履歴のパスワードを一時表示しますか？',
  ),
  '将删除“{name}”。': (en: '“{name}” will be deleted.', ja: '「{name}」を削除します。'),
  '将删除“{name}”及 {count} 条关联订阅。': (
    en: '“{name}” will be deleted. Linked subscriptions to delete: {count}.',
    ja: '「{name}」と関連するサブスクリプション{count}件を削除します。',
  ),
  '网页将显示“{name}”的密码 30 秒。': (
    en: 'The web page will show the password for “{name}” for 30 seconds.',
    ja: 'Webページに「{name}」のパスワードを30秒間表示します。',
  ),
  '确认将在 {duration} 后失效': (
    en: 'This confirmation expires in {duration}',
    ja: 'この確認は{duration}後に期限切れになります',
  ),
  '拒绝': (en: 'Deny', ja: '拒否'),
  '批准本次操作': (en: 'Approve this action', ja: '今回の操作を許可'),
  '上次临时连接已结束': (
    en: 'The last temporary connection has ended',
    ja: '前回の一時接続は終了しました',
  ),
  '临时连接未能继续': (
    en: 'The temporary connection could not continue',
    ja: '一時接続を続行できませんでした',
  ),
  '已由手机或电脑主动断开。': (
    en: 'Disconnected from the phone or PC.',
    ja: 'スマートフォンまたはPCから切断されました。',
  ),
  '网页超过所选无操作时限，已自动断开。': (
    en: 'Disconnected after the selected web inactivity timeout.',
    ja: '設定したWebページの無操作時間を超えたため、自動で切断しました。',
  ),
  '已达到不可关闭的 30 分钟绝对上限。': (
    en: 'The non-disableable 30-minute absolute limit was reached.',
    ja: '無効化できない30分の絶対上限に達しました。',
  ),
  '手机保险库已锁定。': (en: 'The phone vault was locked.', ja: 'スマートフォンの保管庫がロックされました。'),
  '应用进程已退出或被系统终止，连接已结束。': (
    en: 'The connection ended because the app process exited or was terminated by the system.',
    ja: 'アプリのプロセスが終了したか、システムによって停止されたため、接続は終了しました。',
  ),
  '手机保险库状态发生变化，为保护数据已断开。': (
    en: 'Disconnected to protect your data because the phone vault state changed.',
    ja: 'スマートフォンの保管庫状態が変わったため、データ保護のため切断しました。',
  ),
  '局域网地址发生变化，已断开。': (
    en: 'Disconnected because the local-network address changed.',
    ja: 'ローカルネットワークアドレスが変わったため切断しました。',
  ),
  '电脑网页心跳已失联，页面记录已立即转为历史记录。': (
    en: 'The PC web page stopped responding. Its records were immediately converted to historical records.',
    ja: 'PCのWebページからの応答が途絶えました。ページ上の記録は直ちに履歴へ移行しました。',
  ),
  '连接码验证失败，本次服务已失效。': (
    en: 'Connection-code verification failed. This temporary service is no longer valid.',
    ja: '接続コードを確認できませんでした。この一時サービスは無効になりました。',
  ),
  '局域网服务发生异常。': (
    en: 'The local-network service encountered an error.',
    ja: 'ローカルネットワークサービスでエラーが発生しました。',
  ),
  '当前保险库状态不允许开启电脑临时录入。': (
    en: 'Temporary PC Entry cannot start in the current vault state.',
    ja: '現在の保管庫の状態では「PCから一時入力」を開始できません。',
  ),
  '网页空闲时限必须为 1、5、10 或 30 分钟。': (
    en: 'The web page inactivity limit must be 1, 5, 10, or 30 minutes.',
    ja: 'Webページの無操作時間は1、5、10、30分のいずれかに設定してください。',
  ),
  '所选局域网地址已不可用，请重新选择。': (
    en: 'The selected local-network address is no longer available. Choose another address.',
    ja: '選択したローカルネットワークアドレスは利用できなくなりました。別のアドレスを選択してください。',
  ),
  '局域网临时服务启动失败：{error}': (
    en: 'Could not start the temporary local-network service: {error}',
    ja: 'ローカルネットワークの一時サービスを開始できませんでした：{error}',
  ),
  '连接码验证失败或配对请求已失效。请重新开启本次临时连接。': (
    en: 'Connection-code verification failed or the pairing request expired. Start a new temporary connection.',
    ja: '接続コードの確認に失敗したか、ペアリング要求の有効期限が切れました。新しい一時接続を開始してください。',
  ),
  '网页连接异常：{error}': (
    en: 'Web connection error: {error}',
    ja: 'Web接続エラー：{error}',
  ),
  '应用已关闭临时服务。': (
    en: 'Cardock closed the temporary service.',
    ja: 'Cardockが一時サービスを終了しました。',
  ),

  // Notification reliability.
  '通知可靠性': (en: 'Notification reliability', ja: '通知の信頼性'),
  '本机状态检查': (en: 'On-device status check', ja: '端末の状態確認'),
  '只读取系统通知与电池状态，不读取账号、密码、金额或具体订阅内容。': (
    en: 'Reads only system notification and battery status. It does not read accounts, passwords, amounts, or subscription details.',
    ja: 'システムの通知状態とバッテリー状態のみを確認します。アカウント、パスワード、金額、具体的なサブスクリプション内容は読み取りません。',
  ),
  '刷新状态': (en: 'Refresh status', ja: '状態を更新'),
  '应用总通知权限': (en: 'App notification permission', ja: 'アプリ全体の通知権限'),
  '系统允许本应用发送通知': (
    en: 'The system allows Cardock to send notifications',
    ja: 'システムでCardockの通知が許可されています',
  ),
  '系统已阻止本应用的所有通知': (
    en: 'The system blocks all Cardock notifications',
    ja: 'システムでCardockのすべての通知がブロックされています',
  ),
  '“本机订阅提醒”通道': (
    en: '“On-device subscription reminders” channel',
    ja: '「端末内サブスクリプション通知」チャンネル',
  ),
  '通知通道已开启': (en: 'Notification channel is on', ja: '通知チャンネルはオンです'),
  '通知通道已开启，但当前为静默或最低优先级；提醒可能没有声音或不显示在状态栏。': (
    en: 'The channel is on, but its priority is silent or minimal. Reminders may make no sound or stay out of the status bar.',
    ja: 'チャンネルはオンですが、サイレントまたは最低の優先度です。音が鳴らない、またはステータスバーに表示されない可能性があります。',
  ),
  '通知通道已开启，但声音和振动都已关闭。': (
    en: 'The channel is on, but both sound and vibration are off.',
    ja: 'チャンネルはオンですが、音とバイブレーションの両方がオフです。',
  ),
  '通知通道已被关闭': (en: 'Notification channel is off', ja: '通知チャンネルはオフです'),
  '通道尚未创建或系统无法读取': (
    en: 'The channel has not been created or cannot be read by the system',
    ja: 'チャンネルが未作成、またはシステムから状態を取得できません',
  ),
  '打开通知设置': (en: 'Open notification settings', ja: '通知設定を開く'),
  '打开通道设置': (en: 'Open channel settings', ja: 'チャンネル設定を開く'),
  '电池优化': (en: 'Battery optimization', ja: 'バッテリー最適化'),
  '本应用当前不受系统电池优化限制': (
    en: 'Cardock is currently exempt from system battery optimization',
    ja: 'Cardockは現在、システムのバッテリー最適化の対象外です',
  ),
  '系统电池优化可能延迟后台提醒': (
    en: 'System battery optimization may delay background reminders',
    ja: 'システムのバッテリー最適化により、バックグラウンド通知が遅れる可能性があります',
  ),
  '打开电池优化': (en: 'Open battery optimization', ja: 'バッテリー最適化を開く'),
  '精确提醒权限': (en: 'Exact reminder permission', ja: '正確なアラームの権限'),
  '已使用可在休眠状态准时触发的精确闹钟': (
    en: 'Using exact alarms that can fire on time while the device is idle',
    ja: '端末の休止中でも予定時刻に動作できる正確なアラームを使用しています',
  ),
  '未允许时会安全降级，但 Android 可能延迟约1小时或更久': (
    en: 'Safely falls back when not allowed, but Android may delay reminders by about an hour or longer',
    ja: '許可されていない場合は安全な代替方式を使いますが、Androidにより約1時間以上遅れることがあります',
  ),
  '允许精确提醒': (en: 'Allow exact reminders', ja: '正確なアラームを許可'),
  '设备与厂商后台策略': (
    en: 'Device and manufacturer background policies',
    ja: '端末とメーカーのバックグラウンド設定',
  ),
  '打开厂商后台设置': (
    en: 'Open manufacturer background settings',
    ja: 'メーカーのバックグラウンド設定を開く',
  ),
  '{vendor}: {instructions}': (
    en: '{vendor}: {instructions}',
    ja: '{vendor}：{instructions}',
  ),
  '华为': (en: 'Huawei', ja: 'Huawei'),
  '荣耀': (en: 'HONOR', ja: 'HONOR'),
  '小米 / Redmi': (en: 'Xiaomi / Redmi', ja: 'Xiaomi / Redmi'),
  '小米 / Redmi / POCO': (
    en: 'Xiaomi / Redmi / POCO',
    ja: 'Xiaomi / Redmi / POCO',
  ),
  'OPPO / OnePlus / realme': (
    en: 'OPPO / OnePlus / realme',
    ja: 'OPPO / OnePlus / realme',
  ),
  'vivo / iQOO': (en: 'vivo / iQOO', ja: 'vivo / iQOO'),
  '三星': (en: 'Samsung', ja: 'Samsung'),
  'Google / Pixel': (en: 'Google / Pixel', ja: 'Google / Pixel'),
  'Motorola / Lenovo': (en: 'Motorola / Lenovo', ja: 'Motorola / Lenovo'),
  'ASUS / ROG': (en: 'ASUS / ROG', ja: 'ASUS / ROG'),
  '中兴 / nubia': (en: 'ZTE / nubia', ja: 'ZTE / nubia'),
  '魅族': (en: 'Meizu', ja: 'Meizu'),
  'Nothing': (en: 'Nothing', ja: 'Nothing'),
  'TECNO / Infinix / itel': (
    en: 'TECNO / Infinix / itel',
    ja: 'TECNO / Infinix / itel',
  ),
  'Sony': (en: 'Sony', ja: 'Sony'),
  'Nokia / HMD': (en: 'Nokia / HMD', ja: 'Nokia / HMD'),
  '通用 Android': (en: 'General Android', ja: '一般的なAndroid'),
  '设置 > 应用和服务 > 应用启动管理 > 卡坞 · Cardock。': (
    en: 'Settings > Apps & services > App launch > Cardock.',
    ja: '設定 > アプリとサービス > アプリ起動管理 > Cardock。',
  ),
  '关闭“自动管理”，再允许自启动、关联启动和后台活动。': (
    en: 'Turn off Manage automatically, then allow auto-launch, secondary launch, and background activity.',
    ja: '「自動管理」をオフにし、自動起動、連携起動、バックグラウンド動作を許可します。',
  ),
  '在电池设置中确认本应用未被高耗电优化限制。': (
    en: 'In Battery settings, confirm that Cardock is not restricted by high-power-use optimization.',
    ja: 'バッテリー設定で、Cardockが高消費電力の最適化による制限を受けていないことを確認します。',
  ),
  '设置 > 应用 > 应用启动管理 > 卡坞 · Cardock。': (
    en: 'Settings > Apps > App launch > Cardock.',
    ja: '設定 > アプリ > アプリ起動管理 > Cardock。',
  ),
  '关闭自动管理，允许自启动、关联启动和后台运行。': (
    en: 'Turn off automatic management and allow auto-launch, secondary launch, and background operation.',
    ja: '自動管理をオフにし、自動起動、連携起動、バックグラウンド実行を許可します。',
  ),
  '设置 > 应用设置 > 应用管理 > 卡坞 · Cardock > 自启动。': (
    en: 'Settings > App settings > Manage apps > Cardock > Autostart.',
    ja: '設定 > アプリ設定 > アプリ管理 > Cardock > 自動起動。',
  ),
  '电量和性能 > 应用智能省电，将本应用设为无限制。': (
    en: 'Battery & performance > App battery saver, then set Cardock to No restrictions.',
    ja: 'バッテリーとパフォーマンス > アプリの省電力で、Cardockを「制限なし」に設定します。',
  ),
  '设置 > 应用 > 自启动，允许卡坞 · Cardock 自启动。': (
    en: 'Settings > Apps > Autostart, then allow Cardock to start automatically.',
    ja: '設定 > アプリ > 自動起動で、Cardockの自動起動を許可します。',
  ),
  '电池 > 应用耗电管理，允许后台活动。': (
    en: 'Battery > App battery usage, then allow background activity.',
    ja: 'バッテリー > アプリの電力使用管理で、バックグラウンド動作を許可します。',
  ),
  '设置 > 应用与权限 > 权限管理 > 自启动，允许本应用。': (
    en: 'Settings > Apps & permissions > Permission management > Autostart, then allow Cardock.',
    ja: '設定 > アプリと権限 > 権限管理 > 自動起動で、Cardockを許可します。',
  ),
  '电池 > 后台耗电管理，允许后台高耗电。': (
    en: 'Battery > Background power usage, then allow high background power usage.',
    ja: 'バッテリー > バックグラウンド電力管理で、バックグラウンドの高消費電力を許可します。',
  ),
  '设置 > 电池和设备维护 > 电池 > 后台使用限制。': (
    en: 'Settings > Battery and device care > Battery > Background usage limits.',
    ja: '設定 > バッテリーとデバイスケア > バッテリー > バックグラウンドでの使用を制限。',
  ),
  '确认本应用不在深度休眠应用列表中。': (
    en: 'Confirm that Cardock is not in the Deep sleeping apps list.',
    ja: 'Cardockが「ディープスリープ中のアプリ」の一覧に含まれていないことを確認します。',
  ),
  '确认本应用不在休眠或深度休眠列表，并加入“永不休眠的应用”（若系统提供）。': (
    en: 'Confirm that Cardock is not in Sleeping or Deep sleeping apps, and add it to Never sleeping apps if that option is available.',
    ja: 'Cardockが「スリープ中のアプリ」または「ディープスリープ中のアプリ」に含まれていないことを確認し、利用できる場合は「スリープ状態にしないアプリ」に追加します。',
  ),
  '在应用详情中允许通知和后台活动。': (
    en: 'Allow notifications and background activity in App info.',
    ja: 'アプリ情報で通知とバックグラウンド動作を許可します。',
  ),
  '在电池优化中将卡坞 · Cardock 设为不受限制或允许后台运行。': (
    en: 'In Battery optimization, set Cardock to Unrestricted or allow background operation.',
    ja: 'バッテリー最適化でCardockを「制限なし」にするか、バックグラウンド実行を許可します。',
  ),
  '系统版本和地区会改变菜单名称；若专用入口打不开，请在应用详情中逐项检查通知、电池和后台权限。': (
    en: 'Menu names vary by system version and region. If a dedicated page does not open, check notifications, battery, and background permissions one by one in App info.',
    ja: 'メニュー名はシステムのバージョンや地域によって変わります。専用画面を開けない場合は、アプリ情報で通知、バッテリー、バックグラウンド権限を順に確認してください。',
  ),
  '固定在最近任务': (en: 'Pin in Recents', ja: '最近使ったアプリに固定'),
  '建议操作': (en: 'Recommended action', ja: '推奨操作'),
  '打开最近任务，找到“卡坞 · Cardock”任务卡，将卡片设为锁定/固定（通常是向下滑动任务卡或点击锁形图标，以当前系统界面为准）。': (
    en: 'Open Recents, find the Cardock task card, and lock or pin it. This usually means swiping down on the card or tapping a lock icon; follow the options shown by your device.',
    ja: '最近使ったアプリを開き、Cardockのカードをロックまたは固定します。通常はカードを下へスワイプするか鍵アイコンをタップしますが、端末に表示される操作に従ってください。',
  ),
  '打开最近任务，找到“卡坞 · Cardock”任务卡；如果系统提供锁定或固定功能，请为本应用启用。': (
    en: 'Open Recents and find the Cardock task card. If your device offers a lock or pin option, enable it for Cardock.',
    ja: '最近使ったアプリを開き、Cardockのカードを探します。端末にロックまたは固定機能がある場合は、Cardockに対して有効にしてください。',
  ),
  '固定只能减少误划和“一键清理”造成的退出；Android 不允许应用读取或代替用户设置此状态。若任务卡仍被划掉并导致系统停止，请重新打开并解锁，以恢复正式提醒。': (
    en: 'Pinning only reduces closures caused by accidental swipes or one-tap cleanup. Android does not let an app read or set this state for you. If the task card is still dismissed and the system stops Cardock, reopen and unlock it to restore scheduled reminders.',
    ja: '固定は、誤ったスワイプや一括クリーンアップによる終了を減らすだけです。Androidでは、アプリがこの状態を読み取ったり代わりに設定したりできません。カードを消した結果システムがCardockを停止した場合は、もう一度開いてロックを解除し、予定済みのリマインダーを再登録してください。',
  ),
  '打开最近任务，找到“卡坞 · Cardock”任务卡，将卡片设为锁定/固定（通常是向下滑动任务卡或点击锁形图标，以当前系统界面为准）。\n固定只能减少误划和“一键清理”造成的退出；Android 不允许应用读取或代替用户设置此状态。若任务卡仍被划掉并导致系统停止，请重新打开并解锁，以恢复正式提醒。': (
    en: 'Open Recents, find the Cardock task card, and lock or pin it. This usually means swiping down on the card or tapping a lock icon; follow the options shown by your device.\nPinning only reduces closures caused by accidental swipes or one-tap cleanup. Android does not let an app read or set this state for you. If the task card is still dismissed and the system stops Cardock, reopen and unlock it to restore scheduled reminders.',
    ja: '最近使ったアプリを開き、Cardockのカードをロックまたは固定します。通常はカードを下へスワイプするか鍵アイコンをタップしますが、端末に表示される操作に従ってください。\n固定は、誤ったスワイプや一括クリーンアップによる終了を減らすだけです。Androidでは、アプリがこの状態を読み取ったり代わりに設定したりできません。カードを消した結果システムがCardockを停止した場合は、もう一度開いてロックを解除し、予定済みのリマインダーを再登録してください。',
  ),
  '打开最近任务，找到“卡坞 · Cardock”任务卡；如果系统提供锁定或固定功能，请为本应用启用。\n固定只能减少误划和“一键清理”造成的退出；Android 不允许应用读取或代替用户设置此状态。若任务卡仍被划掉并导致系统停止，请重新打开并解锁，以恢复正式提醒。': (
    en: 'Open Recents and find the Cardock task card. If your device offers a lock or pin option, enable it for Cardock.\nPinning only reduces closures caused by accidental swipes or one-tap cleanup. Android does not let an app read or set this state for you. If the task card is still dismissed and the system stops Cardock, reopen and unlock it to restore scheduled reminders.',
    ja: '最近使ったアプリを開き、Cardockのカードを探します。端末にロックまたは固定機能がある場合は、Cardockに対して有効にしてください。\n固定は、誤ったスワイプや一括クリーンアップによる終了を減らすだけです。Androidでは、アプリがこの状態を読み取ったり代わりに設定したりできません。カードを消した結果システムがCardockを停止した場合は、もう一度開いてロックを解除し、予定済みのリマインダーを再登録してください。',
  ),
  '当前待发定时提醒': (en: 'Pending scheduled reminders', ja: '送信待ちのリマインダー'),
  '无法读取本应用待发队列': (
    en: 'Could not read Cardock’s pending queue',
    ja: 'Cardockの送信待ちキューを取得できません',
  ),
  '{count} 条（只统计本应用管理的通用提醒）': (
    en: '{count} (only generic reminders managed by Cardock)',
    ja: '{count}件（Cardockが管理する一般的なリマインダーのみ）',
  ),
  '提醒协调状态': (en: 'Reminder reconciliation status', ja: 'リマインダー同期状態'),
  '系统提醒已与当前保险库数据同步': (
    en: 'System reminders are synchronized with the current vault data',
    ja: 'システムのリマインダーは現在の保管庫データと同期されています',
  ),
  '业务数据已保存，系统提醒仍待同步；应用或设备重启后，真实保险库下次解锁时会自动重试。': (
    en: 'Your data is saved, but system reminders are still pending. After an app or device restart, Cardock retries when the primary vault is next unlocked.',
    ja: 'データは保存済みですが、システムのリマインダーはまだ同期されていません。アプリまたは端末の再起動後も、実保管庫を次にロック解除したときに自動で再試行します。',
  ),
  '已重试 {count} 次，系统提醒仍待同步；应用或设备重启后，真实保险库下次解锁时会继续重试。': (
    en: 'Synchronization has failed {count} time(s) and remains pending. After an app or device restart, Cardock retries when the primary vault is next unlocked.',
    ja: '{count}回再試行しましたが、システムのリマインダーはまだ同期されていません。アプリまたは端末の再起動後も、実保管庫を次にロック解除したときに再試行します。',
  ),
  '无法读取保险库内的提醒协调状态': (
    en: 'Could not read the reminder reconciliation state in the vault',
    ja: '保管庫内のリマインダー同期状態を読み取れません',
  ),
  '重新同步提醒': (en: 'Synchronize reminders again', ja: 'リマインダーを再同期'),
  '系统提醒已完成同步。': (
    en: 'System reminders are synchronized.',
    ja: 'システムのリマインダーを同期しました。',
  ),
  '系统提醒仍未完成同步，待协调状态已保留。': (
    en: 'System reminders are still not synchronized. The pending state has been retained.',
    ja: 'システムのリマインダーはまだ同期されていません。保留中の状態は保持されています。',
  ),
  '最近开机 / 升级恢复': (en: 'Latest restart / update recovery', ja: '直近の再起動／更新後の復旧'),
  '暂无开机或覆盖升级后的恢复记录': (
    en: 'No recovery record after a restart or app update',
    ja: '再起動またはアプリ更新後の復旧記録はありません',
  ),
  '设备开机': (en: 'Device restarted', ja: '端末の起動'),
  '应用覆盖升级': (en: 'App updated', ja: 'アプリの更新'),
  '系统时区变更': (en: 'System time zone changed', ja: 'システムのタイムゾーン変更'),
  '系统时间变更': (en: 'System clock changed', ja: 'システム時刻の変更'),
  '精确提醒权限已授予': (en: 'Exact reminder permission granted', ja: '正確なアラームの権限を許可'),
  '系统恢复信号': (en: 'System recovery signal', ja: 'システム復旧シグナル'),
  '已重新提交调度': (en: 'Schedule resubmitted', ja: 'スケジュールを再登録済み'),
  '重新提交失败': (en: 'Resubmission failed', ja: '再登録に失敗'),
  '结果未知': (en: 'Result unknown', ja: '結果不明'),
  '{time} · {trigger} · {result}': (
    en: '{time} · {trigger} · {result}',
    ja: '{time} · {trigger} · {result}',
  ),
  '发送即时测试通知': (en: 'Send an immediate test notification', ja: 'テスト通知を今すぐ送信'),
  '安排约1分钟测试提醒': (
    en: 'Schedule a test reminder in about 1 minute',
    ja: '約1分後のテスト通知を予約',
  ),
  '已发送即时测试通知。': (en: 'Immediate test notification sent.', ja: 'テスト通知を送信しました。'),
  '即时测试通知发送失败。': (
    en: 'Could not send the immediate test notification.',
    ja: 'テスト通知を送信できませんでした。',
  ),
  '已安排约1分钟后的测试提醒。': (
    en: 'Test reminder scheduled for about 1 minute from now.',
    ja: '約1分後のテスト通知を予約しました。',
  ),
  '1分钟测试提醒安排失败。': (
    en: 'Could not schedule the 1-minute test reminder.',
    ja: '1分後のテスト通知を予約できませんでした。',
  ),
  '当前状态无法执行通知测试。': (
    en: 'Notification testing is unavailable in the current state.',
    ja: '現在の状態では通知をテストできません。',
  ),
  '测试通知和定时提醒已安排。': (
    en: 'The test notification and scheduled reminder are ready.',
    ja: 'テスト通知と予約通知を設定しました。',
  ),
  '说明：精确闹钟可改善锁屏与 Doze 下的及时性，但系统强制停止（部分华为机型可能在划掉应用时触发）会取消或暂停提醒，应用无法绕过。请同时允许自启动、关联启动和后台活动。恢复“已重调度”只表示提醒已重新提交给 Android，不代表最终送达。': (
    en: 'Exact alarms can improve timeliness while the screen is locked or the device is in Doze. However, a system force-stop—which may be triggered by dismissing the app on some Huawei devices—can cancel or pause reminders, and Cardock cannot bypass it. Also allow auto-launch, secondary launch, and background activity. A recovery result of “Schedule resubmitted” only means the reminder was submitted to Android again; it does not guarantee delivery.',
    ja: '正確なアラームは、画面ロック中やDoze中の通知時刻を改善できます。ただし、システムによる強制停止（一部のHuawei端末ではアプリを履歴から消すと発生する場合があります）により、通知が取り消しまたは一時停止されることがあり、Cardockはこれを回避できません。自動起動、連携起動、バックグラウンド動作も許可してください。復旧結果の「スケジュールを再登録済み」はAndroidへ再登録したことだけを示し、最終的な配信を保証するものではありません。',
  ),
  '说明：精确闹钟可改善锁屏与 Doze 下的及时性，但系统“强行停止”会使应用进入停止状态，并可能取消或暂停提醒；应用无法绕过，必须由用户重新打开并解锁。部分厂商的划卡或一键清理也可能触发等效限制。请同时允许自启动、关联启动和后台活动。恢复记录只表示恢复入口已运行并通过当前可见检查，不代表最终送达。': (
    en: 'Exact alarms can improve timeliness on the lock screen and in Doze, but a system Force stop puts Cardock in a stopped state and may cancel or pause reminders. Cardock cannot bypass this; the user must reopen and unlock it. On some devices, dismissing the task card or one-tap cleanup may impose an equivalent restriction. Also allow auto-launch, secondary launch, and background activity. A recovery record only shows that the recovery entry point ran and passed currently visible checks; it does not prove final delivery.',
    ja: '正確なアラームは画面ロック中やDoze中の通知時刻を改善できますが、システムの「強制停止」はCardockを停止状態にし、通知を取り消しまたは一時停止する可能性があります。Cardockはこれを回避できないため、ユーザーが再度開いてロックを解除する必要があります。一部の端末では、履歴からのスワイプ削除や一括クリーンアップが同等の制限を起こす場合があります。自動起動、連携起動、バックグラウンド動作も許可してください。復旧記録は、復旧処理が実行され、現在確認できる検査を通過したことだけを示し、最終的な配信を保証しません。',
  ),
  '正常': (en: 'Normal', ja: '正常'),
  '需处理': (en: 'Action needed', ja: '要対応'),
  '信息': (en: 'Info', ja: '情報'),
  '系统设置入口不可用，请手动打开本应用详情。': (
    en: 'Could not open the system settings page. Open Cardock’s App info manually.',
    ja: 'システム設定を開けませんでした。Cardockのアプリ情報を手動で開いてください。',
  ),

  // Custom theme editor.
  '自定义主题': (en: 'Custom theme', ja: 'カスタムテーマ'),
  '快速定制（默认）': (en: 'Quick customization (default)', ja: 'クイックカスタマイズ（標準）'),
  '进阶模块编辑': (en: 'Advanced module editing', ja: '詳細なモジュール編集'),
  '四项控件会同时生成浅色与深色 Token。超出可读范围时自动夹取，且可撤销一次。': (
    en: 'These four controls generate both light and dark tokens. Values are automatically clamped to a readable range, and the last change can be undone.',
    ja: '4つのコントロールからライト／ダーク両方のトークンを生成します。可読範囲を超える値は自動調整され、直前の変更を1回取り消せます。',
  ),
  '四项控件会同时生成浅色与深色 Token。': (
    en: 'These four controls generate both light and dark tokens.',
    ja: '4つのコントロールからライト／ダーク両方のトークンを生成します。',
  ),
  '超出可读范围时自动夹取，且可撤销一次。': (
    en: 'Values are automatically clamped to a readable range, and the last change can be undone.',
    ja: '可読範囲を超える値は自動調整され、直前の変更を1回取り消せます。',
  ),
  '撤销上一次调整': (en: 'Undo last adjustment', ja: '直前の調整を取り消す'),
  '已撤销上一次配色调整。': (
    en: 'The last color adjustment was undone.',
    ja: '直前の配色調整を取り消しました。',
  ),
  '恢复自定义默认值': (en: 'Restore custom defaults', ja: 'カスタム設定を初期値に戻す'),
  '恢复自定义默认值？': (en: 'Restore custom defaults?', ja: 'カスタム設定を初期値に戻しますか？'),
  '只重置自定义主题的浅色、深色和跟随主题时的桌面图标回退；八套固定主题不受影响。保存后才会生效。': (
    en: 'Only the custom theme’s light and dark colors and its fallback launcher icon are reset. The eight preset themes are not affected. Changes take effect after you save.',
    ja: 'カスタムテーマのライト／ダーク配色と、テーマ連動時のランチャーアイコンのフォールバックだけを初期化します。8種類のプリセットテーマには影響しません。保存後に反映されます。',
  ),
  '只重置自定义主题的浅色、深色和跟随主题时的桌面图标回退；': (
    en: 'Only the custom theme’s light and dark colors and its fallback launcher icon are reset. ',
    ja: 'カスタムテーマのライト／ダーク配色と、テーマ連動時のランチャーアイコンのフォールバックだけを初期化します。',
  ),
  '八套固定主题不受影响。保存后才会生效。': (
    en: 'The eight preset themes are not affected. Changes take effect after you save.',
    ja: '8種類のプリセットテーマには影響しません。保存後に反映されます。',
  ),
  '恢复': (en: 'Restore', ja: '復元'),
  '浅色': (en: 'Light', ja: 'ライト'),
  '深色': (en: 'Dark', ja: 'ダーク'),
  '由浅色生成深色': (en: 'Generate dark colors from light', ja: 'ライト配色からダーク配色を生成'),
  '已按浅色配色生成深色起点，可继续逐项调整。': (
    en: 'A dark starting palette was generated from the light colors. You can continue fine-tuning each color.',
    ja: 'ライト配色からダーク配色の初期案を生成しました。各色を引き続き調整できます。',
  ),
  '已生成安全的深色起点；原浅色组合无法完整保留对比度。': (
    en: 'A safe dark starting palette was generated because the light palette could not preserve every contrast requirement.',
    ja: 'ライト配色のままではすべてのコントラスト要件を保てないため、安全なダーク配色の初期案を生成しました。',
  ),
  '已重置{mode}·{group}。': (
    en: 'Reset {mode} · {group}.',
    ja: '{mode}・{group}をリセットしました。',
  ),
  '品牌与导航': (en: 'Brand and navigation', ja: 'ブランドとナビゲーション'),
  '首页总览': (en: 'Home overview', ja: 'ホーム概要'),
  '账号模块': (en: 'Accounts module', ja: 'アカウントモジュール'),
  '订阅模块': (en: 'Subscriptions module', ja: 'サブスクリプションモジュール'),
  '表单与操作': (en: 'Forms and actions', ja: 'フォームと操作'),
  '状态颜色': (en: 'Status colors', ja: '状態カラー'),
  '状态颜色（高级）': (en: 'Status colors (advanced)', ja: '状態カラー（詳細）'),
  '重置本组': (en: 'Reset group', ja: 'このグループをリセット'),
  '解锁高级颜色': (en: 'Unlock advanced colors', ja: '詳細カラーのロックを解除'),
  '重新锁定': (en: 'Lock again', ja: '再びロック'),
  '默认锁定，状态同时保留图标与文字': (
    en: 'Locked by default; statuses still use both icons and text',
    ja: '初期状態ではロックされています。状態はアイコンと文字の両方で示されます',
  ),
  '已解锁；颜色仍须通过语义和对比度校验': (
    en: 'Unlocked; colors must still pass semantic and contrast checks',
    ja: 'ロック解除済み。色は引き続き用途とコントラストの検証に合格する必要があります',
  ),
  '七组 Token · 状态色默认锁定': (
    en: 'Seven token groups · Status colors locked by default',
    ja: '7つのトークングループ · 状態カラーは初期状態でロック',
  ),
  '基础界面': (en: 'Foundations', ja: '基本画面'),
  '页面背景': (en: 'Page background', ja: 'ページ背景'),
  '卡片表面': (en: 'Card surface', ja: 'カード表面'),
  '次级表面': (en: 'Secondary surface', ja: 'セカンダリサーフェス'),
  '主要文字': (en: 'Primary text', ja: 'メインテキスト'),
  '次要文字': (en: 'Secondary text', ja: 'サブテキスト'),
  '边框': (en: 'Borders', ja: '枠線'),
  '品牌主色': (en: 'Primary brand color', ja: 'ブランドのメインカラー'),
  '品牌辅助色': (en: 'Secondary brand color', ja: 'ブランドのサブカラー'),
  '底部导航选中色': (en: 'Selected bottom-navigation color', ja: '下部ナビゲーションの選択色'),
  '焦点色': (en: 'Focus color', ja: 'フォーカスカラー'),
  '总览起始色': (en: 'Overview gradient start', ja: '概要グラデーション開始色'),
  '总览结束色': (en: 'Overview gradient end', ja: '概要グラデーション終了色'),
  '账号强调色': (en: 'Account accent', ja: 'アカウントのアクセントカラー'),
  '账号图标底色': (en: 'Account icon background', ja: 'アカウントアイコンの背景色'),
  '订阅强调色': (en: 'Subscription accent', ja: 'サブスクリプションのアクセントカラー'),
  '订阅图标底色': (en: 'Subscription icon background', ja: 'サブスクリプションアイコンの背景色'),
  '登录名字段色': (en: 'Sign-in ID field color', ja: 'ログインIDフィールドの色'),
  '密码字段色': (en: 'Password field color', ja: 'パスワードフィールドの色'),
  '邮箱字段色': (en: 'Email field color', ja: 'メールフィールドの色'),
  '手机号字段色': (en: 'Phone field color', ja: '電話番号フィールドの色'),
  '网址字段色': (en: 'Website field color', ja: 'Webサイトフィールドの色'),
  '输入框焦点色': (en: 'Input focus color', ja: '入力欄のフォーカス色'),
  '主按钮': (en: 'Primary button', ja: 'メインボタン'),
  '次按钮': (en: 'Secondary button', ja: 'サブボタン'),
  '警告／即将续费': (en: 'Warning / Renewing soon', ja: '警告／まもなく更新'),
  '危险／已到期': (en: 'Danger / Expired', ja: '危険／期限切れ'),
  '暂停': (en: 'Paused', ja: '一時停止'),
  '已取消／中性': (en: 'Canceled / Neutral', ja: '解約済み／ニュートラル'),
  '旧金额强调色（仅兼容）': (
    en: 'Legacy amount accent (compatibility only)',
    ja: '従来の金額アクセント（互換性のみ）',
  ),
  '强调色相 {degrees}°': (en: 'Accent hue {degrees}°', ja: 'アクセントの色相 {degrees}°'),
  '强调色相，当前 {degrees} 度': (
    en: 'Accent hue, currently {degrees} degrees',
    ja: 'アクセントの色相、現在{degrees}度',
  ),
  '浓度': (en: 'Chroma', ja: '彩度'),
  '背景深度': (en: 'Background depth', ja: '背景の深さ'),
  '中性色温': (en: 'Neutral temperature', ja: 'ニュートラル色温度'),
  '自定义主题实时预览': (en: 'Live custom-theme preview', ja: 'カスタムテーマのライブプレビュー'),
  '首页': (en: 'Home', ja: 'ホーム'),
  '账号卡': (en: 'Account card', ja: 'アカウントカード'),
  '订阅卡': (en: 'Subscription card', ja: 'サブスクリプションカード'),
  '账号': (en: 'Accounts', ja: 'アカウント'),
  '订阅': (en: 'Subscriptions', ja: 'サブスクリプション'),
  '新增': (en: 'Add', ja: '追加'),
  '平台账号': (en: 'Platform account', ja: 'サービスアカウント'),
  '脱敏账号摘要 · 关联订阅': (
    en: 'Masked account summary · Linked subscription',
    ja: 'マスク済みアカウント概要 · 関連サブスクリプション',
  ),
  '账号总数': (en: 'Total accounts', ja: 'アカウント合計'),
  '订阅总数': (en: 'Total subscriptions', ja: 'サブスクリプション合計'),
  '订阅服务': (en: 'Subscription service', ja: 'サブスクリプションサービス'),
  '续费日期 · 状态说明': (en: 'Renewal date · Status', ja: '更新日 · 状態'),
  '续费强调色': (en: 'Renewal accent', ja: '更新日のアクセントカラー'),
  '自定义主题跟随主题时的桌面图标': (
    en: 'Fallback launcher icon for Custom Theme when icons follow the theme',
    ja: 'カスタムテーマ連動時のランチャーアイコン',
  ),
  '桌面图标只使用已打包的八套资源，不会在运行时生成自定义颜色。': (
    en: 'Launcher icons use one of eight bundled asset sets; custom colors are not generated at runtime.',
    ja: 'ランチャーアイコンには同梱の8種類のアイコンセットのみを使用し、実行時にカスタムカラーは生成しません。',
  ),
  '回退图标': (en: 'Fallback icon', ja: 'フォールバックアイコン'),
  '这些颜色暂时不能保存': (en: 'These colors cannot be saved yet', ja: 'この配色はまだ保存できません'),
  '请调整以下具体颜色，使文字、图标和交互控件保持清晰：': (
    en: 'Adjust the following colors so text, icons, and controls remain clear:',
    ja: '文字、アイコン、操作部品が見やすくなるよう、次の色を調整してください：',
  ),
  '前景 {foreground} / 背景 {background}': (
    en: 'Foreground {foreground} / Background {background}',
    ja: '前景 {foreground}／背景 {background}',
  ),
  '当前 {ratio}:1，至少 {required}:1；建议起点 {recommended}': (
    en: 'Current {ratio}:1; at least {required}:1. Suggested starting point: {recommended}',
    ja: '現在 {ratio}:1、必要値 {required}:1以上。推奨開始色：{recommended}',
  ),
  '另有 {count} 项，请继续调整后再次保存。': (
    en: '{count} more items need attention. Adjust them and save again.',
    ja: 'ほかに{count}項目あります。調整してからもう一度保存してください。',
  ),
  '自动修正': (en: 'Fix automatically', ja: '自動修正'),
  '已自动修正失败组合，可使用撤销恢复。': (
    en: 'Invalid combinations were fixed automatically. You can use Undo to restore them.',
    ja: '問題のある組み合わせを自動修正しました。「取り消す」で元に戻せます。',
  ),
  '返回调整': (en: 'Back to editing', ja: '調整に戻る'),
  '{count} 项对比度需要调整，修正前无法保存。': (
    en: '{count} contrast items need adjustment before you can save.',
    ja: '{count}件のコントラストを調整するまで保存できません。',
  ),
  '查看比值并自动修正': (en: 'Review ratios and auto-fix', ja: '比率を確認して自動修正'),
  'HEX 颜色': (en: 'HEX color', ja: 'HEXカラー'),
  '请输入 #RRGGBB': (en: 'Enter #RRGGBB', ja: '#RRGGBBを入力してください'),
  '色相': (en: 'Hue', ja: '色相'),
  '饱和度': (en: 'Saturation', ja: '彩度'),
  '明度': (en: 'Brightness', ja: '明度'),
  '自定义主题已安全保存。': (en: 'Custom theme saved safely.', ja: 'カスタムテーマを安全に保存しました。'),
  '自定义主题写入失败，原设置保持不变。': (
    en: 'Could not save the custom theme. Your previous settings were kept.',
    ja: 'カスタムテーマを保存できませんでした。以前の設定は保持されています。',
  ),
  '{mode} · {group} · {token}': (
    en: '{mode} · {group} · {token}',
    ja: '{mode} · {group} · {token}',
  ),

  // Main settings and security.
  '本地保险库': (en: 'On-device vault', ja: '端末内保管庫'),
  '核心保护均在此设备运行': (
    en: 'Core protection runs entirely on this device',
    ja: '主要な保護機能はすべてこの端末で動作します',
  ),
  '主密码': (en: 'Master password', ja: 'マスターパスワード'),
  '已设置': (en: 'Set', ja: '設定済み'),
  '已设置 · 点击修改；修改后需重新开启生物识别': (
    en: 'Set · Tap to change; biometrics must be re-enabled afterward',
    ja: '設定済み · タップして変更。変更後は生体認証の再設定が必要です',
  ),
  '生物识别': (en: 'Biometrics', ja: '生体認証'),
  '已开启': (en: 'On', ja: 'オン'),
  '未开启': (en: 'Off', ja: 'オフ'),
  '自动锁定': (en: 'Auto-lock', ja: '自動ロック'),
  '诱饵保险库': (en: 'Decoy vault', ja: 'おとり保管庫'),
  '已配置': (en: 'Configured', ja: '設定済み'),
  '未配置': (en: 'Not configured', ja: '未設定'),
  '{label}: {value}': (en: '{label}: {value}', ja: '{label}：{value}'),
  '，': (en: ', ', ja: '、'),
  '离开应用': (en: 'After leaving Cardock', ja: 'アプリを離れてから'),
  '离开应用立即锁定': (
    en: 'Lock immediately after leaving Cardock',
    ja: 'アプリを離れたらすぐにロック',
  ),
  '离开应用30秒后锁定': (
    en: 'Lock 30 seconds after leaving Cardock',
    ja: 'アプリを離れて30秒後にロック',
  ),
  '离开应用1分钟后锁定': (
    en: 'Lock 1 minute after leaving Cardock',
    ja: 'アプリを離れて1分後にロック',
  ),
  '离开应用5分钟后锁定': (
    en: 'Lock 5 minutes after leaving Cardock',
    ja: 'アプリを離れて5分後にロック',
  ),
  '离开应用15分钟后锁定': (
    en: 'Lock 15 minutes after leaving Cardock',
    ja: 'アプリを離れて15分後にロック',
  ),
  '立即锁定': (en: 'Lock now', ja: '今すぐロック'),
  '30秒': (en: '30 sec', ja: '30秒'),
  '1分钟': (en: '1 min', ja: '1分'),
  '5分钟': (en: '5 min', ja: '5分'),
  '15分钟': (en: '15 min', ja: '15分'),
  '自动锁定时间': (en: 'Auto-lock delay', ja: '自動ロックまでの時間'),
  '自动锁定时间已更新。': (en: 'Auto-lock delay updated.', ja: '自動ロックまでの時間を更新しました。'),
  '设置保存失败。': (en: 'Could not save the setting.', ja: '設定を保存できませんでした。'),
  '当前仅解锁订阅只读视图': (
    en: 'Subscription-only read access is currently unlocked',
    ja: '現在はサブスクリプションの読み取り専用表示のみ利用できます',
  ),
  '账号、编辑、安全配置和备份仍需真实主密码；可随时点“立即锁定”后改用主密码。': (
    en: 'Accounts, editing, security settings, and backups still require the real master password. Tap Lock now at any time, then unlock with the master password.',
    ja: 'アカウント、編集、セキュリティ設定、バックアップには実際のマスターパスワードが必要です。いつでも「今すぐロック」をタップし、マスターパスワードで入り直せます。',
  ),
  '防截屏保护': (en: 'Screen-capture protection', ja: '画面キャプチャ保護'),
  '开启后系统将阻止截图与录屏，并在最近任务中隐藏应用画面预览': (
    en: 'Blocks screenshots and screen recording, and hides the app preview in Recents',
    ja: 'スクリーンショットと画面録画をブロックし、最近使ったアプリのプレビューを非表示にします',
  ),
  '关闭防截屏保护？': (
    en: 'Turn off screen-capture protection?',
    ja: '画面キャプチャ保護をオフにしますか？',
  ),
  '关闭后，系统截图、录屏和最近任务预览可能暴露应用中的账号、密码与订阅内容。是否继续？': (
    en: 'System screenshots, screen recordings, and the Recents preview may expose accounts, passwords, and subscription details in Cardock. Continue?',
    ja: 'システムのスクリーンショット、画面録画、最近使ったアプリのプレビューに、Cardock内のアカウント、パスワード、サブスクリプション内容が映る可能性があります。続行しますか？',
  ),
  '关闭保护': (en: 'Turn off protection', ja: '保護をオフ'),
  '防截屏保护已开启。': (
    en: 'Screen-capture protection is on.',
    ja: '画面キャプチャ保護をオンにしました。',
  ),
  '防截屏保护已关闭。': (
    en: 'Screen-capture protection is off.',
    ja: '画面キャプチャ保護をオフにしました。',
  ),
  '防截屏保护设置保存失败，请重试。': (
    en: 'Could not save the screen-capture protection setting. Try again.',
    ja: '画面キャプチャ保護の設定を保存できませんでした。もう一度お試しください。',
  ),
  '指纹或人脸解锁': (en: 'Fingerprint or face unlock', ja: '指紋または顔認証でアンロック'),
  '生物识别解锁范围': (en: 'Biometric unlock scope', ja: '生体認証で開く範囲'),
  '选择生物识别范围': (en: 'Choose biometric access', ja: '生体認証で開く範囲を選択'),
  '仅查看订阅（推荐）': (en: 'Subscriptions only (recommended)', ja: 'サブスクリプションのみ（推奨）'),
  '账号资料和密码继续保持锁定；订阅视图只读': (
    en: 'Account details and passwords stay locked; subscriptions are read-only',
    ja: 'アカウント情報とパスワードはロックしたまま、サブスクリプションは読み取り専用で表示します',
  ),
  '完整保险库': (en: 'Full vault', ja: '保管庫全体'),
  '更方便，但被迫使用生物识别时会暴露真实账号': (
    en: 'More convenient, but real accounts may be exposed if you are forced to authenticate',
    ja: '便利ですが、生体認証を強要された場合に実際のアカウントが見られるおそれがあります',
  ),
  '完整保险库可被生物识别打开': (
    en: 'Biometrics can open the full vault',
    ja: '生体認証で保管庫全体を開けます',
  ),
  '启用后，成功验证指纹或人脸会直接显示账号和密码。在人身胁迫场景中，对方可能强迫你使用生物识别；诱饵密码只有在先输入时才能停用这条路径。是否继续？': (
    en: 'After this is enabled, a successful fingerprint or face check shows accounts and passwords directly. In a coercion scenario, someone could force you to authenticate; the decoy password disables this path only when entered first. Continue?',
    ja: '有効にすると、指紋または顔認証に成功した時点でアカウントとパスワードが直接表示されます。脅迫を受けた場合、生体認証を強要される可能性があります。おとりパスワードでこの経路を無効にするには、先におとりパスワードを入力する必要があります。続行しますか？',
  ),
  '我了解并继续': (en: 'I understand, continue', ja: '理解して続行'),
  '启用生物识别解锁': (en: 'Enable biometric unlock', ja: '生体認証アンロックを有効にする'),
  '当前主密码': (en: 'Current master password', ja: '現在のマスターパスワード'),
  '先重新输入当前主密码，再由系统验证。生物识别只保存独立订阅视图的数据密钥，账号秘密仍需主密码。': (
    en: 'Re-enter the current master password, then authenticate with the system. Biometrics protects only the separate subscription-view data key; account secrets still require the master password.',
    ja: '現在のマスターパスワードを再入力してから、システム認証を行います。生体認証で保護するのは独立したサブスクリプション表示用データキーだけで、アカウントの秘密情報には引き続きマスターパスワードが必要です。',
  ),
  '先重新输入当前主密码，再由系统验证。完整模式会允许生物识别直接打开账号和订阅；应用不会保存主密码。': (
    en: 'Re-enter the current master password, then authenticate with the system. Full-vault mode lets biometrics open accounts and subscriptions directly. Cardock does not store the master password.',
    ja: '現在のマスターパスワードを再入力してから、システム認証を行います。保管庫全体モードでは、生体認証でアカウントとサブスクリプションを直接開けます。Cardockはマスターパスワードを保存しません。',
  ),
  '已启用“仅查看订阅”的生物识别。': (
    en: 'Biometrics enabled for subscription-only access.',
    ja: 'サブスクリプションのみの生体認証を有効にしました。',
  ),
  '已启用“完整保险库”的生物识别。': (
    en: 'Biometrics enabled for the full vault.',
    ja: '保管庫全体の生体認証を有効にしました。',
  ),
  '启用失败，请检查主密码和系统生物识别。': (
    en: 'Could not enable biometrics. Check the master password and system biometric settings.',
    ja: '生体認証を有効にできませんでした。マスターパスワードとシステムの生体認証設定を確認してください。',
  ),
  '关闭生物识别解锁？': (en: 'Turn off biometric unlock?', ja: '生体認証アンロックをオフにしますか？'),
  '关闭后仍可继续使用主密码，不会删除加密库。': (
    en: 'You can continue using the master password. The encrypted vault will not be deleted.',
    ja: '引き続きマスターパスワードを使用できます。暗号化された保管庫は削除されません。',
  ),
  '已关闭生物识别快速解锁。': (
    en: 'Biometric quick unlock is off.',
    ja: '生体認証によるクイックアンロックをオフにしました。',
  ),
  '关闭失败，请重试。': (
    en: 'Could not turn it off. Try again.',
    ja: 'オフにできませんでした。もう一度お試しください。',
  ),
  '已停用；请先锁定，再用真实主密码进入后重新开启': (
    en: 'Disabled · Lock first, then enter the real master password and enable it again',
    ja: '無効 · いったんロックし、実際のマスターパスワードで入り直してから再設定してください',
  ),
  '当前仅解锁独立订阅只读视图；账号秘密仍需主密码': (
    en: 'Only the separate read-only subscription view is unlocked; account secrets still require the master password',
    ja: '独立したサブスクリプションの読み取り専用表示のみアンロック中。アカウントの秘密情報にはマスターパスワードが必要です',
  ),
  '完整保险库 · 存在人身胁迫风险': (en: 'Full vault · Coercion risk', ja: '保管庫全体 · 脅迫リスクあり'),
  '完整模式会直接打开账号和订阅；不保存主密码': (
    en: 'Opens accounts and subscriptions directly; the master password is not stored',
    ja: 'アカウントとサブスクリプションを直接開きます。マスターパスワードは保存しません',
  ),
  '完整生物识别存在胁迫风险：他人若能强迫你通过系统验证，可能看到真实账号；诱饵密码需先输入才会停用生物识别。': (
    en: 'Full-vault biometrics carries a coercion risk: someone who forces you to pass system authentication may see real accounts. The decoy password disables biometrics only when entered first.',
    ja: '保管庫全体の生体認証には脅迫リスクがあります。システム認証を強要されると、実際のアカウントが見られる可能性があります。生体認証を無効にするには、先におとりパスワードを入力する必要があります。',
  ),
  '清除内存中的解锁密钥和记录': (
    en: 'Clear unlocked keys and records from memory',
    ja: 'メモリ内のアンロックキーと記録を消去',
  ),
  '密码恢复': (en: 'Password recovery', ja: 'パスワード復旧'),
  '未配置 · 三道密保 + 本机系统强认证': (
    en: 'Not configured · Three security questions + strong device authentication',
    ja: '未設定 · 3つの秘密の質問 + 端末の強力なシステム認証',
  ),
  '不可用 · 已配置诱饵库': (
    en: 'Unavailable · Decoy vault configured',
    ja: '利用不可 · おとり保管庫が設定済み',
  ),
  '已配置 · 3秒内连续点锁屏Logo 5次': (
    en: 'Configured · Tap the lock-screen logo 5 times within 3 seconds',
    ja: '設定済み · ロック画面のロゴを3秒以内に5回連続タップ',
  ),
  '已配置 · 锁屏页直接显示入口': (
    en: 'Configured · Entry shown directly on the lock screen',
    ja: '設定済み · ロック画面に入口を直接表示',
  ),
  '3秒内连续点 Logo 5次': (
    en: 'Tap the logo 5 times within 3 seconds',
    ja: 'ロゴを3秒以内に5回連続タップ',
  ),
  '直接显示“忘记密码？恢复保险库访问”': (
    en: 'Show “Forgot a password? Recover vault access” directly',
    ja: '「パスワードを忘れた場合：保管庫へのアクセスを復旧」を直接表示',
  ),
  '更容易找到，默认推荐': (
    en: 'Easier to find; recommended by default',
    ja: '見つけやすく、初期設定として推奨',
  ),
  '只是降低入口可见度，不增加安全性；辅助功能用户建议直接显示': (
    en: 'Only makes the entry less visible; it does not add security. Direct display is recommended for accessibility users.',
    ja: '入口を目立ちにくくするだけで、安全性は高まりません。アクセシビリティ機能を使用する場合は直接表示を推奨します。',
  ),
  '设置密码恢复': (en: 'Set up password recovery', ja: 'パスワード復旧を設定'),
  '设置密码恢复前请重新输入当前真实主密码。主密码和密保答案都不会保存。': (
    en: 'Re-enter the current real master password before setting up recovery. Neither the master password nor security answers are stored.',
    ja: '復旧を設定する前に、現在の実際のマスターパスワードを再入力してください。マスターパスワードと秘密の質問の答えは保存されません。',
  ),
  '验证真实保险库': (en: 'Verify the real vault', ja: '実際の保管庫を確認'),
  '当前真实主密码': (en: 'Current real master password', ja: '現在の実際のマスターパスワード'),
  '恢复不会显示旧密码。每次恢复都必须同时答对三题，并通过本机指纹或安全级人脸。请使用只有你知道且长期稳定的答案。': (
    en: 'Recovery never reveals the old password. Each recovery requires all three answers plus a fingerprint or secure face check on this device. Use answers that only you know and that will remain stable over time.',
    ja: '復旧で以前のパスワードが表示されることはありません。復旧のたびに3問すべてへ正しく答え、この端末で指紋またはセキュアな顔認証を通過する必要があります。自分だけが知り、長期間変わらない答えを使用してください。',
  ),
  '密保问题 {number}': (en: 'Security question {number}', ja: '秘密の質問 {number}'),
  '答案': (en: 'Answer', ja: '答え'),
  '答案不能为空': (en: 'Enter an answer', ja: '答えを入力してください'),
  '再次输入答案': (en: 'Re-enter answer', ja: '答えを再入力'),
  '请再次输入答案': (en: 'Re-enter the answer', ja: '答えをもう一度入力してください'),
  '显示答案': (en: 'Show answers', ja: '答えを表示'),
  '隐藏答案': (en: 'Hide answers', ja: '答えを非表示'),
  '锁屏入口': (en: 'Lock-screen entry', ja: 'ロック画面の入口'),
  '三道密保问题不能重复。': (
    en: 'Choose three different security questions.',
    ja: '3つの秘密の質問は重複しないように選んでください。',
  ),
  '第{number}道问题的两次答案不一致。': (
    en: 'The two answers for question {number} do not match.',
    ja: '質問{number}の2回の答えが一致しません。',
  ),
  '系统认证并启用': (en: 'Authenticate and enable', ja: 'システム認証して有効化'),
  '密码恢复已启用；请锁定后亲自验证入口和三道答案。': (
    en: 'Password recovery is enabled. Lock Cardock, then personally verify the entry and all three answers.',
    ja: 'パスワード復旧を有効にしました。Cardockをロックし、入口と3つの答えを自分で確認してください。',
  ),
  '密码恢复设置失败，保险库仍可使用原主密码。': (
    en: 'Could not set up password recovery. The vault still uses the original master password.',
    ja: 'パスワード復旧を設定できませんでした。保管庫は引き続き元のマスターパスワードで利用できます。',
  ),
  '关闭密码恢复？': (en: 'Turn off password recovery?', ja: 'パスワード復旧をオフにしますか？'),
  '关闭后，忘记主密码时只能依赖你单独保存的加密备份。业务数据和当前主密码不会改变。': (
    en: 'If you forget the master password, only your separately stored encrypted backup can help. Your records and current master password will not change.',
    ja: 'マスターパスワードを忘れた場合は、別途保存した暗号化バックアップだけが復旧手段になります。記録と現在のマスターパスワードは変わりません。',
  ),
  '继续关闭': (en: 'Turn off', ja: 'オフにする'),
  '关闭恢复前必须重新验证真实主密码。': (
    en: 'Verify the real master password again before turning off recovery.',
    ja: '復旧をオフにする前に、実際のマスターパスワードをもう一度確認してください。',
  ),
  '验证当前主密码': (en: 'Verify current master password', ja: '現在のマスターパスワードを確認'),
  '密码恢复已关闭。': (en: 'Password recovery is off.', ja: 'パスワード復旧をオフにしました。'),
  '密码恢复关闭失败，原配置仍保持不变。': (
    en: 'Could not turn off password recovery. The previous configuration was kept.',
    ja: 'パスワード復旧をオフにできませんでした。以前の設定は保持されています。',
  ),
  '不可用 · 已配置密码恢复': (
    en: 'Unavailable · Password recovery configured',
    ja: '利用不可 · パスワード復旧が設定済み',
  ),

  // Decoy vault and password changes.
  '诱饵密码与独立诱饵库': (
    en: 'Decoy password and separate decoy vault',
    ja: 'おとりパスワードと独立したおとり保管庫',
  ),
  '未配置 · 由你亲自准备诱饵内容': (
    en: 'Not configured · You prepare the decoy content yourself',
    ja: '未設定 · おとりの内容はご自身で用意します',
  ),
  '已配置 · 点击修改；原诱饵内容会保留': (
    en: 'Configured · Tap to change; existing decoy content is kept',
    ja: '設定済み · タップして変更。既存のおとりデータは保持されます',
  ),
  '创建诱饵库前先输入真实主密码。该密码不会保存。': (
    en: 'Enter the real master password before creating a decoy vault. The password is not stored.',
    ja: 'おとり保管庫を作成する前に、実際のマスターパスワードを入力してください。このパスワードは保存されません。',
  ),
  '设置诱饵密码': (en: 'Set decoy password', ja: 'おとりパスワードを設定'),
  '设置要求：6–32个字符。请选择容易记住、但与真实主密码完全不同的故事密码；诱饵密码不用于保护真实账号。': (
    en: 'Requirements: 6–32 characters. Choose a memorable story-like password that is completely different from the real master password. The decoy password does not protect real accounts.',
    ja: '要件：6～32文字。覚えやすく、実際のマスターパスワードとはまったく異なる、物語のようなパスワードを選んでください。おとりパスワードは実際のアカウントを保護するものではありません。',
  ),
  '诱饵密码': (en: 'Decoy password', ja: 'おとりパスワード'),
  '新密码会打开原有诱饵库内容，不会创建空库，也不会删除或修改真实数据。': (
    en: 'The new password opens the existing decoy content. It does not create an empty vault or delete or alter real data.',
    ja: '新しいパスワードで既存のおとり保管庫を開きます。空の保管庫を作成したり、実際のデータを削除・変更したりすることはありません。',
  ),
  '这不是“任意输错密码”。只有这一个明确设置的密码会打开独立诱饵库；它绝不会删除或修改真实数据。': (
    en: 'This is not “any incorrect password.” Only this specifically configured password opens the separate decoy vault, and it never deletes or changes real data.',
    ja: '「どんな間違ったパスワードでもよい」機能ではありません。明示的に設定したこのパスワードだけが独立したおとり保管庫を開き、実際のデータを削除・変更することはありません。',
  ),
  '诱饵库已创建；请锁定后用诱饵密码进入并亲自准备内容。': (
    en: 'Decoy vault created. Lock Cardock, enter with the decoy password, and personally prepare its content.',
    ja: 'おとり保管庫を作成しました。Cardockをロックし、おとりパスワードで入って内容を自分で準備してください。',
  ),
  '诱饵库创建失败。': (
    en: 'Could not create the decoy vault.',
    ja: 'おとり保管庫を作成できませんでした。',
  ),
  '验证当前诱饵密码': (en: 'Verify current decoy password', ja: '現在のおとりパスワードを確認'),
  '输入当前诱饵密码。此步骤不会打开诱饵库，也不会改变生物识别设置。': (
    en: 'Enter the current decoy password. This does not open the decoy vault or change biometric settings.',
    ja: '現在のおとりパスワードを入力してください。この操作でおとり保管庫が開いたり、生体認証設定が変わったりすることはありません。',
  ),
  '当前诱饵密码': (en: 'Current decoy password', ja: '現在のおとりパスワード'),
  '设置新的诱饵密码': (en: 'Set a new decoy password', ja: '新しいおとりパスワードを設定'),
  '新诱饵密码': (en: 'New decoy password', ja: '新しいおとりパスワード'),
  '修改诱饵密码需要真实主密码和当前诱饵密码双重授权；两者都不会保存。': (
    en: 'Changing the decoy password requires both the real master password and current decoy password. Neither is stored.',
    ja: 'おとりパスワードの変更には、実際のマスターパスワードと現在のおとりパスワードの両方が必要です。どちらも保存されません。',
  ),
  '诱饵密码已修改；原诱饵内容保留，旧诱饵密码已失效，生物识别设置未改变。': (
    en: 'Decoy password changed. Existing decoy content was kept, the old decoy password no longer works, and biometric settings were not changed.',
    ja: 'おとりパスワードを変更しました。既存のおとりデータは保持され、以前のパスワードは無効になりました。生体認証設定は変更されていません。',
  ),
  '诱饵密码修改失败，原诱饵密码仍然有效。': (
    en: 'Could not change the decoy password. The previous decoy password still works.',
    ja: 'おとりパスワードを変更できませんでした。以前のパスワードは引き続き有効です。',
  ),
  '为保证双因子恢复不会继续包装旧数据密钥，请先关闭真实保险库密码恢复，再修改真实主密码；修改后可重新设置。': (
    en: 'To prevent two-factor recovery from retaining the old data-key wrapping, turn off real-vault password recovery before changing the real master password. You can set it up again afterward.',
    ja: '二要素復旧が古いデータキーをラップしたままにしないよう、実際のマスターパスワードを変更する前に、実際の保管庫のパスワード復旧をオフにしてください。変更後に再設定できます。',
  ),
  '检测到尚未确认的恢复事务；请先核对并处理“恢复到上次导入前”，再修改主密码。': (
    en: 'An unconfirmed restore transaction was found. Review and resolve “Restore to before the last import” before changing the master password.',
    ja: '未確認の復元処理が見つかりました。マスターパスワードを変更する前に、「前回のインポート前に戻す」を確認して処理してください。',
  ),
  '修改前必须重新验证真实主密码。密码只在本机参与解密，不会保存。': (
    en: 'Verify the real master password again before making the change. It is used only for decryption on this device and is not stored.',
    ja: '変更前に、実際のマスターパスワードをもう一度確認してください。パスワードはこの端末での復号にだけ使用され、保存されません。',
  ),
  '设置新的主密码': (en: 'Set a new master password', ja: '新しいマスターパスワードを設定'),
  '修改时会生成全新的随机 256 位数据密钥，并重新加密真实保险库；请务必记住新密码。': (
    en: 'A new random 256-bit data key will be generated and the real vault will be re-encrypted. Make sure you remember the new password.',
    ja: '新しいランダムな256ビットのデータキーを生成し、実際の保管庫を再暗号化します。新しいパスワードを必ず覚えておいてください。',
  ),
  '新主密码': (en: 'New master password', ja: '新しいマスターパスワード'),
  '设置要求：16–128个字符。自定义密码建议同时包含大写字母、小写字母、数字和符号；也可以使用本机离线生成的高强度随机密码。': (
    en: 'Requirements: 16–128 characters. A custom password should include uppercase and lowercase letters, numbers, and symbols, or you can generate a strong random password offline on this device.',
    ja: '要件：16～128文字。自分で作る場合は、大文字、小文字、数字、記号をすべて含めることを推奨します。この端末で強力なランダムパスワードをオフライン生成することもできます。',
  ),
  '确认修改主密码？': (en: 'Change the master password?', ja: 'マスターパスワードを変更しますか？'),
  '完成后旧主密码不能再打开当前保险库，生物识别快速解锁会安全停用，需要之后用新主密码重新开启。': (
    en: 'After the change, the old master password cannot open the current vault. Biometric quick unlock will be disabled safely and must be enabled again later with the new master password.',
    ja: '変更後は、以前のマスターパスワードで現在の保管庫を開けなくなります。生体認証によるクイックアンロックは安全に無効化され、新しいマスターパスワードで後から再設定する必要があります。',
  ),
  '完成后旧主密码不能再打开当前保险库，生物识别快速解锁会安全停用，需要之后用新主密码重新开启。\n\n本机“上次导入前”的加密回滚副本仍受旧密码保护，将先被永久废弃；独立导出的 .asmbackup 文件不受影响。': (
    en: 'After the change, the old master password cannot open the current vault. Biometric quick unlock will be disabled safely and must be enabled again later with the new master password.\n\nThe encrypted on-device rollback copy from before the last import is still protected by the old password and will be permanently discarded first. Separately exported .asmbackup files are not affected.',
    ja: '変更後は、以前のマスターパスワードで現在の保管庫を開けなくなります。生体認証によるクイックアンロックは安全に無効化され、新しいマスターパスワードで後から再設定する必要があります。\n\n端末内にある「前回のインポート前」の暗号化ロールバックコピーは以前のパスワードで保護されているため、先に完全に破棄されます。別途エクスポートした.asmbackupには影響しません。',
  ),
  '确认修改': (en: 'Change password', ja: '変更する'),
  '主密码已修改；当前数据已换用新随机密钥加密，生物识别已停用。': (
    en: 'Master password changed. Current data is now encrypted with a new random key, and biometrics is off.',
    ja: 'マスターパスワードを変更しました。現在のデータは新しいランダムキーで暗号化され、生体認証はオフになっています。',
  ),
  '主密码修改失败，当前数据未被确认切换。': (
    en: 'Could not change the master password. The current data was not confirmed as switched.',
    ja: 'マスターパスワードを変更できませんでした。現在のデータの切り替えは確定していません。',
  ),
  '再次输入确认': (en: 'Re-enter to confirm', ja: '確認のため再入力'),
  '两次输入的密码不一致。': (
    en: 'The two passwords do not match.',
    ja: '2回入力したパスワードが一致しません。',
  ),
  '离线生成高强度密码': (
    en: 'Generate a strong password offline',
    ja: '強力なパスワードをオフライン生成',
  ),
  '复制（60秒后尽力清理）': (
    en: 'Copy (attempt to clear after 60 sec)',
    ja: 'コピー（60秒後に消去を試行）',
  ),
  '已在本机离线生成': (en: 'Generated offline on this device', ja: 'この端末でオフライン生成済み'),
  '已在本机离线生成。请立即离线保存并核对；应用不会保存或找回这个密码。': (
    en: 'Generated offline on this device. Save and verify it offline now. Cardock does not store or recover this password.',
    ja: 'この端末でオフライン生成しました。今すぐオフラインで保存し、内容を確認してください。Cardockはこのパスワードを保存・復旧できません。',
  ),
  '已复制，应用会在60秒后尽力清除；请留意键盘或厂商剪贴板历史。': (
    en: 'Copied. Cardock will attempt to clear it after 60 seconds. Be aware of keyboard or manufacturer clipboard history.',
    ja: 'コピーしました。60秒後に消去を試みます。キーボードや端末メーカーのクリップボード履歴にご注意ください。',
  ),
  '复制失败，未写入剪贴板。': (
    en: 'Could not copy. Nothing was written to the clipboard.',
    ja: 'コピーできませんでした。クリップボードには書き込まれていません。',
  ),

  // Notifications and subscription defaults.
  '本地续费提醒': (en: 'On-device renewal reminders', ja: '端末内の更新リマインダー'),
  '通知内容取决于你选择的隐私级别；应用内记录才是权威来源': (
    en: 'Notification details follow your selected privacy level; records in Cardock remain the authoritative source.',
    ja: '通知内容は選択したプライバシーレベルに従います。正しい情報はCardock内の記録で確認してください。',
  ),
  '本地续费提醒已开启。': (
    en: 'On-device renewal reminders are on.',
    ja: '端末内の更新リマインダーをオンにしました。',
  ),
  '本地续费提醒已关闭。': (
    en: 'On-device renewal reminders are off.',
    ja: '端末内の更新リマインダーをオフにしました。',
  ),
  '设置已保存为开启，但部分提醒重排失败；下次解锁会自动重试。': (
    en: 'The setting is on, but some reminders could not be rescheduled. Cardock will retry the next time you unlock.',
    ja: '設定はオンになりましたが、一部のリマインダーを再設定できませんでした。次回のアンロック時に自動で再試行します。',
  ),
  '设置已保存为开启，但系统通知初始化失败；请前往“通知可靠性”测试通知并重试。': (
    en: 'The setting is on, but system notifications could not be initialized. Open “Notification reliability” to test notifications and try again.',
    ja: '設定はオンになりましたが、システム通知を初期化できませんでした。「通知の信頼性」で通知をテストして再試行してください。',
  ),
  '设置已保存为关闭，但旧提醒清理失败；下次解锁会自动重试。': (
    en: 'The setting is off, but old reminders could not be cleared. Cardock will retry the next time you unlock.',
    ja: '設定はオフになりましたが、以前のリマインダーを削除できませんでした。次回のアンロック時に自動で再試行します。',
  ),
  '系统通知初始化失败。': (
    en: 'Could not initialize system notifications.',
    ja: 'システム通知を初期化できませんでした。',
  ),
  '系统通知初始化失败，请保持应用在前台后重试。': (
    en: 'Could not initialize system notifications. Keep Cardock in the foreground and try again.',
    ja: 'システム通知を初期化できませんでした。Cardockを前面に表示したまま、もう一度お試しください。',
  ),
  '系统通知可用，但通知设置保存失败。': (
    en: 'System notifications are available, but the notification setting could not be saved.',
    ja: 'システム通知は利用できますが、通知設定を保存できませんでした。',
  ),
  '当前状态无法更改通知设置，请稍后重试。': (
    en: 'Notification settings cannot be changed in the current state. Try again later.',
    ja: '現在の状態では通知設定を変更できません。しばらくしてからもう一度お試しください。',
  ),
  '手机系统已关闭本应用的总通知权限。': (
    en: 'System notification permission for Cardock is off.',
    ja: 'システムでCardock全体の通知権限がオフになっています。',
  ),
  '手机系统已关闭本应用的总通知权限，请先在系统设置中开启。': (
    en: 'System notification permission for Cardock is off. Enable it in system settings first.',
    ja: 'システムでCardock全体の通知権限がオフになっています。先にシステム設定で有効にしてください。',
  ),
  '“本机订阅提醒”通知通道已关闭。': (
    en: 'The “On-device subscription reminders” channel is off.',
    ja: '「端末内サブスクリプション通知」チャンネルがオフになっています。',
  ),
  '“本机订阅提醒”通知通道已关闭，请先在系统通知设置中开启。': (
    en: 'The “On-device subscription reminders” channel is off. Enable it in system notification settings first.',
    ja: '「端末内サブスクリプション通知」チャンネルがオフになっています。先にシステムの通知設定で有効にしてください。',
  ),
  '本应用总通知权限已开启，但“本机订阅提醒”通知通道已关闭，请在系统通知设置中开启该类别。': (
    en: 'Cardock has notification permission, but the “On-device subscription reminders” channel is off. Enable that category in system notification settings.',
    ja: 'Cardock全体の通知権限はオンですが、「端末内サブスクリプション通知」チャンネルがオフです。システムの通知設定でこのカテゴリを有効にしてください。',
  ),
  '无法检查系统通知状态，请稍后重试。': (
    en: 'Could not check system notification status. Try again later.',
    ja: 'システムの通知状態を確認できませんでした。しばらくしてからもう一度お試しください。',
  ),
  '请先开启“本地续费提醒”。': (
    en: 'Turn on “On-device renewal reminders” first.',
    ja: '先に「端末内の更新リマインダー」をオンにしてください。',
  ),
  '请先开启本地续费提醒': (
    en: 'Turn on on-device renewal reminders first',
    ja: '先に端末内の更新リマインダーをオンにしてください',
  ),
  '测试通知与定时提醒': (en: 'Test notifications and reminders', ja: '通知と予約リマインダーをテスト'),
  '权限、通道、电池优化、厂商后台策略与恢复记录': (
    en: 'Permissions, channel, battery optimization, manufacturer policies, and recovery history',
    ja: '権限、チャンネル、バッテリー最適化、メーカーのバックグラウンド設定、復旧履歴',
  ),
  '立即发送测试通知，并安排约1分钟后的通用提醒': (
    en: 'Send a test notification now and schedule a generic reminder in about 1 minute',
    ja: 'テスト通知を今すぐ送信し、約1分後の一般的なリマインダーを予約します',
  ),
  '当前状态无法测试通知，请稍后重试。': (
    en: 'Notifications cannot be tested in the current state. Try again later.',
    ja: '現在の状態では通知をテストできません。しばらくしてからもう一度お試しください。',
  ),
  '即时测试通知发送失败，请检查系统通知设置。': (
    en: 'Could not send the immediate test notification. Check system notification settings.',
    ja: 'テスト通知を送信できませんでした。システムの通知設定を確認してください。',
  ),
  '即时通知已发送，但1分钟测试提醒安排失败。': (
    en: 'The immediate notification was sent, but the 1-minute test reminder could not be scheduled.',
    ja: 'テスト通知は送信しましたが、1分後のテストリマインダーを予約できませんでした。',
  ),
  '已发送即时测试通知，并安排约1分钟后的测试提醒。': (
    en: 'Immediate test notification sent, with another test reminder scheduled in about 1 minute.',
    ja: 'テスト通知を送信し、約1分後のテストリマインダーも予約しました。',
  ),
  '新增订阅默认提前量': (
    en: 'Default reminder lead time for new subscriptions',
    ja: '新しいサブスクリプションの通知タイミング',
  ),
  '新增订阅默认提前提醒': (
    en: 'Default advance reminder for new subscriptions',
    ja: '新しいサブスクリプションの事前通知',
  ),
  '续费当天': (en: 'On the renewal date', ja: '更新当日'),
  '提前{days}天': (en: '{days} days before', ja: '{days}日前'),
  '默认提醒时间已更新，仅影响以后新增订阅。': (
    en: 'Default reminder lead time updated. It applies only to new subscriptions.',
    ja: '既定の通知タイミングを更新しました。今後追加するサブスクリプションにのみ適用されます。',
  ),
  '提醒发送时间': (en: 'Reminder time', ja: '通知時刻'),
  '第一次提醒发送时间': (en: 'First reminder time', ja: '1回目の通知時刻'),
  '第二次提醒发送时间': (en: 'Second reminder time', ja: '2回目の通知時刻'),
  '选择第一次提醒时间': (en: 'Choose the first reminder time', ja: '1回目の通知時刻を選択'),
  '选择第二次提醒时间': (en: 'Choose the second reminder time', ja: '2回目の通知時刻を選択'),
  '选择本地提醒时间': (en: 'Choose on-device reminder time', ja: '端末内リマインダーの時刻を選択'),
  '提醒时间已更新，已安排的本地提醒会同步调整。': (
    en: 'Reminder time updated. Existing on-device reminders will be adjusted too.',
    ja: '通知時刻を更新しました。予約済みの端末内リマインダーも合わせて変更されます。',
  ),
  '默认货币': (en: 'Default currency', ja: '既定の通貨'),
  '新增订阅默认货币': (
    en: 'Default currency for new subscriptions',
    ja: '新しいサブスクリプションの既定通貨',
  ),
  '默认货币已更新，仅影响以后新增订阅。': (
    en: 'Default currency updated. It applies only to new subscriptions.',
    ja: '既定の通貨を更新しました。今後追加するサブスクリプションにのみ適用されます。',
  ),
  '账号显示方式': (en: 'Account display style', ja: 'アカウントの表示形式'),
  '订阅显示方式': (en: 'Subscription display style', ja: 'サブスクリプションの表示形式'),
  '显示方式已更新。': (en: 'Display style updated.', ja: '表示形式を更新しました。'),

  // Encrypted backups and rollback.
  '数据导入与备份': (en: 'Data import and backups', ja: 'データのインポートとバックアップ'),
  '导入外部数据': (en: 'Import external data', ja: '外部データをインポート'),
  '当前会话不能导入外部数据': (
    en: 'External data import is unavailable in the current session',
    ja: '現在のセッションでは外部データをインポートできません',
  ),
  'XLSX/CSV 等外部文件；.asmbackup 请用“恢复”': (
    en: 'External XLSX/CSV etc.; Restore .asmbackup',
    ja: 'XLSX/CSV 等の外部ファイル。.asmbackup は「復元」へ',
  ),
  '导出 Cardock 加密备份': (
    en: 'Export Cardock encrypted backup',
    ja: 'Cardock 暗号化バックアップを書き出す',
  ),
  '.asmbackup · 账号与订阅 · 独立备份密码': (
    en: '.asmbackup · Vault · Separate password',
    ja: '.asmbackup · アカウントとサブスクリプション · 専用パスワード',
  ),
  '当前会话不能导出 Cardock 加密备份': (
    en: 'Cardock encrypted backup export is unavailable in the current session',
    ja: '現在のセッションでは Cardock 暗号化バックアップを書き出せません',
  ),
  '恢复 Cardock 加密备份': (
    en: 'Restore Cardock encrypted backup',
    ja: 'Cardock 暗号化バックアップを復元',
  ),
  '手动/自动备份 .asmbackup；先验证再恢复': (
    en: 'Manual/auto .asmbackup; verify first',
    ja: '手動/自動 .asmbackup。検証後に復元',
  ),
  '自动备份与备份检查': (
    en: 'Automatic backups and backup checks',
    ja: '自動バックアップとバックアップ確認',
  ),
  '撤销最近一次备份恢复': (en: 'Undo the latest backup restore', ja: '直近のバックアップ復元を取り消す'),
  '检测到尚未确认的恢复事务；请先核对并处理“撤销最近一次备份恢复”，再修改主密码。': (
    en: 'An unconfirmed restore transaction was found. Review and handle “Undo the latest backup restore” before changing the master password.',
    ja: '未確認の復元トランザクションがあります。マスターパスワードを変更する前に「直近のバックアップ復元を取り消す」を確認して処理してください。',
  ),
  '已撤销最近一次备份恢复，已回到恢复前的数据。': (
    en: 'The latest backup restore was undone and the pre-restore data is active again.',
    ja: '直近のバックアップ復元を取り消し、復元前のデータへ戻しました。',
  ),
  '上次恢复结果未确认 · 恢复前加密副本仍在': (
    en: 'Previous restore is unconfirmed · The encrypted pre-restore copy remains',
    ja: '前回の復元結果は未確認 · 復元前の暗号化コピーは保持されています',
  ),
  '回到恢复 .asmbackup 前的本机记录': (
    en: 'Return to the on-device records from before the .asmbackup restore',
    ja: '.asmbackup 復元前の端末内記録へ戻します',
  ),
  '本地优先 · 业务数据不访问公网或云；只有主动开启电脑临时录入时才监听可信局域网，断开即停止。': (
    en: 'Local first · Record data does not access the public internet or cloud. Cardock listens on a trusted LAN only while you actively use Temporary PC Entry, and stops as soon as it disconnects.',
    ja: 'ローカル優先 · 記録データはインターネットやクラウドへアクセスしません。「PCから一時入力」を自分で開始している間だけ信頼できるLANで待ち受け、切断すると停止します。',
  ),
  '本地优先 · 业务数据不访问公网或云端': (
    en: 'Local first · Record data does not access the public internet or cloud',
    ja: 'ローカル優先 · 記録データはインターネットやクラウドへアクセスしません',
  ),
  '不访问公网/云 · 仅主动开启时监听可信局域网': (
    en: 'No public internet or cloud · Listens on a trusted LAN only when you start it',
    ja: 'インターネット／クラウド不使用 · 自分で開始した場合だけ信頼できるLANで待ち受け',
  ),
  '正在开启可信局域网临时服务…': (
    en: 'Starting temporary service on the trusted local network…',
    ja: '信頼できるローカルネットワークで一時サービスを開始しています…',
  ),
  '已开启 · 等待电脑输入一次性连接码': (
    en: 'On · Waiting for the one-time connection code on the PC',
    ja: 'オン · PCでワンタイム接続コードが入力されるのを待っています',
  ),
  '电脑网页已连接 · 点击管理或断开': (
    en: 'PC web page connected · Tap to manage or disconnect',
    ja: 'PCのWebページが接続中 · タップして管理または切断',
  ),
  '导出加密备份': (en: 'Export encrypted backup', ja: '暗号化バックアップを書き出す'),
  '.asmbackup 可保存到手机或电脑，使用独立备份密码': (
    en: 'Save .asmbackup to your phone or PC with a separate backup password',
    ja: '.asmbackupをスマートフォンまたはPCへ保存。専用のバックアップパスワードを使用します',
  ),
  '当前会话不能导出便携备份': (
    en: 'Portable backup export is unavailable in the current session',
    ja: '現在のセッションではポータブルバックアップを書き出せません',
  ),
  '当前会话不能使用数据迁移与批量导入': (
    en: 'Data migration and batch import are unavailable in the current session',
    ja: '現在のセッションではデータ移行と一括読み込みを利用できません',
  ),
  '当前会话中不可修改；请先锁定后再进入安全设置': (
    en: 'This cannot be changed in the current session; lock first, then return to security settings',
    ja: '現在のセッションでは変更できません。先にロックしてからセキュリティ設定へ戻ってください',
  ),
  '当前会话不能查看通知可靠性': (
    en: 'Notification reliability is unavailable in the current session',
    ja: '現在のセッションでは通知の信頼性を確認できません',
  ),
  '设置独立备份密码': (en: 'Set a separate backup password', ja: '専用のバックアップパスワードを設定'),
  '每次导出都会使用新的随机密钥材料重新加密。备份密码可以与本机主密码不同，应用不会保存；遗失后无法恢复文件。': (
    en: 'Every export is re-encrypted with fresh random key material. The backup password can differ from the device master password and is not stored by Cardock. If you lose it, the file cannot be restored.',
    ja: 'エクスポートのたびに、新しいランダムなキーデータで再暗号化します。バックアップパスワードは端末のマスターパスワードと異なるものにでき、Cardockには保存されません。紛失するとファイルを復元できません。',
  ),
  '备份密码': (en: 'Backup password', ja: 'バックアップパスワード'),
  '无法生成加密备份。': (
    en: 'Could not create the encrypted backup.',
    ja: '暗号化バックアップを作成できませんでした。',
  ),
  '保存备份失败，请检查文件位置。': (
    en: 'Could not save the backup. Check the file location.',
    ja: 'バックアップを保存できませんでした。保存先を確認してください。',
  ),
  '加密备份已交给系统保存；建议重新选择该文件并完成一次只读验证。': (
    en: 'The encrypted backup was handed to the system for saving. Choose the file again and run a read-only verification.',
    ja: '暗号化バックアップをシステムへ渡して保存しました。もう一度そのファイルを選び、読み取り専用の検証を行うことを推奨します。',
  ),
  '加密备份已保存为 .asmbackup。请打开“自动备份与备份检查”→“检查 Cardock 加密备份（不恢复）”核对文件。': (
    en: 'The encrypted backup was saved as .asmbackup. Open “Automatic backups and backup checks” → “Check Cardock encrypted backup (no restore)” to verify it.',
    ja: '暗号化バックアップを .asmbackup として保存しました。「自動バックアップとバックアップ確認」→「Cardock 暗号化バックアップを確認（復元しない）」で確認してください。',
  ),
  '选择 .asmbackup 加密备份': (
    en: 'Choose an .asmbackup encrypted backup',
    ja: '.asmbackup 暗号化バックアップを選択',
  ),
  '这是日历 .ics 文件，不包含可恢复的 Cardock 保险库；请选择 .asmbackup。': (
    en: 'This is an .ics calendar file and does not contain a restorable Cardock vault. Choose an .asmbackup file.',
    ja: 'これは .ics カレンダーファイルで、復元可能な Cardock 保管庫は含まれていません。.asmbackup を選択してください。',
  ),
  '这是外部表格或文档；请使用“导入外部数据”。恢复入口只接受 .asmbackup。': (
    en: 'This is an external table or document. Use “Import external data”; restore accepts only .asmbackup.',
    ja: 'これは外部の表または文書です。「外部データをインポート」を使用してください。復元では .asmbackup のみ受け付けます。',
  ),
  '所选文件不是可识别的 Cardock 加密备份；请选择 .asmbackup。': (
    en: 'The selected file is not a recognized Cardock encrypted backup. Choose an .asmbackup file.',
    ja: '選択したファイルは認識可能な Cardock 暗号化バックアップではありません。.asmbackup を選択してください。',
  ),
  '验证加密备份': (en: 'Verify encrypted backup', ja: '暗号化バックアップを検証'),
  '先只读验证格式、时间和数量，再验证当前主密码': (
    en: 'First verify the format, time, and counts without changing data, then verify the current master password',
    ja: 'まず形式、日時、件数を読み取り専用で確認し、その後に現在のマスターパスワードを確認します',
  ),
  '请输入创建这份备份时设置的独立备份密码。验证前不会修改本机数据。': (
    en: 'Enter the separate password set when this backup was created. Device data is not changed during verification.',
    ja: 'このバックアップの作成時に設定した専用パスワードを入力してください。検証中に端末のデータが変更されることはありません。',
  ),
  '无法读取所选备份文件。': (
    en: 'Could not read the selected backup file.',
    ja: '選択したバックアップファイルを読み込めませんでした。',
  ),
  '备份验证失败。': (en: 'Backup verification failed.', ja: 'バックアップの検証に失敗しました。'),
  '验证并恢复备份': (en: 'Verify and restore backup', ja: 'バックアップを検証して復元'),
  '生成 .asmbackup，使用独立备份密码。': (
    en: 'Creates an .asmbackup file with a separate backup password.',
    ja: '専用バックアップパスワードで .asmbackup を作成します。',
  ),
  '检查 Cardock 加密备份（不恢复）': (
    en: 'Check Cardock encrypted backup (no restore)',
    ja: 'Cardock 暗号化バックアップを確認（復元しない）',
  ),
  '重新选择 .asmbackup 并完整解密，不改变本机数据。': (
    en: 'Re-select and fully decrypt an .asmbackup without changing device data.',
    ja: '.asmbackup を選び直して完全に復号します。端末内データは変更しません。',
  ),
  '仅恢复 .asmbackup；恢复前仍需当前主密码和明确确认。': (
    en: 'Restores only .asmbackup; the current master password and explicit confirmation are still required.',
    ja: '.asmbackup のみ復元します。現在のマスターパスワードと明示的な確認が必要です。',
  ),
  '导出可读副本（非备份）': (
    en: 'Export readable copy (not a backup)',
    ja: '可読コピーを書き出す（バックアップではありません）',
  ),
  'CSV / JSON 为明文，不能用于恢复 Cardock。': (
    en: 'CSV / JSON is plaintext and cannot be used to restore Cardock.',
    ja: 'CSV / JSON は平文であり、Cardock の復元には使用できません。',
  ),
  '使用同一加密备份文件，不启用网络同步': (
    en: 'Uses the same encrypted backup file; no network sync',
    ja: '同じ暗号化バックアップファイルを使用し、ネットワーク同期は行いません',
  ),
  '确认覆盖本机记录': (en: 'Replace records on this device', ja: 'この端末の記録を置き換える'),
  '备份格式 v{format}，数据 schema {schema}{created}。\n备份包含 {backupAccounts} 个账号、{backupSubscriptions} 条订阅；本机当前有 {currentAccounts} 个账号、{currentSubscriptions} 条订阅。\n\n恢复会替换业务内容，但保留当前本机主密码、自动锁定和通知开关；写入前会先生成本机加密回滚副本。': (
    en: 'Backup format v{format}, data schema {schema}{created}.\nBackup — Account count: {backupAccounts}; subscription count: {backupSubscriptions}. This device — Account count: {currentAccounts}; subscription count: {currentSubscriptions}.\n\nRestoring replaces record content but keeps the current device master password, auto-lock setting, and notification toggle. Cardock creates an encrypted on-device rollback copy before writing.',
    ja: 'バックアップ形式 v{format}、データスキーマ {schema}{created}。\nバックアップにはアカウント{backupAccounts}件、サブスクリプション{backupSubscriptions}件が含まれています。この端末には現在、アカウント{currentAccounts}件、サブスクリプション{currentSubscriptions}件があります。\n\n復元すると記録内容は置き換わりますが、現在の端末のマスターパスワード、自動ロック、通知のオン／オフは維持されます。書き込み前に端末内の暗号化ロールバックコピーを作成します。',
  ),
  '备份格式 v{format}，数据 schema {schema}{created}。\n': (
    en: 'Backup format v{format}, data schema {schema}{created}.\n',
    ja: 'バックアップ形式 v{format}、データスキーマ {schema}{created}。\n',
  ),
  '备份包含 {backupAccounts} 个账号、{backupSubscriptions} 条订阅；本机当前有 ': (
    en: 'The backup contains {backupAccounts} accounts and {backupSubscriptions} subscriptions; this device currently has ',
    ja: 'バックアップにはアカウント{backupAccounts}件、サブスクリプション{backupSubscriptions}件が含まれています。この端末には現在、',
  ),
  '{currentAccounts} 个账号、{currentSubscriptions} 条订阅。\n\n': (
    en: '{currentAccounts} accounts and {currentSubscriptions} subscriptions.\n\n',
    ja: 'アカウント{currentAccounts}件、サブスクリプション{currentSubscriptions}件があります。\n\n',
  ),
  '恢复会替换业务内容，但保留当前本机主密码、自动锁定和通知开关；写入前会先生成本机加密回滚副本。': (
    en: 'Restoring replaces record content but keeps the current device master password, auto-lock setting, and notification toggle. Cardock creates an encrypted on-device rollback copy before writing.',
    ja: '復元すると記録内容は置き換わりますが、現在の端末のマスターパスワード、自動ロック、通知のオン／オフは維持されます。書き込み前に端末内の暗号化ロールバックコピーを作成します。',
  ),
  '，创建于 {time}': (en: ', created {time}', ja: '、作成日時 {time}'),
  '当前本机主密码': (en: 'Current device master password', ja: '現在の端末のマスターパスワード'),
  '输入“恢复”确认': (en: 'Type “Restore” to confirm', ja: '確認のため「復元」と入力'),
  '确认恢复': (en: 'Restore', ja: '復元する'),
  '恢复成功：已用当前本机主密码重新加密保存。': (
    en: 'Restore complete. The data was re-encrypted with the current device master password.',
    ja: '復元が完了しました。現在の端末のマスターパスワードで再暗号化して保存しました。',
  ),
  '恢复失败，本机原数据未被替换。': (
    en: 'Restore failed. The original data on this device was not replaced.',
    ja: '復元に失敗しました。この端末の元のデータは置き換えられていません。',
  ),
  '备份健康检查': (en: 'Backup health check', ja: 'バックアップの健全性確認'),
  '尚无已验证备份 · 点击选择文件做只读检查': (
    en: 'No verified backup yet · Tap to choose a file for a read-only check',
    ja: '検証済みのバックアップはありません · タップしてファイルを選び、読み取り専用で確認',
  ),
  '最近验证 {time} · 格式 v{version}': (
    en: 'Last verified {time} · Format v{version}',
    ja: '直近の検証 {time} · 形式 v{version}',
  ),
  '最近导出 {time} · 尚未重新读取验证': (
    en: 'Last exported {time} · Not read back and verified yet',
    ja: '直近の書き出し {time} · 再読み込み検証は未実施',
  ),
  '把 .asmbackup 文件复制到电脑即可离线保管；没有该备份的独立密码就无法读取内容。': (
    en: 'Copy the .asmbackup file to a PC for offline storage. Its contents cannot be read without the separate backup password.',
    ja: '.asmbackupファイルをPCへコピーしてオフライン保管できます。専用のバックアップパスワードがなければ内容を読み取れません。',
  ),
  '恢复到上次导入前': (en: 'Restore to before the last import', ja: '前回のインポート前に戻す'),
  '上次恢复结果未确认 · 加密回滚副本仍在': (
    en: 'Last restore is unconfirmed · Encrypted rollback copy is still available',
    ja: '前回の復元は未確認 · 暗号化ロールバックコピーを保持中',
  ),
  '本机加密回滚副本可用': (
    en: 'Encrypted on-device rollback copy available',
    ja: '端末内の暗号化ロールバックコピーを利用できます',
  ),
  '恢复到导入前的数据？': (
    en: 'Restore data from before the import?',
    ja: 'インポート前のデータへ戻しますか？',
  ),
  '这会用上次导入前自动保存的本机加密副本替换当前业务内容。当前主密码保持不变。': (
    en: 'This replaces the current record content with the encrypted on-device copy saved automatically before the last import. The current master password stays the same.',
    ja: '現在の記録内容を、前回のインポート前に自動保存した端末内の暗号化コピーで置き換えます。現在のマスターパスワードは変わりません。',
  ),
  '只有当前真实主密码才能使用恢复前回滚副本。': (
    en: 'Only the current real master password can use the pre-restore rollback copy.',
    ja: '復元前のロールバックコピーを使用できるのは、現在の実際のマスターパスワードだけです。',
  ),
  '已恢复到上次导入前的数据。': (
    en: 'Data from before the last import was restored.',
    ja: '前回のインポート前のデータに戻しました。',
  ),
  '回滚失败。': (en: 'Rollback failed.', ja: 'ロールバックに失敗しました。'),

  // Appearance, language, and product status.
  '外观与桌面图标': (en: 'Appearance and launcher icon', ja: '外観とランチャーアイコン'),
  '外观模式': (en: 'Appearance mode', ja: '外観モード'),
  '应用主题': (en: 'App theme', ja: 'アプリテーマ'),
  '主题': (en: 'Theme', ja: 'テーマ'),
  '编辑自定义配色': (en: 'Edit custom colors', ja: 'カスタム配色を編集'),
  '主题已应用。': (en: 'Theme applied.', ja: 'テーマを適用しました。'),
  '主题保存失败，已恢复之前的设置。': (
    en: 'Could not save the theme. The previous setting was restored.',
    ja: 'テーマを保存できませんでした。以前の設定に戻しました。',
  ),
  '外观模式保存失败，已恢复之前的设置。': (
    en: 'Could not save the appearance mode. The previous setting was restored.',
    ja: '外観モードを保存できませんでした。以前の設定に戻しました。',
  ),
  '{theme} · {brightness} · 桌面 {launcher}': (
    en: '{theme} · {brightness} · Launcher {launcher}',
    ja: '{theme} · {brightness} · ランチャー {launcher}',
  ),
  '{count} 项 · 未来30天待续费': (
    en: '{count} renewing in the next 30 days',
    ja: '今後30日以内の更新：{count}件',
  ),
  '桌面图标颜色': (en: 'Launcher icon color', ja: 'ランチャーアイコンの色'),
  '跟随→': (en: 'Follow theme →', ja: 'テーマ連動→'),
  '跟随主题 · 当前 {family}': (
    en: 'Follow theme · Currently {family}',
    ja: 'テーマに連動 · 現在は{family}',
  ),
  '固定为 {family}': (en: 'Fixed to {family}', ja: '{family}に固定'),
  '八套固定主题各自使用对应颜色的桌面图标': (
    en: 'Each of the eight preset themes uses its matching launcher icon color',
    ja: '8種類のプリセットテーマごとに対応するランチャーアイコンの色を使用します',
  ),
  '自定义主题使用已选的固定图标回退': (
    en: 'The custom theme uses the selected fixed icon as its fallback',
    ja: 'カスタムテーマでは、選択した固定アイコンをフォールバックとして使用します',
  ),
  '主题，{theme}': (en: 'Theme, {theme}', ja: 'テーマ、{theme}'),
  '主题，{theme}，完整版专属': (
    en: 'Theme, {theme}, Full Version only',
    ja: 'テーマ、{theme}、完全版限定',
  ),
  '桌面图标颜色，{family}': (
    en: 'Launcher icon color, {family}',
    ja: 'ランチャーアイコンの色、{family}',
  ),
  '瓷蓝与暖黄': (en: 'Ceramic blue and warm yellow', ja: 'セラミックブルーとウォームイエロー'),
  '樱粉与丁香': (en: 'Cherry pink and lilac', ja: 'サクラピンクとライラック'),
  '黑曜与鎏金': (en: 'Obsidian and gold', ja: 'オブシディアンとゴールド'),
  '薄荷与珊瑚': (en: 'Mint and coral', ja: 'ミントとコーラル'),
  '冰蓝与青色': (en: 'Ice blue and cyan', ja: 'アイスブルーとシアン'),
  '丁香与烟紫': (en: 'Lilac and smoky purple', ja: 'ライラックとスモーキーパープル'),
  '烧橙、橄榄与油墨': (en: 'Burnt orange, olive, and ink', ja: 'バーントオレンジ、オリーブ、インク'),
  '荧光绿与黑': (en: 'Neon green and black', ja: 'ネオングリーンとブラック'),
  '真实替换手机桌面图标。': (
    en: 'Changes the actual launcher icon. ',
    ja: '実際のランチャーアイコンを変更します。',
  ),
  ' 选择后由 Android 切换启动器入口；桌面图标可能需要几秒刷新。应用内 LOGO 自动跟随主题，不再独立选择。': (
    en: ' After you choose, Android switches the launcher entry. The icon may take a few seconds to refresh. The logo inside Cardock follows the theme automatically and is no longer selected separately.',
    ja: ' 選択するとAndroidがランチャーの入口を切り替えます。アイコンの更新には数秒かかる場合があります。Cardock内のロゴはテーマに自動で連動し、個別には選択しません。',
  ),
  ' 选择后由 Android 切换启动器入口；桌面图标可能需要几秒刷新。': (
    en: ' After you choose, Android switches the launcher entry. The icon may take a few seconds to refresh.',
    ja: ' 選択するとAndroidがランチャーの入口を切り替えます。アイコンの更新には数秒かかる場合があります。',
  ),
  '应用内 LOGO 自动跟随主题，不再独立选择。': (
    en: 'The logo inside Cardock follows the theme automatically and is no longer selected separately.',
    ja: 'Cardock内のロゴはテーマに自動で連動し、個別には選択しません。',
  ),
  '应用内品牌标志自动跟随主题。': (
    en: 'The in-app brand mark follows the theme automatically.',
    ja: 'アプリ内のブランドマークはテーマに自動で連動します。',
  ),
  '桌面图标将在几秒内更新': (
    en: 'The launcher icon will update in a few seconds',
    ja: 'ランチャーアイコンは数秒以内に更新されます',
  ),
  '桌面图标切换失败，已恢复之前的设置。': (
    en: 'Could not change the launcher icon. The previous setting was restored.',
    ja: 'ランチャーアイコンを変更できませんでした。以前の設定に戻しました。',
  ),
  '免费版 5 订阅 / 15 账户 · 一次购买，永久解锁': (
    en: 'Free: 5 subscriptions / 15 accounts · One-time purchase unlocks forever',
    ja: '無料版：サブスクリプション5件／アカウント15件 · 買い切りで永続アンロック',
  ),
  '仅在你自己的手机热点或可信私有无线网络使用。应用不会访问公网、云或中继；不要在公共或陌生 Wi-Fi 开启。\n\n'
      '连接前建议先在电脑打开浏览器无痕/隐私窗口，以减少常规浏览记录和站点数据残留；无痕模式仍不能保证电脑绝对不留痕。\n\n'
      '普通锁屏、返回 Home、切换应用或接听来电时，电脑连接会继续保留；Android 会显示一条不含账号、密码或订阅内容的低敏前台服务通知。\n\n'
      '保险库锁定后，电脑仍可继续填写尚未提交的内容；保存或导入会暂停，需回到卡坞并解锁手机后继续。\n\n'
      '只要应用进程仍在，正常使用中仅手机主动断开或所选连接时间到达会结束；划掉卡坞、强制停止、应用进程死亡或手机关机会使服务自然不可用。': (
    en: 'Use this only with your own phone hotspot or a trusted private Wi-Fi network. Cardock does not use the public internet, cloud services, or a relay. Do not enable it on public or unfamiliar Wi-Fi.\n\nBefore connecting, consider opening a private or incognito browser window on the PC to reduce ordinary history and site-data traces. Private browsing cannot guarantee that the PC leaves no trace.\n\nOrdinary screen locking, returning Home, switching apps, or taking a call keeps the PC connection alive. On Android, Cardock shows a low-sensitivity foreground-service notification that contains no account, password, or subscription details.\n\nIf the vault locks, you can keep typing unsubmitted content on the PC; saving or importing pauses until you return to Cardock and unlock the phone.\n\nWhile the app process remains alive, normal use ends the connection only when you disconnect on the phone or the selected duration expires. Swiping Cardock away, force-stopping it, process death, or powering off the phone makes the service unavailable.',
    ja: 'ご自身のスマートフォンのテザリング、または信頼できるプライベートWi-Fiでのみ使用してください。Cardockはインターネット、クラウド、中継サービスを利用しません。公共または不明なWi-Fiでは開始しないでください。\n\n接続前にPCのブラウザでシークレット／プライベートウィンドウを開くと、通常の閲覧履歴やサイトデータの残留を減らせます。ただし、PCに痕跡が一切残らないことを保証するものではありません。\n\n通常の画面ロック、ホーム画面への移動、アプリの切り替え、着信への応答では、PCとの接続は維持されます。Androidでは、アカウント、パスワード、サブスクリプションの内容を含まない機密性の低いフォアグラウンドサービス通知が表示されます。\n\n保管庫がロックされても、PCでは未送信の内容を引き続き入力できます。保存またはインポートは一時停止し、Cardockに戻ってスマートフォンをアンロックすると続行できます。\n\nアプリのプロセスが動作している間、通常の使用で接続が終了するのは、スマートフォンで切断した場合または選択した接続時間が終了した場合だけです。Cardockをタスクから終了する、強制停止する、プロセスが終了する、またはスマートフォンの電源を切ると、サービスは利用できなくなります。',
  ),
  '普通锁屏、返回 Home、切换应用或接听来电时，电脑连接会继续保留；Android 会显示一条不含账号、密码或订阅内容的低敏前台服务通知。\n\n'
      '保险库锁定后，电脑仍可继续填写尚未提交的内容；保存或导入会暂停，需回到卡坞并解锁手机后继续。\n\n'
      '只要应用进程仍在，正常使用中仅手机主动断开或所选连接时间到达会结束；划掉卡坞、强制停止、应用进程死亡或手机关机会使服务自然不可用。': (
    en: 'Ordinary screen locking, returning Home, switching apps, or taking a call keeps the PC connection alive. On Android, Cardock shows a low-sensitivity foreground-service notification that contains no account, password, or subscription details.\n\nIf the vault locks, you can keep typing unsubmitted content on the PC; saving or importing pauses until you return to Cardock and unlock the phone.\n\nWhile the app process remains alive, normal use ends the connection only when you disconnect on the phone or the selected duration expires. Swiping Cardock away, force-stopping it, process death, or powering off the phone makes the service unavailable.',
    ja: '通常の画面ロック、ホーム画面への移動、アプリの切り替え、着信への応答では、PCとの接続は維持されます。Androidでは、アカウント、パスワード、サブスクリプションの内容を含まない機密性の低いフォアグラウンドサービス通知が表示されます。\n\n保管庫がロックされても、PCでは未送信の内容を引き続き入力できます。保存またはインポートは一時停止し、Cardockに戻ってスマートフォンをアンロックすると続行できます。\n\nアプリのプロセスが動作している間、通常の使用で接続が終了するのは、スマートフォンで切断した場合または選択した接続時間が終了した場合だけです。Cardockをタスクから終了する、強制停止する、プロセスが終了する、またはスマートフォンの電源を切ると、サービスは利用できなくなります。',
  ),
  '连接时间': (en: 'Connection duration', ja: '接続時間'),
  '本次连接持续时间': (en: 'Duration of this connection', ja: '今回の接続時間'),
  '可选 1/5/10/30 分钟，默认 5 分钟；从开启服务时开始计时': (
    en: 'Choose 1, 5, 10, or 30 minutes. The default is 5 minutes, counted from when the service starts.',
    ja: '1／5／10／30分から選択できます。初期値は5分で、サービス開始時から計測します。',
  ),
  '电脑网页正在等待你的决定。请核对下面内容后直接批准或拒绝。': (
    en: 'The PC web page is waiting for your decision. Review the details below, then approve or reject it here.',
    ja: 'PCのWebページが判断を待っています。以下の内容を確認し、ここで許可または拒否してください。',
  ),
  '手机锁屏、Home 或切到后台不会主动结束连接；需要立即结束请点“主动断开”。': (
    en: 'Locking the phone, returning Home, or moving Cardock to the background does not end the connection. Tap Disconnect to end it now.',
    ja: '画面ロック、ホーム画面への移動、バックグラウンドへの切り替えでは接続は終了しません。すぐ終了するには「切断」を押してください。',
  ),
  '本次连接还剩 {remaining}，到时自动断开': (
    en: 'This connection has {remaining} remaining and will disconnect automatically.',
    ja: 'この接続の残り時間は{remaining}です。終了時に自動で切断します。',
  ),
  '继续验证': (en: 'Continue verification', ja: '検証を続ける'),
  '确认': (en: 'Confirm', ja: '確認'),
};

final Map<String, String> settingsEnglishTranslations =
    Map<String, String>.unmodifiable(<String, String>{
      for (final entry in _settingsTranslations.entries)
        entry.key: entry.value.en,
    });

final Map<String, String> settingsJapaneseTranslations =
    Map<String, String>.unmodifiable(<String, String>{
      for (final entry in _settingsTranslations.entries)
        entry.key: entry.value.ja,
    });
