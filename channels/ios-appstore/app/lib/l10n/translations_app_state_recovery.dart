const Map<String, String>
appStateRecoveryEnglishTranslations = <String, String>{
  '上一次系统验证仍在结束，请稍后重试；原密码和保险库数据未修改。':
      'The previous system authentication is still finishing. Try again shortly; the existing password and vault data were not changed.',
  '本机恢复密钥暂时无法访问，密保操作未完成；原密码和保险库数据未修改。':
      'The recovery key on this device could not be accessed. The recovery operation was not completed; the existing password and vault data were not changed.',
  '系统验证已中断，密保操作未完成。请保持应用在前台重试。':
      'System authentication was interrupted. The recovery operation was not completed. Keep Cardock in the foreground and try again.',
  '系统验证已超时，密保操作未完成。请重新发起验证。':
      'System authentication timed out. The recovery operation was not completed. Start authentication again.',
  '本机未设置设备锁屏密码，无法保护密保密钥。请先设置设备锁屏密码；无需开启面容 ID 或触控 ID。':
      'A device passcode is required to protect security-question recovery. Set a device passcode first; Face ID or Touch ID is not required.',
  '本机设备身份验证未完成，密保设置或恢复未执行。可使用设备锁屏密码重试。':
      'Device authentication was not completed. Security-question setup or recovery was not performed. Try again using the device passcode.',
  '旧版密保密钥仍受原生物识别保护，暂时无法读取。请使用原密码进入设置，关闭本机所有已配置的密保后再重新设置；业务数据不会因此删除。':
      'The existing recovery key is still protected by its original biometrics and could not be read. Use the original passwords to open Settings, turn off every configured recovery setup on this device, then set recovery up again. This does not delete vault data.',

  '本机尚未配置诱饵保险库。': 'No decoy vault is configured on this device.',
  '该保险库已配置密码恢复；如需更换问题，请先验证密码并关闭原配置。':
      'Password recovery is already configured for this vault. To change the questions, verify its password and turn off the existing configuration first.',
  '真实保险库密码恢复已启用，生物识别快速解锁已安全停用；请锁定后亲自验证恢复入口。':
      'Real-vault password recovery is enabled, and biometric quick unlock was safely disabled. Lock Cardock and personally verify the recovery entry.',
  '诱饵保险库密码恢复已启用；请锁定后亲自验证恢复入口。':
      'Decoy-vault password recovery is enabled. Lock Cardock and personally verify the recovery entry.',
  '两套保险库不能使用完全相同的三道密保问题；请至少更换一道。':
      'The two vaults cannot use exactly the same three security questions. Change at least one.',
  '当前真实主密码或诱饵密码不正确。':
      'The current real master password or decoy password is incorrect.',
  '密码恢复已提交，但当前会话无法刷新；请用真实主密码重新解锁。':
      'Password recovery was committed, but this session could not refresh. Unlock again with the real master password.',
  '真实保险库密码恢复已关闭；当前密码和业务数据未改变。':
      'Real-vault password recovery is off. The current password and app data were not changed.',
  '诱饵保险库密码恢复已关闭；当前密码和业务数据未改变。':
      'Decoy-vault password recovery is off. The current password and app data were not changed.',
  '密码恢复时，新密码统一为16–32个字符；建议使用大小写字母、数字和符号。':
      'For password recovery, use 16–32 characters. Include upper- and lowercase letters, numbers, and symbols.',
  '保险库密码已安全重设并生成全新数据密钥。':
      'The vault password was securely reset with a new data key.',
  '保险库密码已重设，但安全计数状态暂时无法更新；请稍后重新锁定并核对。':
      'The vault password was reset, but the security counter could not be updated. Lock again later and verify access.',
  '无法完成恢复；请核对当前显示的三道问题及对应答案，并通过本机系统强认证。':
      'Recovery could not be completed. Check the answers for the three displayed questions and pass strong system authentication on this device.',
  '保险库完整性验证失败，密码和数据均未修改。':
      'Vault integrity verification failed. The password and data were not changed.',
  '密码恢复未完成；请不要卸载应用。请重新核对恢复信息，或在确认有可用加密备份后再选择重新开始。':
      'Password recovery was not completed. Do not uninstall Cardock. Recheck the recovery information, or choose to start over only after confirming that a usable encrypted backup is available.',
  '请先关闭诱饵保险库密码恢复，再修改诱饵密码；完成后可重新设置三道密保。':
      'Turn off decoy-vault password recovery before changing the decoy password. You can configure three security questions again afterward.',
  '本机没有可用的强生物识别能力，密码恢复无法继续；你仍可尝试原密码，或在确认有可用加密备份后选择重新开始。':
      'Strong biometric authentication is not available on this device, so password recovery cannot continue. You can still try the original password, or choose to start over after confirming that a usable encrypted backup is available.',
  '当前存储环境不支持诱饵保险库。':
      'The current storage environment does not support a decoy vault.',
  '诱饵保险库已创建。请立即锁定并用诱饵密码进入，亲自添加可信但不敏感的内容。':
      'The decoy vault was created. Lock Cardock now, enter with the decoy password, and personally add believable but non-sensitive content.',
  '诱饵密码不能与当前主密码相同。':
      'The decoy password cannot match the current master password.',
  '本机已配置诱饵保险库；为避免误删数据，本版本不会覆盖它。':
      'A decoy vault is already configured on this device. This version will not overwrite it, preventing accidental data loss.',
  '诱饵保险库创建失败，真实保险库未被修改。':
      'The decoy vault could not be created. The real vault was not changed.',
  '本机已配置密码恢复；如需更换问题，请先验证主密码并关闭原配置。':
      'Password recovery is already configured on this device. To change the questions, verify the master password and turn off the existing setup first.',
  '当前存储环境不支持本机双因子密码恢复。':
      'The current storage environment does not support on-device two-factor password recovery.',
  '密码恢复已启用，生物识别快速解锁已安全停用；请锁定后亲自验证恢复入口。':
      'Password recovery is enabled, and biometric quick unlock was safely disabled. Lock Cardock and personally verify the recovery flow.',
  '当前真实主密码不正确。': 'The current real master password is incorrect.',
  '请选择三道不同的内置问题，并完整填写三组答案。':
      'Choose three different built-in questions and answer all three.',
  '密码恢复已提交，但当前会话无法刷新；请用原主密码重新解锁。':
      'Password recovery was committed, but this session could not refresh. Unlock again with the original master password.',
  '密码恢复设置未完成，当前主密码和保险库数据未改变。':
      'Password-recovery setup was not completed. The current master password and vault data were not changed.',
  '密码恢复已关闭；当前主密码和业务数据未改变。':
      'Password recovery is off. The current master password and app data were not changed.',
  '本机密码恢复已经处于关闭状态。': 'Password recovery is already off on this device.',
  '密码恢复已关闭，但当前会话无法刷新；请用主密码重新解锁。':
      'Password recovery is off, but this session could not refresh. Unlock again with the master password.',
  '未能关闭密码恢复，原配置保持不变。':
      'Password recovery could not be turned off. The existing setup remains unchanged.',
  '检测到尚未确认的备份恢复事务；为避免丢失唯一回退点，已停止重设主密码。':
      'An unconfirmed backup-restore transaction was found. Master-password reset was stopped to preserve the only rollback point.',
  '本机仍保留上次导入前的加密回滚副本；请先用原主密码完成或处理该恢复事务。':
      'This device still has an encrypted rollback copy from before the last import. Use the original master password to complete or resolve that restore transaction first.',
  '主密码已安全重设并生成全新数据密钥；生物识别快速解锁已停用。':
      'The master password was securely reset with a new data key. Biometric quick unlock is off.',
  '主密码已重设，但安全计数状态暂时无法清零；重新锁定后请优先使用生物识别。':
      'The master password was reset, but the security counter could not be cleared. After locking again, use biometric unlock first.',
  '无法完成恢复；请重新核对三道答案并通过本机系统强认证。':
      'Recovery could not be completed. Recheck all three answers and pass strong system authentication on this device.',
  '保险库完整性验证失败，主密码和数据均未修改。':
      'Vault integrity verification failed. The master password and data were not changed.',
  '该保险库来自更高版本应用，本版本不能安全恢复。':
      'This vault comes from a newer app version and cannot be recovered safely by this version.',
  '密码恢复未完成；请不要卸载应用，并使用原主密码或加密备份。':
      'Password recovery was not completed. Do not uninstall Cardock; use the original master password or an encrypted backup.',
  '请先关闭真实保险库密码恢复，再修改真实主密码；完成后可重新设置三道密保。':
      'Turn off real-vault password recovery before changing the real master password. You can configure three security questions again afterward.',
  '当前存储环境不支持安全修改主密码。':
      'The current storage environment does not support a secure master-password change.',
  '本机恢复前回滚副本已按你的确认永久废弃，但主密码未修改；当前保险库仍使用原主密码。':
      'As confirmed, the on-device pre-restore rollback copy was permanently discarded. The master password was not changed, and the vault still uses the original password.',
  '检测到尚未确认的恢复事务；为避免失去唯一回退点，已停止修改主密码。':
      'An unconfirmed restore transaction was found. The master-password change was stopped to preserve the only rollback point.',
  '本机仍有“上次导入前”回滚副本；确认永久放弃该副本后才能修改主密码。':
      'A “before last import” rollback copy remains on this device. Confirm that you permanently give up that copy before changing the master password.',
  '主密码已修改；旧的本机恢复前回滚副本已废弃，生物识别已安全停用。':
      'The master password was changed. The old on-device pre-restore rollback copy was discarded, and biometric unlock was safely disabled.',
  '主密码已修改；生物识别已安全停用，请按需用新主密码重新开启。':
      'The master password was changed, and biometric unlock was safely disabled. Enable it again with the new master password when needed.',
  '主密码已修改；旧的本机恢复前回滚副本已废弃，生物识别已安全停用。 安全计数状态暂时无法持久化。':
      'The master password was changed. The old on-device pre-restore rollback copy was discarded, and biometric unlock was safely disabled. The security counter could not be saved.',
  '主密码已修改；生物识别已安全停用，请按需用新主密码重新开启。 安全计数状态暂时无法持久化。':
      'The master password was changed, and biometric unlock was safely disabled. Enable it again with the new master password when needed. The security counter could not be saved.',
  '新主密码不能与当前主密码相同。':
      'The new master password cannot match the current master password.',
  '新主密码不能与当前诱饵密码相同。':
      'The new master password cannot match the current decoy password.',
  '保险库完整性验证失败；为避免破坏数据，主密码未修改。':
      'Vault integrity verification failed. The master password was not changed, preventing data damage.',
  '当前真实主密码无法验证。': 'The current real master password could not be verified.',
  '主密码轮换未完成；当前主库仍使用原主密码，生物识别可能已安全停用，请重试。':
      'The master-password rotation was not completed. The real vault still uses the original password, and biometric unlock may have been safely disabled. Try again.',
  '无法安全确认或废弃本机恢复回滚副本；主密码未修改。':
      'The on-device rollback copy for backup restores could not be safely confirmed or discarded. The master password was not changed.',
  '主密码修改未完成；当前主库仍使用原主密码，请不要卸载应用并稍后重试。':
      'The master-password change was not completed. The real vault still uses the original password. Do not uninstall Cardock; try again later.',
  '无法开始修改主密码；当前数据未被修改。':
      'The master-password change could not begin. Current data was not changed.',
  '当前存储环境不支持修改诱饵密码。':
      'The current storage environment does not support changing the decoy password.',
  '诱饵密码已修改；原有诱饵内容保留，生物识别配置未改变。':
      'The decoy password was changed. Existing decoy content was preserved, and biometric settings were not changed.',
  '新诱饵密码不能与当前诱饵密码相同。':
      'The new decoy password cannot match the current decoy password.',
  '新诱饵密码不能与真实主密码相同。':
      'The new decoy password cannot match the real master password.',
  '当前真实主密码或当前诱饵密码不正确。':
      'The current real master password or current decoy password is incorrect.',
  '诱饵库完整性验证失败；原诱饵密码和真实数据均未被修改。':
      'Decoy-vault integrity verification failed. The original decoy password and real data were not changed.',
  '无法验证当前诱饵库凭据。': 'The current decoy-vault credentials could not be verified.',
  '诱饵密码修改失败；原诱饵密码仍然有效，真实保险库未被修改。':
      'The decoy password could not be changed. The original decoy password remains valid, and the real vault was not changed.',
};

