import Foundation

/// One run of the guided live test: what it saw, and what that means.
///
/// The test is live rather than a check of preconditions because a precondition check can
/// report healthy while detection is broken -- permissions in place, observers registered,
/// nothing actually arriving -- which is the exact failure it exists to catch. There is no
/// Apple-supported way to start Dictation programmatically, so the prompt to the person is
/// the mechanism, not a shortcoming.
///
/// It subscribes to the same machine the overlay uses. A test with its own observation path
/// could pass while the live one is broken.
public final class SelfTestSession {
  public enum Outcome: Equatable, Sendable {
    case passed
    case partial
    case failed
  }

  public struct Result: Equatable, Sendable {
    public let outcome: Outcome
    public let summary: String
    /// Seconds from the prompt to the observed start, and from the start to the stop.
    public let startLatency: TimeInterval?
    public let stopLatency: TimeInterval?
  }

  private let startedAt: Date
  private var observedStart: Date?
  private var observedStop: Date?

  public init(startedAt: Date = Date()) {
    self.startedAt = startedAt
  }

  /// A test begun while a session is already in flight would read that session as its own
  /// result, so the caller refuses rather than starting.
  public static func mayStart(currentState: EdgeMachine.State) -> Bool {
    currentState == .idle
  }

  /// Only the first transition of each kind counts, so a second session inside the window
  /// cannot overwrite the measured latency.
  public func observe(_ state: EdgeMachine.State, at when: Date = Date()) {
    switch state {
    case .listening:
      if observedStart == nil { observedStart = when }
    case .idle:
      if observedStart != nil, observedStop == nil { observedStop = when }
    }
  }

  public func resolve(at when: Date = Date(), timedOut: Bool) -> Result {
    let startLatency = observedStart.map { $0.timeIntervalSince(startedAt) }
    let stopLatency = observedStart.flatMap { start in
      observedStop.map { $0.timeIntervalSince(start) }
    }

    switch (observedStart, observedStop) {
    case (nil, _):
      return Result(
        outcome: .failed,
        summary: """
          Detection is not working. The start of a dictation session was never observed, so \
          nothing reached the detector. Check that Dictation is enabled in System Settings, \
          and see the log for what did arrive.
          """,
        startLatency: nil,
        stopLatency: nil)
    case (_, nil):
      return Result(
        outcome: .partial,
        summary: """
          The start was observed but the stop was not. The band would go up and stay up. \
          This is the failure that leaves the border on screen after Dictation has ended.
          """,
        startLatency: startLatency,
        stopLatency: nil)
    default:
      let budget = String(format: "%.0fms", (stopLatency ?? 0) * 1000)
      return Result(
        outcome: .passed,
        summary: "Detection is working. Start and stop were both observed; stop took \(budget).",
        startLatency: startLatency,
        stopLatency: stopLatency)
    }
  }
}
