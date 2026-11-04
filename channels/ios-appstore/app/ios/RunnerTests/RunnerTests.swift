import Flutter
import UIKit
import XCTest
import StoreKit
import StoreKitTest
import LocalAuthentication
import Security
@testable import Runner

private final class CardockRebuildTestMessenger: NSObject, FlutterBinaryMessenger {
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handlers.removeAll() }
  func invoke(_ method: String, arguments: Any? = nil, channel: String = "cardock/vault_rebuild_v1") async -> Any? {
    guard let handler = handlers[channel] else {
      XCTFail("iOS rebuild channel must be registered"); return nil
    }
    let codec = FlutterStandardMethodCodec.sharedInstance()
    return await withCheckedContinuation { continuation in
      handler(codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))) { response in
        guard let response else { continuation.resume(returning: nil); return }
        continuation.resume(returning: codec.decodeEnvelope(response))
      }
    }
  }
}

private final class CardockTestRebuildAuthentication: CardockRebuildAuthenticating {
  var availabilityError: NSError?
  var success: Bool? = true
  var reply: (@Sendable (Bool, Error?) -> Void)?
  var replyOnBackgroundQueue = false
  var invalidated = false
  func available(error: inout NSError?) -> Bool { error = availabilityError; return availabilityError == nil }
  func evaluate(reason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
    self.reply = reply
    if let success {
      if replyOnBackgroundQueue {
        DispatchQueue.global().async {
          XCTAssertFalse(Thread.isMainThread)
          reply(success, nil)
        }
      } else { reply(success, nil) }
    }
  }
  func invalidate() { invalidated = true }
}

final class CardockRebuildTests: XCTestCase {
  private let request = ["title": "Test identity", "message": "TEST ONLY: confirm deletion"]

  func testPermitExpiresAndCannotBeReplayed() {
    var time: TimeInterval = 10
    let permit = CardockRebuildPermit(now: { time })
    let first = permit.issue()["token"] as! String
    let args = ["token": first]
    XCTAssertTrue(permit.consume(args))
    XCTAssertFalse(permit.consume(args))
    let expired = permit.issue()["token"] as! String
    time += 121
    XCTAssertFalse(permit.consume(["token": expired]))
    let invalidated = permit.issue()["token"] as! String
    permit.invalidate()
    XCTAssertFalse(permit.consume(["token": invalidated]))
  }

  func testUnissuedMissingOrWrongTokenNeverAuthorizesDeletion() {
    let permit = CardockRebuildPermit()
    XCTAssertFalse(permit.consume(["phrase": "删除本机 Cardock 数据"]))
    let issued = permit.issue()["token"] as! String
    XCTAssertFalse(permit.consume(["token": "wrong", "phrase": "删除本机 Cardock 数据"]))
    XCTAssertFalse(permit.consume(["token": issued]))
    _ = permit.issue()
    XCTAssertFalse(permit.consume([:]))
  }

  @MainActor func testRegisteredChannelAuthenticatesWithoutRecoveryAndConsumesOnce() async {
    let messenger = CardockRebuildTestMessenger()
    let auth = CardockTestRebuildAuthentication()
    var cleared = false
    let bridge = CardockVaultRebuildBridge(messenger: messenger, makeContext: { auth },
      isActive: { true }, protectedDataAvailable: { true }, clearCommitted: { result in cleared = true; result(nil) })
    let result = await messenger.invoke("authorize", arguments: request) as? [String: Any]
    XCTAssertEqual(result?["unsecured"] as? Bool, false)
    XCTAssertNotNil(result?["token"])
    XCTAssertTrue(auth.invalidated)
    XCTAssertFalse(cleared)
    let args = ["token": result?["token"] as? String ?? "missing"]
    let accepted = await messenger.invoke("consume", arguments: args) as? Bool
    let replay = await messenger.invoke("consume", arguments: args) as? Bool
    XCTAssertEqual(accepted, true)
    XCTAssertEqual(replay, false)
    XCTAssertFalse(cleared)
    withExtendedLifetime(bridge) {}
  }

  @MainActor func testCancelledAuthenticationNeverGrantsPermission() async {
    let messenger = CardockRebuildTestMessenger()
    let auth = CardockTestRebuildAuthentication(); auth.success = false
    let bridge = CardockVaultRebuildBridge(messenger: messenger, makeContext: { auth },
      isActive: { true }, protectedDataAvailable: { true })
    let result = await messenger.invoke("authorize", arguments: request)
    XCTAssertNil(result)
    withExtendedLifetime(bridge) {}
  }

  @MainActor func testBackgroundQueueAuthenticationCallbacksReturnToMainActor() async {
    for success in [true, false] {
      let messenger = CardockRebuildTestMessenger()
      let auth = CardockTestRebuildAuthentication()
      auth.success = success; auth.replyOnBackgroundQueue = true
      let bridge = CardockVaultRebuildBridge(messenger: messenger, makeContext: { auth },
        isActive: { XCTAssertTrue(Thread.isMainThread); return true },
        protectedDataAvailable: { XCTAssertTrue(Thread.isMainThread); return true })
      let result = await messenger.invoke("authorize", arguments: request)
      if success {
        XCTAssertEqual((result as? [String: Any])?["unsecured"] as? Bool, false)
      } else { XCTAssertNil(result) }
      XCTAssertTrue(auth.invalidated)
      withExtendedLifetime(bridge) {}
    }
  }