const Map<String, String>
appStateRecoveryJapaneseTranslations = <String, String>{
  '上一次系统验证仍在结束，请稍后重试；原密码和保险库数据未修改。':
      '前のシステム認証の終了処理中です。しばらくしてから再試行してください。元のパスワードと保管庫データは変更されていません。',
  '本机恢复密钥暂时无法访问，密保操作未完成；原密码和保险库数据未修改。':
      'この端末の復旧キーにアクセスできません。秘密の質問に関する操作は完了していません。元のパスワードと保管庫データは変更されていません。',
  '系统验证已中断，密保操作未完成。请保持应用在前台重试。':
      'システム認証が中断されました。秘密の質問に関する操作は完了していません。Cardockを前面に保って再試行してください。',
  '系统验证已超时，密保操作未完成。请重新发起验证。':
      'システム認証がタイムアウトしました。秘密の質問に関する操作は完了していません。認証をやり直してください。',
  '本机未设置设备锁屏密码，无法保护密保密钥。请先设置设备锁屏密码；无需开启面容 ID 或触控 ID。':
      '秘密の質問の復旧キーを保護するには端末のパスコードが必要です。端末のパスコードを設定してください。Face IDやTouch IDは不要です。',
  '本机设备身份验证未完成，密保设置或恢复未执行。可使用设备锁屏密码重试。':
      '端末の本人確認が完了していません。秘密の質問の設定または復旧は実行されませんでした。端末のパスコードで再試行できます。',
  '旧版密保密钥仍受原生物识别保护，暂时无法读取。请使用原密码进入设置，关闭本机所有已配置的密保后再重新设置；业务数据不会因此删除。':
      '旧版の復旧キーは元の生体認証で保護されており、読み取れません。元のパスワードで設定を開き、この端末で設定済みの復旧をすべて無効にしてから再設定してください。保管庫のデータは削除されません。',

  '本机尚未配置诱饵保险库。': 'この端末にはおとり保管庫が設定されていません。',
  '该保险库已配置密码恢复；如需更换问题，请先验证密码并关闭原配置。':
      'この保管庫にはパスワード復旧が設定済みです。質問を変更するには、この保管庫のパスワードを確認し、現在の設定を先にオフにしてください。',
  '真实保险库密码恢复已启用，生物识别快速解锁已安全停用；请锁定后亲自验证恢复入口。':
      '実際の保管庫のパスワード復旧を有効にし、生体認証によるクイックロック解除を安全のため無効にしました。Cardockをロックし、復旧の入口をご自身で確認してください。',
  '诱饵保险库密码恢复已启用；请锁定后亲自验证恢复入口。':
      'おとり保管庫のパスワード復旧を有効にしました。Cardockをロックし、復旧の入口をご自身で確認してください。',
  '两套保险库不能使用完全相同的三道密保问题；请至少更换一道。':
      '2つの保管庫で、まったく同じ3つの秘密の質問は使用できません。少なくとも1つ変更してください。',
  '当前真实主密码或诱饵密码不正确。': '現在の実際のマスターパスワードまたはおとりパスワードが正しくありません。',
  '密码恢复已提交，但当前会话无法刷新；请用真实主密码重新解锁。':
      'パスワード復旧を確定しましたが、現在のセッションを更新できませんでした。実際のマスターパスワードで再度ロックを解除してください。',
  '真实保险库密码恢复已关闭；当前密码和业务数据未改变。':
      '実際の保管庫のパスワード復旧をオフにしました。現在のパスワードとアプリデータは変更していません。',
  '诱饵保险库密码恢复已关闭；当前密码和业务数据未改变。':
      'おとり保管庫のパスワード復旧をオフにしました。現在のパスワードとアプリデータは変更していません。',
  '密码恢复时，新密码统一为16–32个字符；建议使用大小写字母、数字和符号。':
      'パスワード復旧では16～32文字を使用してください。英大文字・小文字、数字、記号を含めることを推奨します。',
  '保险库密码已安全重设并生成全新数据密钥。': '保管庫のパスワードを安全に再設定し、新しいデータキーを生成しました。',
  '保险库密码已重设，但安全计数状态暂时无法更新；请稍后重新锁定并核对。':
      '保管庫のパスワードを再設定しましたが、セキュリティカウンターを更新できませんでした。後でもう一度ロックし、アクセスを確認してください。',
  '无法完成恢复；请核对当前显示的三道问题及对应答案，并通过本机系统强认证。':
      '復旧を完了できませんでした。表示された3つの質問への答えを確認し、この端末の強力なシステム認証を完了してください。',
  '保险库完整性验证失败，密码和数据均未修改。': '保管庫の整合性を確認できませんでした。パスワードとデータは変更していません。',
  '密码恢复未完成；请不要卸载应用。请重新核对恢复信息，或在确认有可用加密备份后再选择重新开始。':
      'パスワード復旧は完了していません。Cardockをアンインストールしないでください。復旧情報を再確認するか、利用可能な暗号化バックアップがあることを確認してから、やり直す操作を選んでください。',
  '请先关闭诱饵保险库密码恢复，再修改诱饵密码；完成后可重新设置三道密保。':
      'おとりパスワードを変更する前に、おとり保管庫のパスワード復旧をオフにしてください。変更後に3つの秘密の質問を再設定できます。',
  '本机没有可用的强生物识别能力，密码恢复无法继续；你仍可尝试原密码，或在确认有可用加密备份后选择重新开始。':
      'この端末では強力な生体認証を利用できないため、パスワード復旧を続行できません。以前のパスワードを試すか、利用可能な暗号化バックアップがあることを確認してからやり直す操作を選んでください。',
  '当前存储环境不支持诱饵保险库。': '現在のストレージ環境はおとり保管庫に対応していません。',
  '诱饵保险库已创建。请立即锁定并用诱饵密码进入，亲自添加可信但不敏感的内容。':
      'おとり保管庫を作成しました。今すぐCardockをロックし、おとりパスワードで入り、もっともらしく見える、機密情報を含まない内容をご自身で追加してください。',
  '诱饵密码不能与当前主密码相同。': 'おとりパスワードを現在のマスターパスワードと同じにすることはできません。',
  '本机已配置诱饵保险库；为避免误删数据，本版本不会覆盖它。':
      'この端末にはおとり保管庫が設定済みです。誤ってデータを失わないよう、このバージョンでは上書きしません。',
  '诱饵保险库创建失败，真实保险库未被修改。': 'おとり保管庫を作成できませんでした。実際の保管庫は変更していません。',
  '本机已配置密码恢复；如需更换问题，请先验证主密码并关闭原配置。':
      'この端末ではパスワード復旧が設定済みです。質問を変更するには、先にマスターパスワードを確認し、現在の設定をオフにしてください。',
  '当前存储环境不支持本机双因子密码恢复。': '現在のストレージ環境は端末内の二要素パスワード復旧に対応していません。',
  '密码恢复已启用，生物识别快速解锁已安全停用；请锁定后亲自验证恢复入口。':
      'パスワード復旧を有効にし、生体認証によるクイックロック解除を安全のため無効にしました。Cardockをロックし、復旧手順をご自身で確認してください。',
  '当前真实主密码不正确。': '現在の実際のマスターパスワードが正しくありません。',
  '请选择三道不同的内置问题，并完整填写三组答案。': '異なる組み込み質問を3つ選び、3つすべてに回答してください。',
  '密码恢复已提交，但当前会话无法刷新；请用原主密码重新解锁。':
      'パスワード復旧を確定しましたが、現在のセッションを更新できませんでした。元のマスターパスワードで再度ロックを解除してください。',
  '密码恢复设置未完成，当前主密码和保险库数据未改变。':
      'パスワード復旧の設定は完了していません。現在のマスターパスワードと保管庫データは変更していません。',
  '密码恢复已关闭；当前主密码和业务数据未改变。': 'パスワード復旧をオフにしました。現在のマスターパスワードとアプリデータは変更していません。',
  '本机密码恢复已经处于关闭状态。': 'この端末ではパスワード復旧がすでにオフです。',
  '密码恢复已关闭，但当前会话无法刷新；请用主密码重新解锁。':
      'パスワード復旧をオフにしましたが、現在のセッションを更新できませんでした。マスターパスワードで再度ロックを解除してください。',
  '未能关闭密码恢复，原配置保持不变。': 'パスワード復旧をオフにできませんでした。現在の設定は変更していません。',
  '检测到尚未确认的备份恢复事务；为避免丢失唯一回退点，已停止重设主密码。':
      '未確認のバックアップ復元処理を検出しました。唯一のロールバックポイントを失わないよう、マスターパスワードのリセットを停止しました。',
  '本机仍保留上次导入前的加密回滚副本；请先用原主密码完成或处理该恢复事务。':
      'この端末には、前回のインポート前の暗号化ロールバックコピーが残っています。元のマスターパスワードで復元処理を完了または解決してください。',
  '主密码已安全重设并生成全新数据密钥；生物识别快速解锁已停用。':
      'マスターパスワードを安全にリセットし、新しいデータ鍵を生成しました。生体認証によるクイックロック解除はオフです。',
  '主密码已重设，但安全计数状态暂时无法清零；重新锁定后请优先使用生物识别。':
      'マスターパスワードをリセットしましたが、セキュリティカウンターを消去できませんでした。再度ロックした後は、先に生体認証を使用してください。',
  '无法完成恢复；请重新核对三道答案并通过本机系统强认证。':
      '復旧を完了できませんでした。3つの回答を再確認し、この端末でシステムの強力な認証を完了してください。',
  '保险库完整性验证失败，主密码和数据均未修改。': '保管庫の整合性を確認できませんでした。マスターパスワードとデータは変更していません。',
  '该保险库来自更高版本应用，本版本不能安全恢复。':
      'この保管庫は新しいバージョンのアプリで作成されているため、このバージョンでは安全に復旧できません。',
  '密码恢复未完成；请不要卸载应用，并使用原主密码或加密备份。':
      'パスワード復旧は完了していません。Cardockをアンインストールせず、元のマスターパスワードまたは暗号化バックアップを使用してください。',
  '请先关闭真实保险库密码恢复，再修改真实主密码；完成后可重新设置三道密保。':
      '実際のマスターパスワードを変更する前に、実際の保管庫のパスワード復旧をオフにしてください。変更後に3つの秘密の質問を再設定できます。',
  '当前存储环境不支持安全修改主密码。': '現在のストレージ環境は安全なマスターパスワード変更に対応していません。',
  '本机恢复前回滚副本已按你的确认永久废弃，但主密码未修改；当前保险库仍使用原主密码。':
      '確認に基づき、端末内の復元前のロールバックコピーを完全に破棄しました。マスターパスワードは変更されておらず、保管庫は元のパスワードを使用しています。',
  '检测到尚未确认的恢复事务；为避免失去唯一回退点，已停止修改主密码。':
      '未確認の復元処理を検出しました。唯一のロールバックポイントを失わないよう、マスターパスワードの変更を停止しました。',
  '本机仍有“上次导入前”回滚副本；确认永久放弃该副本后才能修改主密码。':
      'この端末には「前回のインポート前」のロールバックコピーが残っています。完全に破棄することを確認してから、マスターパスワードを変更してください。',
  '主密码已修改；旧的本机恢复前回滚副本已废弃，生物识别已安全停用。':
      'マスターパスワードを変更しました。端末内の古い復元前のロールバックコピーを破棄し、生体認証を安全のため無効にしました。',
  '主密码已修改；生物识别已安全停用，请按需用新主密码重新开启。':
      'マスターパスワードを変更し、生体認証を安全のため無効にしました。必要に応じて新しいマスターパスワードで再度有効にしてください。',
  '主密码已修改；旧的本机恢复前回滚副本已废弃，生物识别已安全停用。 安全计数状态暂时无法持久化。':
      'マスターパスワードを変更しました。端末内の古い復元前のロールバックコピーを破棄し、生体認証を安全のため無効にしました。セキュリティカウンターは保存できませんでした。',
  '主密码已修改；生物识别已安全停用，请按需用新主密码重新开启。 安全计数状态暂时无法持久化。':
      'マスターパスワードを変更し、生体認証を安全のため無効にしました。必要に応じて新しいマスターパスワードで再度有効にしてください。セキュリティカウンターは保存できませんでした。',
  '新主密码不能与当前主密码相同。': '新しいマスターパスワードを現在のものと同じにすることはできません。',
  '新主密码不能与当前诱饵密码相同。': '新しいマスターパスワードを現在のおとりパスワードと同じにすることはできません。',
  '保险库完整性验证失败；为避免破坏数据，主密码未修改。':
      '保管庫の整合性を確認できませんでした。データを損傷しないよう、マスターパスワードは変更していません。',
  '当前真实主密码无法验证。': '現在の実際のマスターパスワードを確認できませんでした。',
  '主密码轮换未完成；当前主库仍使用原主密码，生物识别可能已安全停用，请重试。':
      'マスターパスワードの更新は完了していません。実際の保管庫は元のパスワードを使用しています。生体認証は安全のため無効になっている可能性があります。再試行してください。',
  '无法安全确认或废弃本机恢复回滚副本；主密码未修改。':
      '端末内のバックアップ復元用ロールバックコピーを安全に確認または破棄できませんでした。マスターパスワードは変更していません。',
  '主密码修改未完成；当前主库仍使用原主密码，请不要卸载应用并稍后重试。':
      'マスターパスワードの変更は完了していません。実際の保管庫は元のパスワードを使用しています。Cardockをアンインストールせず、後で再試行してください。',
  '无法开始修改主密码；当前数据未被修改。': 'マスターパスワードの変更を開始できませんでした。現在のデータは変更していません。',
  '当前存储环境不支持修改诱饵密码。': '現在のストレージ環境はおとりパスワードの変更に対応していません。',
  '诱饵密码已修改；原有诱饵内容保留，生物识别配置未改变。':
      'おとりパスワードを変更しました。既存のおとり内容は保持され、生体認証設定は変更されていません。',
  '新诱饵密码不能与当前诱饵密码相同。': '新しいおとりパスワードを現在のものと同じにすることはできません。',
  '新诱饵密码不能与真实主密码相同。': '新しいおとりパスワードを実際のマスターパスワードと同じにすることはできません。',
  '当前真实主密码或当前诱饵密码不正确。': '現在の実際のマスターパスワードまたはおとりパスワードが正しくありません。',
  '诱饵库完整性验证失败；原诱饵密码和真实数据均未被修改。':
      'おとり保管庫の整合性を確認できませんでした。元のおとりパスワードと実データは変更していません。',
  '无法验证当前诱饵库凭据。': '現在のおとり保管庫の認証情報を確認できませんでした。',
  '诱饵密码修改失败；原诱饵密码仍然有效，真实保险库未被修改。':
      'おとりパスワードを変更できませんでした。元のおとりパスワードは引き続き有効で、実際の保管庫は変更していません。',
};
