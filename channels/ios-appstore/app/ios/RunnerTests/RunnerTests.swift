import Flutter
import UIKit
import XCTest
import StoreKit
import StoreKitTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testBoundedFileReadAndOversizeRejection() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data([1, 2, 3]).write(to: file)
    XCTAssertEqual(try CardockCoreBridge.readBounded(file, maximum: 3), Data([1, 2, 3]))
    XCTAssertThrowsError(try CardockCoreBridge.readBounded(file, maximum: 2))
  }
  func testEmptyAndMissingFileAreFailures() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    XCTAssertThrowsError(try CardockCoreBridge.readBounded(file, maximum: 3))
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    XCTAssertThrowsError(try CardockCoreBridge.readBounded(file, maximum: 3))
  }
}


final class CardockStorePolicyTests: XCTestCase {
  func testSignedAppAndPurchaseEnvironmentsMustMatch() {
    let unknown = AppStore.Environment(rawValue: "FutureUnknownEnvironment")
    let environments: [AppStore.Environment] = [.production, .sandbox, .xcode, unknown]
    for app in environments {
      for transaction in environments {
        for testing in [false, true] {
          let storePair = app == transaction && (app == .production || app == .sandbox)
          #if DEBUG
            let xcodePair = app == .xcode && transaction == .xcode && testing
          #else
            let xcodePair = false
          #endif
          XCTAssertEqual(
            CardockStoreReceiptVerifier.permitsEnvironment(
              transaction: transaction, application: app, localTesting: testing),
            storePair || xcodePair)
        }
      }
    }
  }

  func testDeviceDigestRequiresTheMatchingDevice() {
    let nonce = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let device = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let hex = "d0e337c2dab0ef7dc720ea3ddad1e910a3f0b86e3258e31d3e16fcd006227a91b1f598a3a9e7076293102d1961c2208f"
    let bytes = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
    let digest = Data(bytes)
    XCTAssertTrue(CardockStoreReceiptVerifier.matchesDevice(nonce: nonce, digest: digest, deviceID: device))
    XCTAssertFalse(CardockStoreReceiptVerifier.matchesDevice(nonce: nonce, digest: digest, deviceID: nil))
    XCTAssertFalse(CardockStoreReceiptVerifier.matchesDevice(nonce: nonce, digest: digest, deviceID: UUID()))
    XCTAssertFalse(CardockStoreReceiptVerifier.matchesDevice(nonce: nonce, digest: Data(), deviceID: device))
  }
}

// Explicit local Xcode diagnostics. No real store payment or AppStore.sync is invoked.
#if CARDOCK_LOCAL_STOREKIT_TESTS
private final class CardockTestMessenger: NSObject, FlutterBinaryMessenger {
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    callback?(nil)
  }
  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    handlers.removeAll()
  }
  func invoke(_ method: String, arguments: Any? = nil) async -> Any? {
    guard let handler = handlers["cardock/commercial_license"] else { return nil }
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let message = codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))
    return await withCheckedContinuation { continuation in
      handler(message) { response in
        guard let response else { continuation.resume(returning: nil); return }
        continuation.resume(returning: codec.decodeEnvelope(response))
      }
    }
  }
}

