---
title: AppKit overlay never appears because window.animator() does not run in an accessory app
date: 2026-09-21
category: ui-bugs
module: overlay
problem_type: ui_bug
component: frontend
symptoms:
  - "Overlay window reports the correct frame, level and alphaValue, and its layer holds every sublayer, but nothing is drawn on screen"
  - "The window stays ordered in after hide, because the fade-out completion that calls orderOut never fires"
  - "An empty screencapture looks like proof the overlay is broken"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [appkit, nswindow, lsuielement, core-animation, screencapture, verification]
---

# AppKit overlay never appears because window.animator() does not run in an accessory app

## Problem

A borderless overlay window in an `LSUIElement` accessory app was faded in with `NSAnimationContext.runAnimationGroup` and `window.animator().alphaValue`. The animation never ran, so the window sat ordered in at alpha 0 — on screen and invisible. The same failure hid the other half: the fade-out's completion handler, which called `orderOut`, also never fired, so the window was never taken down.

## Symptoms

- Every value AppKit reports is correct. The window is at its level across the full display frame, `alphaValue` is the target, the content view's layer exists and holds all its sublayers with the right frames and border widths.
- Nothing is drawn.
- After `hide()`, the window remains ordered in.
- A `screencapture` taken while the overlay is up contains no trace of it, which reads as confirmation that the overlay is broken.

## What Didn't Work

- **Removing the capture opt-out.** `sharingType` was switched from `.none` to `.readOnly` on the theory that the band was drawing and only being excluded from capture. The capture stayed empty.
- **Lowering the window level.** The level was dropped from `screenSaver + 1` to `.floating`, on the theory that windows at or above the shielding level are excluded from some capture paths. The capture stayed empty.
- **Creating the backing layer explicitly.** `wantsLayer = true` alone does not guarantee a layer for a view that is not yet in a window, and `addSublayer` on a nil layer is a silent no-op — a real hazard, and worth keeping ([`GlowOverlay.swift:161`](../../../Sources/DictationGlowCore/GlowOverlay.swift)), but it was not the cause here.
- **Reading `CGWindowListCopyWindowInfo`.** It keeps listing the window after `orderOut` has run and AppKit reports `isVisible == false`, so it cannot be used to tell shown from hidden for this window class.

None of these were the problem, and the capture stayed empty through all of them — because the capture was never evidence in the first place.

## Solution

Drive the fade with Core Animation on the view's own layer instead of AppKit's animator proxy, and time the order-out rather than hanging it off a completion block ([`GlowOverlay.swift:72-94`](../../../Sources/DictationGlowCore/GlowOverlay.swift)):

```swift
// Before — never runs in an accessory app
window.alphaValue = 0
window.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { context in
  context.duration = duration
  window.animator().alphaValue = bandOpacity
}

// After — the render server drives this regardless of who is active
window.alphaValue = bandOpacity
window.orderFrontRegardless()
window.contentView?.layer?.opacity = 1
let animation = CABasicAnimation(keyPath: "opacity")
animation.fromValue = from
animation.toValue = to
animation.duration = duration
layer.add(animation, forKey: "bandFade")
```

The layer's model value is set directly before the animation is added, so the end state is correct whether or not the animation plays. `CATransaction.setCompletionBlock` proved unreliable for this window too, so the order-out is a `DispatchQueue.main.asyncAfter` matched to the fade duration.

## Why This Works

AppKit's animator proxy is driven by the application's own animation machinery. An accessory app that is never the active application does not reliably run it, and there is no error — the animation is simply never performed, leaving the property at whatever it was set to before. Setting `alphaValue = 0` first and relying on the animator to raise it is therefore a design that fails closed into invisibility.

A `CABasicAnimation` added to a layer is committed to the render server, which animates it independently of application activation state.

## Prevention

- **In an app that is never frontmost, do not rely on `window.animator()` or `NSAnimationContext` for anything whose end state matters.** Set the model value directly and use Core Animation for the transition, so a fade that does not play still leaves the correct final state.
- **Never treat a screen capture as evidence about an overlay window.** This one is confirmed visible on screen and absent from every capture path tried. An empty capture is not a negative result; it is no result. The only check that settles an overlay is looking at the screen, and for a long-running agent that means asking a person.
- **A verification that cannot fail is not a verification.** The original check for this overlay was "the window exists in `CGWindowListCopyWindowInfo`" plus "it does not appear in a screenshot". Both passed while the band was invisible, because neither observes drawing. Before recording a check as proof, ask what result would have falsified it.

## Related Issues

- Built and merged in [#1](https://github.com/raineorshine/dictation-glow/pull/1).
- [`docs/detection.md`](../../detection.md) carries the standing warning about screenshot verification, next to the detection mechanism it applies to.
