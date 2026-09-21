import XCTest
@testable import DictationGlowCore

final class SelfTestTests: XCTestCase {
  // AE4. Nothing arriving is a named failure, not a pass. This is the whole reason the test
  // is live rather than a precondition check.
  func testNoEventsBeforeTheTimeoutFailsNamingTheUnobservedStart() {
    let session = SelfTestSession(startedAt: Date(timeIntervalSince1970: 0))
    let result = session.resolve(at: Date(timeIntervalSince1970: 30), timedOut: true)
    XCTAssertEqual(result.outcome, .failed)
    XCTAssertTrue(result.summary.contains("start"), "must name what was not seen: \(result.summary)")
    XCTAssertNil(result.startLatency)
    XCTAssertNil(result.stopLatency)
  }

  // R12. Both edges inside the timeout is a pass carrying both latencies.
  func testBothEdgesObservedPassesWithBothLatencies() {
    let session = SelfTestSession(startedAt: Date(timeIntervalSince1970: 0))
    session.observe(.listening, at: Date(timeIntervalSince1970: 4))
    session.observe(.idle, at: Date(timeIntervalSince1970: 9))
    let result = session.resolve(at: Date(timeIntervalSince1970: 9), timedOut: false)
    XCTAssertEqual(result.outcome, .passed)
    XCTAssertEqual(result.startLatency, 4)
    XCTAssertEqual(result.stopLatency, 5)
  }

  // Edge: only the start arriving is partial, not a pass.
  func testOnlyTheStartObservedIsPartialNamingTheMissingStop() {
    let session = SelfTestSession(startedAt: Date(timeIntervalSince1970: 0))
    session.observe(.listening, at: Date(timeIntervalSince1970: 3))
    let result = session.resolve(at: Date(timeIntervalSince1970: 30), timedOut: true)
    XCTAssertEqual(result.outcome, .partial)
    XCTAssertTrue(result.summary.contains("stop"), "must name the missing stop: \(result.summary)")
    XCTAssertEqual(result.startLatency, 3)
    XCTAssertNil(result.stopLatency)
  }

  // Edge: a test begun while a session is already in flight would read that session as its
  // own result, so it is refused rather than started.
  func testRefusesToStartWhileAlreadyListening() {
    XCTAssertFalse(SelfTestSession.mayStart(currentState: .listening))
    XCTAssertTrue(SelfTestSession.mayStart(currentState: .idle))
  }

  // The stop budget is a target, not a gate (R11): a slow pass is still a pass, and says so.
  func testASlowButCompleteSessionStillPassesAndReportsTheBudget() {
    let session = SelfTestSession(startedAt: Date(timeIntervalSince1970: 0))
    session.observe(.listening, at: Date(timeIntervalSince1970: 2))
    session.observe(.idle, at: Date(timeIntervalSince1970: 12))
    let result = session.resolve(at: Date(timeIntervalSince1970: 12), timedOut: false)
    XCTAssertEqual(result.outcome, .passed)
    XCTAssertEqual(result.stopLatency, 10)
  }

  // Only the first transition of each kind counts, so a second session inside the window
  // cannot overwrite the measured latency.
  func testLaterTransitionsDoNotOverwriteTheFirstOnes() {
    let session = SelfTestSession(startedAt: Date(timeIntervalSince1970: 0))
    session.observe(.listening, at: Date(timeIntervalSince1970: 2))
    session.observe(.idle, at: Date(timeIntervalSince1970: 5))
    session.observe(.listening, at: Date(timeIntervalSince1970: 7))
    session.observe(.idle, at: Date(timeIntervalSince1970: 9))
    let result = session.resolve(at: Date(timeIntervalSince1970: 9), timedOut: false)
    XCTAssertEqual(result.startLatency, 2)
    XCTAssertEqual(result.stopLatency, 3)
  }
}
