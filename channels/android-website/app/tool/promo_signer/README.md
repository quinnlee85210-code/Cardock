# Cardock 离线推广签码工具

本工具使用 Ed25519 为指定设备的申请码签发永久完整版权益。应用只内置公钥并离线验签；私钥和签发记录只保存在开发者本机，不得提交到 Git、发送给用户或打入 APK。

所有命令均在 `app` 目录执行。

## 日常使用：双击签发并自动校验

生产密钥已经建立后，日常给亲友或首批用户发码只需双击：

```text
tool\promo_signer\promo_sign.bat
```

窗口会依次要求输入用户的 8 位申请码、本机备注，并输入 `YES` 做最终确认。工具会在本机完成 Ed25519 签发、公钥自校验和 CSV 记录；只有校验通过后才展示可发送给用户的激活码。备注可留空，只保存在本机 `issued_codes.csv`，不进入激活码。

日常签发不要再次运行 `keygen`，也不要把 `promo_private.key`、`issued_codes.csv` 或整个签码工具目录发送给用户。完整激活码只发送给提供对应申请码的用户。

## 第一步：生成密钥

```powershell
..\toolchains\flutter\3.44.8\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\promo_signer\promo_signer.dart keygen
```

命令会在本工具目录生成被 `.gitignore` 排除的 `promo_private.key`，并只向终端输出公钥 Dart 常量。把公钥常量粘贴到 `lib/core/entitlements/promo_activation_config.dart` 后重新构建应用。

私钥丢失后不能再签发与当前应用公钥匹配的新激活码。请自行制作加密的离线私钥备份，但绝不能把私钥放进仓库、源码备份、发布包、聊天记录或云同步目录。

一旦带该公钥的版本正式发布，不得重新执行 `keygen --force` 更换密钥，否则既有用户保存的激活码会在应用升级后验签失败并安全回退免费态。

## 第二步：按申请码签发

```powershell
..\toolchains\flutter\3.44.8\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\promo_signer\promo_signer.dart sign --request 8位申请码 --note "首批体验用户"
```

命令会输出可发送给用户的激活码，并把签发时间、申请码、激活码和备注追加到同样被忽略的 `issued_codes.csv`。备注只保存在开发者本机，不进入激活码 payload。

此命令保留给高级或自动化使用；日常操作优先使用上方 `promo_sign.bat`，它会自动执行签发后的公钥校验。

## 第三步：发码前自校验

```powershell
..\toolchains\flutter\3.44.8\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\promo_signer\promo_signer.dart verify --code 激活码
```

看到“验证通过”、申请码和签发时间后再发送。用户卸载重装会获得新的安装 ID 和申请码，旧激活码按设计不能在新安装或其他设备上使用。
