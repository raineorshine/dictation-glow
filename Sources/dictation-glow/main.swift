import AppKit
import DictationGlowCore

// A menu bar accessory: no Dock icon, no window at launch. LSUIElement in Info.plist says
// the same thing to LaunchServices; this says it to the running process.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let arguments = Array(CommandLine.arguments.dropFirst())

// Shows the band for a few seconds and exits. Not a feature -- it is how the overlay is
// checked against a real window server, which no unit test can do.
if arguments.first == "--show-band" {
  let seconds = Double(arguments.dropFirst().first ?? "") ?? 3
  let overlay = GlowOverlay()
  overlay.show()
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    overlay.hide()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
  }
  application.run()
} else {
  let delegate = AppDelegate()
  delegate.tracing = arguments.contains("--trace")
  application.delegate = delegate
  application.run()
}
