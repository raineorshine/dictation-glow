import AppKit
import DictationGlowCore

/// The status item and its menu. The app's only visible surface.
final class MenuBar {
  private let item: NSStatusItem
  private let menu = NSMenu()
  private var launchItem: NSMenuItem!
  private let menuDelegate = MenuRefresher()
  private var statusLine: NSMenuItem!

  /// Asked for the line that says when detection last worked, so the menu does not hold a
  /// copy of that state.
  var lastConfirmedDescription: () -> String = { "No session seen yet" }
  var onRunSelfTest: () -> Void = {}

  init() {
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(
      systemSymbolName: "mic", accessibilityDescription: "Dictation Glow")
    // The image's description names it, but the title is what a name is looked up by, and an
    // image-only button leaves that empty: the item reads `missing value` to a script.
    item.button?.setAccessibilityTitle("Dictation Glow")

    statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    statusLine.isEnabled = false
    menu.addItem(statusLine)
    menu.addItem(.separator())

    let test = NSMenuItem(
      title: "Run Self-Test…", action: #selector(runSelfTest), keyEquivalent: "")
    test.target = self
    menu.addItem(test)

    launchItem = NSMenuItem(
      title: "Open at Login", action: #selector(toggleLaunch), keyEquivalent: "")
    launchItem.target = self
    menu.addItem(launchItem)

    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: "Quit Dictation Glow", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    menu.addItem(quit)

    menuDelegate.onOpen = { [weak self] in self?.refresh() }
    menu.delegate = menuDelegate
    item.menu = menu
  }

  private func refresh() {
    statusLine.title = lastConfirmedDescription()
    launchItem.state = LoginItemPolicy.isOn(LoginItem.status) ? .on : .off
  }

  @objc private func runSelfTest() { onRunSelfTest() }

  @objc private func toggleLaunch(_ sender: NSMenuItem) {
    let turningOn = sender.state == .off
    if let error = LoginItem.setEnabled(turningOn) {
      // Leave the control showing what is actually true rather than what was asked for.
      sender.state = LoginItemPolicy.isOn(LoginItem.status) ? .on : .off
      let alert = NSAlert()
      alert.messageText = "Could not change the login item"
      alert.informativeText = error
      alert.runModal()
    } else {
      sender.state = turningOn ? .on : .off
    }
  }
}

/// Menus have no block-based will-open hook, so the delegate is its own object. It is owned
/// by the MenuBar it serves rather than shared: a second MenuBar would otherwise overwrite
/// the first one's callback and quietly refresh the wrong instance.
private final class MenuRefresher: NSObject, NSMenuDelegate {
  var onOpen: () -> Void = {}
  func menuWillOpen(_ menu: NSMenu) { onOpen() }
}
