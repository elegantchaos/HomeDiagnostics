import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Formatting Tests

@Suite("Formatting Tests")
struct FormattingTests {

  /// Tests that the UUID naming summary appears for logs with named UUIDs
  @Test("Output includes entity summary for known patterns")
  func testOutputEntitySummaryForNamedUUIDs() async throws {
    // Prepare sample log entries with extractable names
    let entries = [
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .error,
        message: "[Bank Street/Lamp/11112222-3333-4444-5555-666677778888] Device error"
      ),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .info,
        message: "[Plantation Road/Camera/9999AAAA-BBBB-CCCC-DDDD-EEEEFFFF0000] Motion detected"
      ),
    ]
    // Simulate the analyzer's entity extraction on each log entry
    var collector = EntityCollector()
    for entry in entries {
      collector.add(entry: entry)
    }
    var resolver = EntityResolver(annotations: collector.annotations)
    resolver.resolve()

    let analysis = LogAnalysis(
      totalEntries: entries.count,
      errorCount: 1,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 1,
      subsystemCounts: ["com.apple.HomeKit": entries.count],
      problematicEntries: entries.filter { $0.isProblematic },
      allEntries: entries,
      uuidNameResolver: resolver
    )
    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false
    )
    let output = formatter.format()
    // Assert that the summary is present and contains friendly home/device names
    #expect(output.localizedStandardContains("UUID NAMING SUMMARY"))
    #expect(output.localizedStandardContains("Bank Street"))
    #expect(output.localizedStandardContains("Lamp"))
    #expect(output.localizedStandardContains("Plantation Road"))
    #expect(output.localizedStandardContains("Camera"))
  }


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
      uuidNameResolver: EntityResolver(annotations: [])
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
