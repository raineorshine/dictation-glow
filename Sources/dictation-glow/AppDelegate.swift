import AppKit
import DictationGlowCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let overlay = GlowOverlay()
  private let monitor = DictationMonitor()
  private let machine = EdgeMachine()
  private lazy var policy = VisibilityPolicy(band: overlay)
  private var menuBar: MenuBar?
  private let log = EventLog(directory: EventLog.defaultDirectory())

  /// Prints each state change, so the wiring can be checked against real notifications
  /// without a menu bar to look at.
  var tracing = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    machine.onChange = { [weak self] state in
      guard let self else { return }
      self.policy.apply(state)
      self.log.noteStateChange(state)
      if self.tracing {
        print("state=\(state) at \(Date().timeIntervalSince1970)")
        fflush(stdout)
      }
    }
    monitor.onEvent = { [weak self] event, when in
      guard let self else { return }
      self.log.record(event, at: when)
      if self.tracing {
        print("event=\(event.rawValue) at \(when.timeIntervalSince1970)")
        fflush(stdout)
      }
      self.machine.handle(event)
    }
    monitor.start()

    let bar = MenuBar()
    bar.lastConfirmedDescription = { [weak self] in
      self?.log.lastConfirmedDescription() ?? "No dictation session seen yet"
    }
    menuBar = bar
    LoginItem.registerOnFirstRunIfNeeded()
  }
}