final class CardockStoreKitLocalTests: XCTestCase {
  private func latestTransaction(productID: String, expectedID: UInt64) async throws -> VerificationResult<Transaction> {
    // The test-session write and StoreKit 2 read can complete on different queues.
    for _ in 0..<50 {
      if let result = await Transaction.latest(for: productID) {
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
          if transaction.id == expectedID { return result }
        }
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    return try XCTUnwrap(nil as VerificationResult<Transaction>?, "The purchased transaction must become readable.")
  }

  @MainActor
  func testVerifiedNativeBridgePurchaseRestoreReadAndRefund() async throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("This optional StoreKit diagnostic requires iOS 17 or later.")
    }
    let configuration = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "CardockLocal", withExtension: "storekit"))
    let session = try SKTestSession(contentsOf: configuration)
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions() }

    let messenger = CardockTestMessenger()
    let bridge = CardockStorePurchaseBridge(messenger: messenger)
    defer { withExtendedLifetime(bridge) {} }
    let beforePurchase = await messenger.invoke("verifyStore", arguments: ["refresh": false])
    XCTAssertEqual(beforePurchase as? Bool, false)
    let price = await messenger.invoke("storePrice")
    XCTAssertFalse(try XCTUnwrap(price as? String).isEmpty)

    let products = try await Product.products(for: ["cardock_full_lifetime"])
    let product = try XCTUnwrap(products.first)
    XCTAssertEqual(products.count, 1)
    XCTAssertEqual(product.type, .nonConsumable)
    // This test-only API cannot initiate a real store payment.
    let purchase = try await session.buyProduct(identifier: product.id)
    let result = try await latestTransaction(productID: product.id, expectedID: purchase.id)
    let application = try await AppTransaction.shared
    guard case .verified(let transaction) = result, case .verified(let app) = application else {
      XCTFail("Local StoreKit must provide verified application and purchase receipts.")
      return
    }
    XCTAssertEqual(transaction.id, purchase.id)
    XCTAssertEqual(transaction.environment, .xcode)
    XCTAssertEqual(app.environment, .xcode)
    let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
    let device = try XCTUnwrap(AppStore.deviceVerificationID)
    func verify(
      _ value: VerificationResult<Transaction>,
      appReceipt: VerificationResult<AppTransaction>, productID: String,
      expectedBundle: String, deviceID: UUID?, testing: Bool
    ) -> Transaction? {
      CardockStoreReceiptVerifier.verifiedPurchase(
        value, application: appReceipt, productID: productID, bundleID: expectedBundle,
        deviceID: deviceID, localTesting: testing)
    }
    XCTAssertNotNil(verify(result, appReceipt: application, productID: product.id,
      expectedBundle: bundleID, deviceID: device, testing: true))
    XCTAssertNil(verify(result, appReceipt: application, productID: product.id,
      expectedBundle: bundleID, deviceID: device, testing: false))
    XCTAssertNil(verify(result, appReceipt: application, productID: "wrong.product",
      expectedBundle: bundleID, deviceID: device, testing: true))
    XCTAssertNil(verify(result, appReceipt: application, productID: product.id,
      expectedBundle: "wrong.bundle", deviceID: device, testing: true))
    XCTAssertNil(verify(result, appReceipt: application, productID: product.id,
      expectedBundle: bundleID, deviceID: UUID(), testing: true))
    XCTAssertNil(verify(result, appReceipt: application, productID: product.id,
      expectedBundle: bundleID, deviceID: nil, testing: true))
    XCTAssertNil(verify(.unverified(transaction, .invalidSignature), appReceipt: application,
      productID: product.id, expectedBundle: bundleID, deviceID: device, testing: true))
    XCTAssertNil(verify(result, appReceipt: .unverified(app, .invalidSignature),
      productID: product.id, expectedBundle: bundleID, deviceID: device, testing: true))

    let owned = await messenger.invoke("verifyStore", arguments: ["refresh": false])
    XCTAssertEqual(owned as? Bool, true)
    await transaction.finish()
    let freshMessenger = CardockTestMessenger()
    let freshBridge = CardockStorePurchaseBridge(messenger: freshMessenger)
    defer { withExtendedLifetime(freshBridge) {} }
    let restored = await freshMessenger.invoke("verifyStore", arguments: ["refresh": false])
    XCTAssertEqual(restored as? Bool, true, "A fresh bridge must reverify the stored signed entitlement.")

    let consumable = try await session.buyProduct(identifier: "cardock_local_test_consumable")
    let consumableResult = try await latestTransaction(
      productID: consumable.productID, expectedID: consumable.id)
    XCTAssertNil(verify(consumableResult, appReceipt: application, productID: consumable.productID,
      expectedBundle: bundleID, deviceID: device, testing: true))
    await consumable.finish()

    try session.refundTransaction(identifier: UInt(transaction.id))
    var remainsOwned = true
    for _ in 0..<50 {
      let state = await messenger.invoke("verifyStore", arguments: ["refresh": false])
      remainsOwned = try XCTUnwrap(state as? Bool)
      if !remainsOwned { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertFalse(remainsOwned)
    if let refunded = await Transaction.latest(for: product.id) {
      XCTAssertNil(verify(refunded, appReceipt: application, productID: product.id,
        expectedBundle: bundleID, deviceID: device, testing: true))
    }
  }
}
#endif

