import Darwin
import Flutter
import Network
import UIKit

@MainActor
final class CardockLocalNetworkBridge {
  private let addresses: FlutterMethodChannel
  private let runtime: FlutterMethodChannel
  private var monitor: NWPathMonitor?
  private var addressResult: FlutterResult?
  private var addressRequest: UUID?
  private var running = false
  private var previousIdleTimerDisabled = false
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  init(messenger: FlutterBinaryMessenger) {
    addresses = FlutterMethodChannel(name: "cardock/ios_local_network_v1", binaryMessenger: messenger)
    runtime = FlutterMethodChannel(name: "cardock/temporary_web_runtime", binaryMessenger: messenger)
    addresses.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else { result(FlutterError(code: "interrupted", message: nil, details: nil)); return }
        guard call.method == "listAddresses" else { result(FlutterMethodNotImplemented); return }
        self.listAddresses(result)
      }
    }
    runtime.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else { result(FlutterError(code: "interrupted", message: nil, details: nil)); return }
        switch call.method {
        case "start":
          guard UIApplication.shared.applicationState == .active else {
            result(FlutterError(code: "activity_not_resumed", message: nil, details: nil)); return
          }
          if !self.running {
            self.running = true
            self.previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            self.beginBackgroundTime()
          }
          result(nil)
        case "stop":
          if self.running {
            self.running = false
            UIApplication.shared.isIdleTimerDisabled = self.previousIdleTimerDisabled
          }
          self.endBackgroundTime()
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  // iOS grants only finite background execution. Expiration releases that grant,
  // not the logical session. Its original Dart deadline and access gates remain.
  private func beginBackgroundTime() {
    guard running, backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Cardock computer entry") { [weak self] in
      self?.endBackgroundTime()
    }
  }
  private func endBackgroundTime() {
    guard backgroundTask != .invalid else { return }
    let task = backgroundTask
    backgroundTask = .invalid
    UIApplication.shared.endBackgroundTask(task)
  }
  @objc private func becameActive() {
    if running { beginBackgroundTime() }
  }

  private func listAddresses(_ result: @escaping FlutterResult) {
    guard addressResult == nil else {
      result(FlutterError(code: "operation_in_progress", message: nil, details: nil)); return
    }
    let id = UUID()
    addressResult = result; addressRequest = id
    let observer = NWPathMonitor(requiredInterfaceType: .wifi)
    monitor = observer
    observer.pathUpdateHandler = { [weak self] path in
      let names = path.status == .satisfied && path.usesInterfaceType(.wifi)
        ? Set(path.availableInterfaces.filter { $0.type == .wifi }.map { $0.name }) : Set<String>()
      let values = Self.wifiAddresses(names: names)
      Task { @MainActor in self?.finishAddresses(values, id: id) }
    }
    observer.start(queue: DispatchQueue(label: "cardock.local-network-addresses"))
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.finishAddresses(FlutterError(code: "network_unavailable", message: nil, details: nil), id: id)
    }
  }
  private func finishAddresses(_ value: Any, id: UUID) {
    guard addressRequest == id else { return }
    monitor?.cancel(); monitor = nil
    let result = addressResult
    addressResult = nil; addressRequest = nil
    result?(value)
  }
  nonisolated static func isPrivateIPv4(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 4 else { return false }
    return bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
      (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254)
  }
  nonisolated private static func wifiAddresses(names: Set<String>) -> [[String: String]] {
    guard !names.isEmpty else { return [] }
    var first: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&first) == 0, let first else { return [] }
    defer { freeifaddrs(first) }
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    var results = [[String: String]]()
    while let pointer = cursor {
      let item = pointer.pointee
      cursor = item.ifa_next
      guard let namePointer = item.ifa_name, let address = item.ifa_addr else { continue }
      let name = String(cString: namePointer)
      guard names.contains(name), address.pointee.sa_family == UInt8(AF_INET),
        item.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING) else { continue }
      let ipv4 = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee
      var raw = ipv4.sin_addr
      let bytes = withUnsafeBytes(of: &raw) { Array($0) }
      guard isPrivateIPv4(bytes) else { continue }
      let text = bytes.map(String.init).joined(separator: ".")
      results.append(["address": text, "interfaceName": name])
    }
    return results.sorted { $0["address", default: ""] < $1["address", default: ""] }
  }
}
