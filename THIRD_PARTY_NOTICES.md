# 第三方材料与许可 / Third-party materials and licenses

顶层 `LICENSE` 只适用于有权许可的 Cardock 自有材料。**它不收回、替代或限制第三方许可证已经授予的权利。** 第三方材料即使与 Cardock 代码放在同一目录、源码文件或生成资源内，仍适用相应原许可。不能将 Cardock 的“不得分发／商业衍生”条件套用于独立第三方组件。

## 本仓库保留的材料

| 材料 | 位置与处理 |
| --- | --- |
| 锁定 Pub 依赖的许可 | [third_party_licenses/pub](third_party_licenses/pub)；88 个不同的锁定 hosted 包，各自保留原许可文件。版本、归档 SHA256 和许可文件 SHA256 见 [清单](third_party_licenses/MANIFEST.json)。 |
| Flutter 与 Dart SDK 许可 | [Flutter 3.44.8](third_party_licenses/Flutter-3.44.8-LICENSE)、[Dart 3.12.2](third_party_licenses/Dart-3.12.2-LICENSE)。仓库不包含完整 SDK；许可材料不是 SDK 分发包。 |
| file_picker 10.3.10 的 iOS 集成副本 | [third_party/file_picker](channels/ios-appstore/third_party/file_picker) 及其中 MIT `LICENSE`、`UPSTREAM_FILES.json`、`CARDOCK_INTEGRATION.md`。保留本地修改说明和相对路径依赖。 |
| archive、Tika、SLF4J、Commons IO、desugar 的附属声明 | 各渠道 `app/assets/licenses/` 内保留已有 LICENSE／NOTICE，包含 archive 内部其他组件声明。 |
| 品牌识别图标 | 各渠道 `app/assets/brands/v1/THIRD_PARTY_NOTICES.txt`：部分图形源自 Simple Icons 16.28.0，CC0-1.0。名称和商标仍属于各自权利人，仅用于识别用户录入的服务，不表示授权或背书。 |
| Unicode 归一化 | unorm_dart 0.3.2，MIT；品牌通知保留声明，各渠道 `manifests/cardock-unorm-dart-source.json` 保存原来源和哈希。 |
| 生成的临时网页 JavaScript | 各渠道 `app/assets/temporary_web/app.js` 包含 Cardock 编译结果、Dart 运行时及第三方依赖部分；这些第三方部分继续适用原许可。对应审查源码为各自 `app/tool/temporary_web_client.dart`。 |

许可文件从本项目既有、与各 `pubspec.lock` 版本对应的缓存收集；缓存记录的包归档 SHA256 与锁文件匹配。本次没有升级依赖，也没有把许可清单当作漏洞扫描或整个供应链安全证明。

Android 的 Gradle／Maven 依赖和平台 SDK 根据已提交构建配置获取，继续遵守各自许可。此仓库没有重新分发这些平台 SDK 或完整运行时二进制。构建官方安装包时仍须保留工具链生成的适用许可通知。

## English

The root license covers only Cardock-owned materials the Licensor is entitled to license. Third-party licenses remain in effect and take precedence for their materials, including vendored dependencies, artwork and third-party portions of generated JavaScript. The root restrictions do not revoke rights granted in those components.

The supplied license collection covers the 88 distinct hosted packages pinned by the three snapshots, with original license files and hashes. The iOS vendored file_picker dependency retains its MIT license and integration record. Existing native/asset notices remain in each snapshot. Flutter and Dart license copies are included; the SDKs themselves are not redistributed. This collection is not a vulnerability assessment or a claim that every platform dependency has undergone an independent audit.
