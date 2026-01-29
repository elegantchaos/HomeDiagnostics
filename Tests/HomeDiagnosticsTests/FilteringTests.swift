import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Filtering Tests

@Suite("Filtering Tests")
struct FilteringTests {

  /// Tests plain text filtering (case-insensitive)
  @Test("Filter with plain text (case-insensitive)")
  func testPlainTextFilter() async throws {
    let collector = LogCollector(
      timeInterval: "1d",
      includeDebug: false
    )

    let testCases = [
      ("hue", "Contains Hue device", true),
      ("HUE", "Contains Hue device", true),
      ("philips", "Contains Hue device", false),
      ("device", "Contains Hue device", true),
    ]

    for (pattern, text, shouldMatch) in testCases {
      let result = collector.matchesFilter(text, pattern: pattern)
      #expect(result == shouldMatch)
    }
  }

  /// Tests regex filtering
  @Test("Filter with regex pattern")
  func testRegexFilter() async throws {
    let collector = LogCollector(
      timeInterval: "1d",
      includeDebug: false
    )

    let testCases = [
      ("hue|philips", "Contains Hue device", true),
      ("hue|philips", "Contains Philips device", true),
      ("hue|philips", "Contains Nanoleaf device", false),
      ("timeout.*accessory", "Connection timeout to accessory", true),
      ("timeout.*accessory", "Accessory timeout error", false),
      ("\\d{4}-\\d{2}-\\d{2}", "Date: 2026-01-29", true),
    ]

    for (pattern, text, shouldMatch) in testCases {
      let result = collector.matchesFilter(text, pattern: pattern)
      #expect(result == shouldMatch)
    }
  }

  /// Tests invalid regex fallback to plain text
  @Test("Invalid regex falls back to plain text search")
  func testInvalidRegexFallback() async throws {
    let collector = LogCollector(
      timeInterval: "1d",
      includeDebug: false
    )

    // Invalid regex pattern (unbalanced bracket)
    let pattern = "[invalid"
    let text = "Contains [invalid in the text"

    let result = collector.matchesFilter(text, pattern: pattern)
    #expect(result == true)
  }

  /// Tests errors-only filtering
  @Test("Filter for errors, faults, and warnings only")
  func testErrorsOnlyFilter() async throws {
    let jsonInput = """
      [
        {
          "timestamp": "2026-01-29 14:30:15.123456+0000",
          "messageType": "Error",
          "eventMessage": "Error message",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        },
        {
          "timestamp": "2026-01-29 14:30:16.234567+0000",
          "messageType": "Info",
          "eventMessage": "Info message",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        },
        {
          "timestamp": "2026-01-29 14:30:17.345678+0000",
          "messageType": "Warning",
          "eventMessage": "Warning message",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        },
        {
          "timestamp": "2026-01-29 14:30:18.456789+0000",
          "messageType": "Fault",
          "eventMessage": "Fault message",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        },
        {
          "timestamp": "2026-01-29 14:30:19.567890+0000",
          "messageType": "Debug",
          "eventMessage": "Debug message",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        }
      ]
      """

    let collector = LogCollector(
      timeInterval: "1d",
      includeDebug: false,
      errorsOnly: true
    )

    let entries = collector.parseJSONLogOutput(jsonInput, subsystem: "com.apple.HomeKit")

    #expect(entries.count == 3)  // Error, Warning, Fault only
    #expect(entries[0].level == .error)
    #expect(entries[1].level == .warning)
    #expect(entries[2].level == .fault)
  }

  /// Tests combined filter and errors-only
  @Test("Filter with text pattern and errors-only")
  func testCombinedFilters() async throws {
    let jsonInput = """
      [
        {
          "timestamp": "2026-01-29 14:30:15.123456+0000",
          "messageType": "Error",
          "eventMessage": "Hue device error",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        },
        {
          "timestamp": "2026-01-29 14:30:16.234567+0000",
          "messageType": "Info",
          "eventMessage": "Hue device info",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        },
        {
          "timestamp": "2026-01-29 14:30:17.345678+0000",
          "messageType": "Error",
          "eventMessage": "Nanoleaf error",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        }
      ]
      """

    let collector = LogCollector(
      timeInterval: "1d",
      includeDebug: false,
      filter: "hue",
      errorsOnly: true
    )

    let entries = collector.parseJSONLogOutput(jsonInput, subsystem: "com.apple.HomeKit")

    #expect(entries.count == 1)  // Only "Hue device error"
    #expect(entries[0].message == "Hue device error")
  }
}
