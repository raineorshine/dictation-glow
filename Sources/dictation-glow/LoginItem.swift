import Foundation
import ServiceManagement
import DictationGlowCore

/// The ServiceManagement side of the login item. The decision lives in LoginItemPolicy; this
/// only carries it out and reports what happened.
enum LoginItem {
  private static let registeredBeforeKey = "com.raine.dictationglow.hasRegisteredLoginItem"

  static var status: LoginItemPolicy.Status {
    switch SMAppService.mainApp.status {
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    case .notRegistered: return .notRegistered
    case .notFound: return .notFound
    @unknown default: return .notFound
    }
  }

  /// True only for the installed copy. A build-tree copy reading or writing the record
  /// repoints it at itself, and the build script deletes that copy on the next build.
  static var isInstalledLocation: Bool {
    Bundle.main.bundlePath.hasPrefix("/Applications/")
  }

  /// R18. Registers once, on a genuine first run, and never again. A user who turns the item
  /// off in System Settings stays turned off.
  static func registerOnFirstRunIfNeeded() {
    let hasRegisteredBefore = UserDefaults.standard.bool(forKey: registeredBeforeKey)
    guard isInstalledLocation else { return }
    let decision = LoginItemPolicy.decide(
      status: status,
      hasRegisteredBefore: hasRegisteredBefore,
      isInstalledLocation: true)
    guard decision == .register else { return }
    do {
      try SMAppService.mainApp.register()
      UserDefaults.standard.set(true, forKey: registeredBeforeKey)
    } catch {
      // Not fatal: the app still works for this session, it just will not come back after a
      // restart. The menu says so rather than the app failing to launch.
      NSLog("dictation-glow: could not register the login item: \(error.localizedDescription)")
    }
  }

  /// The menu's toggle. Returns the error text when the change did not take, so the caller
  /// can restore the control rather than leaving it lying.
  static func setEnabled(_ enabled: Bool) -> String? {
    do {
      if enabled {
        try SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: registeredBeforeKey)
      } else {
        try SMAppService.mainApp.unregister()
      }
      return nil
    } catch {
      return error.localizedDescription
    }
  }
}
