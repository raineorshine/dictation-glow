# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Detection

### Confirming signal
The system notification that identifies native Dictation specifically, by name, and so establishes that Dictation is listening without any inference from audio.

Because it names Dictation rather than describing microphone activity, nothing has to work out which process holds the microphone. It is undocumented, which is the project's standing fragility: it can be renamed or withdrawn without warning, and the failure is silent and looks exactly like not dictating.

### Edge
A transition of Dictation between listening and not listening. The start edge and the stop edge are treated separately because they have different consequences: a missed start shows no band, while a missed stop leaves the band standing and claims Dictation is live when it is not.

### Listening
The state in which Dictation is confirmed to be capturing speech, and the only state in which the Band is shown.

Entered only on a confirming signal, never optimistically — an unattributed microphone, or a keypress that might not have started Dictation, does not enter it. A listening state that stands far longer than any real session is given back unasked, because the signal that ends it can be dropped silently and a stranded band is worse than no band.

### Coalescing window
The brief interval after an apparent stop during which a following start cancels that stop rather than being treated as a new session.

It exists because a start sequence emits its own spurious stop before it emits the start. Without the window, every session would begin with the band flashing off and on.

### Self-test
A guided check that exercises the live detector end to end: it asks the person to dictate, watches the same machinery the overlay uses, and reports whether each edge was observed and how quickly.

It is deliberately live rather than a check of preconditions, because permissions and registrations can all be in order while nothing actually arrives — which is the failure it exists to catch. It reports the edges separately, so a detector that sees the start but not the stop is distinguishable from one that sees nothing.

### Last confirmed
The time of the most recent session the app observed all the way through, start edge to stop edge.

A stop with no preceding start does not count, because it proves nothing about detection. This is what distinguishes a healthy detector during a quiet stretch from one that has silently stopped working.

## Overlay

### Band
The blue glow drawn around the outer edge of every display for exactly as long as Dictation is listening.

One band per display rather than one around the region they collectively cover, so displays of different sizes do not leave a band running through space no screen occupies. Its colour is fixed rather than following the system appearance, because it is drawn over other applications' windows and states its own colour rather than borrowing one. It has no intermediate strengths: it is at full strength or absent — the Profile shapes how that strength is spread across the glow's depth, not how much of it there is.

### Profile
The shape of the Band across its depth: the width and alpha of the rim on the display's own edge, how far the glow reaches inward, the alpha it leaves the rim at, and the exponent the fall is shaped by.

Named profiles rather than tuned constants, because which one is right is a matter of taste against a real desktop and that is a judgement to be re-made rather than argued from the numbers. Four ship and `--compare-bands` walks them; the rim is the one in use. A band four points wide at full strength reads as a line drawn around the screen, where a point of rim under a wide falloff reads as the edge itself being lit.

### Display corner
The radius the system rounds a display's corners to, which the Band is drawn to at each corner.

No public API reports it and no screen capture can measure it, because a rounded display photographs square: the mask is applied after the framebuffer. It is read from the window server through a private call, in points of the display's current mode, so it changes with the scaled resolution. A display that reports no corner keeps a square band. A square band on a rounded display is cut by the panel at each corner, which breaks it exactly where the eye follows it around.

### Fail closed
The project's standing rule that the Band is shown only on positive confirmation, and that any ambiguity resolves to showing nothing.

The accepted cost is that an absent band is ambiguous — it means Dictation is idle, or the detector is broken, or the app is not running. The Self-test and Last confirmed exist to make that ambiguity resolvable rather than to remove it.

## Flagged ambiguities

- "Verified" had been applied to checks that observe window-server bookkeeping or a screen capture. Neither observes whether the Band is drawn, so neither verifies the overlay; only a person looking at the screen does.
