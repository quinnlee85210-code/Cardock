import Flutter
import LocalAuthentication
import Security
import UIKit

protocol CardockSecretAuthenticating: AnyObject {
  var keychainContext: LAContext { get }
  func prepare(allowPasscode: Bool)
  func available(_ policy: LAPolicy, error: inout NSError?) -> Bool
  func evaluate(_ policy: LAPolicy, reason: String, reply: @escaping @Sendable (Bool, Error?) -> Void)
  func invalidate()
}

extension LAContext: CardockSecretAuthenticating {
  var keychainContext: LAContext { self }
  func prepare(allowPasscode: Bool) {
    localizedFallbackTitle = allowPasscode ? nil : ""
    touchIDAuthenticationAllowableReuseDuration = 0
  }
  func available(_ policy: LAPolicy, error: inout NSError?) -> Bool {
    canEvaluatePolicy(policy, error: &error)
  }
  func evaluate(_ policy: LAPolicy, reason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
    evaluatePolicy(policy, localizedReason: reason, reply: reply)
  }
}

struct CardockSecretKeychain {
  var copy: (CFDictionary) -> (OSStatus, CFTypeRef?) = { query in
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query, &value)
    return (status, value)
  }
  var add: (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
  var update: (CFDictionary, CFDictionary) -> OSStatus = { SecItemUpdate($0, $1) }
  var delete: (CFDictionary) -> OSStatus = { SecItemDelete($0) }
}

/// Counts logical operations until cancellation/finish AND all queued IO have drained.
/// The registry only protects counters; Security framework calls never run under its lock.
private final class CardockSecretWorkRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return count }
  func acquire() { lock.lock(); count += 1; lock.unlock() }
  func release() { lock.lock(); precondition(count > 0); count -= 1; lock.unlock() }
}

private final class CardockSecretWorkToken: @unchecked Sendable {
  private static let registry = CardockSecretWorkRegistry()
  static var pendingCount: Int { registry.pendingCount }
  private let lock = NSLock()
  private var live = true
  private var queuedOrRunning = 0
  private var ownsLease = true
  init() { Self.registry.acquire() }
  deinit { if ownsLease { Self.registry.release() } }
  var isLive: Bool { lock.lock(); defer { lock.unlock() }; return live }
  func enqueue() -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard live else { return false }
    queuedOrRunning += 1; return true
  }
  func workerReturned() {
    lock.lock()
    precondition(queuedOrRunning > 0)
    queuedOrRunning -= 1
    let release = !live && queuedOrRunning == 0 && ownsLease
    if release { ownsLease = false }
    lock.unlock()
    if release { Self.registry.release() }
  }
  func cancel() {
    lock.lock(); live = false
    let release = queuedOrRunning == 0 && ownsLease
    if release { ownsLease = false }
    lock.unlock()
    if release { Self.registry.release() }
  }
  func performIfLive<T>(_ body: () -> T) -> T? {
    guard isLive else { return nil }
    // An issued call cannot be recalled; the lease prevents later operations overtaking it.
    return body()
  }
}

/// Owned by one completion at a time; stale completions erase their unused data.
private final class CardockSecretReadResult: @unchecked Sendable {
  let status: OSStatus
  var data: Data?
  init(_ status: OSStatus, _ value: CFTypeRef?) {
    self.status = status; data = value as? Data
  }
  func erase() {
    if var bytes = data { data = nil; bytes.resetBytes(in: 0..<bytes.count) }
  }
  deinit { erase() }
}

