import Foundation
import Testing

@testable import HomeDiagnosticsCore

@Suite("LogCollector Entry Limit")
struct LogCollectorEntryLimitTests {
  @Test("Entry limit is respected in streamEntries with string input")
  func testEntryLimitWithStringInput() async throws {
    let jsonInput = """
      [
          { "timestamp": "2026-01-29 14:30:15.123456+0000", "messageType": "Info", "eventMessage": "A", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
          { "timestamp": "2026-01-29 14:30:16.123456+0000", "messageType": "Info", "eventMessage": "B", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
          { "timestamp": "2026-01-29 14:30:17.123456+0000", "messageType": "Info", "eventMessage": "C", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" }
      ]
      """
    let logInput = StringLogInput(json: jsonInput, name: "com.apple.HomeKit")
    let collector = LogCollector<StringLogInput>(entryLimit: 2)
    var yielded: [LogEntry] = []
    for try await entry in collector.streamEntries(from: logInput) {
      yielded.append(entry)
    }
    #expect(yielded.count == 2)
    #expect(yielded[0].message == "A")
    #expect(yielded[1].message == "B")
  }

  @Test("Entry limit is respected in collectLogs for multiple inputs")
  func testEntryLimitWithMultipleInputs() async throws {
    let jsonInput = """
      [
          { "timestamp": "2026-01-29 14:30:15.123456+0000", "messageType": "Info", "eventMessage": "A", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
          { "timestamp": "2026-01-29 14:30:16.123456+0000", "messageType": "Info", "eventMessage": "B", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
          { "timestamp": "2026-01-29 14:30:17.123456+0000", "messageType": "Info", "eventMessage": "C", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" }
      ]
      """
    let logInputs = [
      StringLogInput(json: jsonInput, name: "com.apple.HomeKit"),
      StringLogInput(json: jsonInput, name: "com.apple.Home"),
    ]
    let collector = LogCollector<StringLogInput>(entryLimit: 1)
    var yielded: [LogEntry] = []
    for try await entry in collector.collectLogs(from: logInputs) {
      yielded.append(entry)
    }
    // Should yield 1 entry per input (total 2)
    #expect(yielded.count == 2)
  }

  @Test("Unlimited entry limit yields all entries")
  func testUnlimitedEntryLimit() async throws {
    let jsonInput = """
      [
          { "timestamp": "2026-01-29 14:30:15.123456+0000", "messageType": "Info", "eventMessage": "A", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
          { "timestamp": "2026-01-29 14:30:16.123456+0000", "messageType": "Info", "eventMessage": "B", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
          { "timestamp": "2026-01-29 14:30:17.123456+0000", "messageType": "Info", "eventMessage": "C", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" }
      ]
      """
    let logInput = StringLogInput(json: jsonInput, name: "com.apple.HomeKit")
    let collector = LogCollector<StringLogInput>(entryLimit: nil)
    var yielded: [LogEntry] = []
    for try await entry in collector.streamEntries(from: logInput) {
      yielded.append(entry)
    }
    #expect(yielded.count == 3)
  }
}
