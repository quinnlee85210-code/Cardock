import CryptoKit
import Foundation
import StoreKit

/// Only signed app and purchase receipts from the same environment can grant access.
/// The local Xcode environment is additionally confined to explicit Debug builds.
enum CardockStoreReceiptVerifier {
  static func permitsEnvironment(
    transaction: AppStore.Environment,
    application: AppStore.Environment,
    localTesting: Bool
  ) -> Bool {
    guard transaction == application else { return false }
    if transaction == .production || transaction == .sandbox { return true }
    #if DEBUG
      return transaction == .xcode && localTesting
    #else
      return false
    #endif
  }

  static func matchesDevice(
    nonce: UUID, digest: Data, deviceID: UUID?
  ) -> Bool {
    guard let deviceID else { return false }
    let text = nonce.uuidString.lowercased() + deviceID.uuidString.lowercased()
    return Data(SHA384.hash(data: Data(text.utf8))) == digest
  }

  static func verifiedPurchase(
    _ result: VerificationResult<Transaction>,
    application: VerificationResult<AppTransaction>,
    productID: String,
    bundleID: String,
    deviceID: UUID?,
    localTesting: Bool
  ) -> Transaction? {
    guard !productID.isEmpty, !bundleID.isEmpty,
      case .verified(let transaction) = result,
      case .verified(let app) = application,
      app.bundleID == bundleID,
      transaction.productID == productID,
      transaction.productType == .nonConsumable,
      transaction.revocationDate == nil,
      transaction.expirationDate == nil,
      !transaction.isUpgraded,
      permitsEnvironment(
        transaction: transaction.environment, application: app.environment,
        localTesting: localTesting),
      matchesDevice(
        nonce: app.deviceVerificationNonce, digest: app.deviceVerification,
        deviceID: deviceID),
      matchesDevice(
        nonce: transaction.deviceVerificationNonce, digest: transaction.deviceVerification,
        deviceID: deviceID)
    else { return nil }
    return transaction
  }
}