/// Keychain ACLs enforce reads: recovery accepts device authentication, quick unlock requires biometrics.
@MainActor
final class CardockBiometricSecretBridge {
  private let channel: FlutterMethodChannel
  private let makeContext: () -> CardockSecretAuthenticating
  private let keychain: CardockSecretKeychain
  private let defaults: UserDefaults
  private let isActive: () -> Bool
  private let protectedDataAvailable: () -> Bool
  private let timeoutSeconds: TimeInterval
  private let executeKeychain: (@escaping () -> Void) -> Void
  private var workToken: CardockSecretWorkToken?
  private var readResult: CardockSecretReadResult?
  private var context: CardockSecretAuthenticating?
  private var pending: FlutterResult?
  private var operation: UUID?
  private var authenticatedAction: (() -> Void)?
  private var timeout: DispatchWorkItem?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger,
    makeContext: @escaping () -> CardockSecretAuthenticating = { LAContext() },
    keychain: CardockSecretKeychain = CardockSecretKeychain(),
    defaults: UserDefaults = .standard,
    isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
    protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
    timeoutSeconds: TimeInterval = 60,
    executeKeychain: @escaping (@escaping () -> Void) -> Void = { work in
      DispatchQueue.global(qos: .userInitiated).async(execute: DispatchWorkItem(block: work))
    }) {
    self.makeContext = makeContext; self.keychain = keychain; self.defaults = defaults
    self.isActive = isActive; self.protectedDataAvailable = protectedDataAvailable
    self.timeoutSeconds = timeoutSeconds; self.executeKeychain = executeKeychain
    channel = FlutterMethodChannel(name: "cardock/ios_biometric_secret_v1", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else { result(Self.failure("lifecycle_canceled")); return }
        self.handle(call, result: result)
      }
    }
    for name in [UIApplication.didEnterBackgroundNotification,
      UIApplication.protectedDataWillBecomeUnavailableNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in Task { @MainActor in self?.backgrounded() }
      })
    }
    observers.append(NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
        [weak self] _ in Task { @MainActor in self?.becameActive() }
      })
  }
  deinit {
    workToken?.cancel(); context?.invalidate(); readResult?.erase()
    observers.forEach(NotificationCenter.default.removeObserver)
    if let result = pending {
      Task { @MainActor in result(FlutterError(code: "lifecycle_canceled", message: nil, details: nil)) }
    }
  }
  static var pendingKeychainOperationCount: Int { CardockSecretWorkToken.pendingCount }

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

  private static func failure(_ code: String, stage: String? = nil, status: OSStatus? = nil) -> FlutterError {
    let stages: Set<String> = ["read_v2", "read_legacy", "write", "migration_add", "migration_verify"]
    var details: [String: Any] = [:]
    if let stage, stages.contains(stage) { details["stage"] = stage }
    if let status { details["osStatus"] = Int(status) }
    return FlutterError(code: code, message: nil, details: details.isEmpty ? nil : details)
  }
  private static func keychainFailure(_ status: OSStatus, stage: String, kind: String, legacy: Bool = false) -> FlutterError {
    let code: String
    switch status {
    case errSecUserCanceled: code = "user_canceled"
    case errSecItemNotFound: code = "key_missing"
    case errSecAuthFailed, errSecInteractionNotAllowed:
      code = legacy ? "legacy_recovery_unavailable" :
        (kind == "recovery" ? "device_authentication_unavailable" : "biometric_unavailable")
    default: code = "storage_error"
    }
    return failure(code, stage: stage, status: status)
  }
  private static func marker(_ kind: String) -> String { "cardock.biometric-secret.v1.\(kind).configured" }
  static func query(_ kind: String, legacy: Bool = false) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: kind == "recovery" && !legacy
       ? "com.localaccount.cardock.recovery-secret.v2"
       : "com.localaccount.cardock.biometric-secret.v1.\(kind)",
     kSecAttrAccount as String: kind,
     kSecAttrSynchronizable as String: false]
  }
  static func policy(_ kind: String) -> LAPolicy {
    kind == "recovery" ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics
  }
  static func accessControl(_ kind: String) -> SecAccessControl? {
    SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      kind == "recovery" ? .userPresence : .biometryCurrentSet, nil)
  }
  static func clearForCommittedRebuild(
    defaults: UserDefaults = .standard,
    delete: (CFDictionary) -> OSStatus = { SecItemDelete($0) },
    probe: (CFDictionary) -> OSStatus = { SecItemCopyMatching($0, nil) }
  ) throws {
    // A committed rebuild will retry through its durable journal after outstanding IO drains.
    // Check before any deletion or marker change; never wait for IO on the main actor.
    guard CardockSecretWorkToken.pendingCount == 0 else { throw CocoaError(.fileWriteUnknown) }
    for attributes in [query("quickUnlock"), query("recovery"), query("recovery", legacy: true)] {
      let status = delete(attributes as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw CocoaError(.fileWriteUnknown) }
      var check = attributes
      check[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
      guard probe(check as CFDictionary) == errSecItemNotFound else { throw CocoaError(.fileWriteUnknown) }
    }
    for kind in ["quickUnlock", "recovery"] { defaults.removeObject(forKey: marker(kind)) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let kind = args["kind"] as? String,
      ["quickUnlock", "recovery"].contains(kind) else { result(Self.failure("invalid_secret")); return }
    if call.method == "availability" {
      let probe = makeContext()
      var error: NSError?
      let available = probe.available(Self.policy(kind), error: &error)
      result(available ? "available" : (error?.code == LAError.biometryNotEnrolled.rawValue ? "not_enrolled" : "unavailable"))
      probe.invalidate(); return
    }
    if call.method == "isConfigured" { result(defaults.bool(forKey: Self.marker(kind))); return }
    guard operation == nil, CardockSecretWorkToken.pendingCount == 0 else {
      result(Self.failure("auth_in_progress")); return
    }
    guard isActive(), protectedDataAvailable() else { result(Self.failure("activity_not_resumed")); return }
    if call.method == "delete" {
      let queries = kind == "recovery"
        ? [Self.query(kind), Self.query(kind, legacy: true)] : [Self.query(kind)]
      for query in queries {
        let status = keychain.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { result(Self.failure("storage_error")); return }
      }
      defaults.removeObject(forKey: Self.marker(kind)); result(nil); return
    }
    guard call.method == "read" || call.method == "write" else { result(FlutterMethodNotImplemented); return }
    var payload: Data?
    if call.method == "write" {
      guard let text = args["payload"] as? String, let data = text.data(using: .utf8),
        Self.validPayload(data, kind: kind) else { result(Self.failure("invalid_secret")); return }
      payload = data
    } else if !defaults.bool(forKey: Self.marker(kind)) { result(nil); return }

    let auth = makeContext()
    auth.prepare(allowPasscode: kind == "recovery")
    let reason = NSLocalizedString(kind == "recovery" ? "CardockRecoveryAuthentication" : "CardockQuickUnlockAuthentication", comment: "")
    auth.keychainContext.localizedReason = reason
    if payload != nil {
      var error: NSError?
      guard auth.available(Self.policy(kind), error: &error) else {
        result(Self.failure(Self.errorCode(error, kind: kind, legacy: false))); auth.invalidate(); return
      }
    }
    let id = UUID(), token = CardockSecretWorkToken()
    operation = id; pending = result; context = auth; workToken = token
    let timer = DispatchWorkItem { [weak self] in
      guard let self, self.operation == id else { return }
      self.finish(Self.failure("timeout"))
    }
    timeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timer)
    if let payload {
      auth.evaluate(Self.policy(kind), reason: reason) { [weak self] success, error in
        Task { @MainActor in
          guard let self, self.operation == id else { return }
          guard success else {
            self.finish(Self.failure(Self.errorCode(error, kind: kind, legacy: false))); return
          }
          self.whenActive(id) { [weak self] in
            self?.write(payload, kind: kind, auth: auth.keychainContext, id: id, token: token)
          }
        }
      }
    } else {
      // A generic-password attributes query also enforces its ACL. Read the item directly
      // so Security authenticates the actual stored ACL, without an unauthenticated probe.
      read(kind, auth: auth.keychainContext, legacy: false, id: id, token: token)
    }
  }
  private func whenActive(_ id: UUID, action: @escaping () -> Void) {
    guard operation == id else { return }
    authenticatedAction = action
    becameActive()
  }
  func becameActive() {
    guard isActive(), protectedDataAvailable() else { return }
    let action = authenticatedAction; authenticatedAction = nil; action?()
  }
  func backgrounded() {
    if operation != nil { finish(Self.failure("lifecycle_canceled")) }
  }
  private func finish(_ value: Any?) {
    let result = pending
    pending = nil; operation = nil; authenticatedAction = nil
    timeout?.cancel(); timeout = nil
    workToken?.cancel(); workToken = nil
    context?.invalidate(); context = nil
    readResult?.erase(); readResult = nil
    result?(value)
  }
  private static func authenticatedQuery(_ kind: String, auth: LAContext, legacy: Bool = false) -> [String: Any] {
    var query = Self.query(kind, legacy: legacy)
    query[kSecUseAuthenticationContext as String] = auth
    return query
  }
  private static func dataQuery(_ kind: String, auth: LAContext, legacy: Bool = false) -> [String: Any] {
    var query = authenticatedQuery(kind, auth: auth, legacy: legacy)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    return query
  }
  private func scheduleKeychain(_ token: CardockSecretWorkToken, work: @escaping () -> Void) {
    guard token.enqueue() else { return }
    executeKeychain {
      defer { token.workerReturned() }
      work()
    }
  }
  private func write(_ payload: Data, kind: String, auth: LAContext, id: UUID, token: CardockSecretWorkToken) {
    guard operation == id, isActive(), protectedDataAvailable() else { return }
    // Policy authentication already succeeded. Mutations must not request a second prompt.
    auth.interactionNotAllowed = true
    let query = Self.authenticatedQuery(kind, auth: auth)
    guard let acl = Self.accessControl(kind) else { finish(Self.failure("storage_error", stage: "write", status: errSecParam)); return }
    var attributes = query
    attributes[kSecAttrAccessControl as String] = acl
    attributes[kSecValueData as String] = payload
    let keychain = self.keychain
    scheduleKeychain(token) { [weak self] in
      let status = token.performIfLive { () -> OSStatus in
        let status = keychain.update(query as CFDictionary, [kSecValueData as String: payload] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        guard token.isLive else { return errSecUserCanceled }
        return keychain.add(attributes as CFDictionary)
      }
      Task { @MainActor in
        guard let self, self.operation == id, let status else { return }
        guard status == errSecSuccess else {
          self.finish(Self.keychainFailure(status, stage: "write", kind: kind)); return
        }
        self.whenActive(id) { [weak self] in
          guard let self, self.operation == id else { return }
          self.defaults.set(true, forKey: Self.marker(kind)); self.finish(nil)
        }
      }
    }
  }
  private func read(_ kind: String, auth: LAContext, legacy: Bool, id: UUID, token: CardockSecretWorkToken) {
    guard operation == id, isActive(), protectedDataAvailable() else { return }
    let query = Self.dataQuery(kind, auth: auth, legacy: legacy), keychain = self.keychain
    scheduleKeychain(token) { [weak self] in
      guard token.isLive else { return }
      let (status, value) = keychain.copy(query as CFDictionary)
      let outcome = CardockSecretReadResult(status, value)
      Task { @MainActor in
        guard let self, self.operation == id else { outcome.erase(); return }
        if status == errSecItemNotFound, kind == "recovery", !legacy {
          outcome.erase()
          self.whenActive(id) { [weak self] in
            self?.read(kind, auth: auth, legacy: true, id: id, token: token)
          }
          return
        }
        guard status == errSecSuccess else {
          outcome.erase()
          self.finish(Self.keychainFailure(status, stage: legacy ? "read_legacy" : "read_v2", kind: kind, legacy: legacy)); return
        }
        guard let data = outcome.data, Self.validPayload(data, kind: kind) else {
          outcome.erase(); self.finish(Self.failure("corrupted_secret", stage: legacy ? "read_legacy" : "read_v2")); return
        }
        self.readResult = outcome
        self.whenActive(id) { [weak self] in
          guard let self, self.operation == id else { outcome.erase(); return }
          if legacy { self.migrate(outcome, kind: kind, auth: auth, id: id, token: token) }
          else { self.deliver(outcome, id: id) }
        }
      }
    }
  }
  private func deliver(_ outcome: CardockSecretReadResult, id: UUID) {
    guard operation == id, isActive(), protectedDataAvailable() else { return }
    guard let data = outcome.data, let text = String(data: data, encoding: .utf8) else {
      finish(Self.failure("corrupted_secret")); return
    }
    finish(text)
  }
  private func migrate(_ outcome: CardockSecretReadResult, kind: String, auth: LAContext, id: UUID, token: CardockSecretWorkToken) {
    guard operation == id, isActive(), protectedDataAvailable(), let payload = outcome.data else { return }
    auth.interactionNotAllowed = true
    guard let acl = Self.accessControl(kind) else { finish(Self.failure("storage_error", stage: "migration_add", status: errSecParam)); return }
    var attributes = Self.authenticatedQuery(kind, auth: auth)
    attributes[kSecAttrAccessControl as String] = acl
    attributes[kSecValueData as String] = payload
    let query = Self.dataQuery(kind, auth: auth), keychain = self.keychain
    scheduleKeychain(token) { [weak self] in
      let result = token.performIfLive { () -> (OSStatus, String) in
        // Copy the identical root only. Never update a duplicate or delete the legacy item.
        let status = keychain.add(attributes as CFDictionary)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return (status, "migration_add") }
        guard token.isLive else { return (errSecUserCanceled, "migration_verify") }
        let (checkStatus, checkValue) = keychain.copy(query as CFDictionary)
        let check = CardockSecretReadResult(checkStatus, checkValue)
        defer { check.erase() }
        guard checkStatus == errSecSuccess else { return (checkStatus, "migration_verify") }
        return (check.data == payload ? errSecSuccess : errSecDecode, "migration_verify")
      }
      Task { @MainActor in
        guard let self, self.operation == id, let result else { return }
        guard result.0 == errSecSuccess else {
          self.finish(Self.keychainFailure(result.0, stage: result.1, kind: kind)); return
        }
        self.whenActive(id) { [weak self] in self?.deliver(outcome, id: id) }
      }
    }
  }
  private static func errorCode(_ error: Error?, kind: String, legacy: Bool) -> String {
    guard let error = error as? LAError else {
      return kind == "recovery" ? "device_authentication_unavailable" : "biometric_unavailable"
    }
    switch error.code {
    case .userCancel, .userFallback: return "user_canceled"
    case .appCancel, .systemCancel: return "system_canceled"
    case .passcodeNotSet: return kind == "recovery" ? "passcode_not_set" : "biometric_unavailable"
    default:
      if legacy { return "legacy_recovery_unavailable" }
      if kind == "recovery" { return "device_authentication_unavailable" }
      switch error.code {
      case .biometryLockout: return "biometric_lockout"
      case .biometryNotEnrolled: return "not_enrolled"
      default: return "biometric_unavailable"
      }
    }
  }
}
