# 安全审查与报告

本仓库接受安全审查，公开源码不等于独立审计通过，也不证明绝对安全或没有后门。

## 报告方式

请通过 [官方支持页面](https://maskden.com/cardock/support) 的联系渠道报告可利用漏洞。建议先私下提供：渠道、版本、相关源码位置、合成数据复现步骤、预期与实际结果，以及影响范围。

不要提交真实密码、保险库、备份口令、购买凭据、签名私钥、个人设备标识或生产订单。使用自己有权测试的隔离环境和虚构数据，不测试他人的设备、账户或生产订单。没有固定响应时限或已完成外部审计的承诺。

源码许可允许公开审查发现及合理必需的少量代码片段，包括负面结论，不要求作者先批准结论。先私下协调是建议，不是禁止批评的许可条款。

## 需要分别检查的边界

- 保险库、诱饵库、订阅只读投影及商业授权属于不同安全边界。取得商业权益不代表取得解密保险库的权限。
- 加密实现、密码强度、系统认证、设备安全和备份保管都影响实际安全。软件不承诺防止已完全受控、root 或越狱设备上的攻击。
- 网站 Android 正式包无 INTERNET 权限；外部浏览器打开的购买、订单和支持网站仍会联网。
- Play 和 iOS 的商店接口、系统服务，以及用户主动启动的局域网功能不能被描述为“完全不联网”。
- 临时局域网电脑录入只用于用户主动启动的短会话。初始 HTTP 页面不能认证页面来源，不宣称完整 HTTPS 或端到端安全。iOS 后台挂起也可能中断会话。
- 离线授权无法即时获知退款或撤销；应用授权保护不能保证在攻击者控制程序时不可修改。
- 查看源码、成功编译、测试通过、官方包签名与实际安全审计是不同证据。本次不声称已完成与官方商店分发包的逐字节可复现构建验证。

## 私人审查构建

在隔离模拟器或专用测试设备中使用虚构数据。自行签名的版本没有官方签名身份，不能冒充官方更新或用它验证正式商店购买。不要覆盖存有真实密码的日用安装，也不要通过卸载或清空数据来绕过签名不匹配。

## English

Report exploitable issues using the contact channel on the official support page. Include the channel, release, source location, synthetic reproduction and impact. Do not submit real vaults, passwords, credentials, device identifiers or production orders. Private disclosure is encouraged; publishing critical findings does not require the author's approval. Source publication is not a completed independent audit or a no-backdoor guarantee. Builds, signatures, store transactions and security review have distinct evidence boundaries.
