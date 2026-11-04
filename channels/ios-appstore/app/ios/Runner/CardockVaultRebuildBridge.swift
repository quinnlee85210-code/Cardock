import Flutter
import LocalAuthentication
import Security
import UIKit
import UserNotifications

protocol CardockRebuildAuthenticating: AnyObject {
  func available(error: inout NSError?) -> Bool
  func evaluate(reason: String, reply: @escaping @Sendable (Bool, Error?) -> Void)
  func invalidate()
}

extension LAContext: CardockRebuildAuthenticating {
  func available(error: inout NSError?) -> Bool {
    canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
  }
  func evaluate(reason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
    touchIDAuthenticationAllowableReuseDuration = 0
    evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: reply)
  }
}

/// Short-lived, single-use permission to commit deletion; never an unlock key.
final class CardockRebuildPermit {
  private let now: () -> TimeInterval
  private var token: String?
  private var issuedAt: TimeInterval = 0

  init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.now = now
  }
  func issue() -> [String: Any] {
    invalidate()
    let value = UUID().uuidString
    token = value; issuedAt = now()
    return ["token": value, "unsecured": false]
  }
  private func valid(_ value: String?) -> Bool {
    let age = now() - issuedAt
    return token != nil && value == token && age >= 0 && age <= 120
  }
  func consume(_ args: [String: Any]) -> Bool {
    defer { invalidate() }
    return valid(args["token"] as? String)
  }
  func invalidate() { token = nil }
}

@MainActor
final class CardockVaultRebuildBridge {
  private let channel: FlutterMethodChannel
  private let makeContext: () -> CardockRebuildAuthenticating
  private let isActive: @MainActor () -> Bool
  private let protectedDataAvailable: @MainActor () -> Bool
  private let clearCommitted: (@escaping (Any?) -> Void) -> Void
  private let permit: CardockRebuildPermit
  private var context: CardockRebuildAuthenticating?
  private var pending: FlutterResult?
  private var operation: UUID?
  private var authenticated = false
  private var timeout: DispatchWorkItem?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger,
    makeContext: @escaping () -> CardockRebuildAuthenticating = { LAContext() },
    isActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
    protectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
    permit: CardockRebuildPermit = CardockRebuildPermit(),
    clearCommitted: ((@escaping (Any?) -> Void) -> Void)? = nil) {
    self.makeContext = makeContext; self.isActive = isActive
    self.protectedDataAvailable = protectedDataAvailable
    self.permit = permit; self.clearCommitted = clearCommitted ?? Self.clearCommittedData
    channel = FlutterMethodChannel(name: "cardock/vault_rebuild_v1", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else { result(CardockCoreBridge.error("interrupted")); return }
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

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "clearCommitted" {
      guard pending == nil, protectedDataAvailable() else {
        result(CardockCoreBridge.error("rebuild_unavailable")); return
      }
      permit.invalidate()
      clearCommitted(result)
      return
    }
    guard let args = call.arguments as? [String: Any] else {
      result(CardockCoreBridge.error("invalid_arguments")); return
    }
    switch call.method {
    case "authorize": authorize(args, result: result)
    case "beginHold", "cancelHold":
      result(CardockCoreBridge.error("device_authentication_required"))
    case "consume":
      guard isActive(), protectedDataAvailable(), pending == nil else {
        permit.invalidate(); result(false); return
      }
      result(permit.consume(args))
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func authorize(_ args: [String: Any], result: @escaping FlutterResult) {
    guard pending == nil, isActive(), protectedDataAvailable(),
      let message = args["message"] as? String, !message.isEmpty, message.utf8.count <= 1024 else {
      result(CardockCoreBridge.error("rebuild_unavailable")); return
    }
    permit.invalidate()
    let auth = makeContext()
    var error: NSError?
    guard auth.available(error: &error) else {
      auth.invalidate()
      // iOS deletion always requires successful system authentication.
      result(CardockCoreBridge.error("device_authentication_unavailable"))
      return
    }
    let id = UUID()
    operation = id; pending = result; context = auth
    let timer = DispatchWorkItem { [weak self] in
      guard let self, self.operation == id else { return }
      self.finish(CardockCoreBridge.error("authentication_timeout"))
    }
    timeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timer)
    auth.evaluate(reason: message) { [weak self] success, _ in
      Task { @MainActor in
        guard let self, self.operation == id else { return }
        guard success else { self.finish(nil); return }
        self.authenticated = true
        self.becameActive()
      }
    }
  }

  func becameActive() {
    guard isActive(), protectedDataAvailable(), authenticated, pending != nil else { return }
    finish(permit.issue())
  }
  func backgrounded() {
    permit.invalidate()
    if pending != nil { finish(nil) }
  }
  private func finish(_ value: Any?) {
    let result = pending
    pending = nil; operation = nil; authenticated = false
    timeout?.cancel(); timeout = nil
    context?.invalidate(); context = nil
    result?(value)
  }

  /// Startup replay is permitted only for our exact durable committed intent.
  static func validateCommittedJournal(in root: URL) throws {
    guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw CocoaError(.fileReadNoPermission)
    }
    let journal = root.appendingPathComponent("cardock_rebuild_v1.json")
    guard try FileManager.default.attributesOfItem(atPath: journal.path)[.type] as? FileAttributeType == .typeRegular else {
      throw CocoaError(.fileReadNoPermission)
    }
    let data = try CardockCoreBridge.readBounded(journal, maximum: 256)
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(value.keys) == Set(["version", "phase"]),
      let version = value["version"] as? NSNumber,
      CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
      value["phase"] as? String == "committed" else { throw CocoaError(.fileReadCorruptFile) }
  }

  static func clearLocalHandles(in root: URL) throws {
    try validateCommittedJournal(in: root)
    let handles = root.appendingPathComponent("cardock_backup_handles_v1", isDirectory: true)
    let manager = FileManager.default
    do {
      let attributes = try manager.attributesOfItem(atPath: handles.path)
      guard attributes[.type] as? FileAttributeType == .typeDirectory else {
        throw CocoaError(.fileReadNoPermission)
      }
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return
    }
    // Delete local opaque receipts, never resolve their external bookmarks.
    try manager.removeItem(at: handles)
  }

  private static func clearCommittedData(completion: @escaping (Any?) -> Void) {
    do {
      let root = try FileManager.default.url(for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: false)
      try validateCommittedJournal(in: root)
      try CardockBiometricSecretBridge.clearForCommittedRebuild()
      try clearLocalHandles(in: root)
    } catch { completion(CardockCoreBridge.error("rebuild_cleanup_failed")); return }
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
    center.getPendingNotificationRequests { pending in
      center.getDeliveredNotifications { delivered in
        DispatchQueue.main.async {
          completion(pending.isEmpty && delivered.isEmpty ? nil : CardockCoreBridge.error("rebuild_cleanup_failed"))
        }
      }
    }
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    timeout?.cancel()
    context?.invalidate()
  }
}
