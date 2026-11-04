import Flutter
import UIKit
import StoreKit
import CryptoKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var launcherIconBridge: CardockLauncherIconBridge?
  private var purchaseBridge: CardockStorePurchaseBridge?
  private var coreBridge: CardockCoreBridge?
  private var biometricBridge: CardockBiometricSecretBridge?
  private var rebuildBridge: CardockVaultRebuildBridge?
  private var localNetworkBridge: CardockLocalNetworkBridge?
  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CardockStorePurchaseBridge") {
      launcherIconBridge = CardockLauncherIconBridge(messenger: registrar.messenger())
      coreBridge = CardockCoreBridge(messenger: registrar.messenger())
      biometricBridge = CardockBiometricSecretBridge(messenger: registrar.messenger())
      rebuildBridge = CardockVaultRebuildBridge(messenger: registrar.messenger())
      localNetworkBridge = CardockLocalNetworkBridge(messenger: registrar.messenger())
      purchaseBridge = CardockStorePurchaseBridge(messenger: registrar.messenger())
    }
  }
}

/// StoreKit verifies both receipts; the app binds environment, bundle, product and device.
/// No boolean purchase flag is persisted.
@MainActor
final class CardockStorePurchaseBridge {
  private let channel: FlutterMethodChannel
  private let config: [String: String]
  private var updates: Task<Void, Never>?
  private var buying = false
  // A bounded, in-memory snapshot. Never include receipts, JWS, Apple IDs,
  // device identifiers, localized error messages or NSError.userInfo.
  private var lastPurchase: [String: Any] = [:]

