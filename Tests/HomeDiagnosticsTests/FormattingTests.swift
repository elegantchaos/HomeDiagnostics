import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Formatting Tests

@Suite("Formatting Tests")
struct FormattingTests {

  /// Tests compact date formatting
  @Test("Format date compactly")
  func testCompactDateFormat() async throws {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let date = formatter.date(from: "2026-01-29 14:30:15")!

    let analysis = LogAnalysis(
      totalEntries: 0,
      errorCount: 0,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 0,
      subsystemCounts: [:],
      problematicEntries: [],
      allEntries: []
    )

    let _ = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false
    )

    // Access the private method via the output
    let entry = LogEntry(
      timestamp: date, subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Test")

    let analysisWithEntry = LogAnalysis(
      totalEntries: 1,
      errorCount: 0,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 0,
      subsystemCounts: ["com.apple.HomeKit": 1],
      problematicEntries: [],
      allEntries: [entry]
    )

    let formatterWithEntry = OutputFormatter(
      analysis: analysisWithEntry,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false
    )

    let output = formatterWithEntry.format()

    // Verify compact date format appears (MM/dd HH:mm)
    #expect(output.contains("01/29 14:30"))
  }

  /// Tests subsystem formatting removes "com.apple." prefix
  @Test("Format subsystem removes com.apple. prefix")
  func testSubsystemFormatting() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Test message")

    let analysis = LogAnalysis(
      totalEntries: 1,
      errorCount: 0,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 0,
      subsystemCounts: ["com.apple.HomeKit": 1],
      problematicEntries: [],
      allEntries: [entry]
    )

    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false
    )

    let output = formatter.format()

    // Verify shortened subsystem name appears
    #expect(output.contains("[HomeKit]"))
    #expect(!output.contains("[com.apple.HomeKit]"))
  }

  /// Tests Info level is hidden in metadata
  @Test("Hide Info level in metadata")
  func testInfoLevelHidden() async throws {
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "Info message")

    let analysis = LogAnalysis(
      totalEntries: 1,
      errorCount: 0,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 0,
      subsystemCounts: ["com.apple.HomeKit": 1],
      problematicEntries: [],
      allEntries: [entry]
    )

    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false
    )

    let output = formatter.format()

    // Verify Info level is not shown
    #expect(!output.contains("[Info]"))
  }

  /// Tests non-Info levels are shown in metadata
  @Test("Show non-Info levels in metadata")
  func testNonInfoLevelsShown() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Error message"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .warning,
        message: "Warning message"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .fault,
        message: "Fault message"),
    ]

    let analysis = LogAnalysis(
      totalEntries: 3,
      errorCount: 1,
      faultCount: 1,
      warningCount: 1,
      problematicCount: 3,
      subsystemCounts: ["com.apple.HomeKit": 3],
      problematicEntries: entries,
      allEntries: entries
    )

    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false
    )

    let output = formatter.format()

    // Verify levels are shown
    #expect(output.contains("[Error]"))
    #expect(output.contains("[Warning]"))
    #expect(output.contains("[Fault]"))
  }

  /// Tests errors-only skips PROBLEMATIC ENTRIES section
  @Test("Errors-only mode skips PROBLEMATIC ENTRIES section")
  func testErrorsOnlySkipsProblematicSection() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Error message")
    ]

    let analysis = LogAnalysis(
      totalEntries: 1,
      errorCount: 1,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 1,
      subsystemCounts: ["com.apple.HomeKit": 1],
      problematicEntries: entries,
      allEntries: entries
    )

    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: true
    )

    let output = formatter.format()

    // Verify PROBLEMATIC ENTRIES section is not present
    #expect(!output.contains("PROBLEMATIC ENTRIES"))
  }
}
