import Flutter
import UIKit
import UniformTypeIdentifiers
import Darwin
import CryptoKit
import UserNotifications

private final class CardockReadOperation {
  let coordinator = NSFileCoordinator()
  private let lock = NSLock()
  private var stopped = false
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
  func cancel() {
    lock.lock(); stopped = true; lock.unlock()
    coordinator.cancel()
  }
}

/// Phase 1 system boundary. No business key or vault contents enter this bridge.
@MainActor
final class CardockCoreBridge: NSObject, UIDocumentPickerDelegate {
  private var channels: [FlutterMethodChannel] = []
  private let backupQueue = DispatchQueue(label: "cardock.backup-directory", qos: .userInitiated)
  private var pending: FlutterResult?
  private var picker: UIDocumentPickerViewController?
  private var operationID = UUID()
  private var operation = ""
  private var limit = 0
  private var exportURL: URL?
  private var readOperation: CardockReadOperation?
  private var timeout: DispatchWorkItem?
  private var backgroundObserver: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    register("cardock/screen_protection", messenger) { call, result in
      switch call.method {
      case "getSecureFlag": result(SceneDelegate.privacyEnabled)
      case "setSecureFlag":
        guard let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool else {
          result(Self.error("invalid_arguments")); return
        }
        SceneDelegate.privacyEnabled = enabled
        for scene in UIApplication.shared.connectedScenes {
          (scene.delegate as? SceneDelegate)?.updatePrivacyPreference()
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    register("cardock/ios_core_v1", messenger) { [weak self] call, result in
      guard let self else { result(Self.error("interrupted")); return }
      switch call.method {
      case "prepareStorage":
        do { try Self.prepareStorage(); result(true) }
        catch { result(Self.error("storage_unavailable")) }
      case "frameReady":
        for scene in UIApplication.shared.connectedScenes where scene.activationState == .foregroundActive {
          (scene.delegate as? SceneDelegate)?.acknowledgeSafeFrame()
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    register("account_subscription_manager/unlock_clock_v1", messenger) { call, result in
      guard call.method == "read" else { result(FlutterMethodNotImplemented); return }
      var boot = timeval()
      var size = MemoryLayout<timeval>.size
      var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
      guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else {
        result(Self.error("clock_unavailable")); return
      }
      var timebase = mach_timebase_info_data_t()
      guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else {
        result(Self.error("clock_unavailable")); return
      }
      // Continuous time includes sleep; a changed boot identity conservatively rearms cooldown.
      let milliseconds = Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
      result(["bootCount": Int64(boot.tv_sec), "elapsedRealtimeMilliseconds": Int64(milliseconds)])
    }
    register("account_subscription_manager/sensitive_clipboard", messenger) { call, result in
      guard call.method == "copySensitive" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: Any], let text = args["text"] as? String,
        !text.isEmpty, let seconds = args["clearAfterSeconds"] as? Int, (0...300).contains(seconds),
        UIApplication.shared.applicationState == .active else { result(Self.error("unavailable")); return }
      UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [
        .localOnly: true, .expirationDate: Date().addingTimeInterval(TimeInterval(seconds))])
      result(nil)
    }
    register("cardock/document_storage_v1", messenger) { [weak self] call, result in
      guard let self else { result(Self.error("interrupted")); return }
      switch call.method {
      case "pickBackup", "pickImport", "saveBackup", "pickDirectory": self.begin(call, result)
      case "hasPermission", "createBackup", "write", "read", "deleteOwned":
        guard UIApplication.shared.isProtectedDataAvailable else {
          result(Self.error("interrupted")); return
        }
        self.backupQueue.async {
          let response: Any?
          do { response = try CardockBackupDirectoryStore().handle(call) }
          catch let error as CardockBackupDirectoryFailure { response = Self.error(error.code) }
          catch let error as CocoaError {
            switch error.code {
            case .fileNoSuchFile, .fileReadNoSuchFile: response = Self.error("directory_missing")
            case .fileWriteOutOfSpace: response = Self.error("storage_full")
            case .fileReadNoPermission, .fileWriteNoPermission: response = Self.error("permission_revoked")
            default: response = Self.error("provider_refused")
            }
          }
          catch { response = Self.error("provider_refused") }
          DispatchQueue.main.async { result(response) }
        }
      case "beginExport", "appendExport", "finishExport", "abortExport":
        result(Self.error("unsupported_platform"))
      default: result(FlutterMethodNotImplemented)
      }
    }
    register("cardock/notification_reliability", messenger) { call, result in
      switch call.method {
      case "inspect":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let allowed: Bool
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral: allowed = true
          case .denied, .notDetermined: allowed = false
          @unknown default: allowed = false
          }
          DispatchQueue.main.async {
            result(["manufacturer": "Apple", "model": "iPhone / iPad",
              "applicationNotificationsEnabled": allowed,
              "reminderChannelSoundEnabled": settings.soundSetting == .enabled])
          }
        }
      case "openSettings":
        guard let args = call.arguments as? [String: Any],
          let target = args["target"] as? String,
          ["applicationNotifications", "reminderChannel"].contains(target),
          UIApplication.shared.applicationState == .active,
          let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
          result(false); return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      default: result(FlutterMethodNotImplemented)
      }
    }
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.complete(Self.error("interrupted"), dismiss: true) }
    }
  }

  private func register(_ name: String, _ messenger: FlutterBinaryMessenger,
    handler: @escaping FlutterMethodCallHandler) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler(handler)
    channels.append(channel)
  }

  static func prepareStorage() throws {
    guard UIApplication.shared.isProtectedDataAvailable else { throw CocoaError(.fileReadNoPermission) }
    let manager = FileManager.default
    var support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    // Only the app's private support directory; reject links before changing attributes.
    guard try support.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw CocoaError(.fileReadNoPermission)
    }
    try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: support.path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try support.setResourceValues(values)
    var enumerationFailed = false
    guard let files = manager.enumerator(at: support, includingPropertiesForKeys: [.isSymbolicLinkKey],
      options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else {
      throw CocoaError(.fileReadNoPermission)
    }
    do {
      for case let file as URL in files {
        if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
          throw CocoaError(.fileReadNoPermission)
        }
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
      }
    }
    if enumerationFailed { throw CocoaError(.fileReadNoPermission) }
  }

  private func begin(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard pending == nil else { result(Self.error("operation_in_progress")); return }
    guard UIApplication.shared.applicationState == .active,
      let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .filter({ $0.activationState == .foregroundActive }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
      var presenter = window.rootViewController else { result(Self.error("ui_unavailable")); return }
    while let presented = presenter.presentedViewController { presenter = presented }
    guard !presenter.isBeingDismissed else { result(Self.error("ui_unavailable")); return }
    pending = result
    operationID = UUID()
    operation = call.method
    limit = call.method == "pickImport" ? 10 * 1024 * 1024 : 16 * 1024 * 1024
    let controller: UIDocumentPickerViewController
    if call.method == "pickDirectory" {
      controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    } else if call.method == "saveBackup" {
      guard let args = call.arguments as? [String: Any], let data = args["bytes"] as? FlutterStandardTypedData,
        !data.data.isEmpty, data.data.count <= limit, let name = args["name"] as? String,
        name.range(of: #"^AccountBook_[0-9]{8}_[0-9]{4}\.asmbackup$"#, options: .regularExpression) != nil else {
        complete(Self.error("invalid_document")); return
      }
      do {
        var directory = FileManager.default.temporaryDirectory.appendingPathComponent("cardock-export-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
          attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let url = directory.appendingPathComponent(name)
        exportURL = url
        try data.data.write(to: url, options: [.atomic, .completeFileProtection])
        controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
      } catch { complete(Self.error("write_failed")); return }
    } else {
      // Content is still validated by the existing codecs; .data permits extension-less provider files.
      controller = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
    }
    controller.allowsMultipleSelection = false
    controller.delegate = self
    controller.modalPresentationStyle = .fullScreen
    picker = controller
    let id = operationID
    let timer = DispatchWorkItem { [weak self] in
      guard let self, self.operationID == id else { return }
      self.complete(Self.error("timeout"), dismiss: true)
    }
    timeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timer)
    presenter.present(controller, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard controller === picker else { return }
    complete(operation == "saveBackup" ? false : nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard controller === picker, pending != nil, readOperation == nil else { return }
    guard urls.count == 1, let url = urls.first, url.isFileURL else { complete(Self.error("read_failed")); return }
    if operation == "saveBackup" { complete(true); return }
    let id = operationID
    let maximum = limit
    let choosingDirectory = operation == "pickDirectory"
    let reading = CardockReadOperation()
    readOperation = reading
    // File coordination and provider reads must not block the main/UI thread.
    DispatchQueue.global(qos: .userInitiated).async {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      guard scoped || url.resolvingSymlinksInPath().path.hasPrefix(NSHomeDirectory() + "/") else {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.operationID == id else { return }
          self.complete(Self.error("permission_revoked"))
        }
        return
      }
      var coordinationError: NSError?
      var response: Any = Self.error("read_failed")
      reading.coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
        do {
          if choosingDirectory {
            guard !reading.isCancelled else { throw CocoaError(.userCancelled) }
            response = try CardockBackupDirectoryStore.directoryBookmark(coordinated)
          } else {
            let data = try Self.readBounded(coordinated, maximum: maximum, isCancelled: { reading.isCancelled })
            response = ["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: data)]
          }
        } catch let error as CocoaError where error.code == .fileReadTooLarge {
          response = Self.error("too_large")
        } catch { response = Self.error("read_failed") }
      }
      if coordinationError != nil { response = Self.error("provider_unavailable") }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.operationID == id else { return }
        self.complete(response)
      }
    }
  }

  nonisolated static func readBounded(_ url: URL, maximum: Int, isCancelled: () -> Bool = { false }) throws -> Data {
    guard maximum > 0, !isCancelled() else { throw CocoaError(.userCancelled) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while let chunk = try handle.read(upToCount: min(64 * 1024, maximum - data.count + 1)), !chunk.isEmpty {
      guard chunk.count <= maximum - data.count else { throw CocoaError(.fileReadTooLarge) }
      guard !isCancelled() else { throw CocoaError(.userCancelled) }
      data.append(chunk)
    }
    guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    return data
  }

  private func complete(_ value: Any?, dismiss: Bool = false) {
    guard let callback = pending else { return }
    pending = nil
    readOperation?.cancel(); readOperation = nil
    operationID = UUID() // Reject late provider completion and repeated delegate callbacks.
    timeout?.cancel(); timeout = nil
    let controller = picker; picker = nil
    if dismiss { controller?.dismiss(animated: false) }
    if let url = exportURL {
      // Only this operation's own temporary export directory, never the chosen destination.
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
      exportURL = nil
    }
    callback(value)
  }

  nonisolated static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "The system operation could not complete.", details: nil)
  }

  deinit {
    timeout?.cancel()
    if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
  }
}


