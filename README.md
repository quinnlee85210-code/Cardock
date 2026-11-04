# Cardock

**公开源码，接受安全审查。官方完整版继续采用一次性买断。**

Cardock 是本地账号、密码与订阅记录工具。本仓库按网站 Android、Google Play Android 与 App Store iOS 三个渠道提供客户端源码，方便检查加密、数据存储、网络访问、备份恢复和授权行为。

这是 **Source Available（源码可见）** 项目，采用 [Cardock 源码审查许可](LICENSE)，**不是允许自由再分发的开源项目**。可以阅读、下载并在私人环境中编译、修改和运行以进行安全审查、验证与评估；本许可不授权另行分发安装包、发布衍生产品或闭源商业改版。GitHub 平台条款授予的浏览、Fork 等权利，以及第三方组件的原许可证权利，不受本项目自有许可限制。

[English](README.en.md) · [官方下载](https://maskden.com/cardock/download) · [支持](https://maskden.com/cardock/support) · [构建与检查](BUILDING.md) · [安全边界](SECURITY.md)

## 为什么公开源码

保存密码的工具应该允许别人检查它如何工作。公开源码提供了验证条件，但不等于已经通过独立安全审计，也不构成“没有后门”“没有漏洞”或绝对安全的证明。欢迎提出有证据的问题，包括负面审查结论。

本仓库不包含用户保险库、购买订单、生产服务凭据、应用签名私钥、授权签发私钥或内部开发历史。公开的验签公钥、应用标识和证书指纹是检查正式版本所需的信息。

## 版本与目录

| 目录 | 对应版本 | 用途与网络边界 |
| --- | --- | --- |
| [channels/android-website](channels/android-website) | 1.0.3+87 / schema15 | 官网 Android 客户端；正式包不申请 INTERNET 权限，购买和订单操作交给外部浏览器，应用离线验证授权；不提供临时局域网电脑录入。 |
| [channels/android-play](channels/android-play) | 1.0.2+86 / schema15 | Google Play 客户端；使用 Play Billing，保留用户主动启动的临时局域网电脑录入。 |
| [channels/ios-appstore](channels/ios-appstore) | 1.0.1+92 / schema15（已提交审核，等待审核，未正式发布） | iOS 客户端；使用 StoreKit，保留用户主动启动的临时局域网电脑录入；最低 iOS 16。 |

三个目录是各渠道的独立源码快照，避免把不同渠道的权限、购买和平台实现混在一起。每个快照可能包含 Flutter 跨平台工程模板；其他平台目录的存在不表示该渠道已经在那些平台发布。iOS 的 `third_party/file_picker` 是必需的相对路径依赖。

iOS 92 已提交 App Store 审核，当前正在等待审核；当前 App Store 正式版本仍为 1.0.0。该快照包括系统认证重置、密保恢复修复、三语名称和设置页文案更新。源码快照可供审查不代表 Apple 已批准或发布更新。

原始来源、逐文件 SHA256 及公开副本的构建／测试路径适配见 [SOURCE_PROVENANCE.json](SOURCE_PROVENANCE.json) 和 [PUBLICATION.md](PUBLICATION.md)。本次公开不改变现有应用版本、购买权益或用户数据格式。

## 安全审查入口

在各渠道的 `app/` 内：

- `lib/core/security/`、`lib/core/storage/`：主密码、加密保险库、诱饵库、迁移、备份与恢复。
- `lib/core/entitlements/`：免费额度、官网验签及商店授权接口。
- `lib/core/temporary_web/`、`tool/temporary_web_client.dart`：临时电脑会话与网页客户端；网站 Android 渠道未启用该产品入口。
- `android/app/src/`、`ios/Runner/`：系统认证、平台文件接口、网络权限和商店桥接。
- `test/`：合成数据测试；测试密钥和虚构凭据不代表正式签发凭据。

业务记录保存在本地保险库；商业授权与保险库分开处理。临时电脑页的初始 HTTP 页面存在真实性验证边界，不宣称完整 HTTPS 或端到端安全。详细限制与报告渠道见 [SECURITY.md](SECURITY.md)。

## 官方版本与收费

官方应用免费下载。免费版可记录最多 15 个账号、5 个订阅，并使用默认主题；完整版解锁数量限制及高级主题等功能。官网既有价格为人民币 9.90 元一次买断；各商店和地区的实际价格以官方付款界面为准，不自动续费。

官方版本由开发者签名并持续维护。私人审查构建不会获得官方签名、商店购买或官网授权身份；不要把它覆盖安装到存有真实密码的日用设备。官方下载入口集中在 [maskden.com](https://maskden.com/cardock/download)。

## 许可与反馈

Cardock 自有代码适用 [LICENSE](LICENSE)；第三方代码、图标、运行时片段和许可证继续按各自条款处理，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。Cardock、Maskden 名称和标识不用于为第三方版本背书。

普通问题可提交 Issue；涉及可利用漏洞或敏感数据的问题，建议先按 [SECURITY.md](SECURITY.md) 私下报告。代码贡献接收规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。
