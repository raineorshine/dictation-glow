import CoreGraphics
import XCTest
@testable import DictationGlowCore

final class BandGeometryTests: XCTestCase {
  // R1. One band per screen, never one around the union of them.
  func testOneBandPerScreenOfDifferentHeights() {
    let screens = [
      CGRect(x: 0, y: 0, width: 2560, height: 1664),
      CGRect(x: 2560, y: 0, width: 1920, height: 1080),
    ]
    let bands = BandGeometry.bands(for: screens.map { BandGeometry.Display(frame: $0) })
    XCTAssertEqual(bands.count, 2)
    XCTAssertEqual(bands.map(\.frame), screens)
    // The union would be 2560+1920 wide and 1664 tall; no band may claim the dead
    // space above the shorter display.
    let union = screens.reduce(CGRect.null) { $0.union($1) }
    XCTAssertFalse(bands.contains { $0.frame == union })
  }

  func testSingleScreenProducesOneBandMatchingItsFrame() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let bands = BandGeometry.bands(for: [BandGeometry.Display(frame: screen)])
    XCTAssertEqual(bands.count, 1)
    XCTAssertEqual(bands[0].frame, screen)
  }

  func testNoScreensProducesNoBands() {
    XCTAssertTrue(BandGeometry.bands(for: []).isEmpty)
  }

  // Each display keeps its own corner: a rounded laptop panel next to a square external
  // monitor gets a rounded band and a square one, not one radius for both.
  func testEachBandCarriesItsOwnDisplaysCorner() {
    let bands = BandGeometry.bands(for: [
      BandGeometry.Display(frame: CGRect(x: 0, y: 0, width: 1470, height: 956), cornerRadius: 20.35),
      BandGeometry.Display(frame: CGRect(x: 1470, y: 0, width: 1920, height: 1080)),
    ])
    XCTAssertEqual(bands.map(\.cornerRadius), [20.35, 0])
  }

  // The four radii arrive unlabelled and a panel that rounds one corner rounds all four, so
  // the largest is the corner -- whichever two of the four came back zero.
  func testCornerRadiusTakesTheLargestReportedRadius() {
    XCTAssertEqual(BandGeometry.cornerRadius(forReportedRadii: [0, 0, 20.3528, 20.3499]), 20.3528)
    XCTAssertEqual(BandGeometry.cornerRadius(forReportedRadii: [20.3528, 20.3499, 0, 0]), 20.3528)
  }

  // A display that reports nothing rounded, and one the window server refuses to answer for,
  // both keep the square corner the band has always drawn.
  func testCornerRadiusIsZeroWithoutAReportedCorner() {
    XCTAssertEqual(BandGeometry.cornerRadius(forReportedRadii: [0, 0, 0, 0]), 0)
    XCTAssertEqual(BandGeometry.cornerRadius(forReportedRadii: []), 0)
  }

  // Concentric: inset by d, the corner is d smaller, and past the radius it is square again.
  func testRingRadiiStepInWithTheirInsetsAndClampAtSquare() {
    let outer: CGFloat = 20.35
    for inset in BandGeometry.defaultProfile.ringInsets {
      let radius = BandGeometry.ringRadius(outer: outer, inset: inset)
      XCTAssertEqual(radius, max(0, outer - inset), accuracy: 0.0001)
      XCTAssertGreaterThanOrEqual(radius, 0)
    }
    XCTAssertEqual(BandGeometry.ringRadius(outer: 4, inset: 19), 0)
  }

  // A square display stays square all the way in: no ring may round what the display does not.
  func testRingRadiiStaySquareOnASquareDisplay() {
    for inset in BandGeometry.defaultProfile.ringInsets {
      XCTAssertEqual(BandGeometry.ringRadius(outer: 0, inset: inset), 0)
    }
  }

  // R4. Every profile's falloff is monotonic and never exceeds its peak.
  func testEveryVariantFallsMonotonicallyFromItsPeak() {
    for profile in BandGeometry.variants {
      let alphas = profile.ringAlphas
      XCTAssertEqual(alphas.count, profile.ringCount, profile.name)
      XCTAssertLessThanOrEqual(alphas[0], profile.peakAlpha, profile.name)
      for (a, b) in zip(alphas, alphas.dropFirst()) {
        XCTAssertGreaterThan(a, b, "\(profile.name): ring alpha must fall inward")
      }
      XCTAssertGreaterThan(alphas.last!, 0, "\(profile.name): a glow that ends at zero ends invisibly")
    }
  }

  // Each ring sits one step further in than the last, starting just inside the rim, so the
  // rings abut rather than overlapping or leaving a gap.
  func testEveryVariantsRingsTileInwardFromTheRim() {
    for profile in BandGeometry.variants {
      let insets = profile.ringInsets
      XCTAssertEqual(insets.count, profile.ringCount, profile.name)
      XCTAssertEqual(insets[0], profile.rimWidth, profile.name)
      for (a, b) in zip(insets, insets.dropFirst()) {
        XCTAssertEqual(b - a, BandGeometry.Profile.ringWidth, accuracy: 0.0001, profile.name)
      }
      XCTAssertEqual(insets.last! + BandGeometry.Profile.ringWidth, profile.totalWidth, accuracy: 0.0001, profile.name)
    }
  }

  // The variants are what a person chooses between by name, so the names have to be distinct
  // and the default has to be one of them.
  func testVariantsAreNamedDistinctlyAndTheDefaultIsOneOfThem() {
    let names = BandGeometry.variants.map(\.name)
    XCTAssertEqual(Set(names).count, names.count)
    XCTAssertTrue(BandGeometry.variants.contains(BandGeometry.defaultProfile))
    XCTAssertEqual(BandGeometry.variant(named: BandGeometry.defaultProfile.name), BandGeometry.defaultProfile)
    XCTAssertNil(BandGeometry.variant(named: "no such band"))
  }

  // The ask was a wider, more gradual glow than the border it replaces: every variant but the
  // one kept for comparison reaches further in and spends less of itself on a hard edge.
  func testEveryGlowIsWiderAndSofterThanTheBorderItReplaces() {
    let border = BandGeometry.variant(named: "border")!
    for profile in BandGeometry.variants where profile != border {
      XCTAssertGreaterThan(profile.totalWidth, border.totalWidth, profile.name)
      XCTAssertLessThan(profile.rimWidth, border.rimWidth, profile.name)
    }
    XCTAssertNotEqual(BandGeometry.defaultProfile, border)
  }

  // R3. Fixed colour, not appearance-following.
  func testBandColorIsFixedRegardlessOfAppearance() {
    XCTAssertEqual(BandGeometry.bandColorComponents.red, 0x0A / 255.0, accuracy: 0.0001)
    XCTAssertEqual(BandGeometry.bandColorComponents.green, 0x84 / 255.0, accuracy: 0.0001)
    XCTAssertEqual(BandGeometry.bandColorComponents.blue, 0xFF / 255.0, accuracy: 0.0001)
  }
}
