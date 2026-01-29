import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Deduplication Tests

@Suite("Deduplication Tests")
struct DeduplicationTests {

  /// Tests message normalization removes UUIDs
  @Test("Normalize message removes UUIDs")
  func testNormalizeUUID() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Device [4A8856A0-38E3-5AF4-AC52-8390FFE944A2] failed")

    let normalized = entry.normalizedMessage

    #expect(normalized == "Device [<UUID>] failed")
  }

  /// Tests message normalization removes hex addresses
  @Test("Normalize message removes hex addresses")
  func testNormalizeHexAddress() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Memory address: 0x7fff8a4b2c10")

    let normalized = entry.normalizedMessage

    #expect(normalized == "Memory address: <ADDR>")
  }

  /// Tests message normalization removes timestamps
  @Test("Normalize message removes timestamps")
  func testNormalizeTimestamp() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Event at 2026-01-29 14:30:15.123456")

    let normalized = entry.normalizedMessage

    #expect(normalized == "Event at <TIMESTAMP>")
  }

  /// Tests deduplication key generation
  @Test("Generate deduplication key correctly")
  func testDeduplicationKey() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: "Device [4A8856A0-38E3-5AF4-AC52-8390FFE944A2] failed")

    let key = entry.deduplicationKey

    #expect(key == "com.apple.HomeKit|Error|Device [<UUID>] failed")
  }

  /// Tests identical messages deduplicate
  @Test("Identical messages should deduplicate")
  func testIdenticalMessagesDeduplicate() async throws {
    let entry1 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: "Device [4A8856A0-38E3-5AF4-AC52-8390FFE944A2] failed")

    let entry2 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: "Device [FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF] failed")

    #expect(entry1.deduplicationKey == entry2.deduplicationKey)
  }
}
