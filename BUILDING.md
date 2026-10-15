# 私人编译与检查

这些步骤用于 [LICENSE](LICENSE) 允许的安全审查、验证与评估。自编译产物不具有官方签名或购买身份。本仓库不提供正式签名私钥、生产凭据或开发者商店账号。

## 工具链

- Flutter 3.44.8，配套 Dart 3.12.2；保留各渠道现有 `pubspec.lock`。
- Android：JDK 17、Android SDK 36、Build Tools 36.0.0，以及该 Flutter 版本选择的 NDK。Gradle wrapper 由 Flutter 构建工具按已提交的配置生成。
- iOS：macOS 与 Xcode；原发行验证使用 Xcode 26.6，最低 iOS 16。Windows 不能完成 iOS 原生编译或签名验证。
- 安装工具和下载依赖需符合使用者所在地、网络和平台的要求；本仓库不写入开发者的本机代理或 SDK 绝对路径。

## 获取依赖并检查

进入相应快照的 `app` 目录，例如：

```text
cd channels/android-website/app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

已具备完整锁定版本缓存时可使用 `flutter pub get --offline --enforce-lockfile`。不要为通过解析而更新锁文件。普通测试中的真实浏览器项目默认跳过；显式启用时需要独立配置 Chrome。

iOS 必须保留 `channels/ios-appstore/third_party/file_picker` 与 `app` 的相对位置。汇率测试依赖同级 `manifests`；资产边界测试依赖同级 `.gitignore` 和 `app/tool/promo_signer`，这些都已包含。

## Android 无签名 Release 检查

在当前终端进程中将 `CARDOCK_SIGNING_MODE` 设为 `unsigned`。PowerShell 示例：

```powershell
$env:CARDOCK_SIGNING_MODE = 'unsigned'
flutter build apk --release --dart-define-from-file=../config/distribution/website.public.json
```

Google Play 快照使用 `google_play.public.json`；检查 AAB 时将 `apk` 改为 `appbundle`。必须匹配渠道配置，尤其网站渠道的离线 Manifest 由 `website` 构建参数选择。无签名 APK 用于构建检查，不能作为可安装的官方产物。

需要安装私人评估版本时，可在隔离环境中使用自己的 PKCS12 签名：`CARDOCK_SIGNING_MODE=formal`、`CARDOCK_KEYSTORE_PATH`、`CARDOCK_KEY_ALIAS`、`CARDOCK_KEYSTORE_PASSWORD`。口令只通过私人进程环境传入，不写仓库或日志。`continuity` 在此仅使用本环境的 debug signer，不会产生开发者的官方证书。

公开配置保留官方证书指纹和验签公钥。自签名构建与官方指纹不匹配时，商业购买桥接拒绝信任是预期行为；私人构建不等于官方购买／授权测试。不要把自编译版本覆盖安装到日用官方安装上。

## iOS 无签名编译

在 macOS 的 iOS 快照 `app` 目录运行：

```text
flutter build ios --release --no-codesign --dart-define-from-file=../config/distribution/app_store.public.json
```

签名运行需在自己的私人副本中配置本人 Apple Team 与适合测试的 Bundle ID，遵守 Apple 要求。仓库内官方 Team／Bundle／商品标识是公开发行身份，不授予访问对应账号或创建有效交易的权限。不要修改后把私人构建标为官方版本。

## 临时网页客户端

各快照的 `tool/temporary_web_client.dart` 与 `assets/temporary_web/app.js` 必须配对审查。可输出到新目录，避免覆盖原始发布资源：

```text
dart compile js -O2 --no-source-maps -o build/review/app.js tool/temporary_web_client.dart
```

先创建 `build/review`。该命令用于重建检查；没有声明它已与已发布 JS 或官方安装包逐字节一致。生成 JS 含 Dart 运行时和第三方依赖代码，原许可继续有效。

## 本次公开副本的适配

只调整了测试／辅助工具路径：原生测试使用当前 Gradle user home；两个 Android 通知测试通过 `package_config.json` 查找插件；版本边界测试改为检查已提交的 Flutter 版本传递配置，不再读取开发者本机生成的 `local.properties`；开发环境签发辅助批处理使用 `DART_EXE` 或 PATH。运行时 Dart/Kotlin/Swift、资源、公开生产配置和依赖锁保持各发布来源的字节。详细差异和实际检查结果见 [PUBLICATION.md](PUBLICATION.md)。
