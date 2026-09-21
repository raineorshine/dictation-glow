import AppKit

/// The band on screen: one borderless window per display, each drawn as layers.
///
/// One window per screen rather than one window over the union of them, so each display
/// supplies its own backing scale and colour space and nothing is allocated over the dead
/// space between mismatched displays.
///
/// Not an accessibility element, deliberately: it is a mark drawn over somebody else's
/// window rather than a control, it answers no key, and a borderless window sitting over
/// every app is the last thing a reader should have to step through to get past.
public final class GlowOverlay {
  /// The shape of the glow. Changing it rebuilds the layers on the spot, so a run that walks
  /// the variants can hand the next one to a band that is already up.
  public var profile: BandGeometry.Profile {
    didSet {
      guard profile != oldValue else { return }
      for window in windows {
        (window.contentView as? BandView)?.apply(profile: profile)
      }
      rebuild()
    }
  }
  private var windows: [NSWindow] = []
  private var visible = false
  /// Bumped on every show, so a fade-out completion can tell whether it is still the
  /// latest instruction.
  private var generation = 0
  private var screenObserver: NSObjectProtocol?

  public init(profile: BandGeometry.Profile = BandGeometry.defaultProfile) {
    self.profile = profile
    // A screen coming or going, or changing resolution, is the only event that moves the
    // edge of a desktop. Nothing else has to be heard about.
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.rebuild()
    }
  }

  deinit {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
  }

  /// R5. Fades in. Idempotent: showing while already shown does not restart the fade (R4).
  ///
  /// The fade is a Core Animation on the band's own layer, not `window.animator()`. AppKit's
  /// animator proxy never runs in this app -- an accessory that is never the active
  /// application -- which left the window ordered in at alpha zero, so the band was on screen
  /// and invisible, and the fade-out's completion (which orders the window away) never fired
  /// either. The render server drives a CABasicAnimation regardless of who is active.
  public func show(duration: TimeInterval = Timing.fadeIn) {
    guard !visible else { return }
    visible = true
    generation += 1
    rebuild()
    for window in windows {
      window.alphaValue = Timing.bandOpacity
      window.orderFrontRegardless()
      window.contentView?.layer?.opacity = 1
      fade(window, from: 0, to: 1, duration: duration)
    }
  }

  /// R5. Fades out, then orders the windows away.
  ///
  /// The completion re-checks visibility and the show generation before ordering out. A
  /// show() landing inside the fade would otherwise be undone by the previous hide's
  /// completion arriving late, which leaves the band down while the machine says listening.
  public func hide(duration: TimeInterval = Timing.fadeOut) {
    guard visible else { return }
    visible = false
    let issued = generation
    for window in windows {
      window.contentView?.layer?.opacity = 0
      fade(window, from: 1, to: 0, duration: duration) { [weak self] in
        guard let self, !self.visible, self.generation == issued else { return }
        window.orderOut(nil)
      }
    }
  }

  private func fade(
    _ window: NSWindow, from: Float, to: Float, duration: TimeInterval,
    completion: (() -> Void)? = nil
  ) {
    guard let layer = window.contentView?.layer else {
      completion?()
      return
    }
    CATransaction.begin()
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "bandFade")
    CATransaction.commit()
    // The order-out is timed rather than hung off the transaction's completion block, which
    // does not fire reliably for this window. The layer's model value is already at the
    // target, so the band is visually gone either way; this only decides when the window
    // stops being ordered in.
    if let completion {
      DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }
  }

  public var isVisible: Bool { visible }

  /// Fade lengths and the band's standing opacity. Slightly slower out than in, so the
  /// disappearance does not read as a flicker.
  public enum Timing {
    public static let fadeIn: TimeInterval = 0.12
    public static let fadeOut: TimeInterval = 0.18
    /// On the window rather than in the colours, so the band and the falloff holding its
    /// shape go down together. It is up for the length of a dictation session and sits on
    /// top of what is being read underneath it.
    public static let bandOpacity: CGFloat = 0.5
  }

  private func rebuild() {
    let bands = BandGeometry.bands(for: NSScreen.screens.map(Self.display(for:)))

    while windows.count > bands.count {
      windows.removeLast().orderOut(nil)
    }
    while windows.count < bands.count {
      windows.append(Self.makeWindow(profile: profile))
    }
    for (window, band) in zip(windows, bands) {
      window.setFrame(band.frame, display: false)
      (window.contentView as? BandView)?.layoutBand(cornerRadius: band.cornerRadius)
      Self.assertAllSpaces(on: window)
      if visible { window.orderFrontRegardless() }
    }
  }

  /// The corner is read on every rebuild rather than cached: the window server reports it in
  /// points of the display's current mode, so a change of scaled resolution changes it --
  /// and that arrives as the same screen-parameters notification that moves the edge.
  public static func display(for screen: NSScreen) -> BandGeometry.Display {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let number = screen.deviceDescription[key] as? NSNumber else {
      return BandGeometry.Display(frame: screen.frame)
    }
    let radii = DisplayCorners.reportedRadii(for: CGDirectDisplayID(number.uint32Value))
    return BandGeometry.Display(
      frame: screen.frame, cornerRadius: BandGeometry.cornerRadius(forReportedRadii: radii))
  }

  /// On every Space, unmoved by Exposé, and over another app's full-screen window. The band
  /// marks a microphone that is live regardless of which desktop is in front of it.
  private static let allSpaces: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .stationary, .fullScreenAuxiliary,
  ]

  /// Says it again, to a window that has already been told.
  ///
  /// A window's membership drifts: a long-lived band window is registered with the window
  /// server against the Spaces that existed when it was born, and it is not carried into one
  /// created afterwards -- measured, on a band window that had been up for hours, as
  /// membership in the current Space alone while a window created minutes earlier from the
  /// same binary held both. From the outside that is exactly the reported symptom, and from
  /// inside the process `collectionBehavior` still reads as `.canJoinAllSpaces`, so nothing
  /// in the app can tell that the registration has gone stale.
  ///
  /// Cleared before it is set so the assignment is a change rather than a no-op: a setter
  /// that short-circuits on an equal value would never reach the window server, which is the
  /// one place the stale registration lives. Measured as harmless on a healthy window -- it
  /// keeps every Space it had and does not blink -- and as an immediate repair on a drifted
  /// one, whether it is ordered in at the time or not.
  private static func assertAllSpaces(on window: NSWindow) {
    window.collectionBehavior = []
    window.collectionBehavior = allSpaces
  }

  private static func makeWindow(profile: BandGeometry.Profile) -> NSWindow {
    let window = NSWindow(
      contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    // The app is never the active one, and a window that accepted a click would activate it
    // and redraw the target's title bar inactive.
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    // Above the screen saver, so a full-screen app does not cover the one thing that has to
    // stay visible.
    window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    window.collectionBehavior = allSpaces
    // Opts out of the legacy capture path, where it works: a band at the screen's edge is
    // inside any capture that reaches it, and the process photographing is not always this
    // one. It is not capture protection -- since macOS 15.4 a window marked .none is still
    // captured by ScreenCaptureKit, and Apple states there is no public API that prevents
    // capture -- so expect the band in screen recordings and shares.
    window.sharingType = .none
    window.contentView = BandView(profile: profile)
    return window
  }
}

