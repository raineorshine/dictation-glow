# dictation-glow — native macOS Dictation visual feedback

Explore the design and open questions with the user before implementation.

Design a small macOS utility that provides much more visible feedback whenever Apple’s native macOS Dictation is active. The utility should not replace Dictation; it should detect native Dictation state and render a prominent visual overlay.

Brainstorm and investigate the most reliable detection architecture, including Accessibility observation of the native Dictation UI, keyboard/Globe-Fn shortcut monitoring, microphone/process activity, dictation-related system processes, distributed/Darwin notifications, and WindowServer inspection. Prefer fast optimistic UI plus slower authoritative confirmation/correction. Evaluate latency, false positives/negatives, macOS-version stability, private-API dependence, required permissions, behavior across apps, simultaneous microphone use, Voice Control, Siri, third-party dictation, fullscreen, multiple monitors, and custom Dictation shortcuts.

Prototype strategy: first build a diagnostic harness that logs candidate signals before/during/after native Dictation, then identify the strongest signal combination, document failure modes, recommend the smallest robust production architecture, and if sufficiently confident implement a minimal overlay. Overlay should be non-activating, always-on-top, ignore mouse events, not steal focus, support Spaces/fullscreen appropriately, and fade in/out smoothly.

Central question: How can a third-party macOS utility determine, with low latency and high confidence, that Apple’s native Dictation is currently active?

The detection approaches above are candidates to investigate, not verified signals. Begin with collaborative brainstorming; the prototype strategy describes subsequent work.
