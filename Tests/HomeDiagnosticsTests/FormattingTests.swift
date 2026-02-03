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
      errorsOnly: false,
      useColors: false
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
      filter: "hue",
      useColors: false
    )

    let output = formatter.format()
    // Only the .error and .warning entries with "hue" in the message should appear
    #expect(output.localizedStandardContains("Hue bridge error occurred!"))
    #expect(output.localizedStandardContains("Pending Hue device."))
    #expect(!output.localizedStandardContains("Normal operation started."))
    #expect(!output.localizedStandardContains("Nanoleaf device error."))
  }

  /// Tests that deduplication summary includes both approaches
  @Test("Deduplication summary reports both counters")
  func testDeduplicationSummaryCounters() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        category: "HMHomeManager",
        formatString: "updateHomes(timeout:) found homes [%{public}s]",
        level: .info,
        message: "updateHomes(timeout:) found homes [ABC]"
      ),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        category: "HMHomeManager",
        formatString: "updateHomes(timeout:) found homes [%{public}s]",
        level: .info,
        message: "updateHomes(timeout:) found homes [DEF]"
      ),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .error,
        message: "Device [4A8856A0-38E3-5AF4-AC52-8390FFE944A2] failed"
      ),
    ]

    let analysis = LogAnalysis(
      totalEntries: entries.count,
      errorCount: 1,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 1,
      subsystemCounts: ["com.apple.HomeKit": entries.count],
      problematicEntries: entries.filter { $0.isProblematic },
      allEntries: entries,
      uuidNameResolver: EntityResolver(annotations: [])
    )

    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: true,
      errorsOnly: false,
      useColors: false
    )

    let output = formatter.format()
    #expect(output.localizedStandardContains("Format-string dedupe:"))
    #expect(output.localizedStandardContains("normalized dedupe:"))
  }

  /// Tests minimum occurrence filtering in deduplicated output
  @Test("Minimum occurrence filter hides low-frequency entries")
  func testMinimumOccurrenceFiltering() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .info,
        message: "Timeout after 5 seconds"
      ),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .info,
        message: "Timeout after 10 seconds"
      ),
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .error,
        message: "Single failure"
      ),
    ]

    let analysis = LogAnalysis(
      totalEntries: entries.count,
      errorCount: 1,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 1,
      subsystemCounts: ["com.apple.HomeKit": entries.count],
      problematicEntries: entries.filter { $0.isProblematic },
      allEntries: entries,
      uuidNameResolver: EntityResolver(annotations: [])
    )

    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: true,
      errorsOnly: false,
      minimumOccurrence: 2,
      useColors: false
    )

    let output = formatter.format()
    #expect(output.localizedStandardContains("Timeout after 5 seconds"))
    #expect(!output.localizedStandardContains("Single failure"))
  }

  /// Tests that plain output does not include ANSI escape codes
  @Test("Plain output omits ANSI codes")
  func testPlainOutputOmitsAnsiCodes() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .error,
        message: "Hue bridge error occurred!"
      )
    ]
    let analysis = LogAnalysis(
      totalEntries: entries.count,
      errorCount: 1,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 1,
      subsystemCounts: ["com.apple.HomeKit": entries.count],
      problematicEntries: entries,
      allEntries: entries,
      uuidNameResolver: EntityResolver(annotations: [])
    )
    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: true,
      errorsOnly: false,
      useColors: false
    )

    let output = formatter.format()
    #expect(!output.contains("\u{001B}["))
  }

  /// Tests that category appears in metadata
  @Test("Output includes category in metadata")
  func testCategoryInMetadata() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        category: "HMHomeManager",
        level: .info,
        message: "Starting home manager"
      )
    ]
    let analysis = LogAnalysis(
      totalEntries: entries.count,
      errorCount: 0,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 0,
      subsystemCounts: ["com.apple.HomeKit": entries.count],
      problematicEntries: [],
      allEntries: entries,
      uuidNameResolver: EntityResolver(annotations: [])
    )
    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false,
      useColors: false
    )

    let output = formatter.format()
    #expect(output.localizedStandardContains("[HMHomeManager]"))
  }

  /// Tests that default-level entries omit the level tag
  @Test("Default level omits tag")
  func testDefaultLevelOmitsTag() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(),
        subsystem: "com.apple.HomeKit",
        process: "homed",
        level: .default,
        message: "Default level message"
      )
    ]
    let analysis = LogAnalysis(
      totalEntries: entries.count,
      errorCount: 0,
      faultCount: 0,
      warningCount: 0,
      problematicCount: 0,
      subsystemCounts: ["com.apple.HomeKit": entries.count],
      problematicEntries: [],
      allEntries: entries,
      uuidNameResolver: EntityResolver(annotations: [])
    )
    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: false,
      deduplicate: false,
      errorsOnly: false,
      useColors: false
    )

    let output = formatter.format()
    #expect(!output.localizedStandardContains("[Default]"))
  }
}
