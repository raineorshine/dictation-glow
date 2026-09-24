import XCTest
@testable import DictationGlowCore

final class EdgeMachineTests: XCTestCase {
  private func makeMachine() -> (EdgeMachine, FakeClock, () -> [EdgeMachine.State]) {
    let clock = FakeClock()
    var seen: [EdgeMachine.State] = []
    let machine = EdgeMachine(clock: clock)
    machine.onChange = { seen.append($0) }
    return (machine, clock, { seen })
  }

  // R6. A start notification raises listening.
  func testStartedListeningFromIdleEmitsListening() {
    let (machine, _, seen) = makeMachine()
    machine.handle(.startedListening)
    XCTAssertEqual(seen(), [.listening])
    XCTAssertEqual(machine.state, .listening)
  }

  // R7, R8. A stop with nothing following settles to idle once the window elapses.
  func testDidExitWithNoStartFollowingEmitsIdle() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.startedListening)
    machine.handle(.didExitDictationMode)
    XCTAssertEqual(machine.state, .listening, "must not drop the band before the window elapses")
    clock.advance(EdgeMachine.coalescingWindow + 0.01)
    XCTAssertEqual(seen(), [.listening, .idle])
  }

  // R11a. A stop inside a start sequence is not a stop.
  func testDidExitFollowedByStartWithinWindowNeverEmitsIdle() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.startedListening)
    machine.handle(.didExitDictationMode)
    clock.advance(0.08)
    machine.handle(.startedListening)
    clock.advance(1.0)
    XCTAssertEqual(seen(), [.listening], "the cancelled pending stop must not surface")
    XCTAssertEqual(machine.state, .listening)
  }

  func testDidExitFollowedByStartAfterWindowEmitsIdleThenListening() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.startedListening)
    machine.handle(.didExitDictationMode)
    clock.advance(0.2)
    machine.handle(.startedListening)
    XCTAssertEqual(seen(), [.listening, .idle, .listening])
  }

  // R11a names willStartListening as equally cancelling.
  func testWillStartListeningAlsoCancelsThePendingStop() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.startedListening)
    machine.handle(.didExitDictationMode)
    clock.advance(0.05)
    machine.handle(.willStartListening)
    clock.advance(1.0)
    XCTAssertEqual(seen(), [.listening])
  }

  // Fail closed: an announced start is not a live microphone. A start that stalls in
  // DictationIM posts this and never StartedListening.
  func testWillStartListeningAloneDoesNotRaiseTheBand() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.didEnterDictationMode)
    machine.handle(.willStartListening)
    clock.advance(10)
    XCTAssertEqual(seen(), [])
    XCTAssertEqual(machine.state, .idle)
  }

  // Edge: repeated starts are one transition, not many (R4 has no intermediate states).
  func testRepeatedStartedListeningEmitsListeningOnce() {
    let (machine, _, seen) = makeMachine()
    machine.handle(.startedListening)
    machine.handle(.startedListening)
    XCTAssertEqual(seen(), [.listening])
  }

  // Edge: a stop while already idle changes nothing.
  func testDidExitWhileIdleEmitsNothing() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.didExitDictationMode)
    clock.advance(1.0)
    XCTAssertEqual(seen(), [])
    XCTAssertEqual(machine.state, .idle)
  }

  // R10. Anything outside the registered set never reaches the machine, but if it does it
  // is inert rather than a transition.
  func testUnrelatedEventIsIgnored() {
    let (machine, _, seen) = makeMachine()
    machine.handle(.didEnterDictationMode)
    XCTAssertEqual(seen(), [])
    XCTAssertEqual(machine.state, .idle)
  }

  // Distributed notifications drop silently under load, and a dropped stop would strand the
  // band on screen -- the one failure worse than not showing it at all.
  func testAStrandedListeningStateClearsAtTheCeiling() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.startedListening)
    clock.advance(EdgeMachine.sessionCeiling - 1)
    XCTAssertEqual(machine.state, .listening, "the ceiling must not cut a live session short")
    clock.advance(2)
    XCTAssertEqual(seen(), [.listening, .idle])
    XCTAssertEqual(machine.state, .idle)
  }

  // A stop that does arrive cancels the ceiling, so it cannot fire later over an idle band.
  func testAnOrdinaryStopCancelsTheCeiling() {
    let (machine, clock, seen) = makeMachine()
    machine.handle(.startedListening)
    machine.handle(.didExitDictationMode)
    clock.advance(EdgeMachine.coalescingWindow + 0.01)
    XCTAssertEqual(seen(), [.listening, .idle])
    clock.advance(EdgeMachine.sessionCeiling * 2)
    XCTAssertEqual(seen(), [.listening, .idle], "the ceiling must not fire after a clean stop")
  }

  // The name set is the detector's whole contract with the system; pin it.
  func testObservedNotificationNamesArePinned() {
    XCTAssertEqual(
      DictationMonitor.observedNames,
      [
        "DictationIMNotificationWillStartListening",
        "DictationIMNotificationStartedListening",
        "DictationIMNotificationDidEnterDictationMode",
        "DictationIMNotificationDidExitDictationMode",
      ])
  }
}
