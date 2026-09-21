---
title: A display's corner radius has no public API, and a screenshot cannot measure it
date: 2026-09-21
category: ui-bugs
module: overlay
problem_type: ui_bug
component: frontend
symptoms:
  - "A square band on a rounded display is cut at each corner by the panel, breaking the band where the eye follows it around"
  - "No AppKit or Core Graphics call reports how the system rounds a display"
  - "A screen capture of a rounded display comes back with square corners, so the curve cannot be measured off a photograph"
root_cause: missing_api
resolution_type: code_fix
severity: medium
tags: [skylight, spi, nsscreen, calayer, corner-radius, disassembly, verification]
---

# A display's corner radius has no public API, and a screenshot cannot measure it

## Problem

The band is drawn on each screen's own boundary. On a display whose corners are rounded, a
square band runs past the curve at each corner and is cut there, so the band breaks at the
four places the eye follows it around. Matching the curve needs the display's corner radius,
and nothing public reports it.

## What does not work

- **`NSScreen`** has no corner property. `safeAreaInsets` describes the notch and the menu
  bar, not the curve.
- **A full-screen window.** `-[NSWindow _shouldMatchScreenCorners]` returns true for one, but
  `_cornerRadius`, `_cornerRadii` and `_effectiveCornerRadii` all read zero: the rounding is
  applied by the window server, not by a radius AppKit holds.
- **Measuring it off a capture.** A `screencapture` of a rounded display comes back with
  square corners and desktop content all the way into them. The mask is applied downstream of
  the framebuffer, so the curve is not in the picture — the same class of mistake as reading
  an empty screenshot as proof the overlay is broken.
- **SwiftUI** carries an `EnvironmentValues.displayCornerRadius`, but it is internal.

## What works

`SLSDisplayGetCornerRadii` in SkyLight, bound weakly at runtime. The header is private, so
the signature was taken from the instruction stream:

```
CGError SLSDisplayGetCornerRadii(CGDirectDisplayID display,
                                 double *first, double *second,
                                 double *third, double *fourth)
```

The display id arrives in `x0` and four out pointers in `x1`–`x4`. Each is written only if
non-null, and the return is `kCGErrorFailure` for a display id the window server does not
know. **Passing fewer than four pointers crashes**: the function stores through whatever the
argument registers happen to hold, which is what a one-pointer guess at the signature does.

The values are in points of the display's *current mode*, not in pixels, so they change with
the scaled resolution and have to be read again on every screen-parameters change rather than
cached once.

On a 13-inch MacBook Air (M3, notched, built-in panel, 1470 × 956 pt mode) it answers
`0, 0, 20.3528, 20.3499`.

## Which argument is which corner

Not recoverable from the instruction stream, and it does not matter: `BandGeometry` takes the
largest of the four and draws every corner to it. A panel that rounds one corner rounds all
four symmetrically, and where the system leaves a corner unmasked the hardware still cuts it,
so the same radius is right either way round. A display that reports nothing rounded — every
external monitor — comes back all zeros and keeps the square corner the band has always drawn.

## Drawing it

macOS rounds with a *continuous* corner — a squircle, fuller through the diagonal than a
circle of the same radius — which no `NSBezierPath` draws. `CALayer.cornerCurve = .continuous`
is that curve, and a layer is the only thing that offers it. This is the second reason the
band is layers rather than a drawn path; the first is that the inward falloff is concentric
rings, each of which is the same curve again at `radius - inset`, clamped at zero where the
inset runs past the radius and the corner is square again.

## Verification

Looking at it is the only check, as with everything else about the band:

```
/Applications/DictationGlow.app/Contents/MacOS/dictation-glow --show-band 6
```

`--show-band` prints the radius it resolved per screen before it draws, so a band drawn
square on a rounded display can be told apart from one drawn on a display that reported
nothing.
