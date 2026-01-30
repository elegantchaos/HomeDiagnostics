import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Log Parsing Tests

@Suite("Log Parsing Tests")
struct LogParsingTests {

  /// Tests parsing valid JSON log output
  @Test("Parse valid JSON log entries")
  func testParseValidJSON() async throws {
    let collector = makeTestCollector(timeInterval: "1d", includeDebug: false)

    let jsonInput = """
      [
        {
          "timestamp": "2026-01-29 14:30:15.123456+0000",
          "messageType": "Error",
          "eventMessage": "Test error message",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/System/Library/PrivateFrameworks/HomeKit.framework/homed"
        }
      ]
      """

    let entries = try collector.parseJSONEntries(jsonInput, subsystem: "com.apple.HomeKit")

    #expect(entries.count == 1)
    #expect(entries[0].message == "Test error message")
    #expect(entries[0].level == .error)
    #expect(entries[0].subsystem == "com.apple.HomeKit")
    #expect(entries[0].process == "homed")
  }

  /// Tests parsing multiple log entries with different types
  @Test("Parse multiple log entries with different message types")
  func testParseMultipleEntries() async throws {
    let collector = makeTestCollector(timeInterval: "1d", includeDebug: false)

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
          "subsystem": "com.apple.Home",
          "processImagePath": "/Applications/Home.app/Contents/MacOS/Home"
        },
        {
          "timestamp": "2026-01-29 14:30:17.345678+0000",
          "messageType": "Warning",
          "eventMessage": "Warning message",
          "subsystem": "com.apple.homed",
          "processImagePath": "/usr/libexec/homed"
        }
      ]
      """

    let entries = try collector.parseJSONEntries(jsonInput, subsystem: "com.apple.HomeKit")

    #expect(entries.count == 3)
    #expect(entries[0].level == .error)
    #expect(entries[1].level == .info)
    #expect(entries[2].level == .warning)
  }

  /// Tests mapping messageType to LogLevel correctly
  @Test("Map messageType to LogLevel correctly")
  func testMessageTypeMapping() async throws {
    let collector = makeTestCollector(timeInterval: "1d", includeDebug: false)

    let testCases: [(messageType: String, expectedLevel: LogLevel)] = [
      ("Debug", .debug),
      ("Info", .info),
      ("Default", .info),  // Default maps to Info
      ("Error", .error),
      ("Fault", .fault),
    ]

    for testCase in testCases {
      let jsonInput = """
        [
          {
            "timestamp": "2026-01-29 14:30:15.123456+0000",
            "messageType": "\(testCase.messageType)",
            "eventMessage": "Test message",
            "subsystem": "com.apple.HomeKit",
            "processImagePath": "/usr/libexec/homed"
          }
        ]
        """

      let entries = try collector.parseJSONEntries(jsonInput, subsystem: "com.apple.HomeKit")

      #expect(entries.count == 1)
      #expect(entries[0].level == testCase.expectedLevel)
    }
  }

  /// Tests parsing empty JSON array
  @Test("Parse empty JSON array")
  func testParseEmptyJSON() async throws {
    let entries = try parseEntries("[]", subsystem: "com.apple.HomeKit")
    #expect(entries.isEmpty)
  }

  /// Tests parsing malformed JSON
  @Test("Parse malformed JSON returns empty array")
  func testParseMalformedJSON() async throws {
    let entries = try parseEntries("{not valid json", subsystem: "com.apple.HomeKit")
    #expect(entries.isEmpty)
  }

  /// Tests parsing JSON with missing required fields
  @Test("Parse JSON with missing fields skips invalid entries")
  func testParseMissingFields() async throws {
    let jsonInput = """
      [
        {
          "timestamp": "2026-01-29 14:30:15.123456+0000",
          "messageType": "Error",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        }
      ]
      """
    let entries = try parseEntries(jsonInput, subsystem: "com.apple.HomeKit")
    #expect(entries.isEmpty)
  }

  /// Tests date parsing with correct timestamp format
  @Test("Parse timestamp correctly")
  func testTimestampParsing() async throws {
    let jsonInput = """
      [
        {
          "timestamp": "2026-01-29 14:30:15.123456+0000",
          "messageType": "Info",
          "eventMessage": "Test message",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        }
      ]
      """
    let entries = try parseEntries(jsonInput, subsystem: "com.apple.HomeKit")
    #expect(entries.count == 1)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    let expectedDate = formatter.date(from: "2026-01-29 14:30:15.123456+0000")
    #expect(entries[0].timestamp == expectedDate)
  }

  /// Tests process name extraction from path
  @Test("Extract process name from path correctly")
  func testProcessNameExtraction() async throws {
    let testCases = [
      ("/usr/libexec/homed", "homed"),
      ("/Applications/Home.app/Contents/MacOS/Home", "Home"),
      ("/System/Library/PrivateFrameworks/HomeKit.framework/homed", "homed"),
    ]
    for (path, expectedName) in testCases {
      let jsonInput = """
        [
          {
            "timestamp": "2026-01-29 14:30:15.123456+0000",
            "messageType": "Info",
            "eventMessage": "Test message",
            "subsystem": "com.apple.HomeKit",
            "processImagePath": "\(path)"
          }
        ]
        """
      let entries = try parseEntries(jsonInput, subsystem: "com.apple.HomeKit")
      #expect(entries.count == 1)
      #expect(entries[0].process == expectedName)
    }
  }
}