struct CardockBackupDirectoryFailure: Error {
  let code: String
}

/// Persistent picker bookmarks and exact ownership receipts, never arbitrary paths.
/// All calls run on the bridge's serial worker; only encrypted backup bytes enter it.
final class CardockBackupDirectoryStore {
  private static let treePrefix = "ios-directory:"
  private static let filePrefix = "ios-backup:"
  private static let maximumBytes = 16 * 1024 * 1024
  private let receiptDirectory: URL

  init(receiptDirectory: URL? = nil) throws {
    self.receiptDirectory = try receiptDirectory ?? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("cardock_backup_handles_v1", isDirectory: true)
    try FileManager.default.createDirectory(at: self.receiptDirectory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    guard try self.receiptDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    var directory = self.receiptDirectory
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
  }

  static func directoryBookmark(_ url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard url.isFileURL, values.isDirectory == true, values.isSymbolicLink != true else {
      throw CardockBackupDirectoryFailure(code: "directory_missing")
    }
    // iOS preserves the picker security scope in a minimal bookmark; macOS-only
    // .withSecurityScope creation/resolution options are intentionally absent.
    let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    return treePrefix + data.base64EncodedString()
  }

  private func withDirectory<T>(_ tree: String, _ body: (URL) throws -> T) throws -> T {
    guard tree.hasPrefix(Self.treePrefix), tree.utf8.count <= 128 * 1024,
      let data = Data(base64Encoded: String(tree.dropFirst(Self.treePrefix.count))) else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    var stale = false
    let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
    // A changed provider grant requires the user to select the folder again.
    guard !stale, url.isFileURL else { throw CardockBackupDirectoryFailure(code: "permission_revoked") }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard scoped || url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(NSHomeDirectory() + "/") else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw CardockBackupDirectoryFailure(code: "directory_missing")
    }
    return try body(url)
  }

