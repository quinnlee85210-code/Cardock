const Map<String, String> appStateGeneralEnglishTranslations = <String, String>{
  '无法验证本机安全计时状态；主密码输入已暂停，可继续使用已配置的生物识别。':
      'The secure device timer could not be verified. Master-password entry is paused, but configured biometric unlock remains available.',
  '无法访问本机加密存储。': 'The encrypted on-device storage could not be accessed.',
  '本机已存在加密库，请使用主密码解锁。':
      'An encrypted vault already exists on this device. Unlock it with the master password.',
  '主密码长度必须为12到128个字符。': 'The master password must be 12–128 characters.',
  '无法创建本机加密库，请稍后重试。':
      'The encrypted on-device vault could not be created. Try again later.',
  '主密码输入正在冷却，请等待{duration}后继续尝试；本机数据不会清空、锁死或删除。':
      'Master password entry is temporarily unavailable. Try again in {duration}. On-device data will not be erased, permanently locked, or deleted.',
  '主密码已验证，但安全计数状态暂时无法持久化；重新锁定后请优先使用生物识别。':
      'The master password was verified, but the security counter could not be saved. After locking again, use biometric unlock first.',
  '加密数据完整性验证失败；本次不计入密码错误次数。':
      'Encrypted-data integrity verification failed. This attempt does not count as an incorrect password.',
  '该加密库由更高版本应用创建；为防止数据降级覆盖，本版本已停止打开。':
      'This vault was created by a newer app version. This version will not open it, preventing an older format from overwriting data.',
  '该数据由更高版本应用写入；为防止数据降级覆盖，本版本已停止打开。':
      'This data was written by a newer app version. This version will not open it, preventing an older format from overwriting data.',
  '该加密库使用本版本不支持的密钥派生参数；为防止降级覆盖，本版本已停止打开。':
      'This vault uses key-derivation settings that this app version does not support. It will remain closed to prevent a downgrade overwrite.',
  '加密数据格式或完整性验证失败；本次不计入密码错误次数。':
      'The encrypted-data format or integrity check failed. This attempt does not count as an incorrect password.',
  '无法读取本机加密库。': 'The encrypted on-device vault could not be read.',
  '主密码已连续输错{count}次，请等待{duration}后继续尝试；本机数据不会清空、锁死或删除。':
      'The master password was entered incorrectly {count} times. Try again in {duration}. On-device data will not be erased, permanently locked, or deleted.',
  '主密码不正确，本轮还可尝试{count}次；连续输错5次后将开始30秒冷却，本机数据不会被删除。':
      'The master password is incorrect. {count} attempts remain before a 30-second cooldown begins. On-device data will not be deleted.',
  '账号及订阅记录未能写入本机加密库。':
      'The account and subscription records could not be saved to the encrypted on-device vault.',
  '账号或订阅内容无效，请检查后重试。':
      'The account or subscription contains invalid information. Check it and try again.',
  '关联账号不存在，订阅记录未保存。':
      'The linked account no longer exists. The subscription was not saved.',
  '订阅记录未能写入本机加密库。':
      'The subscription could not be saved to the encrypted on-device vault.',
  '订阅内容无效，请检查后重试。':
      'The subscription contains invalid information. Check it and try again.',
  '订阅记录或关联账号不存在。': 'The subscription or its linked account no longer exists.',
  '订阅修改未能写入本机加密库。':
      'The subscription changes could not be saved to the encrypted on-device vault.',
  '订阅记录不存在。': 'The subscription no longer exists.',
  '订阅删除未能写入本机加密库。':
      'The subscription deletion could not be saved to the encrypted on-device vault.',
  '续费日期未能写入本机加密库。':
      'The renewal date could not be saved to the encrypted on-device vault.',
  '延后提醒未能写入本机加密库。':
      'The postponed reminder could not be saved to the encrypted on-device vault.',
  '取消状态未能写入本机加密库。':
      'The cancellation status could not be saved to the encrypted on-device vault.',
  '订阅恢复状态未能写入本机加密库。':
      'The reactivation status could not be saved to the encrypted on-device vault.',
  '订阅操作无效，请检查记录状态。':
      'This action is not valid for the subscription’s current status.',
  '账号记录不存在。': 'The account no longer exists.',
  '请输入要替换的新密码。': 'Enter the replacement password.',
  '账号修改未能写入本机加密库。':
      'The account changes could not be saved to the encrypted on-device vault.',
  '账号内容无效，请检查后重试。':
      'The account contains invalid information. Check it and try again.',
  '账号删除未能写入本机加密库。':
      'The account deletion could not be saved to the encrypted on-device vault.',
  '最近查看记录未能写入本机加密库。':
      'The recently viewed state could not be saved to the encrypted on-device vault.',
  '设置未能写入本机加密库。':
      'The settings could not be saved to the encrypted on-device vault.',
  '设置内容无效。': 'The settings contain an invalid value.',
  '无法取得系统通知权限。': 'System notification permission could not be requested.',
  '无法检查系统通知状态。': 'The system notification status could not be checked.',
  '通知设置内容无效。': 'The notification settings contain an invalid value.',
  '设置已保存，但订阅快捷视图未能同步；生物识别已安全停用，请用主密码重新启用。':
      'Settings were saved, but the subscription quick view could not be synchronized. Biometric unlock was safely disabled; use the master password to enable it again.',
  '通知设置已保存为开启，但系统通知初始化失败；请使用设置页测试功能重试。':
      'Notifications were turned on, but system notification setup failed. Use the test action in Settings to try again.',
  '通知设置已保存为开启，但部分提醒重排失败；下次解锁会重试。':
      'Notifications were turned on, but some reminders could not be rescheduled. Cardock will retry after the next unlock.',
  '通知设置已保存为关闭，但旧提醒清理失败；下次解锁会重试。':
      'Notifications were turned off, but some old reminders could not be removed. Cardock will retry after the next unlock.',
  '通知设置未能写入本机加密库。':
      'The notification settings could not be saved to the encrypted on-device vault.',
  '当前主密码不正确。': 'The current master password is incorrect.',
  '无法验证当前主密码。': 'The current master password could not be verified.',
  '未能启用生物识别，请确认已录入可用的指纹或人脸。':
      'Biometric unlock could not be enabled. Make sure a supported fingerprint or face is enrolled.',
  '未能关闭生物识别快速解锁。': 'Biometric quick unlock could not be turned off.',
};

