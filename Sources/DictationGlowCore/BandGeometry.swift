import CoreGraphics

/// Where the band goes and what it is made of.
///
/// Copied from axshot's drive frame rather than imported: the two apps share no code at
/// runtime. The falloff is drawn as concentric rings rather than as a blur. A blurred shadow
/// needs a path to be cast from, and the only exact one here is a curve no path can hold, so
/// the falloff is drawn out of the same rounded rectangle instead: each ring is the display's
/// corner again rather than an approximation of it.
///
/// One ring per point of depth, each an exact alpha, so the profile across the band is
/// stated outright rather than being whatever a blur radius happens to produce.
///
/// The corner is the display's own, taken from the window server through `DisplayCorners`
/// rather than guessed at. A square band on a rounded display is cut at each corner by the
/// panel, which breaks the band exactly where the eye follows it around -- and a guessed
/// curve would be cut in the same way wherever it ran wide.
public enum BandGeometry {
  /// The shape of the glow across its depth: a rim on the screen's own edge, then a fall to
  /// nothing over `depth` points inward.
  ///
  /// The rim is what a border is when it stops pretending to be one -- at a point or two it
  /// reads as the edge being lit rather than as a line drawn around the screen. A profile
  /// with no rim at all is the whole glow and nothing else.
  public struct Profile: Equatable {
    /// What to call it when a person is choosing between them.
    public let name: String
    /// The solid rim on the screen's own edge, in points. Zero for none.
    public let rimWidth: CGFloat
    /// The rim's alpha, before the window's own opacity.
    public let rimAlpha: CGFloat
    /// How far the glow reaches inward from the rim, in points.
    public let depth: CGFloat
    /// The glow's alpha where it leaves the rim, before the window's own opacity.
    public let peakAlpha: CGFloat
    /// How the fall is shaped. 1 is a straight ramp; above it the glow leaves the edge
    /// quickly and trails off, which is what light falling away looks like and what a
    /// straight ramp reads as a stack of rings instead. Below it the glow holds its strength
    /// out into the screen and then drops.
    public let falloff: CGFloat

    public init(
      name: String, rimWidth: CGFloat, rimAlpha: CGFloat, depth: CGFloat, peakAlpha: CGFloat,
      falloff: CGFloat
    ) {
      self.name = name
      self.rimWidth = rimWidth
      self.rimAlpha = rimAlpha
      self.depth = depth
      self.peakAlpha = peakAlpha
      self.falloff = falloff
    }

    /// One ring per point. Finer than a point buys nothing: the ramp is already below the
    /// step a person can see, and every ring is a layer the render server composites.
    public static let ringWidth: CGFloat = 1

    public var ringCount: Int { Int(depth / Self.ringWidth) }

    /// Sampled at the middle of each ring, so the first ring is a step down from the rim
    /// rather than a second copy of it, and the last is a step above nothing rather than
    /// nothing -- a glow that ends at exactly zero ends invisibly either way.
    public var ringAlphas: [CGFloat] {
      (0..<ringCount).map { i in
        let t = (CGFloat(i) + 0.5) / CGFloat(ringCount)
        return peakAlpha * pow(1 - t, falloff)
      }
    }

    /// Each ring sits one step further in than the last, starting just inside the rim.
    public var ringInsets: [CGFloat] {
      (0..<ringCount).map { rimWidth + CGFloat($0) * Self.ringWidth }
    }

    /// Rim and glow together, in points.
    public var totalWidth: CGFloat { rimWidth + depth }
  }

  /// The profiles worth looking at, in order of how much screen they take.
  ///
  /// They are kept rather than deleted once one is chosen: the choice is a matter of taste
  /// against a real desktop, which is a thing to be re-made when the taste changes, and the
  /// numbers are the whole argument.
  public static let variants: [Profile] = [
    // The original: a band that states an edge. Kept as the thing the others are judged
    // against, not because it is one of them.
    Profile(name: "border", rimWidth: 4, rimAlpha: 1, depth: 16, peakAlpha: 0.34, falloff: 2),
    // A lit edge: one point of rim, then most of the glow spent in the first third of its
    // depth. Closest to the original in weight, and nothing in it reads as a line.
    Profile(name: "rim", rimWidth: 1, rimAlpha: 0.85, depth: 48, peakAlpha: 0.5, falloff: 2.2),
    // No rim at all. The strongest point is the screen's edge and it is already a glow
    // there, falling away over twice the depth of the one above.
    Profile(name: "halo", rimWidth: 0, rimAlpha: 0, depth: 96, peakAlpha: 0.55, falloff: 1.8),
    // The widest and the gentlest: a wash that holds most of its strength well into the
    // screen before it goes. Unmistakable in the corner of an eye, and the most of the
    // desktop spent on saying so.
    Profile(name: "wash", rimWidth: 0, rimAlpha: 0, depth: 160, peakAlpha: 0.45, falloff: 1.3),
  ]

  public static func variant(named name: String) -> Profile? {
    variants.first { $0.name == name }
  }

  /// What the band draws with unless something asks for another. Chosen by looking at all
  /// four on a real desktop: the rim is the only one that still states an edge, and the other
  /// two spend more of the screen than what they are saying is worth.
  public static let defaultProfile = variant(named: "rim")!

  /// One band per screen, never one around the union of them. Two displays of different
  /// heights leave the union running through dead space above the shorter one: a band
  /// nobody can see, and no band along the edge that is there.
  public struct Band: Equatable {
    public let frame: CGRect
    /// The outer corner, which the rim is drawn to and every ring steps in from.
    public let cornerRadius: CGFloat
    public init(frame: CGRect, cornerRadius: CGFloat = 0) {
      self.frame = frame
      self.cornerRadius = cornerRadius
    }
  }

  /// A screen as the band needs it: where it is, and how the system rounds it.
  public struct Display: Equatable {
    public let frame: CGRect
    public let cornerRadius: CGFloat
    public init(frame: CGRect, cornerRadius: CGFloat = 0) {
      self.frame = frame
      self.cornerRadius = cornerRadius
    }
  }

  public static func bands(for displays: [Display]) -> [Band] {
    displays.map { Band(frame: $0.frame, cornerRadius: $0.cornerRadius) }
  }

  /// One radius for all four corners, out of the four the window server reports.
  ///
  /// The four arrive unlabelled -- the call's out parameters carry no names and nothing says
  /// which is which corner -- and on a notched MacBook two of them come back zero while the
  /// other two agree to within a thousandth of a point. Taking the largest and drawing every
  /// corner to it is right either way round: a panel that rounds one corner rounds all four,
  /// symmetrically, and where the system leaves a corner unmasked the panel still cuts it.
  /// A display that reports nothing rounded is square, and stays square.
  public static func cornerRadius(forReportedRadii radii: [CGFloat]) -> CGFloat {
    max(0, radii.max() ?? 0)
  }

  /// Concentric: inset by d, the corner is d smaller, and past the radius it is a corner no
  /// longer -- which is what insetting a rounded rectangle that far actually leaves.
  public static func ringRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
    max(0, outer - inset)
  }

  /// R3. Fixed, not appearance-following: the band is drawn over other applications'
  /// windows and states its own colour rather than borrowing one from the system.
  public static let bandColorComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) =
    (red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
}
