import Foundation
import Testing

@testable import HomeDiagnosticsCore

/// Tests for JSON stream parsing functionality.
///
/// Verifies that the streaming JSON parser correctly handles the unified logging
/// system's JSON array format when reading line-by-line.
@Suite("JSON Stream Parser Tests")
struct JSONStreamParserTests {

  /// Tests parsing complete JSON objects.
  @Test("Parse complete JSON objects")
  func testParseCompleteObjects() async throws {
    let collector = LogCollector<StringLogInput>()

    // Two complete JSON objects as they would appear after stream parsing
    let jsonObjects = [
      """
      {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"Info","eventMessage":"Test message 1","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """,
      """
      {"timestamp":"2026-01-30 10:01:00.000000+0000","messageType":"Error","eventMessage":"Test message 2","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """,
    ]

    var entries: [LogEntry] = []
    let decoder = collector.makeEntryDecoder()
    for jsonString in jsonObjects {
      if let entry = try collector.parseJSONEntry(jsonString, decoder: decoder) {
        entries.append(entry)
      }
    }

    #expect(entries.count == 2)
    #expect(entries[0].message == "Test message 1")
    #expect(entries[0].level == .info)
    #expect(entries[1].message == "Test message 2")
    #expect(entries[1].level == .error)
  }

  /// Tests parseJSONObject with valid JSON object string.
  @Test("Parse single JSON object")
  func testParseSingleJSONObject() async throws {
    let collector = LogCollector<StringLogInput>()

    let jsonString = """
      {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"Info","eventMessage":"Test message","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """

    let decoder = collector.makeEntryDecoder()
    let entry = try collector.parseJSONEntry(jsonString, decoder: decoder)

    #expect(entry != nil)
    #expect(entry?.message == "Test message")
    #expect(entry?.subsystem == "com.apple.HomeKit")
    #expect(entry?.process == "test")
    #expect(entry?.level == .info)
  }

  /// Tests parseJSONObject with different message types.
  @Test("Parse different log levels")
  func testParseLogLevels() async throws {
    let collector = LogCollector<StringLogInput>()

    let testCases: [(messageType: String, expectedLevel: LogLevel)] = [
      ("Debug", .debug),
      ("Info", .info),
      ("Default", .default),
      ("Error", .error),
      ("Fault", .fault),
      ("Warning", .warning),
    ]

    for testCase in testCases {
      let jsonString = """
        {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"\(testCase.messageType)","eventMessage":"Test","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
        """

      let decoder = collector.makeEntryDecoder()
      let entry = try collector.parseJSONEntry(jsonString, decoder: decoder)
      #expect(entry?.level == testCase.expectedLevel)
    }
  }

  /// Tests that invalid JSON returns nil.
  @Test("Handle invalid JSON gracefully")
  func testInvalidJSON() async throws {
    let collector = LogCollector<StringLogInput>()

    let invalidJSON = """
      {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"Info","eventMessage":"Test"
      """

    let decoder = collector.makeEntryDecoder()
    #expect(throws: DecodingError.self) {
      try collector.parseJSONEntry(invalidJSON, decoder: decoder)
    }
  }

  /// Tests that missing required fields returns nil.
  @Test("Handle missing fields")
  func testMissingFields() async throws {
    let collector = LogCollector<StringLogInput>()

    let missingTimestamp = """
      {"messageType":"Info","eventMessage":"Test","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """

    let missingMessage = """
      {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"Info","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """

    let decoder = collector.makeEntryDecoder()
    #expect(throws: DecodingError.self) { try collector.parseJSONEntry(missingTimestamp, decoder: decoder) }
    #expect(throws: DecodingError.self) { try collector.parseJSONEntry(missingMessage, decoder: decoder) }
  }

  /// Tests parsing timestamp format correctly.
  @Test("Parse timestamp format")
  func testTimestampParsing() async throws {
    let collector = LogCollector<StringLogInput>()

    let jsonString = """
      {"timestamp":"2026-01-30 14:25:34.202233+0000","messageType":"Info","eventMessage":"Test","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """

    let decoder = collector.makeEntryDecoder()
    let entry = try collector.parseJSONEntry(jsonString, decoder: decoder)

    #expect(entry != nil)

    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: entry!.timestamp
    )

    #expect(components.year == 2026)
    #expect(components.month == 1)
    #expect(components.day == 30)
    #expect(components.hour == 14)
    #expect(components.minute == 25)
    #expect(components.second == 34)
  }

  /// Tests extracting process name from full path.
  @Test("Extract process name from path")
  func testProcessNameExtraction() async throws {
    let collector = LogCollector<StringLogInput>()

    let testCases: [(path: String, expectedName: String)] = [
      ("/usr/bin/homed", "homed"),
      ("/System/Library/PrivateFrameworks/Home.framework/Home", "Home"),
      ("HomeKit", "HomeKit"),
    ]

    for testCase in testCases {
      let jsonString = """
        {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"Info","eventMessage":"Test","subsystem":"com.apple.HomeKit","processImagePath":"\(testCase.path)"}
        """

      let decoder = collector.makeEntryDecoder()
      let entry = try collector.parseJSONEntry(jsonString, decoder: decoder)
      #expect(entry?.process == testCase.expectedName)
    }
  }

  /// Tests that JSON with nested objects is handled correctly.
  @Test("Parse JSON with nested objects")
  func testNestedObjects() async throws {
    let collector = LogCollector<StringLogInput>()

    // Message field might contain JSON-like content
    let jsonString = """
      {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"Info","eventMessage":"Data: {nested: value}","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """

    let decoder = collector.makeEntryDecoder()
    let entry = try collector.parseJSONEntry(jsonString, decoder: decoder)
    #expect(entry != nil)
    #expect(entry?.message == "Data: {nested: value}")
  }

  /// Tests that strings with escaped quotes are handled correctly.
  @Test("Parse strings with escaped quotes")
  func testEscapedQuotes() async throws {
    let collector = LogCollector<StringLogInput>()

    let jsonString = """
      {"timestamp":"2026-01-30 10:00:00.000000+0000","messageType":"Info","eventMessage":"Message with \\"quotes\\"","subsystem":"com.apple.HomeKit","processImagePath":"/usr/bin/test"}
      """

    let decoder = collector.makeEntryDecoder()
    let entry = try collector.parseJSONEntry(jsonString, decoder: decoder)
    #expect(entry != nil)
    #expect(entry?.message.contains("quotes") == true)
  }
}