const Map<String, String>
appStateGeneralJapaneseTranslations = <String, String>{
  '无法验证本机安全计时状态；主密码输入已暂停，可继续使用已配置的生物识别。':
      '端末の安全なタイマー状態を確認できませんでした。マスターパスワードの入力は一時停止していますが、設定済みの生体認証は引き続き使用できます。',
  '无法访问本机加密存储。': '端末内の暗号化ストレージにアクセスできませんでした。',
  '本机已存在加密库，请使用主密码解锁。': 'この端末には暗号化保管庫があります。マスターパスワードでロックを解除してください。',
  '主密码长度必须为12到128个字符。': 'マスターパスワードは12～128文字にしてください。',
  '无法创建本机加密库，请稍后重试。': '端末内に暗号化保管庫を作成できませんでした。しばらくしてから再試行してください。',
  '主密码输入正在冷却，请等待{duration}后继续尝试；本机数据不会清空、锁死或删除。':
      'マスターパスワード入力の待機時間中です。{duration}後に再試行してください。端末内データが消去、永久ロック、削除されることはありません。',
  '主密码已验证，但安全计数状态暂时无法持久化；重新锁定后请优先使用生物识别。':
      'マスターパスワードを確認しましたが、セキュリティカウンターを保存できませんでした。再度ロックした後は、先に生体認証を使用してください。',
  '加密数据完整性验证失败；本次不计入密码错误次数。': '暗号化データの整合性を確認できませんでした。この試行はパスワード誤入力として数えません。',
  '该加密库由更高版本应用创建；为防止数据降级覆盖，本版本已停止打开。':
      'この保管庫は新しいバージョンのアプリで作成されています。古い形式による上書きを防ぐため、このバージョンでは開きません。',
  '该数据由更高版本应用写入；为防止数据降级覆盖，本版本已停止打开。':
      'このデータは新しいバージョンのアプリで書き込まれています。古い形式による上書きを防ぐため、このバージョンでは開きません。',
  '该加密库使用本版本不支持的密钥派生参数；为防止降级覆盖，本版本已停止打开。':
      'この保管庫は、このバージョンが対応していない鍵導出設定を使用しています。古い形式で上書きしないよう、保管庫を開きません。',
  '加密数据格式或完整性验证失败；本次不计入密码错误次数。':
      '暗号化データの形式または整合性を確認できませんでした。この試行はパスワード誤入力として数えません。',
  '无法读取本机加密库。': '端末内の暗号化保管庫を読み込めませんでした。',
  '主密码已连续输错{count}次，请等待{duration}后继续尝试；本机数据不会清空、锁死或删除。':
      'マスターパスワードを{count}回連続で誤入力しました。{duration}後に再試行してください。端末内データが消去、永久ロック、削除されることはありません。',
  '主密码不正确，本轮还可尝试{count}次；连续输错5次后将开始30秒冷却，本机数据不会被删除。':
      'マスターパスワードが正しくありません。あと{count}回入力できます。5回連続で誤入力すると30秒間の待機時間が始まります。端末内データは削除されません。',
  '账号及订阅记录未能写入本机加密库。': 'アカウントとサブスクリプションを端末内の暗号化保管庫に保存できませんでした。',
  '账号或订阅内容无效，请检查后重试。': 'アカウントまたはサブスクリプションの内容が無効です。確認して再試行してください。',
  '关联账号不存在，订阅记录未保存。': '関連付けたアカウントが存在しないため、サブスクリプションを保存しませんでした。',
  '订阅记录未能写入本机加密库。': 'サブスクリプションを端末内の暗号化保管庫に保存できませんでした。',
  '订阅内容无效，请检查后重试。': 'サブスクリプションの内容が無効です。確認して再試行してください。',
  '订阅记录或关联账号不存在。': 'サブスクリプションまたは関連アカウントが存在しません。',
  '订阅修改未能写入本机加密库。': 'サブスクリプションの変更を端末内の暗号化保管庫に保存できませんでした。',
  '订阅记录不存在。': 'サブスクリプションが存在しません。',
  '订阅删除未能写入本机加密库。': 'サブスクリプションの削除を端末内の暗号化保管庫に保存できませんでした。',
  '续费日期未能写入本机加密库。': '更新日を端末内の暗号化保管庫に保存できませんでした。',
  '延后提醒未能写入本机加密库。': '延期した通知を端末内の暗号化保管庫に保存できませんでした。',
  '取消状态未能写入本机加密库。': '解約状態を端末内の暗号化保管庫に保存できませんでした。',
  '订阅恢复状态未能写入本机加密库。': '再開状態を端末内の暗号化保管庫に保存できませんでした。',
  '订阅操作无效，请检查记录状态。': '現在のサブスクリプション状態ではこの操作を実行できません。',
  '账号记录不存在。': 'アカウントが存在しません。',
  '请输入要替换的新密码。': '置き換える新しいパスワードを入力してください。',
  '账号修改未能写入本机加密库。': 'アカウントの変更を端末内の暗号化保管庫に保存できませんでした。',
  '账号内容无效，请检查后重试。': 'アカウントの内容が無効です。確認して再試行してください。',
  '账号删除未能写入本机加密库。': 'アカウントの削除を端末内の暗号化保管庫に保存できませんでした。',
  '最近查看记录未能写入本机加密库。': '最近表示した状態を端末内の暗号化保管庫に保存できませんでした。',
  '设置未能写入本机加密库。': '設定を端末内の暗号化保管庫に保存できませんでした。',
  '设置内容无效。': '設定に無効な値があります。',
  '无法取得系统通知权限。': 'システムの通知権限を要求できませんでした。',
  '无法检查系统通知状态。': 'システムの通知状態を確認できませんでした。',
  '通知设置内容无效。': '通知設定に無効な値があります。',
  '设置已保存，但订阅快捷视图未能同步；生物识别已安全停用，请用主密码重新启用。':
      '設定を保存しましたが、サブスクリプションのクイック表示を同期できませんでした。生体認証は安全のため無効にしました。マスターパスワードで再度有効にしてください。',
  '通知设置已保存为开启，但系统通知初始化失败；请使用设置页测试功能重试。':
      '通知をオンにしましたが、システム通知を初期化できませんでした。設定画面のテスト機能で再試行してください。',
  '通知设置已保存为开启，但部分提醒重排失败；下次解锁会重试。':
      '通知をオンにしましたが、一部の通知を再登録できませんでした。次回のロック解除後に再試行します。',
  '通知设置已保存为关闭，但旧提醒清理失败；下次解锁会重试。':
      '通知をオフにしましたが、古い通知の一部を削除できませんでした。次回のロック解除後に再試行します。',
  '通知设置未能写入本机加密库。': '通知設定を端末内の暗号化保管庫に保存できませんでした。',
  '当前主密码不正确。': '現在のマスターパスワードが正しくありません。',
  '无法验证当前主密码。': '現在のマスターパスワードを確認できませんでした。',
  '未能启用生物识别，请确认已录入可用的指纹或人脸。': '生体認証を有効にできませんでした。対応する指紋または顔が登録されていることを確認してください。',
  '未能关闭生物识别快速解锁。': '生体認証によるクイックロック解除をオフにできませんでした。',
};