  private func coordinate<T>(_ url: URL, writing: Bool, deleting: Bool = false,
    _ body: (URL) throws -> T) throws -> T {
    var providerError: NSError?
    var outcome: Result<T, Error>?
    let coordinator = NSFileCoordinator()
    let accessor: (URL) -> Void = { target in outcome = Result { try body(target) } }
    if writing {
      coordinator.coordinate(writingItemAt: url, options: deleting ? .forDeleting : [], error: &providerError, byAccessor: accessor)
    } else {
      coordinator.coordinate(readingItemAt: url, options: [], error: &providerError, byAccessor: accessor)
    }
    if let providerError { throw providerError }
    guard let outcome else { throw CardockBackupDirectoryFailure(code: "provider_refused") }
    return try outcome.get()
  }

  private func receiptURL(_ handle: String) throws -> URL {
    guard handle.hasPrefix(Self.filePrefix),
      let id = UUID(uuidString: String(handle.dropFirst(Self.filePrefix.count))) else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    return receiptDirectory.appendingPathComponent(id.uuidString + ".json")
  }

  private func load(_ handle: String) throws -> [String: String] {
    let url = try receiptURL(handle)
    guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    let data = try CardockCoreBridge.readBounded(url, maximum: 192 * 1024)
    guard let record = try JSONSerialization.jsonObject(with: data) as? [String: String],
      record["tree"] != nil, let name = record["name"], Self.validName(name) else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    return record
  }