  @MainActor func testMissingPasscodeAndOtherUnavailableAuthenticationNeverGrantPermission() async {
    for code in [LAError.passcodeNotSet, .biometryNotAvailable, .biometryLockout] {
      let messenger = CardockRebuildTestMessenger()
      let auth = CardockTestRebuildAuthentication()
      auth.availabilityError = NSError(domain: LAError.errorDomain, code: code.rawValue)
      let bridge = CardockVaultRebuildBridge(messenger: messenger, makeContext: { auth },
        isActive: { true }, protectedDataAvailable: { true })
      let result = await messenger.invoke("authorize", arguments: request)
      XCTAssertTrue(result is FlutterError)
      XCTAssertTrue(auth.invalidated)
      XCTAssertNil(auth.reply)
      let consumed = await messenger.invoke("consume", arguments: ["token": "unissued"]) as? Bool
      XCTAssertEqual(consumed, false)
      withExtendedLifetime(bridge) {}
    }
  }

  @MainActor func testBackgroundCancelsPendingAndDiscardsLateSuccess() async {
    let messenger = CardockRebuildTestMessenger()
    let auth = CardockTestRebuildAuthentication(); auth.success = nil
    let bridge = CardockVaultRebuildBridge(messenger: messenger, makeContext: { auth },
      isActive: { true }, protectedDataAvailable: { true })
    let requestTask = Task { await messenger.invoke("authorize", arguments: request) }
    for _ in 0..<100 where auth.reply == nil { await Task.yield() }
    XCTAssertNotNil(auth.reply)
    bridge.backgrounded()
    auth.reply?(true, nil)
    let result = await requestTask.value
    XCTAssertNil(result)
    XCTAssertTrue(auth.invalidated)
    withExtendedLifetime(bridge) {}
  }

  @MainActor func testSuccessfulCallbackWaitsForForeground() async {
    let messenger = CardockRebuildTestMessenger()
    let auth = CardockTestRebuildAuthentication(); auth.success = nil
    var active = true
    let bridge = CardockVaultRebuildBridge(messenger: messenger, makeContext: { auth },
      isActive: { active }, protectedDataAvailable: { true })
    let requestTask = Task { await messenger.invoke("authorize", arguments: request) }
    for _ in 0..<100 where auth.reply == nil { await Task.yield() }
    active = false
    auth.reply?(true, nil)
    for _ in 0..<10 { await Task.yield() }
    XCTAssertFalse(auth.invalidated)
    active = true
    bridge.becameActive()
    let result = await requestTask.value as? [String: Any]
    XCTAssertEqual(result?["unsecured"] as? Bool, false)
    withExtendedLifetime(bridge) {}
  }

  @MainActor func testCommittedJournalRequiredAndOnlyLocalHandlesDeleted() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appendingPathComponent("cardock_rebuild_v1.json")
    let handles = root.appendingPathComponent("cardock_backup_handles_v1")
    try FileManager.default.createDirectory(at: handles, withIntermediateDirectories: true)
    let external = root.appendingPathComponent("preserve.asmbackup")
    try Data("TEST ONLY EXTERNAL BACKUP".utf8).write(to: external)
    try Data(external.path.utf8).write(to: handles.appendingPathComponent("receipt.json"))
    for text in ["{}", "{\"version\":2,\"phase\":\"committed\"}",
      "{\"version\":true,\"phase\":\"committed\"}", "{\"version\":1,\"phase\":\"prepared\"}"] {
      try Data(text.utf8).write(to: journal)
      XCTAssertThrowsError(try CardockVaultRebuildBridge.clearLocalHandles(in: root))
      XCTAssertTrue(FileManager.default.fileExists(atPath: handles.path))
    }
    try Data("{\"version\":1,\"phase\":\"committed\"}".utf8).write(to: journal)
    try CardockVaultRebuildBridge.clearLocalHandles(in: root)
    try CardockVaultRebuildBridge.clearLocalHandles(in: root)
    XCTAssertFalse(FileManager.default.fileExists(atPath: handles.path))
    XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "TEST ONLY EXTERNAL BACKUP")
    XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
  }

  @MainActor func testCleanupOnlyTouchesQuickUnlockAndBothRecoveryItemsAndMarkers() throws {
    let suite = "cardock.rebuild.test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("preserve", forKey: "appearance")
    defaults.set("preserve", forKey: "entitlement")
    for kind in ["quickUnlock", "recovery"] {
      defaults.set(true, forKey: "cardock.biometric-secret.v1.\(kind).configured")
    }
    var accounts: [String] = []
    var services: [String] = []
    try CardockBiometricSecretBridge.clearForCommittedRebuild(defaults: defaults, delete: { query in
      let attributes = query as! [String: Any]
      let kind = attributes[kSecAttrAccount as String] as! String
      accounts.append(kind)
      services.append(attributes[kSecAttrService as String] as! String)
      XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
      return errSecSuccess
    }, probe: { _ in errSecItemNotFound })
    XCTAssertEqual(accounts, ["quickUnlock", "recovery", "recovery"])
    XCTAssertEqual(services, ["com.localaccount.cardock.biometric-secret.v1.quickUnlock",
      "com.localaccount.cardock.recovery-secret.v2", "com.localaccount.cardock.biometric-secret.v1.recovery"])
    XCTAssertEqual(defaults.string(forKey: "appearance"), "preserve")
    XCTAssertEqual(defaults.string(forKey: "entitlement"), "preserve")
    for kind in accounts { XCTAssertNil(defaults.object(forKey: "cardock.biometric-secret.v1.\(kind).configured")) }
  }

  @MainActor func testJournalAndHandlesLinksAreRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("unrelated.json")
    let journal = root.appendingPathComponent("cardock_rebuild_v1.json")
    let data = Data("{\"version\":1,\"phase\":\"committed\"}".utf8)
    try data.write(to: original)
    try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: original)
    XCTAssertThrowsError(try CardockVaultRebuildBridge.validateCommittedJournal(in: root))
    try FileManager.default.removeItem(at: journal)
    try data.write(to: journal)
    let handles = root.appendingPathComponent("cardock_backup_handles_v1")
    try FileManager.default.createSymbolicLink(at: handles, withDestinationURL: original)
    XCTAssertThrowsError(try CardockVaultRebuildBridge.clearLocalHandles(in: root))
    XCTAssertEqual(try Data(contentsOf: original), data)
  }
}

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


