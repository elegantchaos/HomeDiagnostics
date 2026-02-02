import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Integration Tests

@Suite("Integration Tests")
struct IntegrationTests {

  /// Tests end-to-end with string log input
  @Test("End-to-end test with string log input")
  func testEndToEndWithStringLogInput() async throws {
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
          "eventMessage": "Normal operation",
          "subsystem": "com.apple.HomeKit",
          "processImagePath": "/usr/libexec/homed"
        }
      ]
      """

    let logInput = StringLogInput(json: jsonInput, name: "com.apple.HomeKit")
    let collector = LogCollector()

    var entries: [LogEntry] = []
    for try await entry in collector.streamEntries(from: logInput) {
      entries.append(entry)
    }

    #expect(entries.count == 2)
    #expect(entries[0].level == .error)
    #expect(entries[1].level == .info)
  }

  /// Tests loading sample_logs.json resource file
  @Test("Load and parse sample_logs.json resource")
  func testLoadSampleLogsResource() async throws {
    // Try multiple approaches to find the resource
    var resourceURL: URL?

    // Try Bundle.module first
    resourceURL = Bundle.module.url(
      forResource: "sample_logs", withExtension: "json", subdirectory: "Resources")

    // If not found, try without subdirectory
    if resourceURL == nil {
      resourceURL = Bundle.module.url(forResource: "sample_logs", withExtension: "json")
    }

    guard let url = resourceURL else {
      Issue.record("sample_logs.json resource file not found in Bundle.module")
      return
    }

    let jsonData = try Data(contentsOf: url)
    let jsonString = String(data: jsonData, encoding: .utf8)!

    let logInput = StringLogInput(json: jsonString, name: "com.apple.HomeKit")
    let collector = LogCollector()

    var entries: [LogEntry] = []
    for try await entry in collector.streamEntries(from: logInput) {
      entries.append(entry)
    }

    // Verify we parsed the sample data correctly
    #expect(entries.count == 10)

    // Verify different log levels are present
    let errorCount = entries.filter { $0.level == .error }.count
    let infoCount = entries.filter { $0.level == .info }.count
    let warningCount = entries.filter { $0.level == .warning }.count
    let faultCount = entries.filter { $0.level == .fault }.count
    let debugCount = entries.filter { $0.level == .debug }.count

    #expect(errorCount == 4)  // Lines 4, 25, 53, 67
    #expect(infoCount == 3)  // Lines 11, 19, 61
    #expect(warningCount == 1)  // Line 33
    #expect(faultCount == 1)  // Line 40
    #expect(debugCount == 1)  // Line 47
  }
}
