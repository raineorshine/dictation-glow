---
title: AppKit overlay never appears because window.animator() does not run in an accessory app
date: 2026-09-21
last_updated: 2026-09-21
category: ui-bugs
module: overlay
problem_type: ui_bug
component: frontend
symptoms:
  - "Overlay window reports the correct frame, level and alphaValue, and its layer holds every sublayer, but nothing is drawn on screen"
  - "The window stays ordered in after hide, because the fade-out completion that calls orderOut never fires"
  - "An empty screencapture looks like proof the overlay is broken"
  - "CGWindowListCopyWindowInfo keeps listing the window after orderOut and after AppKit reports isVisible == false"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [appkit, nswindow, lsuielement, core-animation, screencapture, verification]
---

# AppKit overlay never appears because window.animator() does not run in an accessory app

## Problem

`GlowOverlay` draws a borderless band around every display in a menu-bar-only (`LSUIElement`) app that is never the active application. The band never appeared on screen, and — as a second symptom of the same root cause — the window never came back down after `hide()`.

## Symptoms

- Every `NSWindow` value checked was correct: the frame covered the full display, `level` was `screenSaver + 1`, `alphaValue` reached its target, and `contentView?.layer` held all 17 sublayers (one 4pt edge plus 16 falloff rings, built in `BandView.build(on:)`, `GlowOverlay.swift:176-191`) at the right frames and border widths.
- Nothing was drawn.
- After `hide()`, the window stayed ordered in.
- `screencapture`, taken while the band was on screen, showed no trace of it — and kept showing no trace of it through three unrelated changes, which is what made the capture look authoritative.

## What Didn't Work

Each of these targeted a real hypothesis about why a correctly-configured window might be excluded from capture. None was unreasonable to try. The mistake was continuing to trust the capture as the falsifying test after each one failed to change its output.

1. **Removing the capture opt-out.** `sharingType` was `.none` (`GlowOverlay.swift:144`), documented as excluding a window from the legacy capture path. Switched to `.readOnly`; the capture stayed empty. This did surface a separate correction now recorded at `GlowOverlay.swift:139-144` and in `docs/detection.md`: since macOS 15.4 a window marked `.none` is still captured by ScreenCaptureKit, and Apple states no public API prevents capture. `.none` is kept, but it is not capture protection.
2. **Lowering the window level.** Dropped from `screenSaver + 1` to `.floating`, on the theory that windows at or above the shielding level are excluded from some capture paths. The capture stayed empty. Restored to `screenSaver + 1` (`GlowOverlay.swift:137`), which is required anyway so a full-screen app cannot cover the band.
3. **Creating the backing layer explicitly.** The theory: `wantsLayer = true` was set before the view was in a window, the layer never materialized, and every `addSublayer` was a silent no-op against `nil`. That is a real AppKit hazard and the guard is kept — the layer is constructed and assigned directly at `GlowOverlay.swift:161-162` rather than relying on lazy creation. But the layer and its 17 sublayers were already present and correctly framed before the change, so it was not the cause.
4. **Reading `CGWindowListCopyWindowInfo` as a visibility oracle.** It kept listing the window after `orderOut(nil)` had run and `NSWindow.isVisible` already reported `false`. The window-server list and AppKit's notion of visibility diverge at exactly the moment that matters, so this cannot distinguish shown from hidden for this window class.

A fifth issue compounded the confusion: earlier `open` launches had left orphaned app instances running, all subscribed to the same distributed notifications and all reacting to the same test sessions. Not a cause, but it made readings incoherent for a stretch. Rule it out first in any repeat — `pkill -f dictation-glow` before a manual run.

None of the four moved the capture, because the band was rendering correctly the whole time. Its absence from `screencapture` and from `CGWindowListCopyWindowInfo` is a property of those tools against this window, not of the window.

## Solution

The fade was driven by the animator proxy, with `alphaValue` set to `0` first and the animator relied on to raise it:

```swift
// Before — animator proxy, never runs in this app
window.alphaValue = 0
window.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { context in
  context.duration = duration
  window.animator().alphaValue = bandOpacity
}
```

The fix moves the animation onto the content view's own `CALayer` and sets the model value directly before adding the animation — `show()` at `GlowOverlay.swift:41-52`, `hide()` at `:59-70`, `fade()` at `:72-95`:

