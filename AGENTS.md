# Working in this repo

A macOS menu bar utility that draws a blue band around every display while native Dictation is listening. Swift, SwiftPM, no Xcode project.

## Build and test

```
./build.sh        # builds, signs, installs to /Applications
swift test        # unit tests (pure logic only)
node scripts/check-doc-citations.mjs   # the docs' citations
```

`swift test` covers `DictationGlowCore`. Everything touching `NSWindow`, `SMAppService`, or the live notification stream has no unit coverage by design — those are verified against the running system, and the gates are listed in the plan's Verification Contract.

## Verifying the overlay

**A screen capture is not evidence about the band.** It is confirmed visible on screen and absent from every capture path tried, including with the capture opt-out removed and the window level lowered. An empty screenshot is not a negative result, it is no result.

The only check that settles what the band *draws* is looking at it:

```
/Applications/DictationGlow.app/Contents/MacOS/dictation-glow --show-band 6
```

For an agent, that means asking a person. Do not spend time chasing an empty capture — see [docs/solutions/ui-bugs/appkit-overlay-invisible-in-accessory-app.md](docs/solutions/ui-bugs/appkit-overlay-invisible-in-accessory-app.md), which is what that costs.

**What the window *is*, as against what it draws, does not need a person.** A throwaway binary that links `.build/release/DictationGlowCore.o` reaches the live overlay through `NSApp.windows` — the band's are the windows at `screenSaver + 1` — so a window-server property can be driven and read against the shipped `GlowOverlay` instead of against a copy of it pasted into a harness. That is the difference between proving the fix and proving a reimplementation of it.

**`CGWindowListCopyWindowInfo` cannot tell shown from hidden here either.** It keeps listing the window after `orderOut` has run and AppKit reports `isVisible == false`.

**Which Spaces the band is on is measurable, and `collectionBehavior` is not the measurement.** It keeps the value it was set to while the window server's registration goes stale underneath it, which is how the band ends up on one Space with every value in the app reading correct. `CGSCopySpacesForWindows` says what the server actually thinks — see [docs/solutions/ui-bugs/canjoinallspaces-registration-goes-stale.md](docs/solutions/ui-bugs/canjoinallspaces-registration-goes-stale.md) for the call and the repair.

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

**Kill every running instance first — after you have taken what the old one knows.** The app runs at login and `open` leaves instances behind; every one of them receives the same distributed notifications, so a stray process will answer your test and make the results incoherent.

```
pkill -f dictation-glow
```

But it also runs for days, and a fault that needs a long-lived process lives nowhere else. A copy launched to reproduce it is a different subject and can be healthy while the one the user is complaining about is not — which reads as the bug not existing, and is the strongest evidence there is that the fault is in accumulated state rather than in the code. Measure the running process before killing it, and compare it against a fresh one rather than replacing it with one.

## Install location

The app must run from `/Applications`. Only the installed copy may read or write the login-item record: reading `SMAppService.mainApp.status` repoints the record at whichever bundle performed the read, and the build script deletes the build-tree copy on the next build.

Branch on `status == .enabled`. A machine with no prior record reports `notFound`, not `notRegistered`, and the value after a user revokes consent differs between the SDK header and the field.

Never re-register a login item the user turned off. Registration happens once, on a genuine first run, gated on a persisted flag.

## Detection

How the app knows Dictation is listening, the measured latencies, what was ruled out, and what breaks it: [docs/detection.md](docs/detection.md). Read it before changing anything in `DictationMonitor` or `EdgeMachine` — the notification names are undocumented and the state machine exists for a reason that is not obvious from the code.

## Shipping

[`ship`](.claude/skills/ship/SKILL.md) lands a change on `origin/main`: gates, the writing the change
owes, rebase, squash, push, then install and *relaunch* — the accessory launched at login keeps the
old binary until it is restarted. Squash to one commit and push; no PR, no merge commits. It runs
only when the user asks for it.

## Learnings

Past problems and their reasoning are filed under [docs/solutions/](docs/solutions/), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`). Check there before re-investigating something that looks like it has been hit before.

**A doc claims as little about the present tree as its point allows, and never a line number.** A `:NN` resolves forever and drifts silently: the reader who checks it lands on whatever moved into that position and reads it as confirmation, which is worse than a dangling reference. Every line number in this repo's solution docs had drifted by the time the rule was written — the citation for `BandView.build(on:)` pointed 70 lines short of it, and the one for `sharingType` at a line in a different function. Name the symbol instead; it moves with the thing it names. `scripts/check-doc-citations.mjs` is a gate over `docs/**`: it bans the form and checks that every cited path and doc link resolves, at the repo root or under a source root, with the files in sibling repos listed as foreign because nothing here can keep them in step. **What no gate can check is whether the prose still describes the code**, which is why an episode is written in the past tense about the tree it happened on: a measurement keeps its figures and says what they measured, and a mechanism that has since been replaced is marked and linked forward rather than rewritten, or the record of why the fix made sense goes with it. Ported from github-triage, which runs the same check from `npm run lint`.

[CONCEPTS.md](CONCEPTS.md) holds the shared domain vocabulary — the words that mean something specific here, like Band, Edge and the coalescing window. Relevant when orienting to the codebase or naming things in it.
