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
  private var windows: [NSWindow] = []
  private var visible = false
  private var screenObserver: NSObjectProtocol?

  public init() {
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
  public func show(duration: TimeInterval = Timing.fadeIn) {
    guard !visible else { return }
    visible = true
    rebuild()
    for window in windows {
      window.alphaValue = 0
      window.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        window.animator().alphaValue = Timing.bandOpacity
      }
    }
  }

  /// R5. Fades out, then orders the windows away.
  public func hide(duration: TimeInterval = Timing.fadeOut) {
    guard visible else { return }
    visible = false
    for window in windows {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        window.animator().alphaValue = 0
      } completionHandler: {
        window.orderOut(nil)
      }
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
    let bands = BandGeometry.bands(for: NSScreen.screens.map(\.frame))
    while windows.count > bands.count {
      windows.removeLast().orderOut(nil)
    }
    while windows.count < bands.count {
      windows.append(Self.makeWindow())
    }
    for (window, band) in zip(windows, bands) {
      window.setFrame(band.frame, display: false)
      (window.contentView as? BandView)?.layoutBand()
      if visible { window.orderFrontRegardless() }
    }
  }

  private static func makeWindow() -> NSWindow {
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
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    // Taken out of every capture on the machine by the window's sharing type rather than by
    // being hidden around each shutter: a band at the screen's edge is inside any capture
    // that reaches it, and the process photographing is not always this one.
    window.sharingType = .none
    window.contentView = BandView()
    return window
  }
}

/// The band itself, drawn as concentric layers so every ring is the same rectangle again
/// rather than an approximation of it.
private final class BandView: NSView {
  private var edge: CALayer?
  private var rings: [CALayer] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    build()
  }

  required init?(coder: NSCoder) { nil }

  override var isFlipped: Bool { false }
  override func isAccessibilityElement() -> Bool { false }
  override func layout() {
    super.layout()
    layoutBand()
  }

  private func build() {
    let c = BandGeometry.bandColorComponents
    let solid = CGColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    let edgeLayer = CALayer()
    edgeLayer.borderColor = solid
    edgeLayer.borderWidth = BandGeometry.edgeWidth
    layer?.addSublayer(edgeLayer)
    edge = edgeLayer
    for alpha in BandGeometry.ringAlphas {
      let ring = CALayer()
      ring.borderColor = CGColor(red: c.red, green: c.green, blue: c.blue, alpha: alpha)
      ring.borderWidth = BandGeometry.ringWidth
      layer?.addSublayer(ring)
      rings.append(ring)
    }
  }

  /// A layer moved without this animates itself into position, and a band that slides after
  /// the screen it is marking is a band that is wrong for as long as the slide lasts.
  func layoutBand() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    let box = CGRect(origin: .zero, size: bounds.size)
    edge?.frame = box
    for (ring, inset) in zip(rings, BandGeometry.ringInsets) {
      ring.frame = box.insetBy(dx: inset, dy: inset)
    }
  }
}