private final class CardockTestSecretAuthentication: CardockSecretAuthenticating {
  let keychainContext = LAContext()
  var availableError: NSError?
  var authenticationError: Error?
  var success: Bool? = true
  var policies: [LAPolicy] = []
  var allowsPasscode = false
  var invalidated = false
  var reply: (@Sendable (Bool, Error?) -> Void)?
  func prepare(allowPasscode: Bool) { allowsPasscode = allowPasscode }
  func available(_ policy: LAPolicy, error: inout NSError?) -> Bool {
    policies.append(policy); error = availableError; return availableError == nil
  }
  func evaluate(_ policy: LAPolicy, reason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
    policies.append(policy); self.reply = reply
    if let success { reply(success, authenticationError) }
  }
  func invalidate() { invalidated = true; keychainContext.invalidate() }
}

private final class CardockTestSecretWorkQueue {
  var jobs: [() -> Void] = []
  func enqueue(_ job: @escaping () -> Void) { jobs.append(job) }
  func runNext() {
    guard !jobs.isEmpty else { XCTFail("Expected queued Keychain operation"); return }
    jobs.removeFirst()()
  }
}

private final class CardockTestSecretKeychain {
  struct Entry { var data: Data; let acl: SecAccessControl }
  var entries: [String: Entry] = [:]
  var copies: [String] = []
  var additions: [String] = []
  var updates: [String] = []
  var deletions: [String] = []
  var readContexts: [LAContext] = []
  var readReasons: [String] = []
  var authenticatedContexts: Set<ObjectIdentifier> = []
  var readError: OSStatus?
  var addError: OSStatus?
  var beforeAdd: (() -> Void)?
  var afterUpdate: (() -> Void)?
  var afterRead: (() -> Void)?
  var readOverride: Data?
  static let v2 = "com.localaccount.cardock.recovery-secret.v2"
  static let v1 = "com.localaccount.cardock.biometric-secret.v1.recovery"
  func api() -> CardockSecretKeychain {
    CardockSecretKeychain(copy: { [self] query in
      let q = query as! [String: Any]
      let service = q[kSecAttrService as String] as! String
      copies.append(service)
      XCTAssertEqual(q[kSecAttrSynchronizable as String] as? Bool, false)
      // Security enforces generic-password ACLs for metadata too. The old probe fails.
      if q[kSecReturnAttributes as String] as? Bool == true {
        return (entries[service] == nil ? errSecItemNotFound : errSecInteractionNotAllowed, nil)
      }
      XCTAssertEqual(q[kSecReturnData as String] as? Bool, true)
      XCTAssertNil(q[kSecUseAuthenticationUI as String])
      guard let context = q[kSecUseAuthenticationContext as String] as? LAContext else {
        return (errSecParam, nil)
      }
      readContexts.append(context); readReasons.append(context.localizedReason)
      if let readError { return (readError, nil) }
      guard let entry = entries[service] else { return (errSecItemNotFound, nil) }
      let identity = ObjectIdentifier(context)
      // Direct reads perform ACL authentication. Noninteractive migration may reuse only
      // the exact context that successfully read the original protected item.
      if !context.interactionNotAllowed { authenticatedContexts.insert(identity) }
      guard authenticatedContexts.contains(identity) else { return (errSecInteractionNotAllowed, nil) }
      afterRead?()
      return (errSecSuccess, (readOverride ?? entry.data) as CFData)
    }, add: { [self] query in
      let q = query as! [String: Any]
      let service = q[kSecAttrService as String] as! String
      XCTAssertTrue((q[kSecUseAuthenticationContext as String] as! LAContext).interactionNotAllowed)
      XCTAssertNil(q[kSecUseAuthenticationUI as String])
      additions.append(service); beforeAdd?()
      if let addError { return addError }
      if entries[service] != nil { return errSecDuplicateItem }
      entries[service] = Entry(data: q[kSecValueData as String] as! Data,
        acl: q[kSecAttrAccessControl as String] as! SecAccessControl)
      return errSecSuccess
    }, update: { [self] query, changes in
      let q = query as! [String: Any]
      let service = q[kSecAttrService as String] as! String
      XCTAssertTrue((q[kSecUseAuthenticationContext as String] as! LAContext).interactionNotAllowed)
      updates.append(service); afterUpdate?()
      guard var entry = entries[service] else { return errSecItemNotFound }
      let values = changes as! [String: Any]
      XCTAssertNil(values[kSecAttrAccessControl as String], "ACLs must never be changed with SecItemUpdate")
      entry.data = values[kSecValueData as String] as! Data
      entries[service] = entry; return errSecSuccess
    }, delete: { [self] query in
      let service = (query as! [String: Any])[kSecAttrService as String] as! String
      deletions.append(service); entries.removeValue(forKey: service); return errSecSuccess
    })
  }
}

