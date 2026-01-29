import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Deduplication Tests

@Suite("Deduplication Tests")
struct DeduplicationTests {

  /// Tests message normalization removes UUIDs
  @Test("Normalize message removes UUIDs")
  func testNormalizeUUID() async throws {
    let testCases = [
      // Mixed case UUID
      ("Device [4A8856A0-38E3-5AF4-AC52-8390FFE944A2] failed", "Device [<id>] failed"),
      // All uppercase UUID
      ("Device [54D46E14-E6E0-46E3-A501-895333ABE393] failed", "Device [<id>] failed"),
      // Lowercase UUID
      ("Device [a1b2c3d4-e5f6-7890-abcd-ef1234567890] failed", "Device [<id>] failed"),
      // UUID without brackets
      ("UUID: 54D46E14-E6E0-46E3-A501-895333ABE393", "UUID: <id>"),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests message normalization removes hex addresses
  @Test("Normalize message removes hex addresses")
  func testNormalizeHexAddress() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Memory address: 0x7fff8a4b2c10")

    let normalized = entry.normalizedMessage

    #expect(normalized == "Memory address: <addr>")
  }

  /// Tests message normalization removes MAC addresses
  @Test("Normalize message removes MAC addresses")
  func testNormalizeMACAddress() async throws {
    let testCases = [
      // Uppercase MAC address
      ("Device MAC: 60:97:3C:21:F9:6F", "Device MAC: <mac>"),
      // Lowercase MAC address
      ("Connected to aa:bb:cc:dd:ee:ff", "Connected to <mac>"),
      // Mixed case MAC address
      ("MAC address 1A:2b:3C:4d:5E:6f found", "MAC address <mac> found"),
      // Multiple MAC addresses
      ("From AA:BB:CC:DD:EE:FF to 11:22:33:44:55:66", "From <mac> to <mac>"),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests message normalization removes timestamps
  @Test("Normalize message removes timestamps")
  func testNormalizeTimestamp() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Event at 2026-01-29 14:30:15.123456")

    let normalized = entry.normalizedMessage

    #expect(normalized == "Event at <timestamp>")
  }

  /// Tests message normalization removes duration values
  @Test("Normalize message removes duration values")
  func testNormalizeDuration() async throws {
    let testCases = [
      ("Timeout after 5.5 seconds", "Timeout after <duration>"),
      ("Completed in 123 milliseconds", "Completed in <duration>"),
      ("Took 1.234 seconds to respond", "Took <duration> to respond"),
      ("Waited 10 ms", "Waited <duration>"),
      ("Duration: 0.5 s", "Duration: <duration>"),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests message normalization removes all numbers
  @Test("Normalize message removes all numbers")
  func testNormalizeNumbers() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Device 123 reported error code 456 at value 78.9")

    let normalized = entry.normalizedMessage

    #expect(normalized == "Device <n> reported error code <n> at value <n>")
  }

  /// Tests deduplication key generation with new placeholders
  @Test("Generate deduplication key correctly")
  func testDeduplicationKey() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: "Device [4A8856A0-38E3-5AF4-AC52-8390FFE944A2] failed")

    let key = entry.deduplicationKey

    #expect(key == "com.apple.HomeKit|Error|Device [<id>] failed")
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

  /// Tests messages with different numbers deduplicate
  @Test("Messages with different numbers should deduplicate")
  func testNumbersDeduplicateDifferentValues() async throws {
    let entry1 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: "Timeout after 5.2 seconds")

    let entry2 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: "Timeout after 10.8 seconds")

    #expect(entry1.deduplicationKey == entry2.deduplicationKey)
  }

  /// Tests complex message normalization
  @Test("Complex message normalization")
  func testComplexNormalization() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message:
        "Device [A1B2C3D4-E5F6-7890-ABCD-EF1234567890] MAC 60:97:3C:21:F9:6F at 0xdeadbeef failed after 2.5 seconds with code 123"
    )

    let normalized = entry.normalizedMessage

    #expect(
      normalized
        == "Device [<id>] MAC <mac> at <addr> failed after <duration> with code <n>")
  }
}
