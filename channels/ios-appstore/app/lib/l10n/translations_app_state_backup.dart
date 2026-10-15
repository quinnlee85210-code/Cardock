const Map<String, String> appStateBackupEnglishTranslations = <String, String>{
  '该加密库由更高版本应用创建；本版本已停止生物识别解锁，请升级应用。':
      'This vault was created by a newer app version. Biometric unlock is disabled in this version; update Cardock.',
  '该数据由更高版本应用写入；本版本已停止生物识别解锁，请升级应用。':
      'This data was written by a newer app version. Biometric unlock is disabled in this version; update Cardock.',
  '该加密库使用本版本不支持的密钥派生参数；本版本已停止生物识别解锁。':
      'This vault uses key-derivation settings that this version does not support. Biometric unlock is disabled.',
  '生物识别未完成或密钥已失效，请使用主密码解锁。':
      'Biometric authentication was not completed or its key is no longer valid. Unlock with the master password.',
  '备份密码强度不足。': 'The backup password is not strong enough.',
  '无法生成加密备份文件。': 'The encrypted backup could not be created.',
  '备份密码错误，或文件已经损坏、被篡改。':
      'The backup password is incorrect, or the file is damaged or has been tampered with.',
  '备份文件格式无效、损坏或来自未来版本。':
      'The backup has an invalid format, is damaged, or comes from a future version.',
  '无法读取加密备份。': 'The encrypted backup could not be read.',
  '数据已写入，但恢复事务状态未能确认；加密回滚副本仍保留，请重新解锁核对。':
      'Data was written, but the restore transaction could not be confirmed. The encrypted rollback copy remains; unlock again and verify the data.',
  '加密备份已恢复，当前主密码和本机安全设置保持不变；订阅快捷视图同步失败，生物识别已停用。':
      'The encrypted backup was restored. The current master password and on-device security settings remain unchanged. Subscription quick-view sync failed, so biometric unlock is off.',
  '加密备份已恢复；当前主密码和本机安全设置保持不变，并已保留恢复前加密回滚副本。':
      'The encrypted backup was restored. The current master password and on-device security settings remain unchanged, and an encrypted pre-restore rollback copy was retained.',
  '加密备份已恢复；当前主密码和本机安全设置保持不变。系统提醒同步失败，应用内日期仍为准。':
      'The encrypted backup was restored, and the current master password and on-device security settings remain unchanged. System reminder sync failed; dates shown in Cardock remain authoritative.',
  '当前本机主密码不正确。': 'The current master password for this device is incorrect.',
  '恢复失败；尚未开始替换本机数据。': 'Restore failed before any on-device data was replaced.',
  '恢复结果未能确认；恢复前加密回滚副本已保留，请重新解锁核对。':
      'The restore result could not be confirmed. An encrypted pre-restore rollback copy was retained; unlock again and verify the data.',
  '没有可用的恢复前回滚副本。': 'No pre-restore rollback copy is available.',
  '已恢复到上次导入前的数据，但回滚事务状态未能确认；当前数据已生效，请重新解锁核对。':
      'Data from before the last import was restored, but the rollback transaction could not be confirmed. The restored data is active; unlock again and verify it.',
  '已恢复到上次导入前的数据；订阅快捷视图同步失败，生物识别已安全停用。':
      'Data from before the last import was restored. Subscription quick-view sync failed, so biometric unlock was safely disabled.',
  '已恢复到上次导入前的数据。': 'Data from before the last import was restored.',
  '无法使用恢复前回滚副本；当前数据未被确认替换。':
      'The pre-restore rollback copy could not be used. Current data was not confirmed as replaced.',
  '记录已保存，但订阅快捷视图未能同步；生物识别已安全停用，请用主密码重新启用。':
      'The record was saved, but the subscription quick view could not be synchronized. Biometric unlock was safely disabled; use the master password to enable it again.',
  '记录已安全保存，但系统提醒同步失败；应用内日期仍为准。':
      'The record was saved securely, but system reminder sync failed. Dates shown in Cardock remain authoritative.',
  '记录已安全保存，但提醒协调状态无法确认；请在通知可靠性页面重新同步。':
      'The record was saved securely, but the reminder reconciliation state could not be confirmed. Resynchronize reminders from Notification reliability.',
  '系统提醒已同步，但待协调状态未能清除；后续重试使用固定提醒编号，不会创建重复提醒。':
      'System reminders were synchronized, but the pending reconciliation state could not be cleared. Later retries use stable reminder IDs and will not create duplicate reminders.',
  '无法保存提醒待协调状态；业务数据未改变，请稍后重试。':
      'The pending reminder reconciliation state could not be saved. Business data was not changed; try again later.',
  '已取消生物识别。': 'Biometric authentication was canceled.',
  '生物识别已超时，请重试。': 'Biometric authentication timed out. Try again.',
  '生物识别暂时锁定，请稍后重试。':
      'Biometric authentication is temporarily locked. Try again later.',
  '生物识别已锁定，请先解锁手机后重试。':
      'Biometric authentication is locked. Unlock the phone first, then try again.',
  '生物识别硬件暂时不可用，请稍后重试。':
      'Biometric hardware is temporarily unavailable. Try again later.',
  '系统中没有可用的强生物识别。': 'No supported strong biometric is enrolled in the system.',
  '系统已暂时停用生物识别传感器，请先完成手机系统安全更新。':
      'The system has temporarily disabled the biometric sensor. Complete the phone’s system security update first.',
  '本机系统不支持当前强生物识别配置。':
      'This device does not support the required strong-biometric configuration.',
  '系统暂时无法确认指纹状态，请保持手机解锁后重试。':
      'The system cannot confirm fingerprint status right now. Keep the phone unlocked and try again.',
  '应用状态发生变化，生物识别已取消，请重试。':
      'Biometric authentication was canceled because the app state changed. Try again.',
  '系统指纹验证界面暂时无法启动，请保持应用在前台后重试。':
      'The system fingerprint prompt could not start. Keep Cardock in the foreground and try again.',
  '本机安全密钥初始化失败，请先用手机锁屏密码解锁设备后重试。':
      'The on-device security key could not be initialized. Unlock the phone with its screen-lock credential, then try again.',
  '快速解锁密钥已失效，请使用主密码重新启用。':
      'The quick-unlock key is no longer valid. Use the master password to enable it again.',
  '未能启用生物识别，请确认系统生物识别可用。':
      'Biometric unlock could not be enabled. Make sure system biometrics are available.',
  '生物识别未完成，请使用主密码解锁。':
      'Biometric authentication was not completed. Unlock with the master password.',
  '已从上一份有效数据恢复，最近一次更改可能未保留。':
      'Cardock recovered the previous valid data. The most recent change may not have been retained.',
  '检测到上次恢复事务可能中断；结果尚未确认，加密回滚副本仍保留。请先核对当前数据。':
      'The last restore transaction may have been interrupted. Its result is unconfirmed, and the encrypted rollback copy remains. Verify the current data first.',
  '恢复回滚状态无法验证；在核对数据前请勿再次导入备份。':
      'The restore rollback state could not be verified. Do not import another backup until you have checked the data.',
  '已取消本机系统强认证，密码恢复未执行。':
      'Strong system authentication was canceled. Password recovery was not performed.',
  '本机尚未录入可用的强指纹或安全级人脸，不能启用或使用密码恢复。':
      'No supported strong fingerprint or secure face is enrolled on this device, so password recovery cannot be enabled or used.',
  '系统生物识别暂时锁定，请按系统提示稍后重试；不会降级为只验证密保答案。':
      'System biometrics are temporarily locked. Follow the system guidance and try again later. Recovery will not fall back to security answers alone.',
  '本机没有可用的强生物识别能力，只能继续使用主密码或独立加密备份。':
      'No supported strong biometric is available on this device. Continue with the master password or a separate encrypted backup.',
  '本机恢复设备密钥已失效或不存在，不能只靠三道密保答案恢复。':
      'The on-device recovery key is missing or no longer valid. The three security answers alone cannot recover the vault.',
  '系统强认证未完成，密码恢复未执行。':
      'Strong system authentication was not completed. Password recovery was not performed.',
};