```swift
// show(), GlowOverlay.swift:41-52
window.alphaValue = Timing.bandOpacity
window.orderFrontRegardless()
window.contentView?.layer?.opacity = 1
fade(window, from: 0, to: 1, duration: duration)

// fade(), GlowOverlay.swift:72-95
CATransaction.begin()
let animation = CABasicAnimation(keyPath: "opacity")
animation.fromValue = from
animation.toValue = to
animation.duration = duration
layer.add(animation, forKey: "bandFade")
CATransaction.commit()
if let completion {
  DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
}
```

Two details matter beyond "use Core Animation instead of the animator":

- **The model values are set to their end state before the animation is added** — `bandOpacity` and `opacity = 1` on show (`GlowOverlay.swift:47,49`), `opacity = 0` on hide (`:64`). A `CABasicAnimation` animates a presentation value over the model value and is removed on completion, reverting to the model. Leaving the model at the wrong end state means any skipped or dropped animation reverts to invisible. Setting it directly makes the correct end state unconditional on the animation running at all.
- **The order-out is timed, and guarded against a race.** `DispatchQueue.main.asyncAfter` at `GlowOverlay.swift:93` replaces `CATransaction.setCompletionBlock`, which also proved unreliable here (`GlowOverlay.swift:88-91`). But a timed side effect can outlive the instruction that scheduled it, so `hide()` captures a generation token (`:62`) and the completion re-checks `!self.visible && self.generation == issued` (`:66`) before calling `orderOut`. Without that, a `show()` landing inside a fade-out's duration would be undone by the previous hide's stale timer. The counter is bumped on every show (`:44`).

## Why This Works

Per this session's conclusion — AppKit's internal animation scheduling was not itself inspected — `NSAnimationContext` and `window.animator()` are driven by the application's own animation machinery, which is tied to the app participating in the active UI update cycle. An accessory app that is never the active application does not reliably get scheduled into it. No error is raised; the animation is simply never performed and the property keeps whatever it was set to immediately before. `show()` set `alphaValue = 0` and depended on the animator to raise it, so the design failed closed: the code path most likely to be skipped carried the entire visible effect.

A `CABasicAnimation` committed through `CATransaction` goes to the render server, which runs independently of the owning app's activation state. That is why moving the animation off the window's animator proxy and onto the view's layer fixes both symptoms at once.

## Prevention

- **In an app that is never frontmost, do not drive any property whose end state matters through `window.animator()` or `NSAnimationContext`.** Set the value directly for the guaranteed end state and use a `CATransaction`-committed animation purely for the transition. Treat an animator-driven fade in such an app as a latent invisibility bug even when it appeared to work in manual testing, where a debug process can end up frontmost and mask it.
- **Do not hang anything whose absence leaves a stuck window off `CATransaction.setCompletionBlock`.** Time it against the animation's known duration, and guard it with a generation token if a newer instruction can arrive before the timer fires.
- **Never treat `screencapture` or `CGWindowListCopyWindowInfo` as evidence about whether an overlay is drawing.** Both were checked here and both were wrong in opposite directions. An empty or stale reading from either is not a negative result; it is not a result.
- **Before recording a check as verified, name the input that would have made it fail.** The original check was "the window appears in `CGWindowListCopyWindowInfo`" plus "it does not appear in a screenshot". Both passed continuously while the band was invisible, because neither observes drawing. A check that would pass regardless of the bug is not a regression guard.
- **The real verification already ships in the repo.** `dictation-glow --show-band <seconds>` (`Sources/dictation-glow/main.swift:60`) puts the band against the real window server for a fixed duration and exits. Running it and having a person look at the screen is the check; a capture of the same moment is not.

## How this fix was confirmed

A person ran `--show-band` and reported the band visible. That is the only check that settled it — three capture-based approaches had already failed to distinguish a working overlay from a broken one. For an autonomous agent this means the verification step is "ask someone to look", and that should be planned for rather than discovered after a long investigation.

## Related Issues

- Fixed and merged in [PR #1](https://github.com/raineorshine/dictation-glow/pull/1).
- [`docs/detection.md`](../../detection.md) — its "Verifying the overlay" section carries the same warning and command, beside the detection mechanism the band is driven by.
- `AGENTS.md` restates these findings in its "Verifying the overlay" and "Animation in this app" sections. Update both together.