@MainActor
final class CardockBiometricPayloadTests: XCTestCase {
  func testRecoveryAndQuickUnlockCannotSharePayloads() throws {
    let quick: [String: Any] = ["version": 2, "vaultId": "fictional", "dataKey": Data(repeating: 1, count: 32).base64EncodedString()]
    let recovery: [String: Any] = ["version": 1, "vaultInstanceId": "fictional", "slotId": "slot", "deviceBindingId": "binding", "deviceSecret": Data(repeating: 2, count: 32).base64EncodedString()]
    let quickData = try JSONSerialization.data(withJSONObject: quick)
    let recoveryData = try JSONSerialization.data(withJSONObject: recovery)
    XCTAssertTrue(CardockBiometricSecretBridge.validPayload(quickData, kind: "quickUnlock"))
    XCTAssertTrue(CardockBiometricSecretBridge.validPayload(recoveryData, kind: "recovery"))
    XCTAssertFalse(CardockBiometricSecretBridge.validPayload(quickData, kind: "recovery"))
    XCTAssertFalse(CardockBiometricSecretBridge.validPayload(recoveryData, kind: "quickUnlock"))
    for change: [String: Any] in [["version": true], ["version": 2.5], ["dataKey": "AA=="], ["vaultId": ""], ["unexpected": "field"]] {
      var changed = quick
      changed.merge(change) { _, new in new }
      XCTAssertFalse(CardockBiometricSecretBridge.validPayload(try JSONSerialization.data(withJSONObject: changed), kind: "quickUnlock"))
    }
  }
  func testWiFiAddressPolicyRejectsPublicLoopbackAndCGNAT() {
    for address: [UInt8] in [[10, 0, 0, 1], [172, 16, 0, 1], [192, 168, 1, 1], [169, 254, 1, 1]] {
      XCTAssertTrue(CardockLocalNetworkBridge.isPrivateIPv4(address))
    }
    for address: [UInt8] in [[127, 0, 0, 1], [8, 8, 8, 8], [100, 64, 0, 1], [172, 32, 0, 1], []] {
      XCTAssertFalse(CardockLocalNetworkBridge.isPrivateIPv4(address))
    }
  }
}


