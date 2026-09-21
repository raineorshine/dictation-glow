# dictation-glow

A macOS menu bar utility that draws a blue glow around the perimeter of every screen for as long as Apple's native Dictation is listening.

It does not replace Dictation. It detects that Dictation is active and says so, loudly enough that you cannot miss it in peripheral vision.

## The problem

Native Dictation stops on its own after a stretch of silence. Nothing announces the cut. You keep talking into a microphone that is no longer listening and find out when you look back at the screen.

The overlay exists so the transition is visible without looking. Blue border means Dictation is live. No border means it is not.

## Status

Working. The overlay, the detector, the menu bar, the login item, the event log, and the self-test are all built and verified.

Detection is confirmed against every start path and against a session sharing the microphone with another application. See [docs/detection.md](docs/detection.md).

## Design decisions

**The border is binary.** Full strength while Dictation is live, a plain fade in and out at the edges. It does not attempt to show the silence timer running down, because that would require a live speech-activity signal and the timeout is already made visible by the border disappearing.

**Attribution fails closed.** The microphone being live is not the same as Dictation being live — a call, a recording, or a third-party dictation tool reads identically. The border is drawn only when Dictation is positively confirmed.

That choice has a cost worth stating outright: a broken detector and an idle Dictation look the same. So the app carries a self-test and a record of the last successfully attributed session. The absence of a border has to be falsifiable, or the failure mode becomes the one this utility was built to fix.

**Detection reads no audio at all.** `DictationIM` posts its own notifications, so the app never has to work out who holds the microphone. That makes the concurrent-microphone case a non-issue by construction rather than something to engineer around, and it is why the app needs no permissions. See [docs/detection.md](docs/detection.md) for what was ruled out along the way.

## Overlay

The perimeter band is taken from [axshot](https://github.com/raineorshine/axshot)'s drive frame: a solid band on each screen's own edge, with the inward falloff drawn as concentric rings rather than as a blur. One frame per screen rather than one around the bounding box, so two displays of different heights do not leave a band running through dead space.

The window is non-activating, ignores mouse events, joins all Spaces, is stationary, and sits above full screen windows. It opts out of screen capture, which keeps it out of ordinary screenshots but not out of screen recordings: since macOS 15.4 that opt-out no longer applies to ScreenCaptureKit, and Apple says no public API prevents capture.

## Permissions

None. Not Accessibility, not Screen Recording, not Microphone.

The notifications are delivered by `distnoted` to any process that asks for them by name, the overlay needs no grant, and registering as a login item needs no grant. The app asks for nothing.

It is still signed with a stable self-signed certificate rather than ad-hoc, because the login-item record is tied to the signed identity: an ad-hoc signature changes on every build, and the registration would have to be approved again each time. Run `./create-signing-cert.sh` once; `build.sh` calls it for you.

## Requirements

macOS 14 or later to build; developed and verified on macOS 26.6.2 with Swift 6.4.

```
./build.sh
```

Builds, signs, and installs to `/Applications`. Run `swift test` for the unit tests.
