import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PlayPrivacyPage extends StatelessWidget {
  const PlayPrivacyPage({super.key});
  static String title(BuildContext context) =>
      (_content[Localizations.localeOf(context).languageCode] ??
              _content['zh']!)['title']
          as String;
  static const _url = String.fromEnvironment('CARDOCK_PRIVACY_POLICY_URL');
  static const _support = String.fromEnvironment('CARDOCK_SUPPORT_EMAIL');
  static const _developer = String.fromEnvironment('CARDOCK_DEVELOPER_NAME');
  @override
  Widget build(BuildContext context) {
    final content =
        _content[Localizations.localeOf(context).languageCode] ??
        _content['zh']!;
    final sections = content['sections'] as List<List<String>>;
    final url = Uri.tryParse(_url);
    return Scaffold(
      appBar: AppBar(title: Text(title(context))),
      body: ListView(
        key: const ValueKey('play-privacy-page'),
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Cardock',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          if (_developer.isNotEmpty) const Text(_developer),
          if (_support.isNotEmpty) const SelectableText(_support),
          for (final section in sections) ...[
            const SizedBox(height: 20),
            Text(section[0], style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(section[1]),
          ],
          if (url != null &&
              url.scheme == 'https' &&
              url.host.isNotEmpty &&
              url.userInfo.isEmpty)
            TextButton(
              onPressed: () async {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              },
              child: Text(content['open'] as String),
            ),
        ],
      ),
    );
  }

  static const Map<String, Map<String, Object>> _content = {
    "zh": {
      "title": "隐私政策",
      "open": "查看公开政策",
      "sections": [
        [
          "本地记录",
          "Cardock 是本地个人账号与订阅记录工具，不要求注册 Cardock 云账户。你录入的账号、密码、订阅、绑定资料和备注保存在本机加密保险库中，不上传给开发者。主密码和独立备份密码不发送给开发者。真实库、诱饵库及订阅只读视图分别受权限约束。",
        ],
        [
          "你选择的数据传输",
          "电脑临时录入仅在你主动开启后提供短时可信局域网会话。初始页面使用 HTTP，不能验证公网身份，也不承诺完整 HTTPS 安全；请只在自己信任的网络与电脑使用。配对后的业务消息受会话校验保护，手机锁定时暂停受保护操作，停止或到期后会话结束。",
        ],
        [
          "文件、分享与备份",
          "你可通过系统文件选择器选择文件、备份位置和分享目标。文件提供方可能是云盘，其处理受该提供方政策约束。加密便携备份使用独立密码；可读导出是明文，应自行保管并及时清理。不要求宽泛存储、通讯录或位置权限。临时内存和文件尽力清理，不承诺安全擦除。",
        ],
        [
          "Google Play 购买",
          "应用免费下载；免费额度为15个账号、5个订阅及橙墨旧刊主题。可经 Google Play 一次购买非消耗型完整版，无自动续费。Google 处理付款、商店账号与交易数据；应用接收购买回执，并在本机验证及加密保存授权。应用不会接收银行卡资料，不向开发者服务器上传保险库或回执。安装授权标识与业务数据分离。购买、恢复和前台核验可能联网；记录功能可离线使用。",
        ],
        [
          "系统能力",
          "生物识别仅调用系统认证；应用不获取生物特征模板。通知默认使用泛化内容，你可选择提醒与精确闹钟许可，系统限制可能影响送达。电脑会话运行时使用前台通知，停止会话即结束。应用不集成广告、行为分析或第三方崩溃上报 SDK；Android/Google 的系统诊断按其设置处理。",
        ],
        [
          "保留与删除",
          "本地记录保留至你删除或重建。回收站通常保留30天，可按应用授权流程永久删除；外部导出和备份须在对应位置另行管理。系统备份和设备迁移排除保险库材料。卸载、清数据或设备密钥失效可能导致本机内容无法恢复，请预先保管独立加密备份。购买恢复只恢复权益，不恢复业务记录。",
        ],
        [
          "联系与变更",
          "主动联系支持时，你发送的邮件地址、内容和附件会由所用邮件服务处理；请不要发送真实密码或完整保险库。公开政策网页的托管方可能记录 IP、浏览器和访问时间，具体主体与保留期限须在正式政策中列明。政策更新将在公开页面说明。本文更新于2026-09-07。",
        ],
      ],
    },
    "en": {
      "title": "Privacy policy",
      "open": "Open public policy",
      "sections": [
        [
          "Local records",
          "Cardock is a personal account and subscription record keeper. No Cardock cloud account is required. Your account entries, passwords, subscriptions, linked details and notes stay in an encrypted vault on your device; they are not uploaded to the developer. Master and backup passwords are not sent to the developer. Real, decoy and read-only views have separate authorization boundaries.",
        ],
        [
          "Transfers you choose",
          "Temporary computer entry starts only when you enable a short session on a trusted local network. Its initial page uses HTTP and cannot establish a public Internet identity or provide a complete HTTPS guarantee. Use a trusted computer and network. Paired messages have session checks; locking the phone pauses protected actions, and stopping or expiry ends the session.",
        ],
        [
          "Files, sharing and backups",
          "You choose files, destinations and sharing recipients through system interfaces. A document provider may be a cloud service governed by its own policy. Portable encrypted backups use a separate password. Readable exports are plain text: protect and clean up your copies. Broad storage, contacts and location access are not requested. Cleanup is best effort, not a promise of secure erasure.",
        ],
        [
          "Google Play purchases",
          "The app is free to download, with 15 accounts, 5 subscriptions and the Paper Archive theme. One non-consumable purchase unlocks the full version, without automatic renewal. Google handles payments, store accounts and transaction data. The app receives purchase receipts, verifies them locally and stores an encrypted authorization cache. It does not receive card details or upload vaults or receipts to a developer server. Installation authorization is separate from vault data. Buying, restoring and foreground checks can use the network; record keeping works offline.",
        ],
        [
          "System features",
          "Biometrics use system authentication; the app does not receive biometric templates. Notifications use generic text by default. Reminder and exact-alarm permissions are optional, and system restrictions can affect delivery. Computer sessions use a foreground notification and end when stopped. No advertising, behavioral analytics or third-party crash reporting SDK is integrated. Android and Google system diagnostics follow their settings.",
        ],
        [
          "Retention and deletion",
          "Local entries remain until you delete or rebuild them. Recycle-bin records normally remain for 30 days and may be permanently deleted through the authorized flow. Manage external exports and backups separately. System backup and device transfer exclude vault material. Uninstalling, clearing data or invalidated device keys can make local data unavailable. Keep a portable encrypted backup. Restoring purchases restores access rights, not your records.",
        ],
        [
          "Support and changes",
          "If you contact support, your chosen email service processes the address, content and attachments you send. Do not send real passwords or an entire vault. The public policy host may log IP addresses, browser details and access times; the operator and retention period must be specified before publication. Changes will be described on the public page. Updated 7 September 2026.",
        ],
      ],
    },
    "ja": {
      "title": "プライバシーポリシー",
      "open": "公開ポリシーを開く",
      "sections": [
        [
          "端末内の記録",
          "Cardock は個人のアカウントとサブスクリプションを記録するツールです。Cardock のクラウドアカウント登録は不要です。入力したアカウント、パスワード、契約、関連情報、メモは端末内の暗号化保管庫に保存され、開発者にアップロードされません。マスターパスワードやバックアップ用パスワードも送信しません。本来の保管庫、おとり保管庫、読み取り専用表示はそれぞれ権限で制限されます。",
        ],
        [
          "選択したデータ転送",
          "パソコンからの一時入力は、利用者が開始した信頼できるローカルネットワーク上の短いセッションだけで動作します。最初のページは HTTP を使用し、公開インターネット上の身元確認や完全な HTTPS の安全性は保証しません。信頼できるネットワークとパソコンをご利用ください。ペアリング後のメッセージにはセッション検証が適用され、端末のロックで保護操作を一時停止し、停止または期限切れで終了します。",
        ],
        [
          "ファイルとバックアップ",
          "システムの選択画面でファイル、保存先、共有先を指定します。クラウドストレージなどの提供元には各社のポリシーが適用されます。暗号化バックアップには独立したパスワードを使用します。可読形式の書き出しは平文のため、適切に保管し不要なコピーを削除してください。ストレージ全体、連絡先、位置情報への権限は要求しません。一時データの消去は最善を尽くしますが、完全消去は保証しません。",
        ],
        [
          "Google Play での購入",
          "アプリは無料でダウンロードでき、アカウント15件、契約5件、ペーパーアーカイブテーマを利用できます。非消費型の完全版を一度購入すると上限と追加テーマが解除され、自動更新はありません。決済、ストアアカウント、取引情報は Google が処理します。アプリは購入レシートを端末内で検証し、権利情報を暗号化して保存します。カード情報は受け取らず、保管庫やレシートを開発者サーバーに送信しません。購入、復元、フォアグラウンドでの確認には通信を利用する場合があります。日常の記録はオフラインで使用できます。",
        ],
        [
          "システム機能",
          "生体認証はシステムを利用し、生体情報のテンプレートは取得しません。通知は標準で一般的な内容を表示します。通知や正確なアラームの許可は利用者が選択でき、システムの制限で配信に影響する場合があります。パソコン接続中はフォアグラウンド通知を表示し、停止すると終了します。広告、行動分析、第三者クラッシュ送信 SDK は組み込んでいません。Android や Google のシステム診断にはそれぞれの設定が適用されます。",
        ],
        [
          "保存と削除",
          "記録は削除または再構築するまで端末内に残ります。ごみ箱の通常の保存期間は30日で、認証後に完全削除できます。外部への書き出しとバックアップは別途管理してください。システムバックアップと端末移行から保管庫情報を除外しています。アンインストール、データ消去、端末の鍵の無効化により記録を復元できなくなる場合があります。独立した暗号化バックアップを保管してください。購入の復元は利用権の復元であり、記録の復元ではありません。",
        ],
        [
          "お問い合わせと変更",
          "お問い合わせ時に送ったメールアドレス、本文、添付ファイルは利用するメールサービスでも処理されます。実際のパスワードや保管庫全体を送らないでください。公開ポリシーのホスティング事業者が IP、ブラウザー情報、アクセス日時を記録する場合があります。公開前に運営者と保存期間を明記します。変更は公開ページに記載します。更新日：2026年9月7日。",
        ],
      ],
    },
  };
}
