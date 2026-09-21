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
    let bands = BandGeometry.bands(for: screens)
    XCTAssertEqual(bands.count, 2)
    XCTAssertEqual(bands.map(\.frame), screens)
    // The union would be 2560+1920 wide and 1664 tall; no band may claim the dead
    // space above the shorter display.
    let union = screens.reduce(CGRect.null) { $0.union($1) }
    XCTAssertFalse(bands.contains { $0.frame == union })
  }

  func testSingleScreenProducesOneBandMatchingItsFrame() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let bands = BandGeometry.bands(for: [screen])
    XCTAssertEqual(bands.count, 1)
    XCTAssertEqual(bands[0].frame, screen)
  }

  func testNoScreensProducesNoBands() {
    XCTAssertTrue(BandGeometry.bands(for: []).isEmpty)
  }

  // R4. The inward falloff is monotonic and never exceeds the peak.
  func testRingAlphaFallsMonotonicallyFromThePeak() {
    let alphas = BandGeometry.ringAlphas
    XCTAssertEqual(alphas.count, BandGeometry.ringCount)
    XCTAssertLessThanOrEqual(alphas[0], BandGeometry.peakAlpha)
    for (a, b) in zip(alphas, alphas.dropFirst()) {
      XCTAssertGreaterThan(a, b, "ring alpha must fall inward")
    }
    XCTAssertGreaterThan(alphas.last!, 0)
  }

  // Each ring sits one step further in than the last, starting inside the solid edge.
  func testRingInsetsStepInwardFromTheEdge() {
    let insets = BandGeometry.ringInsets
    XCTAssertEqual(insets.count, BandGeometry.ringCount)
    XCTAssertEqual(insets[0], BandGeometry.edgeWidth)
    for (a, b) in zip(insets, insets.dropFirst()) {
      XCTAssertEqual(b - a, BandGeometry.ringWidth, accuracy: 0.0001)
    }
  }

  // R3. Fixed colour, not appearance-following.
  func testBandColorIsFixedRegardlessOfAppearance() {
    XCTAssertEqual(BandGeometry.bandColorComponents.red, 0x0A / 255.0, accuracy: 0.0001)
    XCTAssertEqual(BandGeometry.bandColorComponents.green, 0x84 / 255.0, accuracy: 0.0001)
    XCTAssertEqual(BandGeometry.bandColorComponents.blue, 0xFF / 255.0, accuracy: 0.0001)
  }
}