  private func errorCodes(_ error: Error) -> [[String: Any]] {
    var codes: [[String: Any]] = []
    var current: NSError? = error as NSError
    for _ in 0..<3 {
      guard let value = current else { break }
      let domain = value.domain
      let safe = domain.count <= 100 && domain.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
      codes.append(["domain": safe ? domain : "redacted", "code": value.code])
      current = value.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return codes
  }

  private func queryProduct(_ trace: inout [String: Any]) async throws -> Product? {
    trace["stage"] = "product_query"
    trace["requestedIDs"] = [productID]
    let start = ContinuousClock.now
    defer {
      let elapsed = start.duration(to: .now).components
      trace["queryMilliseconds"] = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
    }
    let products = try await Product.products(for: [productID])
    trace["returnedCount"] = products.count
    trace["returnedIDs"] = products.map(\.id)
    trace["notFoundIDs"] = products.contains(where: { $0.id == productID }) ? [] : [productID]
    guard let product = products.first(where: { $0.id == productID }) else {
      trace["stage"] = "product_not_found"
      return nil
    }
    guard product.type == .nonConsumable else {
      trace["stage"] = "product_type_mismatch"
      return nil
    }
    trace["stage"] = "product_ready"
    trace["displayPrice"] = product.displayPrice
    return product
  }

  private func diagnostics() async -> [String: Any] {
    var trace: [String: Any] = [
      "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
      "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
      "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
      "channel": config["CARDOCK_DISTRIBUTION"] ?? "unknown",
      "configured": configured,
      "canMakePayments": AppStore.canMakePayments,
      "purchaseInProgress": buying,
      "lastPurchase": lastPurchase,
      "storefront": "unknown",
    ]
    guard configured else { trace["stage"] = "configuration"; return trace }
    guard !buying else { trace["stage"] = "purchase_in_progress"; return trace }
    // Only this explicitly requested check reads the current storefront.
    if let storefront = await Storefront.current {
      trace["storefront"] = ["id": storefront.id, "countryCode": storefront.countryCode]
    }
    do { _ = try await queryProduct(&trace) }
    catch { trace["errors"] = errorCodes(error) }
    return trace
  }
  private var productID: String { config["CARDOCK_STORE_PRODUCT_ID"] ?? "" }
  private var bundleID: String { config["CARDOCK_APPLICATION_ID"] ?? "" }
  private var configured: Bool {
    config["CARDOCK_DISTRIBUTION"] == "app_store" && !productID.isEmpty &&
      !bundleID.isEmpty && Bundle.main.bundleIdentifier == bundleID
  }
  init(messenger: FlutterBinaryMessenger) {
    var values: [String: String] = [:]
    let defines = Bundle.main.object(forInfoDictionaryKey: "CardockPublicDefines") as? String ?? ""
    for part in defines.split(separator: ",") {
      guard let data = Data(base64Encoded: String(part)), let text = String(data: data, encoding: .utf8),
        let equals = text.firstIndex(of: "=") else { continue }
      values[String(text[..<equals])] = String(text[text.index(after: equals)...])
    }
    config = values
    channel = FlutterMethodChannel(name: "cardock/commercial_license", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor [weak self] in
        guard let self = self else { result(CardockCoreBridge.error("interrupted")); return }
        switch call.method {
        case "inspect":
          guard self.configured, let device = AppStore.deviceVerificationID else { result(["trusted": false]); return }
          let digest = SHA256.hash(data: Data(device.uuidString.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
          result(["trusted": true, "channel": "app_store", "applicationId": self.bundleID, "installationKeySha256": digest])
        case "verifyStore":
          let refresh = (call.arguments as? [String: Any])?["refresh"] as? Bool ?? false
          if refresh {
            do { try await AppStore.sync() } catch { result(CardockCoreBridge.error("store_sync_incomplete")); return }
          }
          result(await self.currentEntitlement())
        case "storePrice":
          guard self.configured else { result(nil); return }
          let products = try? await Product.products(for: [self.productID])
          result(products?.first(where: { $0.id == self.productID && $0.type == .nonConsumable })?.displayPrice)
        case "storeDiagnostics": result(await self.diagnostics())
        case "purchaseStore": result(await self.purchase())
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        guard let self = self else { return }
        let entitlement = await self.currentEntitlement()
        if let owned = entitlement as? Bool, owned, let transaction = try? await self.verified(result) {
          await transaction.finish()
        }
        self.channel.invokeMethod("entitlementsChanged", arguments: nil)
      }
    }
  }
  private func verified(_ result: VerificationResult<Transaction>) async throws -> Transaction? {
    guard configured, case .verified(let transaction) = result,
      transaction.productID == productID else { return nil }
    // Request the signed app transaction only after an owned purchase exists.
    let application = try await AppTransaction.shared
    return CardockStoreReceiptVerifier.verifiedPurchase(
      result, application: application, productID: productID, bundleID: bundleID,
      deviceID: AppStore.deviceVerificationID,
      localTesting: config["CARDOCK_STORE_TESTING"] == "true")
  }
  private func currentEntitlement() async -> Any {
    guard configured else { return false }
    for await result in Transaction.currentEntitlements {
      do {
        if try await verified(result) != nil { return true }
      } catch {
        // A transport failure is not proof that an earlier verified purchase was revoked.
        return CardockCoreBridge.error("store_context_incomplete")
      }
      if case .unverified = result { return CardockCoreBridge.error("transaction_unverified") }
    }
    return false
  }
  private func purchase() async -> String {
    guard !buying else { return "pending" }
    var trace: [String: Any] = ["stage": "configuration", "configured": configured,
      "canMakePayments": AppStore.canMakePayments, "purchaseInvoked": false]
    defer { lastPurchase = trace }
    guard configured else { return "unavailable" }
    guard AppStore.canMakePayments else {
      trace["stage"] = "payments_restricted"
      return "unavailable"
    }
    buying = true
    defer { buying = false }
    do {
      guard let product = try await queryProduct(&trace) else { return "unavailable" }
      trace["stage"] = "purchase"
      trace["purchaseInvoked"] = true
      switch try await product.purchase() {
      case .success(let result):
        trace["stage"] = "transaction_verification"
        guard let transaction = try await verified(result) else { return "unavailable" }
        trace["stage"] = "current_entitlement"
        guard let current = await currentEntitlement() as? Bool, current else { return "pending" }
        await transaction.finish()
        channel.invokeMethod("entitlementsChanged", arguments: nil)
        trace["stage"] = "verified_and_finished"
        return "purchased"
      case .pending:
        trace["stage"] = "pending"
        return "pending"
      case .userCancelled:
        trace["stage"] = "cancelled"
        return "cancelled"
      @unknown default:
        trace["stage"] = "unknown_purchase_result"
        return "unavailable"
      }
    } catch {
      trace["errors"] = errorCodes(error)
      return "unavailable"
    }
  }
  deinit { updates?.cancel() }
}

/// Uses the public UIKit API and returns only after the system completes.
@MainActor
private final class CardockLauncherIconBridge {
  private let channel: FlutterMethodChannel
  private let variants: Set<String> = ["ceramicBlue", "sakuraMist", "paperArchive",
    "lilacMoon", "glacierBlue", "mistCoral", "neonZero", "obsidianGold"]
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "cardock/launcher_icon", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor [weak self] in
        guard let self else { result(FlutterError(code: "UNAVAILABLE", message: nil, details: nil)); return }
        let app = UIApplication.shared
        switch call.method {
        case "getLauncherIcon":
          let name = app.alternateIconName
          if name == nil { result("paperArchive"); return }
          guard let name, name.hasPrefix("Cardock"), self.variants.contains(String(name.dropFirst(7))) else {
            result(FlutterError(code: "ICON_STATE_READ_FAILED", message: nil, details: nil)); return
          }
          result(String(name.dropFirst(7)))
        case "setLauncherIcon":
          guard let args = call.arguments as? [String: Any], let variant = args["variant"] as? String,
            self.variants.contains(variant) else {
            result(FlutterError(code: "INVALID_VARIANT", message: nil, details: nil)); return
          }
          guard app.supportsAlternateIcons, app.applicationState == .active else {
            result(FlutterError(code: "ICON_SWITCH_FAILED", message: nil, details: nil)); return
          }
          let name = variant == "paperArchive" ? nil : "Cardock" + variant
          if app.alternateIconName == name { result(nil); return }
          app.setAlternateIconName(name) { error in
            Task { @MainActor in
              if error != nil || UIApplication.shared.alternateIconName != name {
                result(FlutterError(code: "ICON_SWITCH_FAILED", message: nil, details: nil))
              } else { result(nil) }
            }
          }
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
