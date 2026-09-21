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
public final class DictationMonitor {
  public static let observedNames: [String] = DictationEvent.allCases.map(\.rawValue)

  /// Every observed notification, whether or not it changed state. R19 wants a session that
  /// already failed to be diagnosable afterwards, which means recording what arrived, not
  /// only what it meant.
  public var onEvent: ((DictationEvent, Date) -> Void)?

  private let center: DistributedNotificationCenter
  private var tokens: [NSObjectProtocol] = []

  public init(center: DistributedNotificationCenter = .default()) {
    self.center = center
  }

  deinit { stop() }

  public func start() {
    guard tokens.isEmpty else { return }
    for event in DictationEvent.allCases {
      let token = center.addObserver(
        forName: Notification.Name(event.rawValue), object: nil, queue: .main
      ) { [weak self] _ in
        self?.onEvent?(event, Date())
      }
      tokens.append(token)
    }
  }

  public func stop() {
    tokens.forEach(center.removeObserver)
    tokens.removeAll()
  }
}
