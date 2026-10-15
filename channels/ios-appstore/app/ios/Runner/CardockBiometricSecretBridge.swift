import Flutter
import LocalAuthentication
import Security
import UIKit

/// The Keychain ACL, not a Dart boolean, enforces each biometric secret read.
@MainActor
final class CardockBiometricSecretBridge {
  private let channel: FlutterMethodChannel
  private var context: LAContext?
  private var pending: FlutterResult?
  private var operation: UUID?
  private var authenticatedAction: (() -> Void)?
  private var timeout: DispatchWorkItem?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "cardock/ios_biometric_secret_v1", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else { result(Self.failure("lifecycle_canceled")); return }
        self.handle(call, result: result)
      }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  static func validPayload(_ data: Data, kind: String) -> Bool {
    guard data.count <= 4096,
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    let metadata: [String]
    let secret: String
    let version: Int
    switch kind {
    case "quickUnlock": metadata = ["vaultId"]; secret = "dataKey"; version = 2
    case "recovery": metadata = ["vaultInstanceId", "slotId", "deviceBindingId"]; secret = "deviceSecret"; version = 1
    default: return false
    }
    guard Set(value.keys) == Set(metadata + ["version", secret]),
      let number = value["version"] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(version),
      let encoded = value[secret] as? String, let bytes = Data(base64Encoded: encoded),
      bytes.count == 32 else { return false }
    return metadata.allSatisfy {
      guard let text = value[$0] as? String else { return false }
      return !text.isEmpty && text.utf8.count <= 512
    }
  }

  private static func failure(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }
  private func marker(_ kind: String) -> String { "cardock.biometric-secret.v1.\(kind).configured" }
  private func query(_ kind: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "com.localaccount.cardock.biometric-secret.v1.\(kind)",
     kSecAttrAccount as String: kind,
     kSecAttrSynchronizable as String: false]
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let kind = args["kind"] as? String,
      ["quickUnlock", "recovery"].contains(kind) else { result(Self.failure("invalid_secret")); return }
    if call.method == "availability" {
      let probe = LAContext()
      var error: NSError?
      let available = probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      result(available ? "available" : (error?.code == LAError.biometryNotEnrolled.rawValue ? "not_enrolled" : "unavailable"))
      probe.invalidate()
      return
    }
    if call.method == "isConfigured" { result(UserDefaults.standard.bool(forKey: marker(kind))); return }
    guard operation == nil else { result(Self.failure("auth_in_progress")); return }
    guard UIApplication.shared.applicationState == .active else { result(Self.failure("activity_not_resumed")); return }
    if call.method == "delete" {
      let status = SecItemDelete(query(kind) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { result(Self.failure("storage_error")); return }
      UserDefaults.standard.removeObject(forKey: marker(kind))
      result(nil)
      return
    }
    guard call.method == "read" || call.method == "write" else { result(FlutterMethodNotImplemented); return }
    var payload: Data?
    if call.method == "write" {
      guard let text = args["payload"] as? String, let data = text.data(using: .utf8),
        Self.validPayload(data, kind: kind) else { result(Self.failure("invalid_secret")); return }
      payload = data
    } else if !UserDefaults.standard.bool(forKey: marker(kind)) {
      result(nil)
      return
    }
    let auth = LAContext()
    auth.localizedFallbackTitle = ""
    auth.touchIDAuthenticationAllowableReuseDuration = 0
    var error: NSError?
    guard auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      result(Self.failure(Self.errorCode(error))); auth.invalidate(); return
    }
    let id = UUID()
    operation = id; pending = result; context = auth
    let timer = DispatchWorkItem { [weak self] in
      guard let self, self.operation == id else { return }
      self.finish(Self.failure("timeout"))
    }
    timeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timer)
    let reason = NSLocalizedString(kind == "recovery" ? "CardockRecoveryAuthentication" : "CardockQuickUnlockAuthentication", comment: "")
    auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
      Task { @MainActor in
        guard let self, self.operation == id else { return }
        guard success else { self.finish(Self.failure(Self.errorCode(error))); return }
        // The system prompt may finish before UIKit reports the app active again.
        self.authenticatedAction = { [weak self] in
          guard let self, self.operation == id else { return }
          self.access(kind: kind, payload: payload, auth: auth)
        }
        self.becameActive()
      }
    }
  }
  @objc private func becameActive() {
    guard UIApplication.shared.applicationState == .active else { return }
    let action = authenticatedAction
    authenticatedAction = nil
    action?()
  }
  @objc private func backgrounded() {
    if operation != nil { finish(Self.failure("lifecycle_canceled")) }
  }
  private func finish(_ value: Any?) {
    let result = pending
    pending = nil; operation = nil; authenticatedAction = nil
    timeout?.cancel(); timeout = nil
    context?.invalidate(); context = nil
    result?(value)
  }
  private func access(kind: String, payload: Data?, auth: LAContext) {
    guard UIApplication.shared.applicationState == .active else { finish(Self.failure("lifecycle_canceled")); return }
    var attributes = query(kind)
    attributes[kSecUseAuthenticationContext as String] = auth
    // A successful policy evaluation must unlock the ACL; never show a fallback prompt.
    attributes[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    if let payload {
      let status = SecItemUpdate(attributes as CFDictionary,
        [kSecValueData as String: payload] as CFDictionary)
      var finalStatus = status
      if status == errSecItemNotFound {
        var aclError: Unmanaged<CFError>?
        guard let acl = SecAccessControlCreateWithFlags(nil,
          kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &aclError) else {
          finish(Self.failure("key_generation_failed")); return
        }
        attributes.removeValue(forKey: kSecUseAuthenticationUI as String)
        attributes[kSecAttrAccessControl as String] = acl
        attributes[kSecValueData as String] = payload
        finalStatus = SecItemAdd(attributes as CFDictionary, nil)
      }
      guard finalStatus == errSecSuccess else { finish(Self.failure("storage_error")); return }
      UserDefaults.standard.set(true, forKey: marker(kind))
      finish(nil)
    } else {
      attributes[kSecReturnData as String] = true
      attributes[kSecMatchLimit as String] = kSecMatchLimitOne
      var value: CFTypeRef?
      let status = SecItemCopyMatching(attributes as CFDictionary, &value)
      guard status == errSecSuccess else {
        finish(Self.failure(status == errSecItemNotFound ? "key_missing" : "storage_error")); return
      }
      guard var data = value as? Data else { finish(Self.failure("corrupted_secret")); return }
      defer { data.resetBytes(in: 0..<data.count) }
      guard Self.validPayload(data, kind: kind), let text = String(data: data, encoding: .utf8) else {
        finish(Self.failure("corrupted_secret")); return
      }
      finish(text)
    }
  }
  private static func errorCode(_ error: Error?) -> String {
    guard let error = error as? LAError else { return "biometric_unavailable" }
    switch error.code {
    case .userCancel, .userFallback: return "user_canceled"
    case .appCancel, .systemCancel: return "system_canceled"
    case .biometryLockout: return "biometric_lockout"
    case .biometryNotEnrolled: return "not_enrolled"
    case .biometryNotAvailable, .passcodeNotSet: return "biometric_unavailable"
    default: return "biometric_unavailable"
    }
  }
}
