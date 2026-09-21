import CoreGraphics

/// Where the band goes and what it is made of.
///
/// Copied from axshot's drive frame rather than imported: the two apps share no code at
/// runtime. A solid edge on the screen's own boundary, then the inward falloff drawn as
/// concentric rings rather than as a blur. A blurred shadow needs a path to be cast from,
/// and the only exact one here is a curve no path can hold -- a display's corner radius is
/// not reported by anything -- so the falloff is drawn out of the same rectangle instead.
///
/// The outer boundary is square, deliberately. Where the panel rounds its corner, the
/// panel's own mask clips the band; a curve guessed at here would compete with that mask
/// rather than match it. The band states the bounds it knows and leaves the corner to the
/// hardware.
public enum BandGeometry {
  /// The solid band on the screen's own edge, in points.
  public static let edgeWidth: CGFloat = 4
  /// Each ring of the inward falloff.
  public static let ringWidth: CGFloat = 1
  public static let ringCount = 16
  /// The falloff's starting alpha, before the window's own opacity.
  public static let peakAlpha: CGFloat = 0.34

  /// One band per screen, never one around the union of them. Two displays of different
  /// heights leave the union running through dead space above the shorter one: a band
  /// nobody can see, and no band along the edge that is there.
  public struct Band: Equatable {
    public let frame: CGRect
    public init(frame: CGRect) { self.frame = frame }
  }

  public static func bands(for screenFrames: [CGRect]) -> [Band] {
    screenFrames.map(Band.init(frame:))
  }

  /// Quadratic, so the shadow leaves the band quickly and then trails off, which is what an
  /// inset shadow looks like. A linear ramp reads as a stack of rings instead.
  public static let ringAlphas: [CGFloat] = (0..<ringCount).map { i in
    let fade = pow(1 - CGFloat(i) / CGFloat(ringCount), 2)
    return peakAlpha * fade
  }

  /// Each ring sits one step further in than the last, starting just inside the solid edge.
  public static let ringInsets: [CGFloat] =
    (0..<ringCount).map { edgeWidth + CGFloat($0) * ringWidth }

  /// R3. Fixed, not appearance-following: the band is drawn over other applications'
  /// windows and states its own colour rather than borrowing one from the system.
  public static let bandColorComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) =
    (red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
}