/// Models a Security mutation already issued on another thread and unable to be recalled.
/// All values are synthetic; this helper never calls a system Keychain API.
private final class CardockTestDelayedMutationStore: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: Data]
  private var delayNextUpdate = true
  private let resumeUpdate = DispatchSemaphore(value: 0)
  let issued = XCTestExpectation(description: "synthetic update issued")
  let completed = XCTestExpectation(description: "synthetic update returned")
  init(_ data: Data) { entries = [CardockTestSecretKeychain.v2: data] }
  func resume() { resumeUpdate.signal() }
  func data(_ service: String) -> Data? {
    lock.lock(); defer { lock.unlock() }; return entries[service]
  }
  func probe(_ query: CFDictionary) -> OSStatus {
    let service = (query as! [String: Any])[kSecAttrService as String] as! String
    return data(service) == nil ? errSecItemNotFound : errSecSuccess
  }
  func api() -> CardockSecretKeychain {
    CardockSecretKeychain(copy: { [self] query in
      let service = (query as! [String: Any])[kSecAttrService as String] as! String
      guard let data = data(service) else { return (errSecItemNotFound, nil) }
      return (errSecSuccess, data as CFData)
    }, add: { [self] query in
      let q = query as! [String: Any], service = q[kSecAttrService as String] as! String
      lock.lock(); defer { lock.unlock() }
      if entries[service] != nil { return errSecDuplicateItem }
      entries[service] = q[kSecValueData as String] as? Data; return errSecSuccess
    }, update: { [self] query, changes in
      let service = (query as! [String: Any])[kSecAttrService as String] as! String
      let data = (changes as! [String: Any])[kSecValueData as String] as! Data
      lock.lock(); let delay = delayNextUpdate; delayNextUpdate = false; lock.unlock()
      if delay {
        issued.fulfill()
        guard resumeUpdate.wait(timeout: .now() + 10) == .success else {
          completed.fulfill(); return errSecNotAvailable
        }
      }
      lock.lock(); entries[service] = data; lock.unlock()
      if delay { completed.fulfill() }
      return errSecSuccess
    }, delete: { [self] query in
      let service = (query as! [String: Any])[kSecAttrService as String] as! String
      lock.lock(); defer { lock.unlock() }
      return entries.removeValue(forKey: service) == nil ? errSecItemNotFound : errSecSuccess
    })
  }
}

