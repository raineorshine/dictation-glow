import XCTest
@testable import DictationGlowCore

/// Stands in for the real overlay: records what the policy asked for, without a window server.
private final class RecordingBand: BandControlling {
  private(set) var calls: [String] = []
  private(set) var shown = false
  func show() { calls.append("show"); shown = true }
  func hide() { calls.append("hide"); shown = false }
  var isVisible: Bool { shown }
}

final class VisibilityPolicyTests: XCTestCase {
  // Fail closed: nothing is shown until the machine says listening.
  func testBandStartsDownAndStaysDownWithoutListening() {
    let band = RecordingBand()
    let policy = VisibilityPolicy(band: band)
    XCTAssertFalse(band.isVisible)
    XCTAssertEqual(band.calls, [])
    policy.apply(.idle)
    XCTAssertEqual(band.calls, [], "idle from idle must not touch the band")
  }

  // AE1. Listening then idle shows then hides, in that order.
  func testListeningThenIdleShowsThenHides() {
    let band = RecordingBand()
    let policy = VisibilityPolicy(band: band)
    policy.apply(.listening)
    policy.apply(.idle)
    XCTAssertEqual(band.calls, ["show", "hide"])
  }

  // R4. No intermediate states: a second listening does not re-trigger the fade.
  func testRepeatedListeningDoesNotRetriggerTheFade() {
    let band = RecordingBand()
    let policy = VisibilityPolicy(band: band)
    policy.apply(.listening)
    policy.apply(.listening)
    XCTAssertEqual(band.calls, ["show"])
  }

  // AE3. A microphone that never produces a Dictation event never raises the band. The
  // policy has no audio input at all, which is the structural guarantee.
  func testBandIsNeverShownWithoutADictationEvent() {
    let band = RecordingBand()
    let policy = VisibilityPolicy(band: band)
    for _ in 0..<100 { policy.apply(.idle) }
    XCTAssertFalse(band.isVisible)
    XCTAssertEqual(band.calls, [])
  }

  // AE2, integration. The full chain, monitor events through the machine to the band, with
  // an audio stream conceptually held open throughout: the stop still lands, because nothing
  // in this path consults audio.
  func testStopLandsWhileAnotherProcessHoldsTheMicrophone() {
    let clock = FakeClock()
    let band = RecordingBand()
    let machine = EdgeMachine(clock: clock)
    let policy = VisibilityPolicy(band: band)
    machine.onChange = { policy.apply($0) }

    machine.handle(.willStartListening)
    machine.handle(.startedListening)
    XCTAssertTrue(band.isVisible)
    // The call keeps recording for the whole sequence; the detector never asks.
    machine.handle(.didExitDictationMode)
    clock.advance(EdgeMachine.coalescingWindow + 0.01)
    XCTAssertFalse(band.isVisible)
    XCTAssertEqual(band.calls, ["show", "hide"])
  }
}
