import Foundation

/// Observes the distributed notifications `DictationIM` posts and forwards them as timestamped
/// events.
///
/// Each name is registered explicitly. A nil-name catch-all would receive every distributed
/// notification on the system, which is both a privacy surface and a standing cost for an app
/// that idles all day.
///
/// No entitlement, no TCC grant, no private framework: `distnoted` delivers these to any
/// process that asks for them by name. Verified on macOS 26.6.2 from an unsigned, unentitled
/// binary.
///
/// Registration goes through the `@objc` selector overload rather than the block-based one on
/// purpose. `addObserver(forName:object:queue:using:)` is inherited from `NotificationCenter`
/// and has no `suspensionBehavior` parameter, so it silently registers as `.coalesce` — and a
/// coalesced queue drops all but the last notification while the app is suspended. Losing the
/// stop edge is the one failure that strands the band on screen, so this registers
/// `.deliverImmediately`, which is also what flushes any coalesced queue behind it.
public final class DictationMonitor: NSObject {
  public static let observedNames: [String] = DictationEvent.allCases.map(\.rawValue)

  /// Every observed notification, whether or not it changed state. R19 wants a session that
  /// already failed to be diagnosable afterwards, which means recording what arrived, not
  /// only what it meant.
  public var onEvent: ((DictationEvent, Date) -> Void)?

  private let center: DistributedNotificationCenter
  private let names: [String]
  private var started = false

  /// `names` is injectable so the self-test can be pointed at a name nothing posts, which is
  /// the only way to prove a dead detector reports as dead rather than as an idle system.
  public init(
    center: DistributedNotificationCenter = .default(),
    names: [String] = DictationMonitor.observedNames
  ) {
    self.center = center
    self.names = names
    super.init()
  }

  deinit { stop() }

  public func start() {
    guard !started else { return }
    started = true
    for name in names {
      center.addObserver(
        self,
        selector: #selector(receive(_:)),
        name: Notification.Name(name),
        object: nil,
        suspensionBehavior: .deliverImmediately)
    }
  }

  public func stop() {
    guard started else { return }
    started = false
    center.removeObserver(self)
  }

  @objc private func receive(_ notification: Notification) {
    guard let event = DictationEvent(rawValue: notification.name.rawValue) else { return }
    // Documented as main-thread delivery for multithreaded apps, and measured as such, but
    // the overlay must not depend on that promise holding.
    if Thread.isMainThread {
      onEvent?(event, Date())
    } else {
      DispatchQueue.main.async { [weak self] in self?.onEvent?(event, Date()) }
    }
  }
}
