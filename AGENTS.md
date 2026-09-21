# Working in this repo

A macOS menu bar utility that draws a blue band around every display while native Dictation is listening. Swift, SwiftPM, no Xcode project.

## Build and test

```
./build.sh        # builds, signs, installs to /Applications
swift test        # unit tests (pure logic only)
```

`swift test` covers `DictationGlowCore`. Everything touching `NSWindow`, `SMAppService`, or the live notification stream has no unit coverage by design — those are verified against the running system, and the gates are listed in the plan's Verification Contract.

## Verifying the overlay

**A screen capture is not evidence about the band.** It is confirmed visible on screen and absent from every capture path tried, including with the capture opt-out removed and the window level lowered. An empty screenshot is not a negative result, it is no result.

The only check that settles the overlay is looking at it:

```
/Applications/DictationGlow.app/Contents/MacOS/dictation-glow --show-band 6
```

For an agent, that means asking a person. Do not spend time chasing an empty capture — see [docs/solutions/ui-bugs/appkit-overlay-invisible-in-accessory-app.md](docs/solutions/ui-bugs/appkit-overlay-invisible-in-accessory-app.md), which is what that costs.

**`CGWindowListCopyWindowInfo` cannot tell shown from hidden here either.** It keeps listing the window after `orderOut` has run and AppKit reports `isVisible == false`.

**A capture cannot measure the display's corner either.** A rounded display photographs square: the mask is applied after the framebuffer. `--show-band` prints the radius it resolved per screen before it draws, which is as close to a machine-checkable answer as the band's shape gets. The radius comes from a private SkyLight call with a hand-derived signature that crashes if called wrong — read [docs/solutions/ui-bugs/display-corner-radius-has-no-public-api.md](docs/solutions/ui-bugs/display-corner-radius-has-no-public-api.md) before touching `DisplayCorners`.

## Animation in this app

The app is an `LSUIElement` accessory that is never the active application, so **`window.animator()` and `NSAnimationContext` do not reliably run**. There is no error; the animation is simply never performed and the property keeps its previous value. Use Core Animation on the layer, set the model value directly so the end state is correct whether or not the animation plays, and do not hang required work off a completion block. Full account: the solution doc linked above.

## Observing distributed notifications

Register with the `@objc` selector overload and `.deliverImmediately`:

```swift
center.addObserver(self, selector: #selector(receive(_:)),
                   name: ..., object: nil, suspensionBehavior: .deliverImmediately)
```

The block-based `addObserver(forName:object:queue:using:)` is inherited from `NotificationCenter`, has no `suspensionBehavior` parameter, and silently registers as `.coalesce` — which drops all but the last notification while the app is suspended. Losing the stop edge is the one failure that strands the band on screen.

Register each name explicitly. A nil-name catch-all receives every distributed notification on the system, which is a privacy surface and a standing cost for an app that idles all day.

Distributed notifications are also dropped silently under burst, so nothing may assume start and stop pair up. That is why `EdgeMachine` carries a session ceiling.

## Testing against the live system

**Kill every running instance first.** The app runs at login and `open` leaves instances behind; every one of them receives the same distributed notifications, so a stray process will answer your test and make the results incoherent.

```
pkill -f dictation-glow
```

## Install location

The app must run from `/Applications`. Only the installed copy may read or write the login-item record: reading `SMAppService.mainApp.status` repoints the record at whichever bundle performed the read, and the build script deletes the build-tree copy on the next build.

Branch on `status == .enabled`. A machine with no prior record reports `notFound`, not `notRegistered`, and the value after a user revokes consent differs between the SDK header and the field.

Never re-register a login item the user turned off. Registration happens once, on a genuine first run, gated on a persisted flag.

## Detection

How the app knows Dictation is listening, the measured latencies, what was ruled out, and what breaks it: [docs/detection.md](docs/detection.md). Read it before changing anything in `DictationMonitor` or `EdgeMachine` — the notification names are undocumented and the state machine exists for a reason that is not obvious from the code.

## Learnings

Past problems and their reasoning are filed under [docs/solutions/](docs/solutions/), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`). Check there before re-investigating something that looks like it has been hit before.

[CONCEPTS.md](CONCEPTS.md) holds the shared domain vocabulary — the words that mean something specific here, like Band, Edge and the coalescing window. Relevant when orienting to the codebase or naming things in it.