@MainActor
final class CardockRecoveryAuthenticationTests: XCTestCase {
  private let channel = "cardock/ios_biometric_secret_v1"
  private let marker = "cardock.biometric-secret.v1.recovery.configured"
  private func payload(_ byte: UInt8 = 2) -> Data {
    try! JSONSerialization.data(withJSONObject: ["version": 1, "vaultInstanceId": "fictional-vault",
      "slotId": "test-slot", "deviceBindingId": "test-binding",
      "deviceSecret": Data(repeating: byte, count: 32).base64EncodedString()], options: .sortedKeys)
  }
  private func defaults() -> UserDefaults {
    let suite = "cardock.recovery.test." + UUID().uuidString
    let value = UserDefaults(suiteName: suite)!
    addTeardownBlock { value.removePersistentDomain(forName: suite) }
    addTeardownBlock {
      for _ in 0..<1000 {
        if await MainActor.run(body: { CardockBiometricSecretBridge.pendingKeychainOperationCount == 0 }) { break }
        await Task.yield()
      }
      await MainActor.run { XCTAssertEqual(CardockBiometricSecretBridge.pendingKeychainOperationCount, 0, "Keychain work lease leaked") }
    }
    return value
  }
  private func install(_ keychain: CardockTestSecretKeychain, defaults: UserDefaults, legacy: Bool = false) {
    let acl = legacy
      ? SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil)!
      : CardockBiometricSecretBridge.accessControl("recovery")!
    keychain.entries[legacy ? CardockTestSecretKeychain.v1 : CardockTestSecretKeychain.v2] = .init(data: payload(), acl: acl)
    defaults.set(true, forKey: marker)
  }
  private func waitForWork(_ work: CardockTestSecretWorkQueue) async {
    for _ in 0..<1000 where work.jobs.isEmpty { await Task.yield() }
    XCTAssertFalse(work.jobs.isEmpty)
  }
  private func waitForDrainedWork() async {
    for _ in 0..<1000 where CardockBiometricSecretBridge.pendingKeychainOperationCount != 0 { await Task.yield() }
    XCTAssertEqual(CardockBiometricSecretBridge.pendingKeychainOperationCount, 0)
  }
  func testNewRecoveryAcceptsPasscodePolicyAndUsesUserPresenceACL() async {
    let messenger = CardockRebuildTestMessenger(), auth = CardockTestSecretAuthentication()
    let keychain = CardockTestSecretKeychain(), values = defaults()
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { auth },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    let result = await messenger.invoke("write", arguments: ["kind": "recovery",
      "payload": String(data: payload(), encoding: .utf8)!], channel: channel)
    XCTAssertNil(result)
    XCTAssertEqual(auth.policies, [.deviceOwnerAuthentication, .deviceOwnerAuthentication])
    XCTAssertTrue(auth.allowsPasscode)
    let item = keychain.entries[CardockTestSecretKeychain.v2]!
    let expected = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil)!
    XCTAssertTrue(CFEqual(item.acl, expected))
    XCTAssertEqual(item.data, payload()); XCTAssertNil(keychain.entries[CardockTestSecretKeychain.v1])
    XCTAssertTrue(values.bool(forKey: marker)); XCTAssertTrue(auth.invalidated)
    withExtendedLifetime(bridge) {}
  }
  func testQuickUnlockStillRequiresBiometricsAndCurrentSet() async {
    XCTAssertEqual(CardockBiometricSecretBridge.policy("quickUnlock"), .deviceOwnerAuthenticationWithBiometrics)
    let expected = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil)!
    XCTAssertTrue(CFEqual(CardockBiometricSecretBridge.accessControl("quickUnlock")!, expected))
    let messenger = CardockRebuildTestMessenger(), auth = CardockTestSecretAuthentication()
    auth.availableError = NSError(domain: LAError.errorDomain, code: LAError.biometryNotEnrolled.rawValue)
    let keychain = CardockTestSecretKeychain()
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { auth },
      keychain: keychain.api(), defaults: defaults(), isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    let data = try! JSONSerialization.data(withJSONObject: ["version": 2, "vaultId": "fictional",
      "dataKey": Data(repeating: 1, count: 32).base64EncodedString()])
    let result = await messenger.invoke("write", arguments: ["kind": "quickUnlock",
      "payload": String(data: data, encoding: .utf8)!], channel: channel) as? FlutterError
    XCTAssertEqual(result?.code, "not_enrolled"); XCTAssertFalse(auth.allowsPasscode)
    XCTAssertTrue(keychain.additions.isEmpty); withExtendedLifetime(bridge) {}
  }
  func testDirectReadAuthenticatesStoredACLWhileMetadataProbeWouldFail() async {
    let messenger = CardockRebuildTestMessenger(), auth = CardockTestSecretAuthentication()
    auth.availableError = NSError(domain: LAError.errorDomain, code: LAError.biometryNotEnrolled.rawValue)
    let keychain = CardockTestSecretKeychain(), values = defaults()
    install(keychain, defaults: values)
    var oldProbe = CardockBiometricSecretBridge.query("recovery")
    oldProbe[kSecReturnAttributes as String] = true
    oldProbe[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    XCTAssertEqual(keychain.api().copy(oldProbe as CFDictionary).0, errSecInteractionNotAllowed)
    keychain.copies.removeAll()
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { auth },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? String
    XCTAssertEqual(result, String(data: payload(), encoding: .utf8))
    XCTAssertTrue(auth.policies.isEmpty); XCTAssertNil(auth.reply)
    XCTAssertEqual(keychain.copies, [CardockTestSecretKeychain.v2])
    XCTAssertTrue(keychain.readContexts.first === auth.keychainContext)
    XCTAssertEqual(keychain.readReasons.first?.isEmpty, false)
    withExtendedLifetime(bridge) {}
  }
  func testLegacyRootMigratesIdenticallyAndNextReadUsesFreshV2Context() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
    install(keychain, defaults: values, legacy: true)
    let legacyACL = keychain.entries[CardockTestSecretKeychain.v1]!.acl
    var contexts: [CardockTestSecretAuthentication] = []
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: {
      let auth = CardockTestSecretAuthentication(); contexts.append(auth); return auth
    }, keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    let first = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? String
    XCTAssertEqual(first, String(data: payload(), encoding: .utf8))
    XCTAssertEqual(keychain.entries[CardockTestSecretKeychain.v1]?.data, payload())
    XCTAssertTrue(CFEqual(keychain.entries[CardockTestSecretKeychain.v1]!.acl, legacyACL))
    XCTAssertEqual(keychain.entries[CardockTestSecretKeychain.v2]?.data, payload())
    XCTAssertTrue(CFEqual(keychain.entries[CardockTestSecretKeychain.v2]!.acl, CardockBiometricSecretBridge.accessControl("recovery")!))
    XCTAssertTrue(keychain.readContexts.allSatisfy { $0 === contexts[0].keychainContext })
    XCTAssertTrue(keychain.updates.isEmpty); XCTAssertTrue(keychain.deletions.isEmpty)
    keychain.copies.removeAll()
    let second = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? String
    XCTAssertEqual(second, first); XCTAssertFalse(contexts[0].keychainContext === contexts[1].keychainContext)
    XCTAssertEqual(keychain.copies, [CardockTestSecretKeychain.v2]); withExtendedLifetime(bridge) {}
  }
  func testV2ReadErrorsNeverFallBackAndDiagnosticsContainOnlyStageAndStatus() async {
    for error in [errSecInteractionNotAllowed, errSecAuthFailed, errSecDecode, errSecParam] {
      let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
      install(keychain, defaults: values); install(keychain, defaults: values, legacy: true)
      keychain.readError = error
      let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
        keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
      let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? FlutterError
      XCTAssertNotNil(result)
      XCTAssertEqual(keychain.copies, [CardockTestSecretKeychain.v2])
      let details = result?.details as? [String: Any]
      XCTAssertEqual(Set(details?.keys.map { $0 } ?? []), Set(["stage", "osStatus"]))
      XCTAssertEqual(details?["stage"] as? String, "read_v2"); XCTAssertEqual(details?["osStatus"] as? Int, Int(error))
      XCTAssertNil(result?.message); XCTAssertTrue(values.bool(forKey: marker))
      XCTAssertTrue(keychain.additions.isEmpty); XCTAssertTrue(keychain.deletions.isEmpty)
      withExtendedLifetime(bridge) {}
    }
  }
  func testMigrationFailureAndDuplicateNeverOverwriteLegacyOrAnotherRoot() async {
    for scenario in 0..<4 {
      let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
      install(keychain, defaults: values, legacy: true)
      if scenario == 0 { keychain.addError = errSecNotAvailable }
      else if scenario == 1 { keychain.beforeAdd = { keychain.readError = errSecAuthFailed } }
      else {
        keychain.beforeAdd = {
          keychain.entries[CardockTestSecretKeychain.v2] = .init(data: self.payload(scenario == 2 ? 2 : 3),
            acl: CardockBiometricSecretBridge.accessControl("recovery")!)
        }
      }
      let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
        keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
      let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel)
      if scenario == 2 { XCTAssertEqual(result as? String, String(data: payload(), encoding: .utf8)) }
      else { XCTAssertNotNil(result as? FlutterError) }
      XCTAssertEqual(keychain.entries[CardockTestSecretKeychain.v1]?.data, payload())
      if scenario == 3 { XCTAssertEqual(keychain.entries[CardockTestSecretKeychain.v2]?.data, payload(3)) }
      XCTAssertTrue(keychain.updates.isEmpty); XCTAssertTrue(keychain.deletions.isEmpty)
      XCTAssertTrue(values.bool(forKey: marker)); withExtendedLifetime(bridge) {}
    }
  }
  func testCorruptLegacyPayloadNeverMigrates() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
    install(keychain, defaults: values, legacy: true); keychain.readOverride = Data("invalid".utf8)
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? FlutterError
    XCTAssertEqual(result?.code, "corrupted_secret"); XCTAssertTrue(keychain.additions.isEmpty)
    withExtendedLifetime(bridge) {}
  }
  func testNoPasscodeAndCancelledPolicyNeverWrite() async {
    for missingPasscode in [true, false] {
      let messenger = CardockRebuildTestMessenger(), auth = CardockTestSecretAuthentication()
      let keychain = CardockTestSecretKeychain()
      if missingPasscode { auth.availableError = NSError(domain: LAError.errorDomain, code: LAError.passcodeNotSet.rawValue) }
      else { auth.success = false; auth.authenticationError = NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue) }
      let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { auth },
        keychain: keychain.api(), defaults: defaults(), isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
      let result = await messenger.invoke("write", arguments: ["kind": "recovery",
        "payload": String(data: payload(), encoding: .utf8)!], channel: channel) as? FlutterError
      XCTAssertEqual(result?.code, missingPasscode ? "passcode_not_set" : "user_canceled")
      XCTAssertTrue(keychain.additions.isEmpty); XCTAssertTrue(keychain.updates.isEmpty)
      withExtendedLifetime(bridge) {}
    }
  }
  func testCancelledKeychainPromptPreservesBothItemsAndMarker() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
    install(keychain, defaults: values); install(keychain, defaults: values, legacy: true)
    keychain.readError = errSecUserCanceled
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? FlutterError
    XCTAssertEqual(result?.code, "user_canceled"); XCTAssertEqual(keychain.copies, [CardockTestSecretKeychain.v2])
    XCTAssertEqual(keychain.entries.count, 2); XCTAssertTrue(values.bool(forKey: marker))
    XCTAssertTrue(keychain.additions.isEmpty); XCTAssertTrue(keychain.deletions.isEmpty); withExtendedLifetime(bridge) {}
  }
  func testAuthenticatedReadWaitsForActiveBeforeReturningOrMigrating() async {
    for legacy in [false, true] {
      let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
      install(keychain, defaults: values, legacy: legacy)
      var active = true, completed = false
      keychain.afterRead = { active = false }
      let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
        keychain: keychain.api(), defaults: values, isActive: { active }, protectedDataAvailable: { true }, executeKeychain: { $0() })
      let task = Task { let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel); completed = true; return result }
      for _ in 0..<100 where active { await Task.yield() }
      for _ in 0..<10 { await Task.yield() }
      XCTAssertFalse(active); XCTAssertFalse(completed); XCTAssertTrue(keychain.additions.isEmpty)
      keychain.afterRead = nil; active = true; bridge.becameActive()
      let result = await task.value as? String
      XCTAssertEqual(result, String(data: payload(), encoding: .utf8))
      XCTAssertEqual(keychain.additions.count, legacy ? 1 : 0); withExtendedLifetime(bridge) {}
    }
  }
  func testBackgroundTimeoutAndConcurrentCallsCannotRunQueuedRead() async {
    for expire in [false, true] {
      let messenger = CardockRebuildTestMessenger(), auth = CardockTestSecretAuthentication()
      let keychain = CardockTestSecretKeychain(), values = defaults(), work = CardockTestSecretWorkQueue()
      install(keychain, defaults: values, legacy: true)
      let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { auth },
        keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true },
        timeoutSeconds: expire ? 0.02 : 60, executeKeychain: work.enqueue)
      let task = Task { await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) }
      await waitForWork(work)
      let concurrent = await messenger.invoke("delete", arguments: ["kind": "recovery"], channel: channel) as? FlutterError
      XCTAssertEqual(concurrent?.code, "auth_in_progress")
      if !expire { bridge.backgrounded() }
      let result = await task.value as? FlutterError
      XCTAssertEqual(result?.code, expire ? "timeout" : "lifecycle_canceled")
      work.runNext(); for _ in 0..<10 { await Task.yield() }
      XCTAssertTrue(auth.invalidated); XCTAssertTrue(keychain.copies.isEmpty)
      XCTAssertTrue(keychain.additions.isEmpty); XCTAssertTrue(keychain.deletions.isEmpty)
      XCTAssertEqual(keychain.entries[CardockTestSecretKeychain.v1]?.data, payload()); withExtendedLifetime(bridge) {}
    }
  }
  func testLateLegacyReadCompletionCannotReleaseOrMigrate() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults(), work = CardockTestSecretWorkQueue()
    install(keychain, defaults: values, legacy: true)
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: work.enqueue)
    let task = Task { await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) }
    await waitForWork(work); work.runNext() // v2 is definitely absent
    await waitForWork(work); work.runNext() // successful legacy read, callback not consumed yet
    bridge.backgrounded()
    let result = await task.value as? FlutterError
    XCTAssertEqual(result?.code, "lifecycle_canceled")
    for _ in 0..<10 { await Task.yield() }
    XCTAssertTrue(keychain.additions.isEmpty); XCTAssertNil(keychain.entries[CardockTestSecretKeychain.v2])
    XCTAssertEqual(keychain.entries[CardockTestSecretKeychain.v1]?.data, payload()); withExtendedLifetime(bridge) {}
  }
  func testCancellationBeforeQueuedMigrationPreventsWritingNewItem() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults(), work = CardockTestSecretWorkQueue()
    install(keychain, defaults: values, legacy: true)
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: work.enqueue)
    let task = Task { await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) }
    await waitForWork(work); work.runNext()
    await waitForWork(work); work.runNext()
    await waitForWork(work) // migration has been authorized but has not started
    bridge.backgrounded(); work.runNext()
    let result = await task.value as? FlutterError
    XCTAssertEqual(result?.code, "lifecycle_canceled")
    XCTAssertTrue(keychain.additions.isEmpty); XCTAssertTrue(keychain.deletions.isEmpty)
    XCTAssertNil(keychain.entries[CardockTestSecretKeychain.v2]); withExtendedLifetime(bridge) {}
  }
  func testCancelledLateWriteAuthenticationAndQueuedWriteCannotMutate() async {
    for queuedWrite in [false, true] {
      let messenger = CardockRebuildTestMessenger(), auth = CardockTestSecretAuthentication(), keychain = CardockTestSecretKeychain(), work = CardockTestSecretWorkQueue()
      if !queuedWrite { auth.success = nil }
      let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { auth },
        keychain: keychain.api(), defaults: defaults(), isActive: { true }, protectedDataAvailable: { true }, executeKeychain: work.enqueue)
      let task = Task { await messenger.invoke("write", arguments: ["kind": "recovery", "payload": String(data: payload(), encoding: .utf8)!], channel: channel) }
      if queuedWrite { await waitForWork(work) }
      else { for _ in 0..<100 where auth.reply == nil { await Task.yield() } }
      bridge.backgrounded()
      if queuedWrite { work.runNext() } else { auth.reply?(true, nil) }
      let result = await task.value as? FlutterError
      XCTAssertEqual(result?.code, "lifecycle_canceled")
      for _ in 0..<10 { await Task.yield() }
      XCTAssertTrue(keychain.updates.isEmpty); XCTAssertTrue(keychain.additions.isEmpty); withExtendedLifetime(bridge) {}
    }
  }
  func testCancellationDuringIssuedUpdateReturnsImmediatelyAndPreventsAdd() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain()
    var bridge: CardockBiometricSecretBridge!
    bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: defaults(), isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    var cancellationReturned = false
    keychain.afterUpdate = { bridge.backgrounded(); cancellationReturned = true }
    let result = await messenger.invoke("write", arguments: ["kind": "recovery", "payload": String(data: payload(), encoding: .utf8)!], channel: channel) as? FlutterError
    XCTAssertEqual(result?.code, "lifecycle_canceled"); XCTAssertTrue(cancellationReturned)
    XCTAssertEqual(keychain.updates.count, 1); XCTAssertTrue(keychain.additions.isEmpty)
    keychain.afterUpdate = nil; withExtendedLifetime(bridge) {}
  }
  func testCancellationDuringIssuedMigrationAddPreventsVerificationAndDelivery() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
    install(keychain, defaults: values, legacy: true)
    var bridge: CardockBiometricSecretBridge!
    bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: { $0() })
    var cancellationReturned = false
    keychain.beforeAdd = { bridge.backgrounded(); cancellationReturned = true }
    let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? FlutterError
    XCTAssertEqual(result?.code, "lifecycle_canceled"); XCTAssertTrue(cancellationReturned)
    XCTAssertEqual(keychain.copies, [CardockTestSecretKeychain.v2, CardockTestSecretKeychain.v1])
    XCTAssertEqual(keychain.entries[CardockTestSecretKeychain.v1]?.data, payload())
    XCTAssertTrue(keychain.deletions.isEmpty)
    keychain.beforeAdd = nil; withExtendedLifetime(bridge) {}
  }
  func testCancelledIssuedMutationRejectsRetryAndDeleteUntilItActuallyReturns() async {
    let messenger = CardockRebuildTestMessenger(), values = defaults(), store = CardockTestDelayedMutationStore(payload(1))
    values.set(true, forKey: marker)
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: store.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true })
    defer { store.resume() }
    let first = Task { await messenger.invoke("write", arguments: ["kind": "recovery", "payload": String(data: payload(2), encoding: .utf8)!], channel: channel) }
    await fulfillment(of: [store.issued], timeout: 3)
    bridge.backgrounded()
    let cancelled = await first.value as? FlutterError
    XCTAssertEqual(cancelled?.code, "lifecycle_canceled")
    let retry = await messenger.invoke("write", arguments: ["kind": "recovery", "payload": String(data: payload(3), encoding: .utf8)!], channel: channel) as? FlutterError
    let deletion = await messenger.invoke("delete", arguments: ["kind": "recovery"], channel: channel) as? FlutterError
    XCTAssertEqual(retry?.code, "auth_in_progress", "A canceled but issued mutation must drain before a retry")
    XCTAssertEqual(deletion?.code, "auth_in_progress", "Delete must not race an issued mutation")
    store.resume(); await fulfillment(of: [store.completed], timeout: 3)
    await waitForDrainedWork()
    let final = await messenger.invoke("write", arguments: ["kind": "recovery", "payload": String(data: payload(3), encoding: .utf8)!], channel: channel)
    XCTAssertNil(final); XCTAssertEqual(store.data(CardockTestSecretKeychain.v2), payload(3))
    withExtendedLifetime(bridge) {}
  }
  func testCommittedCleanupRejectsOutstandingMutationAndPreservesMarkerForReplay() async throws {
    let messenger = CardockRebuildTestMessenger(), values = defaults(), store = CardockTestDelayedMutationStore(payload(1))
    values.set(true, forKey: marker)
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: store.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true })
    defer { store.resume() }
    let first = Task { await messenger.invoke("write", arguments: ["kind": "recovery", "payload": String(data: payload(2), encoding: .utf8)!], channel: channel) }
    await fulfillment(of: [store.issued], timeout: 3)
    bridge.backgrounded()
    let cancelled = await first.value as? FlutterError
    XCTAssertEqual(cancelled?.code, "lifecycle_canceled")
    XCTAssertThrowsError(try CardockBiometricSecretBridge.clearForCommittedRebuild(defaults: values,
      delete: store.api().delete, probe: store.probe))
    XCTAssertTrue(values.bool(forKey: marker), "Busy cleanup must preserve the configured marker for committed replay")
    store.resume(); await fulfillment(of: [store.completed], timeout: 3)
    await waitForDrainedWork()
    try CardockBiometricSecretBridge.clearForCommittedRebuild(defaults: values, delete: store.api().delete, probe: store.probe)
    XCTAssertNil(store.data(CardockTestSecretKeychain.v2)); XCTAssertFalse(values.bool(forKey: marker))
    withExtendedLifetime(bridge) {}
  }
  func testDestroyedBridgeCancelsQueuedReadAndReleasesLeaseAfterDrain() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults(), work = CardockTestSecretWorkQueue()
    install(keychain, defaults: values)
    var bridge: CardockBiometricSecretBridge? = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { true }, executeKeychain: work.enqueue)
    let task = Task { await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) }
    await waitForWork(work)
    XCTAssertNotNil(bridge); bridge = nil
    let result = await task.value as? FlutterError
    XCTAssertEqual(result?.code, "lifecycle_canceled")
    XCTAssertEqual(CardockBiometricSecretBridge.pendingKeychainOperationCount, 1)
    work.runNext(); await waitForDrainedWork()
    XCTAssertTrue(keychain.copies.isEmpty); XCTAssertTrue(keychain.additions.isEmpty)
  }
  func testProtectedDataUnavailableNeverStartsKeychainRead() async {
    let messenger = CardockRebuildTestMessenger(), keychain = CardockTestSecretKeychain(), values = defaults()
    install(keychain, defaults: values)
    let bridge = CardockBiometricSecretBridge(messenger: messenger, makeContext: { CardockTestSecretAuthentication() },
      keychain: keychain.api(), defaults: values, isActive: { true }, protectedDataAvailable: { false }, executeKeychain: { $0() })
    let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? FlutterError
    XCTAssertEqual(result?.code, "activity_not_resumed"); XCTAssertTrue(keychain.copies.isEmpty); withExtendedLifetime(bridge) {}
  }
  func testDefaultExecutorPerformsInteractiveKeychainReadOffMainThread() async {
    let messenger = CardockRebuildTestMessenger(), values = defaults(), data = payload()
    values.set(true, forKey: marker)
    let keychain = CardockSecretKeychain(copy: { query in
      XCTAssertFalse(Thread.isMainThread)
      let q = query as! [String: Any]
      XCTAssertEqual(q[kSecReturnData as String] as? Bool, true)
      return (errSecSuccess, data as CFData)
    })
    let bridge = CardockBiometricSecretBridge(messenger: messenger, keychain: keychain,
      defaults: values, isActive: { true }, protectedDataAvailable: { true })
    let result = await messenger.invoke("read", arguments: ["kind": "recovery"], channel: channel) as? String
    XCTAssertEqual(result, String(data: data, encoding: .utf8)); withExtendedLifetime(bridge) {}
  }
  func testSyntheticHostedKeychainReportsMetadataAndNoninteractiveReadStatuses() throws {
    // Diagnostic only: simulator/host support is not real-device passcode acceptance.
    // Use a unique synthetic namespace and never query, change, or delete product items.
    let service = "com.localaccount.cardock.tests.synthetic.recovery." + UUID().uuidString
    let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "synthetic",
      kSecAttrSynchronizable as String: false]
    let acl = try XCTUnwrap(SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil))
    var add = base; add[kSecAttrAccessControl as String] = acl
    add[kSecValueData as String] = Data("synthetic-acl-probe".utf8)
    let context = LAContext(); context.interactionNotAllowed = true
    add[kSecUseAuthenticationContext as String] = context
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw XCTSkip("Synthetic ACL item unsupported in this hosted runtime; add OSStatus=\(addStatus)") }
    defer { XCTAssertEqual(SecItemDelete(base as CFDictionary), errSecSuccess) }
    var metadata = base; metadata[kSecReturnAttributes as String] = true
    metadata[kSecMatchLimit as String] = kSecMatchLimitOne
    metadata[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    var metadataValue: CFTypeRef?
    let metadataStatus = SecItemCopyMatching(metadata as CFDictionary, &metadataValue)
    var read = base; read[kSecReturnData as String] = true
    let readContext = LAContext(); readContext.interactionNotAllowed = true
    read[kSecUseAuthenticationContext as String] = readContext
    var dataValue: CFTypeRef?
    defer {
      if var data = dataValue as? Data {
        dataValue = nil; data.resetBytes(in: 0..<data.count)
      }
      dataValue = nil; metadataValue = nil
    }
    let readStatus = SecItemCopyMatching(read as CFDictionary, &dataValue)
    print("CardockSyntheticKeychainProbe metadataStatus=\(metadataStatus) noninteractiveDataStatus=\(readStatus)")
    if readStatus == errSecSuccess { throw XCTSkip("This runtime does not enforce the synthetic userPresence ACL; not device authentication evidence") }
    XCTAssertNotEqual(readStatus, errSecItemNotFound)
  }
  func testCleanupFailurePreservesConfigurationMarkers() {
    let values = defaults(); values.set(true, forKey: marker)
    var count = 0
    XCTAssertThrowsError(try CardockBiometricSecretBridge.clearForCommittedRebuild(defaults: values,
      delete: { _ in count += 1; return count == 2 ? errSecNotAvailable : errSecSuccess },
      probe: { _ in errSecItemNotFound }))
    XCTAssertTrue(values.bool(forKey: marker))
  }
}
