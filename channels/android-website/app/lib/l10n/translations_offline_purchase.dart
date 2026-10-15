// Website Android offline purchase UI and validation messages.
const offlinePurchaseEnglishTranslations = <String, String>{
  "无法打开外部浏览器，请确认手机已安装并启用浏览器。":
      "Cannot open a browser. Make sure a browser is installed and enabled.",
  "本地购买证明准备失败（P01），请重新打开Cardock后重试；已有数据和授权保持。":
      "Could not prepare purchase proof (P01). Reopen Cardock and retry. Existing data and authorization are preserved.",

  "移除本机官网授权": "Remove website authorization on this device",
  "移除本机官网授权？": "Remove website authorization on this device?",
  "确认移除授权": "Remove authorization",
  "本机将恢复免费版，已有账号、订阅、主密码和安装身份保留。官网订单不会删除；需要时可从官网重新激活。":
      "This device will return to the free version. Existing accounts, subscriptions, master password and installation identity are preserved. Website orders remain; you can activate again from the website.",
  "已移除本机官网授权，恢复免费版。账号、订阅和安装身份已保留。":
      "Website authorization removed. The free version is active. Accounts, subscriptions and installation identity are preserved.",
  "未能移除本机官网授权，请保持真实保险库解锁后重试。":
      "Authorization could not be removed. Keep the real vault unlocked and retry.",
  "付款并提交核验后，预计 1—5 小时完成人工核验；通过后点击网页“在Cardock中激活”。":
      "After payment and submission, manual review usually takes 1–5 hours. Once approved, tap Activate in Cardock on the webpage.",
  "在浏览器中查看付款进度。核验通过后，点击网页“在Cardock中激活”，即可完成激活；Cardock本身不联网。":
      "Check payment progress in your browser. Once approved, tap Activate in Cardock on the webpage. Cardock itself never connects to the network.",
  "在浏览器中打开官网订单": "Open website orders in browser",
  "在浏览器中查看官网订单": "View website orders in browser",
  "在浏览器中购买": "Purchase in browser",
  "准备此订单的离线授权": "Prepare this order’s offline license",
  "继续此订单": "Continue this order",
  "将打开外部浏览器。Cardock只提供本地安装证明，不访问网络。":
      "An external browser will open. Cardock only proves this installation locally and never accesses the network.",
  "订单：{reference}\n将打开外部浏览器并重新证明本次安装。授权仍须离线验签。":
      "Order: {reference}\nAn external browser will open to prove this installation again. The license must still pass offline signature verification.",
  "备用方式：复制官网准备好的完整授权，在此离线验证并激活。旧版独立授权码仍可使用。":
      "Fallback: copy the complete authorization prepared on the website, then verify and activate it offline here. Older standalone license codes still work.",
  "粘贴从官网订单页复制的完整授权":
      "Paste the complete authorization copied from the order page",
  "粘贴并激活": "Paste and activate",
  "验证并激活": "Verify and activate",
  "清空": "Clear",
  "请先复制官网的完整授权，再点击粘贴。":
      "Copy the complete authorization from the website first, then tap Paste.",
  "授权内容过长，请重新复制完整授权。":
      "The authorization is too long. Copy the complete authorization again.",
  "请先清空输入，再粘贴新的完整授权。":
      "Clear the input before pasting another complete authorization.",
  "输入内容已改变，未覆盖。请先清空后再粘贴。":
      "Your input changed and was not overwritten. Clear it before pasting.",
  "剪贴板没有可用文字，请先点击官网“复制完整授权”。":
      "The clipboard has no text. Tap Copy complete authorization on the website first.",
  "剪贴板内容过长，请重新复制官网完整授权。":
      "The clipboard content is too long. Copy the website’s complete authorization again.",
  "无法读取剪贴板，请允许本次粘贴，或在输入框中手动粘贴。":
      "Clipboard access failed. Allow this paste or paste manually into the field.",
  "已离线激活，购买凭证已保存。": "Activated offline. Your purchase receipt is saved.",
  "已离线验证并激活完整版。": "The full version was verified and activated offline.",
  "已打开外部浏览器。核验通过后点击网页“在Cardock中激活”；Cardock本身不联网。":
      "An external browser is open. Once approved, tap Activate in Cardock on the webpage. Cardock itself stays offline.",
  "完整授权格式不正确，请重新复制官网提供的全部内容。":
      "The authorization format is invalid. Copy all content provided by the website again.",
  "授权内容过长或安装身份无效，请重新复制完整授权。":
      "The authorization is too long or the installation identity is invalid. Copy the complete authorization again.",
  "未识别到完整授权，请使用官网旁边的复制按钮，再点击“粘贴并激活”。":
      "No complete authorization was found. Use the website’s adjacent copy button, then tap Paste and activate.",
  "此授权不属于当前安装。请在浏览器中恢复已有购买，不要重新付款。":
      "This license belongs to another installation. Recover the existing purchase in your browser. Do not pay again.",
  "授权验签未通过，请从官网重新复制完整授权。":
      "License signature verification failed. Copy the complete authorization from the website again.",
  "购买凭证与授权不匹配，请重新复制完整授权。":
      "The receipt does not match the license. Copy the complete authorization again.",
  "购买凭证验签或绑定检查未通过，原有授权保持。请重新复制完整授权。":
      "Receipt signature or binding verification failed. Your existing license is unchanged. Copy the complete authorization again.",
  "安装挑战无效或已过期，请从Cardock重新发起并使用同一浏览器。":
      "The installation challenge is invalid or expired. Start again from Cardock and use the same browser.",
  "无法准备本地安装证明，请回到Cardock重试。":
      "The local installation proof could not be prepared. Return to Cardock and retry.",
  "本地安装证明失败，请从Cardock重新发起。":
      "Local installation proof failed. Start again from Cardock.",
  "无法打开外部浏览器，请重试。": "Unable to open the external browser. Try again.",
  "无法返回原浏览器，请从Cardock重新发起。":
      "Unable to return to the original browser. Start again from Cardock.",
  "授权未能完整保存，请保留官网标签页并重试。":
      "The complete authorization could not be saved. Keep the website tab open and retry.",
  "授权验证或保存失败，原有授权保持。请重新复制完整授权。":
      "Verification or saving failed. Your existing license is unchanged. Copy the complete authorization again.",
  "离线材料格式无效，请从官网原订单页重新打开。":
      "The offline material is invalid. Open it again from the original website order page.",
  "离线操作未完成，请从官网原订单页重新打开。":
      "The offline operation did not finish. Open it again from the original order page.",
  "请正常解锁Cardock后重试；原有授权保持。":
      "Unlock Cardock normally and retry. Your existing license is unchanged.",
  "安装签名身份不匹配，请从官网获取正式版本。":
      "The installation signing identity does not match. Get the official release from the website.",
  "请使用官网正式版本的购买入口，或手动粘贴完整授权。":
      "Use the official website release’s purchase entry or paste the complete authorization manually.",
  "本地购买操作未完成，请从Cardock重新发起；原有授权保持。":
      "The local purchase operation did not finish. Start again from Cardock. Your existing license is unchanged.",
  "实付金额": "Amount paid",
  "核验日期": "Verification date",
  "日期来自官网真实核验记录；未将申报、签发或导入时间作为购买日期。":
      "This date comes from the website’s verified payment record. Declaration, issuance and import times are not used as a purchase date.",
  "Cardock本身完全离线；购买、订单查询与恢复由外部浏览器联网完成。":
      "Cardock itself is fully offline. An external browser handles purchases, order checks and recovery online.",
  "完全离线 · APP 不访问互联网或局域网":
      "Fully offline · no internet or local network access",
  "官网 Android 版Cardock本身完全离线，不访问互联网或局域网。购买、订单查询和恢复由外部浏览器联网完成；APP 只在本地证明安装、接收完整签名授权、离线验签并保存。官网版不提供电脑临时录入。账号与订阅数据仍加密保存在本机，保险库、主密码和备份密码不会交给浏览器。":
      "The website Android edition of Cardock is fully offline, with no internet or local network access. An external browser handles purchases, order queries and recovery. The app only proves its installation locally, receives complete signed authorizations, verifies them offline and saves them. This edition has no temporary computer input. Account and subscription records remain encrypted on the device. Your vault, master password and backup password are never passed to the browser.",
};
const offlinePurchaseJapaneseTranslations = <String, String>{
  "无法打开外部浏览器，请确认手机已安装并启用浏览器。": "ブラウザを開けません。ブラウザがインストールされ、有効になっているか確認してください。",
  "本地购买证明准备失败（P01），请重新打开Cardock后重试；已有数据和授权保持。":
      "購入証明を準備できませんでした（P01）。Cardockを開き直してください。既存のデータと認証は保持されます。",

  "移除本机官网授权": "この端末の公式サイト認証を解除",
  "移除本机官网授权？": "この端末の公式サイト認証を解除しますか？",
  "确认移除授权": "認証を解除",
  "本机将恢复免费版，已有账号、订阅、主密码和安装身份保留。官网订单不会删除；需要时可从官网重新激活。":
      "無料版に戻ります。既存のアカウント、サブスクリプション、マスターパスワード、インストールIDは保持されます。公式サイトの注文は削除されず、必要に応じて再認証できます。",
  "已移除本机官网授权，恢复免费版。账号、订阅和安装身份已保留。":
      "公式サイト認証を解除し、無料版に戻りました。アカウント、サブスクリプション、インストールIDは保持されています。",
  "未能移除本机官网授权，请保持真实保险库解锁后重试。": "認証を解除できませんでした。本物の保管庫をロック解除して再試行してください。",
  "付款并提交核验后，预计 1—5 小时完成人工核验；通过后点击网页“在Cardock中激活”。":
      "お支払い後に確認を申請すると、手動確認には通常1～5時間かかります。承認後、ウェブページの「Cardockで有効化」を押してください。",
  "在浏览器中查看付款进度。核验通过后，点击网页“在Cardock中激活”，即可完成激活；Cardock本身不联网。":
      "支払い状況はブラウザで確認します。承認後、ウェブページの「Cardockで有効化」を押してください。Cardock自体は通信しません。",
  "在浏览器中打开官网订单": "ブラウザで公式サイトの注文を開く",
  "在浏览器中查看官网订单": "ブラウザで公式サイトの注文を確認",
  "在浏览器中购买": "ブラウザで購入",
  "准备此订单的离线授权": "この注文のオフラインライセンスを準備",
  "继续此订单": "この注文を続ける",
  "将打开外部浏览器。Cardock只提供本地安装证明，不访问网络。":
      "外部ブラウザを開きます。Cardockは端末内でインストールを証明するだけで、通信しません。",
  "订单：{reference}\n将打开外部浏览器并重新证明本次安装。授权仍须离线验签。":
      "注文：{reference}\n外部ブラウザを開き、このインストールを再度証明します。ライセンスは引き続きオフラインで署名を検証します。",
  "备用方式：复制官网准备好的完整授权，在此离线验证并激活。旧版独立授权码仍可使用。":
      "予備の方法：公式サイトで準備された認証情報全体をコピーし、ここでオフライン検証して有効化します。旧形式の単独ライセンスコードも使用できます。",
  "粘贴从官网订单页复制的完整授权": "注文ページからコピーした認証情報全体を貼り付け",
  "粘贴并激活": "貼り付けて有効化",
  "验证并激活": "検証して有効化",
  "清空": "クリア",
  "请先复制官网的完整授权，再点击粘贴。": "先に公式サイトの認証情報全体をコピーしてから、「貼り付け」を押してください。",
  "授权内容过长，请重新复制完整授权。": "認証情報が長すぎます。認証情報全体を再度コピーしてください。",
  "请先清空输入，再粘贴新的完整授权。": "新しい認証情報全体を貼り付ける前に、入力欄をクリアしてください。",
  "输入内容已改变，未覆盖。请先清空后再粘贴。": "入力が変更されたため上書きしませんでした。クリアしてから貼り付けてください。",
  "剪贴板没有可用文字，请先点击官网“复制完整授权”。": "クリップボードに文字がありません。先に公式サイトの「認証情報全体をコピー」を押してください。",
  "剪贴板内容过长，请重新复制官网完整授权。": "クリップボードの内容が長すぎます。公式サイトの認証情報全体を再度コピーしてください。",
  "无法读取剪贴板，请允许本次粘贴，或在输入框中手动粘贴。":
      "クリップボードを読み取れません。今回の貼り付けを許可するか、入力欄に手動で貼り付けてください。",
  "已离线激活，购买凭证已保存。": "オフラインで有効化し、購入証明を保存しました。",
  "已离线验证并激活完整版。": "オフライン検証が完了し、完全版を有効化しました。",
  "已打开外部浏览器。核验通过后点击网页“在Cardock中激活”；Cardock本身不联网。":
      "外部ブラウザを開きました。承認後、ウェブページの「Cardockで有効化」を押してください。Cardock自体は通信しません。",
  "完整授权格式不正确，请重新复制官网提供的全部内容。": "認証情報の形式が正しくありません。公式サイトの内容全体を再度コピーしてください。",
  "授权内容过长或安装身份无效，请重新复制完整授权。": "認証情報が長すぎるか、インストール識別情報が無効です。認証情報全体を再度コピーしてください。",
  "未识别到完整授权，请使用官网旁边的复制按钮，再点击“粘贴并激活”。":
      "認証情報全体を認識できません。公式サイトの隣接するコピーボタンを使い、「貼り付けて有効化」を押してください。",
  "此授权不属于当前安装。请在浏览器中恢复已有购买，不要重新付款。":
      "このライセンスは別のインストール用です。ブラウザで既存の購入を復元してください。再度支払わないでください。",
  "授权验签未通过，请从官网重新复制完整授权。": "ライセンス署名の検証に失敗しました。公式サイトから認証情報全体を再度コピーしてください。",
  "购买凭证与授权不匹配，请重新复制完整授权。": "購入証明とライセンスが一致しません。認証情報全体を再度コピーしてください。",
  "购买凭证验签或绑定检查未通过，原有授权保持。请重新复制完整授权。":
      "購入証明の署名または対応関係を検証できませんでした。既存の認証は保持されます。認証情報全体を再度コピーしてください。",
  "安装挑战无效或已过期，请从Cardock重新发起并使用同一浏览器。":
      "インストール確認が無効または期限切れです。Cardockからやり直し、同じブラウザを使ってください。",
  "无法准备本地安装证明，请回到Cardock重试。": "端末内のインストール証明を準備できません。Cardockに戻って再試行してください。",
  "本地安装证明失败，请从Cardock重新发起。": "端末内のインストール証明に失敗しました。Cardockからやり直してください。",
  "无法打开外部浏览器，请重试。": "外部ブラウザを開けません。再試行してください。",
  "无法返回原浏览器，请从Cardock重新发起。": "元のブラウザに戻れません。Cardockからやり直してください。",
  "授权未能完整保存，请保留官网标签页并重试。": "認証情報全体を保存できませんでした。公式サイトのタブを残して再試行してください。",
  "授权验证或保存失败，原有授权保持。请重新复制完整授权。":
      "検証または保存に失敗しました。既存の認証は保持されます。認証情報全体を再度コピーしてください。",
  "离线材料格式无效，请从官网原订单页重新打开。": "オフライン認証情報が無効です。公式サイトの元の注文ページから再度開いてください。",
  "离线操作未完成，请从官网原订单页重新打开。": "オフライン処理が完了していません。元の注文ページから再度開いてください。",
  "请正常解锁Cardock后重试；原有授权保持。": "通常の方法でCardockをロック解除して再試行してください。既存の認証は保持されます。",
  "安装签名身份不匹配，请从官网获取正式版本。": "インストールの署名識別情報が一致しません。公式サイトから正式版を入手してください。",
  "请使用官网正式版本的购买入口，或手动粘贴完整授权。": "公式サイト正式版の購入入口を使うか、認証情報全体を手動で貼り付けてください。",
  "本地购买操作未完成，请从Cardock重新发起；原有授权保持。":
      "端末内の購入処理が完了していません。Cardockからやり直してください。既存の認証は保持されます。",
  "实付金额": "支払金額",
  "核验日期": "確認日",
  "日期来自官网真实核验记录；未将申报、签发或导入时间作为购买日期。":
      "日付は公式サイトの実際の入金確認記録に基づきます。申告・発行・インポート日時を購入日として表示しません。",
  "Cardock本身完全离线；购买、订单查询与恢复由外部浏览器联网完成。":
      "Cardock自体は完全にオフラインです。購入・注文確認・復元の通信は外部ブラウザで行います。",
  "完全离线 · APP 不访问互联网或局域网": "完全オフライン · インターネットやLANに接続しません",
  "官网 Android 版Cardock本身完全离线，不访问互联网或局域网。购买、订单查询和恢复由外部浏览器联网完成；APP 只在本地证明安装、接收完整签名授权、离线验签并保存。官网版不提供电脑临时录入。账号与订阅数据仍加密保存在本机，保险库、主密码和备份密码不会交给浏览器。":
      "公式サイトAndroid版のCardockは完全にオフラインで、インターネットやLANに接続しません。購入・注文確認・復元の通信は外部ブラウザで行います。アプリは端末内でインストールを証明し、署名済み認証情報全体を受け取り、オフラインで検証・保存するだけです。この版にパソコンからの一時入力機能はありません。アカウントとサブスクリプションは端末内で暗号化保存され、保管庫・マスターパスワード・バックアップパスワードはブラウザに渡りません。",
};
