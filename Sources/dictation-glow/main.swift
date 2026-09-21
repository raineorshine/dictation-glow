import AppKit
import DictationGlowCore

// A menu bar accessory: no Dock icon, no window at launch. LSUIElement in Info.plist says
// the same thing to LaunchServices; this says it to the running process.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let arguments = Array(CommandLine.arguments.dropFirst())

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

// Says what corner the window server reported, per screen. The corner is the one thing
// about the band a run can state rather than having to be looked at, and a band drawn square
// on a rounded display and one drawn on a display that reports nothing look the same from
// the outside.
func reportCorners() {
  for (index, screen) in NSScreen.screens.enumerated() {
    let display = GlowOverlay.display(for: screen)
    let corner =
      display.cornerRadius > 0
      ? String(format: "%.2fpt corner", Double(display.cornerRadius)) : "square corner"
    print("screen \(index): \(corner)")
  }
}

func describe(_ profile: BandGeometry.Profile) -> String {
  let rim =
    profile.rimWidth > 0
    ? String(format: "%.0fpt rim at %.0f%%", Double(profile.rimWidth), Double(profile.rimAlpha * 100))
    : "no rim"
  return String(
    format: "%@: %@, %.0fpt glow from %.0f%%, falloff %.1f",
    profile.name, rim, Double(profile.depth), Double(profile.peakAlpha * 100),
    Double(profile.falloff))
}

// Shows the band for a few seconds and exits. Not a feature -- it is how the overlay is
// checked against a real window server, which no unit test can do.
if arguments.first == "--show-band" {
  let rest = Array(arguments.dropFirst())
  let seconds = Double(rest.first ?? "") ?? 3
  let named = rest.first(where: { Double($0) == nil })
  guard let profile = named.map({ BandGeometry.variant(named: $0) }) ?? BandGeometry.defaultProfile
  else {
    let names = BandGeometry.variants.map(\.name).joined(separator: ", ")
    FileHandle.standardError.write("no such band: \(named ?? "") -- try one of: \(names)\n".data(using: .utf8)!)
    exit(2)
  }
  reportCorners()
  print(describe(profile))
  let overlay = GlowOverlay(profile: profile)
  overlay.show()
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    overlay.hide()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
  }
  application.run()
} else if arguments.first == "--compare-bands" {
  // Every variant in turn, on the same desktop, each named as it comes up. One at a time and
  // not side by side: the band is the whole perimeter of a screen, so two of them at once is
  // a picture of neither.
  let seconds = Double(arguments.dropFirst().first ?? "") ?? 5
  reportCorners()
  let overlay = GlowOverlay(profile: BandGeometry.variants[0])
  var remaining = BandGeometry.variants
  func showNext() {
    guard !remaining.isEmpty else {
      overlay.hide()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
      return
    }
    let profile = remaining.removeFirst()
    print(describe(profile))
    overlay.profile = profile
    overlay.show()
    // A gap between them, with the band down, so the eye is not comparing the second against
    // an afterimage of the first.
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
      overlay.hide()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: showNext)
    }
  }
  showNext()
  application.run()
} else {
  let delegate = AppDelegate()
  delegate.tracing = arguments.contains("--trace")
  application.delegate = delegate
  application.run()
}