  private func save(_ record: [String: String], handle: String) throws {
    try JSONSerialization.data(withJSONObject: record).write(to: receiptURL(handle), options: [.atomic, .completeFileProtection])
  }

  static func validName(_ name: String) -> Bool {
    name.range(of: #"^Cardock-[0-9]{10,16}-[a-f0-9]{32}\.asmbackup$"#, options: .regularExpression) != nil
  }

  private func validateFile(_ url: URL, parent: URL) throws {
    guard url.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  func handle(_ call: FlutterMethodCall) throws -> Any? {
    guard let args = call.arguments as? [String: Any] else { throw CardockBackupDirectoryFailure(code: "provider_refused") }
    if call.method == "hasPermission" {
      guard let tree = args["tree"] as? String else { return false }
      return (try? withDirectory(tree) { directory in
        try coordinate(directory, writing: false) { target in
          try target.resourceValues(forKeys: [.isWritableKey]).isWritable == true
        }
      }) ?? false
    }
    if call.method == "createBackup" {
      guard let tree = args["tree"] as? String, let name = args["name"] as? String, Self.validName(name) else {
        throw CardockBackupDirectoryFailure(code: "provider_refused")
      }
      return try withDirectory(tree) { directory in
        let file = directory.appendingPathComponent(name)
        let handle = Self.filePrefix + UUID().uuidString
        try coordinate(file, writing: true) { target in
          guard target.standardizedFileURL == file.standardizedFileURL else {
            throw CardockBackupDirectoryFailure(code: "provider_refused")
          }
          try Data().write(to: target, options: .withoutOverwriting)
        }
        try save(["tree": tree, "name": name], handle: handle)
        return handle
      }
    }
    guard ["write", "read", "deleteOwned"].contains(call.method), let handle = args["uri"] as? String else {
      throw CardockBackupDirectoryFailure(code: "provider_refused")
    }
    var record = try load(handle)
    let tree = record["tree"]!
    if call.method == "deleteOwned", args["tree"] as? String != tree {
      throw CardockBackupDirectoryFailure(code: "permission_revoked")
    }
    return try withDirectory(tree) { directory -> Any? in
      let file = directory.appendingPathComponent(record["name"]!)
      return try coordinate(file, writing: call.method != "read", deleting: call.method == "deleteOwned") { target -> Any? in
        try validateFile(target, parent: directory)
        if call.method == "write" {
          guard record["digest"] == nil,
            try target.resourceValues(forKeys: [.fileSizeKey]).fileSize == 0,
            let bytes = args["bytes"] as? FlutterStandardTypedData,
            !bytes.data.isEmpty, bytes.data.count <= Self.maximumBytes else {
            throw CardockBackupDirectoryFailure(code: "provider_refused")
          }
          // Store the expected ciphertext digest first: an interrupted write
          // cannot later authorize deletion of a different provider file.
          record["digest"] = Self.digest(bytes.data)
          try save(record, handle: handle)
          try bytes.data.write(to: target, options: .atomic)
          return nil
        }
        let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let bytes = size == 0 ? Data() : try CardockCoreBridge.readBounded(target, maximum: Self.maximumBytes)
        if let expected = record["digest"] {
          guard Self.digest(bytes) == expected else { throw CardockBackupDirectoryFailure(code: "read_failed") }
        } else if !bytes.isEmpty {
          throw CardockBackupDirectoryFailure(code: "permission_revoked")
        }
        if call.method == "read" {
          guard !bytes.isEmpty else { throw CardockBackupDirectoryFailure(code: "read_failed") }
          return FlutterStandardTypedData(bytes: bytes)
        }
        // This exact registered, unchanged file only. Never enumerate a provider.
        try FileManager.default.removeItem(at: target)
        try FileManager.default.removeItem(at: receiptURL(handle))
        return nil
      }
    }
  }
}
