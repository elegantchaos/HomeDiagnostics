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

  /// Tests format-string key uses the format string when available
  @Test("Format-string key prefers format string")
  func testFormatStringKeyUsesFormatString() async throws {
    let entry = LogEntry(
      timestamp: Date(),
      subsystem: "com.apple.HomeKit",
      process: "homed",
      category: "HMHomeManager",
      formatString: "updateHomes(timeout:) found homes [%{public}s]",
      level: .info,
      message: "updateHomes(timeout:) found homes [ABC, DEF]"
    )

    let key = entry.formatStringKey

    #expect(key == "com.apple.HomeKit|Info|updateHomes(timeout:) found homes [%{public}s]")
  }

  /// Tests format-string key falls back when format string is empty
  @Test("Format-string key falls back on empty format string")
  func testFormatStringKeyFallbackOnEmpty() async throws {
    let entry = LogEntry(
      timestamp: Date(),
      subsystem: "com.apple.HomeKit",
      process: "homed",
      category: nil,
      formatString: " ",
      level: .error,
      message: "Device [4A8856A0-38E3-5AF4-AC52-8390FFE944A2] failed"
    )

    let key = entry.formatStringKey

    #expect(key == entry.deduplicationKey)
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

  // MARK: - Phase 1 Enhancement Tests

  /// Tests bracket prefix normalization
  @Test("Normalize bracket prefixes with UUID/MAC/Number/Bool")
  func testNormalizeBracketPrefix() async throws {
    let testCases = [
      // Standard format with YES
      (
        "[D3AAD67C-68AB-4261-86AC-7AB8969C6203/0B:10:14:18:2B:E3+1/YES] Failed to save",
        "[<prefix>] Failed to save"
      ),
      // Standard format with NO
      (
        "[4C2778CE-E310-4C51-BACB-766111A6D729/60:97:3C:21:F9:6F+1/NO] Failed to save",
        "[<prefix>] Failed to save"
      ),
      // Large number in prefix
      (
        "[97F905BE-F58F-5694-A9A3-7BCC54B2FD82/45:59:90:5D:AE:C3+6623462395620228/YES] unreachable",
        "[<prefix>] unreachable"
      ),
      // Lowercase yes/no
      (
        "[A1B2C3D4-E5F6-7890-ABCD-EF1234567890/AA:BB:CC:DD:EE:FF+123/yes] message",
        "[<prefix>] message"
      ),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests object description normalization
  @Test("Normalize object descriptions with memory addresses")
  func testNormalizeObjectDescriptions() async throws {
    let testCases = [
      // HMFMessage object
      (
        "Failed to find matching identity for <HMFMessage: 0x813f244b0>",
        "Failed to find matching identity for <obj>"
      ),
      // HMBLocalDatabase object
      (
        "Creating database <HMBLocalDatabase: 0x812345678>",
        "Creating database <obj>"
      ),
      // CKContainerID object
      (
        "Container <CKContainerID: 0x813355bf0> initialized",
        "Container <obj> initialized"
      ),
      // Multiple objects
      (
        "Object <HMDDevice: 0xabc123> sent to <HMFQueue: 0xdef456>",
        "Object <obj> sent to <obj>"
      ),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests boolean literal normalization
  @Test("Normalize boolean literals")
  func testNormalizeBooleans() async throws {
    let testCases = [
      // YES/NO
      ("reachable YES, primary resident: NO", "reachable <bool>, primary resident: <bool>"),
      // yes/no
      ("enabled yes, active no", "enabled <bool>, active <bool>"),
      // true/false
      ("success true, failed false", "success <bool>, failed <bool>"),
      // Mixed case (should not match - case sensitive)
      ("Value True or False", "Value True or False"),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests error domain normalization
  @Test("Normalize error domains")
  func testNormalizeErrorDomains() async throws {
    let testCases = [
      // HMErrorDomain
      (
        "Error Domain=HMErrorDomain Code=52 UserInfo={...}",
        "Error Domain=<domain> Code=<n> UserInfo={...}"
      ),
      // NSOSStatusErrorDomain
      (
        "Error Domain=NSOSStatusErrorDomain Code=-25299",
        "Error Domain=<domain> Code=-<n>"
      ),
      // Custom domain
      (
        "Error Domain=MyCustomErrorDomain Code=123",
        "Error Domain=<domain> Code=<n>"
      ),
      // Multiple error domains
      (
        "Error Domain=HMErrorDomain outer, Error Domain=NSErrorDomain inner",
        "Error Domain=<domain> outer, Error Domain=<domain> inner"
      ),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests whitespace normalization
  @Test("Normalize whitespace")
  func testNormalizeWhitespace() async throws {
    let testCases = [
      // Multiple spaces
      ("Device    failed    with    error", "Device failed with error"),
      // Tabs and spaces
      ("Device\t\tfailed  with   error", "Device failed with error"),
      // Leading and trailing spaces
      ("  Device failed  ", "Device failed"),
      // Newlines (treated as whitespace)
      ("Device\nfailed\nwith\nerror", "Device failed with error"),
    ]

    for (input, expected) in testCases {
      let entry = LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: input)
      #expect(entry.normalizedMessage == expected)
    }
  }

  /// Tests real-world message from logs: "Failed to save public key"
  @Test("Real-world: Failed to save public key messages deduplicate")
  func testRealWorldPublicKeyFailure() async throws {
    let message1 =
      "[D3AAD67C-68AB-4261-86AC-7AB8969C6203/0B:10:14:18:2B:E3+1/NO] Failed to save public key(<private>) pairing username(<private>): Error Domain=HMErrorDomain Code=52 UserInfo={NSLocalizedDescription=<private>, NSUnderlyingError=0x814188330 {Error Domain=NSOSStatusErrorDomain Code=-25299 UserInfo={NSLocalizedDescription=<private>}}}"

    let message2 =
      "[4C2778CE-E310-4C51-BACB-766111A6D729/60:97:3C:21:F9:6F+1/NO] Failed to save public key(<private>) pairing username(<private>): Error Domain=HMErrorDomain Code=52 UserInfo={NSLocalizedDescription=<private>, NSUnderlyingError=0x813f84b10 {Error Domain=NSOSStatusErrorDomain Code=-25299 UserInfo={NSLocalizedDescription=<private>}}}"

    let entry1 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: message1)
    let entry2 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: message2)

    // Both should normalize to the same message
    #expect(entry1.normalizedMessage == entry2.normalizedMessage)
    #expect(entry1.deduplicationKey == entry2.deduplicationKey)
  }

  /// Tests real-world message from logs: "unreachable duration"
  @Test("Real-world: Unreachable duration messages deduplicate")
  func testRealWorldUnreachableDuration() async throws {
    let message1 =
      "[97F905BE-F58F-5694-A9A3-7BCC54B2FD82/45:59:90:5D:AE:C3+6623462395620228/YES] unreachable duration for <private> is 1.774517059326172 seconds - reachable YES, primary resident: NO"

    let message2 =
      "[0FC37221-74DB-41F5-873B-BCA5BB70BFD1/45:59:90:5D:AE:C3+1/YES] unreachable duration for <private> is 1.801419973373413 seconds - reachable YES, primary resident: NO"

    let entry1 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: message1)
    let entry2 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: message2)

    // Both should normalize to the same message
    #expect(entry1.normalizedMessage == entry2.normalizedMessage)
    #expect(entry1.deduplicationKey == entry2.deduplicationKey)
  }

  /// Tests Phase 1 end-to-end: complex real-world message normalization
  @Test("Phase 1 end-to-end: Full normalization pipeline")
  func testPhase1EndToEnd() async throws {
    let message =
      "[A1B2C3D4-E5F6-7890-ABCD-EF1234567890/AA:BB:CC:DD:EE:FF+123/YES] Device failed with <HMFMessage: 0x813f244b0> Error Domain=HMErrorDomain Code=52 after 1.5 seconds at 2026-01-29 14:30:15.123456 - reachable YES"

    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
      message: message)

    let expected =
      "[<prefix>] Device failed with <obj> Error Domain=<domain> Code=<n> after <duration> at <timestamp> - reachable <bool>"

    #expect(entry.normalizedMessage == expected)
  }
}
