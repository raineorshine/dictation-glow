import Foundation

public protocol Cancellable: AnyObject {
  func cancel()
}

/// The machine's only dependency on time, so the coalescing window can be resolved by a test
/// without waiting for it.
public protocol MachineClock: AnyObject {
  func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable
}

/// What `DictationIM` says, reduced to the four names that matter.
public enum DictationEvent: String, CaseIterable, Sendable {
  case willStartListening = "DictationIMNotificationWillStartListening"
  case startedListening = "DictationIMNotificationStartedListening"
  case didEnterDictationMode = "DictationIMNotificationDidEnterDictationMode"
  case didExitDictationMode = "DictationIMNotificationDidExitDictationMode"
}

/// Turns the notification stream into a listening/idle signal.
///
/// This is a machine rather than a direct notification-to-visibility binding because
/// `DidExitDictationMode` is not self-evidently a stop: a start sequence emits one too. So a
/// stop becomes pending, and a start arriving inside the coalescing window cancels it. Without
/// that, every session would begin with the band flashing off and on again.
///
/// `DictationIMNotificationStoppedListening` exists as a string in the system binary but was
/// never observed to fire. The stop edge is `DidExitDictationMode`.
public final class EdgeMachine {
  public enum State: Equatable, Sendable {
    case idle
    case listening
  }

  /// Both observed sessions emitted their spurious exit well inside this. A third that did
  /// not would move the constant, not the design.
  public static let coalescingWindow: TimeInterval = 0.15

  public private(set) var state: State = .idle
  public var onChange: ((State) -> Void)?

  private let clock: MachineClock
  private var pendingStop: Cancellable?

  public init(clock: MachineClock = RunLoopClock()) {
    self.clock = clock
  }

  public func handle(_ event: DictationEvent) {
    switch event {
    case .startedListening, .willStartListening:
      // A start cancels a pending stop whether or not the band is currently up: that is the
      // whole of R11a.
      pendingStop?.cancel()
      pendingStop = nil
      transition(to: .listening)
    case .didExitDictationMode:
      guard state == .listening, pendingStop == nil else { return }
      pendingStop = clock.schedule(after: Self.coalescingWindow) { [weak self] in
        guard let self else { return }
        self.pendingStop = nil
        self.transition(to: .idle)
      }
    case .didEnterDictationMode:
      // Observed on every session, but it says the mode was entered rather than that the
      // microphone is live. Logged, never acted on.
      break
    }
  }

  private func transition(to next: State) {
    guard next != state else { return }
    state = next
    onChange?(next)
  }
}

/// The ordinary clock: a run-loop timer on the main queue, where the overlay lives.
public final class RunLoopClock: MachineClock {
  public init() {}

  public func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
    let item = DispatchWorkItem(block: action)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    return WorkItemToken(item: item)
  }

  private final class WorkItemToken: Cancellable {
    private let item: DispatchWorkItem
    init(item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
  }
}
