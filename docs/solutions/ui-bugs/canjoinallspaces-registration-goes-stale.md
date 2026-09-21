---
title: canJoinAllSpaces goes stale on a long-lived window, so the band shows on one Space only
date: 2026-09-21
last_updated: 2026-09-21
category: ui-bugs
module: overlay
problem_type: ui_bug
component: frontend
symptoms:
  - "The band appears on the Space it was last shown on and nowhere else, while the app has been running for hours"
  - "collectionBehavior still reads .canJoinAllSpaces from inside the process, so nothing in the app can tell the registration is stale"
  - "A freshly launched copy of the identical binary shows the band on every Space, which makes the bug look unreproducible"
root_cause: stale_state
resolution_type: code_fix
severity: high
tags: [appkit, nswindow, spaces, collectionbehavior, window-server, cgs]
---

# canJoinAllSpaces goes stale on a long-lived window, so the band shows on one Space only

## Problem

The overlay window is created once and kept for the life of the process, ordered in on `show()`
and out on `hide()`. Its `collectionBehavior` includes `.canJoinAllSpaces` from birth. After the
app has been running a while, the band stops appearing on every Space and appears only on the one
it was last shown on.

## Symptoms

- The band is drawn correctly on one Space and is simply absent on the others.
- `window.collectionBehavior` read from inside the process still contains `.canJoinAllSpaces`.
  The app's own state is right; only the window server's registration is wrong.
- Relaunching the app fixes it, which is what makes this look like it never happened.

## Measuring it

AppKit exposes no way to ask which Spaces a window is actually registered on, so the app cannot
see this and neither can a screenshot. The window server will say, through two private CoreGraphics
calls that are safe to read from a throwaway diagnostic:

```swift
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray?

let spaces = CGSCopySpacesForWindows(
  CGSMainConnectionID(), 7, [NSNumber(value: UInt32(window.windowNumber))] as CFArray) as? [Int]
```

`CGSCopyManagedDisplaySpaces` lists every Space the server knows about, per display, with its
`ManagedSpaceID` and its `type` (`0` is a user desktop, `4` is full-screen). Together they turn
"the band is missing over there" into a number that can be compared between two processes.

That comparison is what identified this. On a two-Space desktop, the band window of an app that
had been up for six hours reported membership in the current Space alone; a window created minutes
earlier from the same binary, in the same app mode, reported both. Identical code, opposite
results — so the bug is in the registration, not in the configuration.

## Root cause

A window's Space membership is decided when the window server registers it and is not
re-evaluated afterwards. `.canJoinAllSpaces` means "all the Spaces there are now", not a standing
subscription, so a Space that comes into existence later does not get the window. The property on
the `NSWindow` keeps its original value either way, which is why the app cannot detect the drift
and why every value an agent is likely to check reads as correct.

## Fix

Say it again on every rebuild, which is every `show()` and every screen-parameters change
(`GlowOverlay.rebuild()`). The assignment is cleared first so it is a change rather than a
possible no-op — a setter that short-circuits on an equal value would never reach the window
server, which is the only place the stale registration lives.

```swift
private static func assertAllSpaces(on window: NSWindow) {
  window.collectionBehavior = []
  window.collectionBehavior = allSpaces
}
```

Measured on a healthy window: it keeps every Space it had, stays ordered in, and does not blink.
Measured on a drifted one: membership is restored immediately, whether the window is ordered in at
the time or not.

## Verification

Reaching the overlay's private windows is possible from a harness that links `DictationGlowCore`,
because they are in `NSApp.windows` and are the only ones at `screenSaver + 1`. Show the band,
drift the window by hand, trigger a rebuild, and read the Space list at each step:

```
1. after show():                          spaces=[1, 3] behavior=273
2. drifted by hand:                       spaces=[3]    behavior=272
3. after rebuild via profile change:      spaces=[1, 3] behavior=273
```

That exercises the shipped `rebuild()` rather than a copy of it, and it is the only check here
that a unit test cannot stand in for: there is no Space, and no window server, under `swift test`.

## What this is not

- **Not a wrong collection behavior.** `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
  was correct all along, and a window built with it lands on every Space every time.
- **Not order-out related.** Ordering a healthy window out and back in, with or without a
  `setFrame` in between, does not cost it a Space.
- **Not the window level.** `screenSaver + 1` is below `CGShieldingWindowLevel()` and plays no
  part in Space membership.
