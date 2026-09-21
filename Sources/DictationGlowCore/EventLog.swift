import Foundation

/// What the app saw, and when detection last worked.
///
/// Two stores with different jobs. The ring is for the menu, which only ever shows the last
/// few entries. The file is for R19: a session that already failed has to be diagnosable
/// afterwards rather than reproduced, which means the record must outlive the process. It is
/// capped rather than unbounded, because this runs at login and would otherwise grow for the
/// life of the machine.
public final class EventLog {
  public struct Entry: Equatable, Sendable {
    public let event: DictationEvent
    public let at: Date
  }

  public let fileURL: URL
  private let ringCapacity: Int
  private let fileSizeLimit: Int
  private var ring: [Entry] = []
  private var sawListening = false
  private let queue = DispatchQueue(label: "com.raine.dictationglow.log")

  public private(set) var lastConfirmed: Date?

  public init(directory: URL, ringCapacity: Int = 200, fileSizeLimit: Int = 512 * 1024) {
    self.ringCapacity = ringCapacity
    self.fileSizeLimit = fileSizeLimit
    self.fileURL = directory.appendingPathComponent("dictation-glow.log")
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
  }

  /// The app's own directory under the user's Logs, which is where a person looking for a
  /// log would think to look.
  public static func defaultDirectory() -> URL {
    let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
    return base.appendingPathComponent("Logs/DictationGlow")
  }

  public var recent: [Entry] { queue.sync { ring } }

  /// R19. Records what arrived, not only what it meant: an event that changed no state is
  /// exactly the kind a later diagnosis needs.
  public func record(_ event: DictationEvent, at when: Date = Date()) {
    queue.sync {
      ring.append(Entry(event: event, at: when))
      if ring.count > ringCapacity { ring.removeFirst(ring.count - ringCapacity) }
      append("\(Self.stamp(when)) \(event.rawValue)")
    }
  }

  /// R13. "Last confirmed" means a session the app saw all the way through. A stop with no
  /// start before it proves nothing about detection.
  public func noteStateChange(_ state: EdgeMachine.State, at when: Date = Date()) {
    queue.sync {
      switch state {
      case .listening:
        sawListening = true
        append("\(Self.stamp(when)) state=listening")
      case .idle:
        append("\(Self.stamp(when)) state=idle")
        guard sawListening else { return }
        sawListening = false
        lastConfirmed = when
      }
    }
  }

  public func lastConfirmedDescription(now: Date = Date()) -> String {
    guard let lastConfirmed else { return "No dictation session seen yet" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return "Last seen \(formatter.localizedString(for: lastConfirmed, relativeTo: now))"
  }

  // Caller holds the queue.
  private func append(_ line: String) {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: fileURL) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: fileURL)
    }
    rotateIfNeeded()
  }

  /// Keeps the tail rather than the head: the entries that explain a session that just
  /// failed are the recent ones.
  private func rotateIfNeeded() {
    guard
      let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
      size > fileSizeLimit,
      let contents = try? String(contentsOf: fileURL, encoding: .utf8)
    else { return }
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    let kept = lines.suffix(max(1, lines.count / 2)).joined(separator: "\n")
    try? kept.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  private static func stamp(_ date: Date) -> String {
    String(format: "%.3f", date.timeIntervalSince1970)
  }
}
