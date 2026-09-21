import AppKit
import DictationGlowCore

// A menu bar accessory: no Dock icon, no window at launch. LSUIElement in Info.plist
// says the same thing to LaunchServices; this says it to the running process.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
