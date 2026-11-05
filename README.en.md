# Cardock

**Source code available for security review. Official full-version builds remain a one-time purchase.**

Cardock stores personal account, password and subscription records in a local vault. This repository publishes separate client source snapshots for the website Android, Google Play Android and App Store iOS channels.

This is a **source-available project, not an open-source license grant**. The [Cardock Source Review License](LICENSE) permits private inspection, compilation, modification and execution for security review, verification and evaluation. It does not authorize redistributing application binaries, publishing derivative products or closed-source commercial variants. Independent rights granted by GitHub's platform terms and by third-party licenses remain unaffected.

[中文](README.md) · [Official downloads](https://maskden.com/cardock/download) · [Build instructions](BUILDING.md) · [Security](SECURITY.md)

| Snapshot | Release | Important distinction |
| --- | --- | --- |
| `channels/android-website` | 1.0.3+87, schema15 | Official APK has no INTERNET permission; purchase and order interactions use an external browser, followed by offline license verification. No temporary LAN input feature. |
| `channels/android-play` | 1.0.2+86, schema15 | Play Billing and an explicitly started temporary LAN input feature. |
| `channels/ios-appstore` | 1.0.1+92, schema15 (publicly released) | StoreKit and temporary LAN input; iOS 16 or later. Includes the required vendored `third_party/file_picker` dependency. |

Each directory is a separate channel snapshot. Platform templates in a snapshot are not proof that it was released on those platforms. Source provenance, per-file hashes and the small build/test portability changes are recorded in [SOURCE_PROVENANCE.json](SOURCE_PROVENANCE.json) and [PUBLICATION.md](PUBLICATION.md).

iOS 1.0.1 is publicly released. The maintainer confirmed publication and normal overall use on 2026-11-04 (America/Los_Angeles). Apple's public US lookup returns version 1.0.1, but does not expose the internal build number; build 92 is traced through the previously submitted build and this publication confirmation. This snapshot includes device-authenticated reset and recovery fixes, localized app names, and settings copy updates. Overall-use confirmation is not new purchase, restore, or per-device test evidence.

Source publication enables inspection. It is not an independent audit or proof that a program contains no backdoors or vulnerabilities. The initial HTTP page used for temporary LAN input has a documented authenticity limitation; the feature is not described as fully HTTPS or end-to-end secure. See [SECURITY.md](SECURITY.md).

Official apps are free to download. The free tier includes 15 accounts, 5 subscriptions and the default theme. A one-time full-version purchase removes those quantity limits and unlocks premium appearance options. The established website price is CNY 9.90; store and regional prices are shown by the official payment UI. No automatic renewal.

This repository excludes production signing keys, license-issuing private keys, credentials, purchase records, user vaults and internal development history. Verification public keys and public certificate fingerprints are intentionally retained. Private review builds do not have an official release identity or official purchase entitlement.

Third-party materials retain their original licenses, including generated runtime portions; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Please read [CONTRIBUTING.md](CONTRIBUTING.md) before sending patches.
