import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // U5 installs the status item. Until then the app runs headless, which is what
    // makes U1 verifiable on its own: it launches, stays up, and shows no Dock icon.
  }
}
