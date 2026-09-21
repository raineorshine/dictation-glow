# dictation-glow

A macOS menu bar utility that draws a blue glow around the perimeter of every screen for as long as Apple's native Dictation is listening.

It does not replace Dictation. It detects that Dictation is active and says so, loudly enough that you cannot miss it in peripheral vision.

## The problem

Native Dictation stops on its own after a stretch of silence. Nothing announces the cut. You keep talking into a microphone that is no longer listening and find out when you look back at the screen.

The overlay exists so the transition is visible without looking. Blue border means Dictation is live. No border means it is not.

## Status

Pre-implementation. The overlay design is settled; the detection architecture is not.

The central unresolved question is how a third-party process determines, with low latency and high confidence, that native Dictation is currently active. The candidate signals — Accessibility observation of the Dictation UI, microphone stream state, dictation-related system processes, distributed notifications, window server inspection — are candidates, not verified signals. The first thing built is a diagnostic harness that logs all of them before, during, and after real Dictation sessions. The production architecture is chosen from what that harness records.

See [HANDOFF.md](HANDOFF.md) for the full brief.

## Design decisions

**The border is binary.** Full strength while Dictation is live, a plain fade in and out at the edges. It does not attempt to show the silence timer running down, because that would require a live speech-activity signal and the timeout is already made visible by the border disappearing.

**Attribution fails closed.** The microphone being live is not the same as Dictation being live — a call, a recording, or a third-party dictation tool reads identically. The border is drawn only when Dictation is positively confirmed.

That choice has a cost worth stating outright: a broken detector and an idle Dictation look the same. So the app carries a self-test and a record of the last successfully attributed session. The absence of a border has to be falsifiable, or the failure mode becomes the one this utility was built to fix.

**Simultaneous microphone use rules out the cheap architecture.** `kAudioDevicePropertyDeviceIsRunningSomewhere` is public, listenable, and needs no permission, but it cannot be the authority on the off edge: if another application holds the microphone while Dictation times out, the property never flips. The confirming signal has to carry both edges on its own.

## Overlay

The perimeter band is taken from [axshot](https://github.com/raineorshine/axshot)'s drive frame: a solid band on each screen's own edge, with the inward falloff drawn as concentric rings rather than as a blur. One frame per screen rather than one around the bounding box, so two displays of different heights do not leave a band running through dead space.

The window is non-activating, ignores mouse events, joins all Spaces, is stationary, sits above full screen windows, and excludes itself from screen capture so it does not appear in anyone's screenshots.

## Permissions

Code signing and permission provisioning follow axshot. An ad-hoc signature's code hash changes on every build and TCC pins grants to that hash, so each rebuild reads as a stranger and Accessibility has to be granted again. A stable self-signed certificate gives a fixed Designated Requirement and the grants survive. This matters more here than usual, since the harness phase means rebuilding constantly.

The app also re-spawns itself with responsibility disclaimed, so TCC attributes the grant to the app rather than to whatever launched it.

## Requirements

macOS 26 or later. Built and tested on 26.6.2.
