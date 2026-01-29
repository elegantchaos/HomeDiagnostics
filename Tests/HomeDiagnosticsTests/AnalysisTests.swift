import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Analysis Tests

@Suite("Analysis Tests")
struct AnalysisTests {

  /// Tests basic analysis statistics
  @Test("Analyze log entries correctly")
  func testBasicAnalysis() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Error 1"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Error 2"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.Home", process: "Home", level: .info,
        message: "Info 1"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .warning,
        message: "Warning 1"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .fault,
        message: "Fault 1"),
    ]

    let analyzer = LogAnalyzer(entries: entries)
    let analysis = analyzer.analyze()

    #expect(analysis.totalEntries == 5)
    #expect(analysis.errorCount == 2)
    #expect(analysis.warningCount == 1)
    #expect(analysis.faultCount == 1)
  }

  /// Tests problematic entry detection
  @Test("Detect problematic entries correctly")
  func testProblematicDetection() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Error message"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .fault,
        message: "Fault message"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Connection failed"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Request timeout"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Device unreachable"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Accessory not responding"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Normal message"),
    ]

    let analyzer = LogAnalyzer(entries: entries)
    let analysis = analyzer.analyze()

    #expect(analysis.problematicCount == 6)  // All except "Normal message"
  }

  /// Tests subsystem counting
  @Test("Count entries per subsystem")
  func testSubsystemCounting() async throws {
    let entries = [
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Message 1"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Message 2"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "Message 3"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.Home", process: "Home", level: .info,
        message: "Message 4"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.homed", process: "homed", level: .info,
        message: "Message 5"),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.homed", process: "homed", level: .info,
        message: "Message 6"),
    ]

    let analyzer = LogAnalyzer(entries: entries)
    let analysis = analyzer.analyze()

    #expect(analysis.subsystemCounts["com.apple.HomeKit"] == 3)
    #expect(analysis.subsystemCounts["com.apple.Home"] == 1)
    #expect(analysis.subsystemCounts["com.apple.homed"] == 2)
  }

  /// Tests empty entry list analysis
  @Test("Analyze empty entry list")
  func testEmptyAnalysis() async throws {
    let entries: [LogEntry] = []

    let analyzer = LogAnalyzer(entries: entries)
    let analysis = analyzer.analyze()

    #expect(analysis.totalEntries == 0)
    #expect(analysis.errorCount == 0)
    #expect(analysis.warningCount == 0)
    #expect(analysis.faultCount == 0)
    #expect(analysis.problematicCount == 0)
    #expect(analysis.subsystemCounts.isEmpty)
  }
}
