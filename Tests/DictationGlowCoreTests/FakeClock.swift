import Foundation
@testable import DictationGlowCore

/// Drives time by hand, so a coalescing window or a session ceiling is resolved by advancing
/// a number rather than by sleeping. Shared by every test that needs to move the machine
/// through a delay.
final class FakeClock: MachineClock {
  private(set) var now: TimeInterval = 0
  private var pending: [(fireAt: TimeInterval, action: () -> Void)] = []

  func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
    let token = Token()
    pending.append((now + delay, { if !token.cancelled { action() } }))
    return token
  }

  func advance(_ by: TimeInterval) {
    now += by
    let due = pending.filter { $0.fireAt <= now }
    pending.removeAll { $0.fireAt <= now }
    due.forEach { $0.action() }
  }

  final class Token: Cancellable {
    var cancelled = false
    func cancel() { cancelled = true }
  }
}
