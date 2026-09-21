import AppKit
import DictationGlowCore

// A menu bar accessory: no Dock icon, no window at launch. LSUIElement in Info.plist says
// the same thing to LaunchServices; this says it to the running process.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let arguments = Array(CommandLine.arguments.dropFirst())

// Shows the band for a few seconds and exits. Not a feature -- it is how the overlay is
// checked against a real window server, which no unit test can do.
if arguments.first == "--login-status" {
  // Says what the login-item record actually holds. Reading status repoints that record at
  // whichever copy reads it, so this refuses to run from anywhere but the installed app.
  print("bundle=\(Bundle.main.bundlePath)")
  print("installedLocation=\(LoginItem.isInstalledLocation)")
  if LoginItem.isInstalledLocation {
    print("status=\(LoginItem.status)")
  } else {
    print("status=not read: refusing to repoint the record from a non-installed copy")
  }
  exit(0)
}

if arguments.first == "--self-test" {
  // The same session object the menu's test uses, without the modal. This is how the test
  // itself is verified, including its failure path.
  let seconds = Double(arguments.dropFirst().first ?? "") ?? 20
  // --broken points the monitor at a name nothing posts, to prove a dead detector is
  // reported as dead rather than as an idle system.
  let broken = arguments.contains("--broken")
  let monitor = broken ? DictationMonitor(names: ["DictationGlowNotificationThatNeverFires"])
                       : DictationMonitor()
  let machine = EdgeMachine()
  let session = SelfTestSession()
  var settled = false
  machine.onChange = { state in
    session.observe(state)
    if state == .idle, !settled {
      settled = true
      let result = session.resolve(timedOut: false)
      print("outcome=\(result.outcome)")
      print(result.summary)
      exit(result.outcome == .passed ? 0 : 1)
    }
  }
  monitor.onEvent = { event, _ in machine.handle(event) }
  monitor.start()
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    guard !settled else { return }
    let result = session.resolve(timedOut: true)
    print("outcome=\(result.outcome)")
    print(result.summary)
    exit(1)
  }
  application.run()
}

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