final class CardockBackupDirectoryTests: XCTestCase {
  private func call(_ method: String, _ args: [String: Any]) -> FlutterMethodCall {
    FlutterMethodCall(methodName: method, arguments: args)
  }
  private func fixture() throws -> (URL, URL, CardockBackupDirectoryStore, String) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cardock-folder-test-" + UUID().uuidString, isDirectory: true)
    let folder = root.appendingPathComponent("chosen", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = try CardockBackupDirectoryStore(receiptDirectory: root.appendingPathComponent("receipts", isDirectory: true))
    return (root, folder, store, try CardockBackupDirectoryStore.directoryBookmark(folder))
  }
  func testBookmarkRoundTripPersistsOwnershipAndNeverOverwritesExistingBackup() throws {
    let (root, folder, store, tree) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let name = "Cardock-1770000000000-" + String(repeating: "a", count: 32) + ".asmbackup"
    XCTAssertEqual(try store.handle(call("hasPermission", ["tree": tree])) as? Bool, true)
    let uri = try XCTUnwrap(try store.handle(call("createBackup", ["tree": tree, "name": name])) as? String)
    let bytes = Data([17, 22, 39])
    _ = try store.handle(call("write", ["uri": uri, "bytes": FlutterStandardTypedData(bytes: bytes)]))
    XCTAssertThrowsError(try store.handle(call("createBackup", ["tree": tree, "name": name])))
    let reopened = try CardockBackupDirectoryStore(receiptDirectory: root.appendingPathComponent("receipts"))
    let read = try XCTUnwrap(try reopened.handle(call("read", ["uri": uri])) as? FlutterStandardTypedData)
    XCTAssertEqual(read.data, bytes)
    XCTAssertThrowsError(try reopened.handle(call("write", ["uri": uri, "bytes": FlutterStandardTypedData(bytes: Data([0]))])))
    _ = try reopened.handle(call("deleteOwned", ["tree": tree, "uri": uri]))
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
  }
  func testRejectsForeignHandlesTraversalAndChangedFilesWithoutDeletingThem() throws {
    let (root, folder, store, tree) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertFalse(CardockBackupDirectoryStore.validName("../another.asmbackup"))
    XCTAssertEqual(try store.handle(call("hasPermission", ["tree": "file:///tmp"])) as? Bool, false)
    XCTAssertThrowsError(try store.handle(call("deleteOwned", ["tree": tree, "uri": "file:///tmp/foreign"])))
    let name = "Cardock-1770000000000-" + String(repeating: "b", count: 32) + ".asmbackup"
    let uri = try XCTUnwrap(try store.handle(call("createBackup", ["tree": tree, "name": name])) as? String)
    _ = try store.handle(call("write", ["uri": uri, "bytes": FlutterStandardTypedData(bytes: Data([1, 2]))]))
    XCTAssertThrowsError(try store.handle(call("deleteOwned", ["tree": "other", "uri": uri])))
    let file = folder.appendingPathComponent(name)
    try Data([3, 4]).write(to: file)
    XCTAssertThrowsError(try store.handle(call("read", ["uri": uri])))
    XCTAssertThrowsError(try store.handle(call("deleteOwned", ["tree": tree, "uri": uri])))
    XCTAssertEqual(try Data(contentsOf: file), Data([3, 4]))
  }
  func testRejectsOversizeWriteAndSymlinkWithoutTouchingTarget() throws {
    let (root, folder, store, tree) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let name = "Cardock-1770000000000-" + String(repeating: "c", count: 32) + ".asmbackup"
    let uri = try XCTUnwrap(try store.handle(call("createBackup", ["tree": tree, "name": name])) as? String)
    XCTAssertThrowsError(try store.handle(call("write", ["uri": uri,
      "bytes": FlutterStandardTypedData(bytes: Data(repeating: 1, count: 16 * 1024 * 1024 + 1))])))
    let outside = root.appendingPathComponent("unrelated")
    try Data([7, 8]).write(to: outside)
    let file = folder.appendingPathComponent(name)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
    XCTAssertThrowsError(try store.handle(call("deleteOwned", ["tree": tree, "uri": uri])))
    XCTAssertEqual(try Data(contentsOf: outside), Data([7, 8]))
  }
}

@MainActor
final class CardockSwitcherPrivacyTests: XCTestCase {
  func testPreferenceControlsActualCoverAndPersists() throws {
    let key = SceneDelegate.privacyPreferenceKey
    let previous = UserDefaults.standard.object(forKey: key)
    defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
    UserDefaults.standard.removeObject(forKey: key)
    XCTAssertTrue(SceneDelegate.privacyEnabled)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first)
    let delegate = SceneDelegate()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    delegate.window = window
    delegate.sceneWillResignActive(scene)
    XCTAssertEqual(window.subviews.count, 1)
    SceneDelegate.privacyEnabled = false
    delegate.updatePrivacyPreference()
    XCTAssertEqual(window.subviews.count, 0)
    delegate.sceneWillResignActive(scene)
    XCTAssertEqual(window.subviews.count, 0)
    XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, false)
    SceneDelegate.privacyEnabled = true
    delegate.sceneWillResignActive(scene)
    XCTAssertEqual(window.subviews.count, 1)
  }
}
