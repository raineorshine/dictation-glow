import XCTest
@testable import DictationGlowCore

final class EventLogTests: XCTestCase {
  private func makeLog(ringCapacity: Int = 4, fileLimit: Int = 4096) -> (EventLog, URL) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("dg-log-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let log = EventLog(
      directory: dir, ringCapacity: ringCapacity, fileSizeLimit: fileLimit)
    return (log, dir)
  }

  // R19. Every observed notification is recorded, including ones that change no state.
  func testRecordsAnEventThatChangesNoState() {
    let (log, dir) = makeLog()
    defer { try? FileManager.default.removeItem(at: dir) }
    log.record(.didEnterDictationMode, at: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(log.recent.count, 1)
    XCTAssertEqual(log.recent.first?.event, .didEnterDictationMode)
  }

  // R13. A completed listening-then-idle cycle is what "last confirmed" means.
  func testCompletedCycleUpdatesLastConfirmed() {
    let (log, dir) = makeLog()
    defer { try? FileManager.default.removeItem(at: dir) }
    XCTAssertNil(log.lastConfirmed)
    log.noteStateChange(.listening, at: Date(timeIntervalSince1970: 10))
    XCTAssertNil(log.lastConfirmed, "a session that has not ended is not yet confirmed")
    log.noteStateChange(.idle, at: Date(timeIntervalSince1970: 40))
    XCTAssertEqual(log.lastConfirmed, Date(timeIntervalSince1970: 40))
  }

  func testIdleWithoutAPrecedingListeningDoesNotConfirm() {
    let (log, dir) = makeLog()
    defer { try? FileManager.default.removeItem(at: dir) }
    log.noteStateChange(.idle, at: Date(timeIntervalSince1970: 40))
    XCTAssertNil(log.lastConfirmed)
  }

  // Edge: the ring drops oldest first and never grows past its bound.
  func testRingDropsOldestFirstAndStaysBounded() {
    let (log, dir) = makeLog(ringCapacity: 3)
    defer { try? FileManager.default.removeItem(at: dir) }
    for i in 0..<10 {
      log.record(.startedListening, at: Date(timeIntervalSince1970: TimeInterval(i)))
    }
    XCTAssertEqual(log.recent.count, 3)
    XCTAssertEqual(log.recent.map(\.at.timeIntervalSince1970), [7, 8, 9])
  }

  // Edge: the file rotates at its limit without losing the most recent entries.
  func testFileRotatesAndKeepsTheMostRecentEntries() throws {
    let (log, dir) = makeLog(ringCapacity: 4, fileLimit: 400)
    defer { try? FileManager.default.removeItem(at: dir) }
    for i in 0..<200 {
      log.record(.startedListening, at: Date(timeIntervalSince1970: TimeInterval(i)))
    }
    let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
    XCTAssertLessThanOrEqual(contents.utf8.count, 400 * 2, "the file must not grow without limit")
    XCTAssertTrue(contents.contains("199"), "the most recent entry must survive rotation")
  }

  // The file is what makes a session that already failed diagnosable afterwards, so it has
  // to outlive the process.
  func testEntriesReachTheFile() throws {
    let (log, dir) = makeLog()
    defer { try? FileManager.default.removeItem(at: dir) }
    log.record(.didExitDictationMode, at: Date(timeIntervalSince1970: 1_000))
    let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
    XCTAssertTrue(contents.contains("DictationIMNotificationDidExitDictationMode"))
  }
}
