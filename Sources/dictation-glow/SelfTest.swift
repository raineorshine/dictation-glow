import AppKit
import DictationGlowCore

/// Runs the guided live test against the app's own detector.
///
/// Subscribes to the same machine the overlay uses rather than observing separately: a test
/// with its own path could pass while the live one is broken, which is the failure it exists
/// to catch.
final class SelfTestRunner {
  private var session: SelfTestSession?
  private var timeout: DispatchWorkItem?
  private var panel: NSAlert?

  /// How long to wait for the person to start and finish a short dictation. Long enough to
  /// find the shortcut and say a few words.
  private static let window: TimeInterval = 60

  /// Fed by the app's state changes, whether or not a test is running.
  func observe(_ state: EdgeMachine.State) {
    guard let session else { return }
    session.observe(state)
    // A completed cycle ends the test immediately rather than waiting out the window.
    if case .idle = state {
      finish(timedOut: false)
    }
  }

  func run(currentState: EdgeMachine.State) {
    guard session == nil else { return }
    guard SelfTestSession.mayStart(currentState: currentState) else {
      present(
        title: "Dictation is already running",
        text: "Stop the current dictation session, then run the test again. Starting now "
          + "would measure that session rather than this test.",
        style: .warning)
      return
    }

    session = SelfTestSession()
    let item = DispatchWorkItem { [weak self] in self?.finish(timedOut: true) }
    timeout = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.window, execute: item)

    // There is no supported way to start Dictation programmatically, so the person does it.
    let alert = Self.makeAlert(
      title: "Start dictation now",
      text: """
        Press your Dictation shortcut, say a few words, then stop. This window closes by \
        itself once a full session has been seen, or after a minute.
        """)
    alert.addButton(withTitle: "Cancel")
    panel = alert
    if alert.runModal() == .alertFirstButtonReturn {
      cancel()
    }
  }

  private func cancel() {
    timeout?.cancel()
    timeout = nil
    session = nil
    panel = nil
  }

  private func finish(timedOut: Bool) {
    guard let session else { return }
    timeout?.cancel()
    timeout = nil
    self.session = nil
    let result = session.resolve(timedOut: timedOut)

    // The prompt's runModal() is still on the stack: a nested modal run loop keeps servicing
    // the notifications that got us here, so the alert would sit there until clicked even
    // though the result is already known.
    if panel != nil {
      panel = nil
      NSApp.abortModal()
    }

    DispatchQueue.main.async {
      self.present(
        title: {
          switch result.outcome {
          case .passed: return "Detection is working"
          case .partial: return "Detection is partly working"
          case .failed: return "Detection is not working"
          }
        }(),
        text: result.summary,
        style: result.outcome == .passed ? .informational : .critical)
    }
  }

  private func present(title: String, text: String, style: NSAlert.Style) {
    let alert = Self.makeAlert(title: title, text: text)
    alert.alertStyle = style
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  /// The app is never frontmost, so every alert has to ask for the foreground before it can
  /// be seen. Callers add their own buttons.
  private static func makeAlert(title: String, text: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    NSApp.activate(ignoringOtherApps: true)
    return alert
  }
}
