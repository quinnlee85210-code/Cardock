import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?
  static let privacyPreferenceKey = "cardock.appSwitcherPrivacyEnabled"
  static var privacyEnabled: Bool {
    get { (UserDefaults.standard.object(forKey: privacyPreferenceKey) as? Bool) ?? true }
    set { UserDefaults.standard.set(newValue, forKey: privacyPreferenceKey) }
  }
  func updatePrivacyPreference() {
    if !Self.privacyEnabled {
      privacyCover?.removeFromSuperview()
      privacyCover = nil
    }
  }
  override func sceneWillResignActive(_ scene: UIScene) {
    cover()
    super.sceneWillResignActive(scene)
  }
  override func sceneDidEnterBackground(_ scene: UIScene) {
    cover()
    super.sceneDidEnterBackground(scene)
  }
  override func sceneWillEnterForeground(_ scene: UIScene) {
    cover()
    super.sceneWillEnterForeground(scene)
  }
  private func cover() {
    guard Self.privacyEnabled, privacyCover == nil, let window else { return }
    let view = UIView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.backgroundColor = .systemBackground
    view.isUserInteractionEnabled = true
    view.accessibilityViewIsModal = true
    window.addSubview(view)
    privacyCover = view
  }
  func acknowledgeSafeFrame() {
    guard window?.windowScene?.activationState == .foregroundActive else { return }
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
