import Flutter
import UIKit
import StoreKit
import CryptoKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var purchaseBridge: CardockStorePurchaseBridge?
  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CardockStorePurchaseBridge") {
      purchaseBridge = CardockStorePurchaseBridge(messenger: registrar.messenger())
    }
  }
}

/// StoreKit verifies Apple's signature; the app additionally checks product, environment,
/// revocation and Apple's current-device digest. No boolean purchase flag is persisted.
@MainActor
private final class CardockStorePurchaseBridge {
  private let channel: FlutterMethodChannel
  private let config: [String: String]
  private var updates: Task<Void, Never>?
  private var buying = false
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
        guard let self = self else { result(false); return }
        switch call.method {
        case "inspect":
          guard self.configured, let device = AppStore.deviceVerificationID else { result(["trusted": false]); return }
          let digest = SHA256.hash(data: Data(device.uuidString.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
          result(["trusted": true, "channel": "app_store", "applicationId": self.bundleID, "installationKeySha256": digest])
        case "verifyStore":
          let refresh = (call.arguments as? [String: Any])?["refresh"] as? Bool ?? false
          if refresh {
            do { try await AppStore.sync() } catch { result(await self.currentEntitlement()); return }
          }
          result(await self.currentEntitlement())
        case "storePrice":
          guard self.configured else { result(nil); return }
          let products = try? await Product.products(for: [self.productID])
          result(products?.first(where: { $0.id == self.productID && $0.type == .nonConsumable })?.displayPrice)
        case "purchaseStore": result(await self.purchase())
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        guard let self = self else { return }
        if let transaction = self.verified(result) { await transaction.finish() }
      }
    }
  }
  private func verified(_ result: VerificationResult<Transaction>) -> Transaction? {
    guard configured, case .verified(let transaction) = result,
      transaction.productID == productID, transaction.productType == .nonConsumable,
      transaction.revocationDate == nil, transaction.expirationDate == nil,
      !transaction.isUpgraded, let device = AppStore.deviceVerificationID else { return nil }
    let testing = config["CARDOCK_STORE_TESTING"] == "true"
    guard transaction.environment == .production || (testing && (transaction.environment == .sandbox || transaction.environment == .xcode)) else { return nil }
    let text = transaction.deviceVerificationNonce.uuidString.lowercased() + device.uuidString.lowercased()
    guard Data(SHA384.hash(data: Data(text.utf8))) == transaction.deviceVerification else { return nil }
    return transaction
  }
  private func currentEntitlement() async -> Bool {
    guard configured else { return false }
    for await result in Transaction.currentEntitlements {
      if let transaction = verified(result) { await transaction.finish(); return true }
    }
    return false
  }
  private func purchase() async -> String {
    guard configured, !buying else { return "unavailable" }
    buying = true
    defer { buying = false }
    do {
      guard let product = try await Product.products(for: [productID]).first,
        product.id == productID, product.type == .nonConsumable else { return "unavailable" }
      switch try await product.purchase() {
      case .success(let result):
        guard let transaction = verified(result) else { return "unavailable" }
        await transaction.finish()
        return "purchased"
      case .pending: return "pending"
      case .userCancelled: return "cancelled"
      @unknown default: return "unavailable"
      }
    } catch { return "unavailable" }
  }
  deinit { updates?.cancel() }
}