const Map<String, String> appStateBackupJapaneseTranslations = <String, String>{
  '该加密库由更高版本应用创建；本版本已停止生物识别解锁，请升级应用。':
      'この保管庫は新しいバージョンのアプリで作成されています。このバージョンでは生体認証によるロック解除を停止しています。Cardockを更新してください。',
  '该数据由更高版本应用写入；本版本已停止生物识别解锁，请升级应用。':
      'このデータは新しいバージョンのアプリで書き込まれています。このバージョンでは生体認証によるロック解除を停止しています。Cardockを更新してください。',
  '该加密库使用本版本不支持的密钥派生参数；本版本已停止生物识别解锁。':
      'この保管庫は、このバージョンが対応していない鍵導出設定を使用しています。生体認証によるロック解除は停止しています。',
  '生物识别未完成或密钥已失效，请使用主密码解锁。': '生体認証が完了していないか、鍵が無効です。マスターパスワードでロックを解除してください。',
  '备份密码强度不足。': 'バックアップパスワードの強度が不足しています。',
  '无法生成加密备份文件。': '暗号化バックアップを作成できませんでした。',
  '备份密码错误，或文件已经损坏、被篡改。': 'バックアップパスワードが正しくないか、ファイルが破損または改ざんされています。',
  '备份文件格式无效、损坏或来自未来版本。': 'バックアップの形式が無効、ファイルが破損、または将来のバージョンで作成されています。',
  '无法读取加密备份。': '暗号化バックアップを読み込めませんでした。',
  '数据已写入，但恢复事务状态未能确认；加密回滚副本仍保留，请重新解锁核对。':
      'データを書き込みましたが、復元処理を確認できませんでした。暗号化ロールバックコピーは保持されています。再度ロックを解除してデータを確認してください。',
  '加密备份已恢复，当前主密码和本机安全设置保持不变；订阅快捷视图同步失败，生物识别已停用。':
      '暗号化バックアップを復元しました。現在のマスターパスワードと端末内セキュリティ設定は変更されていません。サブスクリプションのクイック表示を同期できなかったため、生体認証はオフです。',
  '加密备份已恢复；当前主密码和本机安全设置保持不变，并已保留恢复前加密回滚副本。':
      '暗号化バックアップを復元しました。現在のマスターパスワードと端末内セキュリティ設定は変更されておらず、復元前の暗号化ロールバックコピーを保持しています。',
  '加密备份已恢复；当前主密码和本机安全设置保持不变。系统提醒同步失败，应用内日期仍为准。':
      '暗号化バックアップを復元しました。現在のマスターパスワードと端末内セキュリティ設定は変更されていません。システム通知の同期に失敗したため、Cardock内の日付を基準にしてください。',
  '当前本机主密码不正确。': 'この端末の現在のマスターパスワードが正しくありません。',
  '恢复失败；尚未开始替换本机数据。': '端末内データの置き換えを開始する前に復元が失敗しました。',
  '恢复结果未能确认；恢复前加密回滚副本已保留，请重新解锁核对。':
      '復元結果を確認できませんでした。復元前の暗号化ロールバックコピーは保持されています。再度ロックを解除して確認してください。',
  '没有可用的恢复前回滚副本。': '利用できる復元前ロールバックコピーがありません。',
  '已恢复到上次导入前的数据，但回滚事务状态未能确认；当前数据已生效，请重新解锁核对。':
      '前回のインポート前のデータに戻しましたが、ロールバック処理を確認できませんでした。復元したデータは有効です。再度ロックを解除して確認してください。',
  '已恢复到上次导入前的数据；订阅快捷视图同步失败，生物识别已安全停用。':
      '前回のインポート前のデータに戻しました。サブスクリプションのクイック表示を同期できなかったため、生体認証を安全のため無効にしました。',
  '已恢复到上次导入前的数据。': '前回のインポート前のデータに戻しました。',
  '无法使用恢复前回滚副本；当前数据未被确认替换。':
      '復元前ロールバックコピーを使用できませんでした。現在のデータが置き換えられたことは確認されていません。',
  '记录已保存，但订阅快捷视图未能同步；生物识别已安全停用，请用主密码重新启用。':
      '記録を保存しましたが、サブスクリプションのクイック表示を同期できませんでした。生体認証は安全のため無効にしました。マスターパスワードで再度有効にしてください。',
  '记录已安全保存，但系统提醒同步失败；应用内日期仍为准。':
      '記録は安全に保存されましたが、システム通知を同期できませんでした。Cardock内の日付を基準にしてください。',
  '记录已安全保存，但提醒协调状态无法确认；请在通知可靠性页面重新同步。':
      '記録は安全に保存されましたが、リマインダー同期状態を確認できませんでした。通知の信頼性ページからリマインダーを再同期してください。',
  '系统提醒已同步，但待协调状态未能清除；后续重试使用固定提醒编号，不会创建重复提醒。':
      'システムのリマインダーは同期されましたが、保留中の同期状態を消去できませんでした。以後の再試行では固定のリマインダーIDを使用するため、重複するリマインダーは作成されません。',
  '无法保存提醒待协调状态；业务数据未改变，请稍后重试。':
      '保留中のリマインダー同期状態を保存できませんでした。業務データは変更されていません。後でもう一度お試しください。',
  '已取消生物识别。': '生体認証をキャンセルしました。',
  '生物识别已超时，请重试。': '生体認証がタイムアウトしました。もう一度お試しください。',
  '生物识别暂时锁定，请稍后重试。': '生体認証は一時的にロックされています。しばらくしてから再試行してください。',
  '生物识别已锁定，请先解锁手机后重试。': '生体認証がロックされています。先に端末のロックを解除してから再試行してください。',
  '生物识别硬件暂时不可用，请稍后重试。': '生体認証ハードウェアは一時的に利用できません。しばらくしてから再試行してください。',
  '系统中没有可用的强生物识别。': 'システムに対応する強力な生体認証が登録されていません。',
  '系统已暂时停用生物识别传感器，请先完成手机系统安全更新。':
      'システムが生体認証センサーを一時的に無効にしています。先に端末のシステムセキュリティ更新を完了してください。',
  '本机系统不支持当前强生物识别配置。': 'この端末は必要な強力な生体認証設定に対応していません。',
  '系统暂时无法确认指纹状态，请保持手机解锁后重试。': '指紋の状態を確認できませんでした。端末のロックを解除したまま再試行してください。',
  '应用状态发生变化，生物识别已取消，请重试。': 'アプリの状態が変化したため、生体認証をキャンセルしました。もう一度お試しください。',
  '系统指纹验证界面暂时无法启动，请保持应用在前台后重试。':
      'システムの指紋認証画面を開始できませんでした。Cardockを前面に表示したまま再試行してください。',
  '本机安全密钥初始化失败，请先用手机锁屏密码解锁设备后重试。':
      '端末内セキュリティ鍵を初期化できませんでした。端末の画面ロック用認証情報でロックを解除してから再試行してください。',
  '快速解锁密钥已失效，请使用主密码重新启用。': 'クイックロック解除用の鍵が無効です。マスターパスワードで再度有効にしてください。',
  '未能启用生物识别，请确认系统生物识别可用。': '生体認証を有効にできませんでした。システムの生体認証が利用可能か確認してください。',
  '生物识别未完成，请使用主密码解锁。': '生体認証が完了しませんでした。マスターパスワードでロックを解除してください。',
  '已从上一份有效数据恢复，最近一次更改可能未保留。': '直前の有効なデータから復旧しました。最新の変更は保持されていない可能性があります。',
  '检测到上次恢复事务可能中断；结果尚未确认，加密回滚副本仍保留。请先核对当前数据。':
      '前回の復元処理が中断した可能性があります。結果は未確認で、暗号化ロールバックコピーは保持されています。先に現在のデータを確認してください。',
  '恢复回滚状态无法验证；在核对数据前请勿再次导入备份。':
      '復元ロールバック状態を確認できませんでした。データを確認するまで別のバックアップをインポートしないでください。',
  '已取消本机系统强认证，密码恢复未执行。': 'システムの強力な認証をキャンセルしました。パスワード復旧は実行していません。',
  '本机尚未录入可用的强指纹或安全级人脸，不能启用或使用密码恢复。':
      'この端末には対応する強力な指紋または安全な顔認証が登録されていないため、パスワード復旧を有効化または使用できません。',
  '系统生物识别暂时锁定，请按系统提示稍后重试；不会降级为只验证密保答案。':
      'システムの生体認証は一時的にロックされています。システムの案内に従って後で再試行してください。秘密の質問の回答だけでの確認には切り替わりません。',
  '本机没有可用的强生物识别能力，只能继续使用主密码或独立加密备份。':
      'この端末では対応する強力な生体認証を利用できません。マスターパスワードまたは独立した暗号化バックアップを使用してください。',
  '本机恢复设备密钥已失效或不存在，不能只靠三道密保答案恢复。':
      '端末内の復旧鍵が無効または存在しません。3つの秘密の質問の回答だけでは保管庫を復旧できません。',
  '系统强认证未完成，密码恢复未执行。': 'システムの強力な認証が完了しませんでした。パスワード復旧は実行していません。',
};