/// The band itself, drawn as concentric layers so every ring is the display's corner again
/// rather than an approximation of it.
private final class BandView: NSView {
  private var rim: CALayer?
  private var rings: [CALayer] = []
  private var profile: BandGeometry.Profile
  /// The display's own corner, handed down on every rebuild. Held so that a layout arriving
  /// from AppKit rather than from a rebuild draws the same corner rather than a square one.
  private var cornerRadius: CGFloat = 0

  init(profile: BandGeometry.Profile) {
    self.profile = profile
    super.init(frame: .zero)
    // The backing layer has to exist before sublayers are added. `wantsLayer` alone does not
    // guarantee one for a view that is not yet in a window, and addSublayer on a nil layer
    // is a silent no-op -- the band then never draws, with a perfectly visible window.
    let root = CALayer()
    layer = root
    wantsLayer = true
    build(on: root)
  }

  required init?(coder: NSCoder) { nil }

  override var isFlipped: Bool { false }
  override func isAccessibilityElement() -> Bool { false }
  override func layout() {
    super.layout()
    layoutBand(cornerRadius: cornerRadius)
  }

  /// A different profile is a different number of rings, so the layers are built again
  /// rather than reassigned. The caller lays the band out afterwards.
  func apply(profile: BandGeometry.Profile) {
    self.profile = profile
    guard let root = layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    root.sublayers?.forEach { $0.removeFromSuperlayer() }
    rim = nil
    rings = []
    build(on: root)
    layoutBand(cornerRadius: cornerRadius)
  }

  private func build(on root: CALayer) {
    let c = BandGeometry.bandColorComponents
    func color(_ alpha: CGFloat) -> CGColor {
      CGColor(red: c.red, green: c.green, blue: c.blue, alpha: alpha)
    }
    if profile.rimWidth > 0 {
      let rimLayer = CALayer()
      rimLayer.borderColor = color(profile.rimAlpha)
      rimLayer.borderWidth = profile.rimWidth
      // macOS rounds with a continuous corner -- a squircle, fuller through the diagonal than
      // a circle of the same radius -- and no `NSBezierPath` draws that curve. A layer is the
      // only thing that offers it, which is the reason the band is layers rather than a path.
      rimLayer.cornerCurve = .continuous
      root.addSublayer(rimLayer)
      rim = rimLayer
    }
    for alpha in profile.ringAlphas {
      let ring = CALayer()
      ring.borderColor = color(alpha)
      ring.borderWidth = BandGeometry.Profile.ringWidth
      ring.cornerCurve = .continuous
      root.addSublayer(ring)
      rings.append(ring)
    }
  }

  /// A layer moved without this animates itself into position, and a band that slides after
  /// the screen it is marking is a band that is wrong for as long as the slide lasts.
  func layoutBand(cornerRadius radius: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    cornerRadius = radius
    let box = CGRect(origin: .zero, size: bounds.size)
    rim?.frame = box
    rim?.cornerRadius = radius
    for (ring, inset) in zip(rings, profile.ringInsets) {
      ring.frame = box.insetBy(dx: inset, dy: inset)
      ring.cornerRadius = BandGeometry.ringRadius(outer: radius, inset: inset)
    }
  }
}

extension GlowOverlay: BandControlling {
  public func show() { show(duration: Timing.fadeIn) }
  public func hide() { hide(duration: Timing.fadeOut) }
}
