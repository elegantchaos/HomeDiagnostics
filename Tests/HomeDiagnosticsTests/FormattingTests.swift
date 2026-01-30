import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Formatting Tests

@Suite("Formatting Tests")
struct FormattingTests {

  // ...existing tests...

  /// Tests output-layer filtering with filter and errorsOnly jointly
  @Test("Format applies filter and errorsOnly together")
  func testOutputLayerFilterAndErrorsOnly() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .error,
        message: "Hue bridge error occurred!"),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .warning,
        message: "Pending Hue device."),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .info,
        message: "Normal operation started."),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .error,
        message: "Nanoleaf device error."),
    ]

    let analysis = LogAnalysis(
      totalEntries: entries.count,
      errorCount: 2,
      faultCount: 0,
      warningCount: 1,
      problematicCount: 3,
      subsystemCounts: ["com.apple.HomeKit": entries.count],
      problematicEntries: entries.filter { $0.isProblematic },
      allEntries: entries,
      uuidNamer: UUIDNamer()
    )

    // Should only include problematic entries with "hue" (case-insensitive)
    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: true,
      filter: "hue"
    )

    let output = formatter.format()
    // Only the .error and .warning entries with "hue" in the message should appear
    #expect(output.localizedStandardContains("Hue bridge error occurred!"))
    #expect(output.localizedStandardContains("Pending Hue device."))
    #expect(!output.localizedStandardContains("Normal operation started."))
    #expect(!output.localizedStandardContains("Nanoleaf device error."))
  }
}
