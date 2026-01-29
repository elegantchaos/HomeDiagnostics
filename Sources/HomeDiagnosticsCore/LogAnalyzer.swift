import Foundation

/// Analyzes collected log entries to produce statistical summaries.
///
/// Examines log entries to count occurrences by severity level, identify
/// problematic entries, and group entries by subsystem. Produces a
/// `LogAnalysis` struct containing all computed statistics.
public struct LogAnalyzer {
  /// The log entries to be analyzed.
  public let entries: [LogEntry]

  /// Creates a new log analyzer for the specified entries.
  ///
  /// - Parameter entries: The log entries to analyze.
  public init(entries: [LogEntry]) {
    self.entries = entries
  }

  /// Performs statistical analysis on the log entries.
  ///
  /// Counts entries by severity level (error, fault, warning), identifies
  /// problematic entries (errors, faults, or messages with failure keywords),
  /// and groups entries by subsystem.
  ///
  /// - Returns: Analysis results containing counts and categorizations.
  public func analyze() -> LogAnalysis {
    let totalCount = entries.count
    let errorCount = entries.filter { $0.level == .error }.count
    let faultCount = entries.filter { $0.level == .fault }.count
    let warningCount = entries.filter { $0.level == .warning }.count

    let problematicCount = entries.filter { $0.isProblematic }.count

    let subsystemCounts = Dictionary(grouping: entries) { $0.subsystem }
      .mapValues { $0.count }

    let problematicEntries = entries.filter { $0.isProblematic }

    // Note: Debug logging happens via global function in main executable
    // debug("Analysis complete: \(totalCount) total, \(errorCount) errors, \(faultCount) faults, \(warningCount) warnings")

    return LogAnalysis(
      totalEntries: totalCount,
      errorCount: errorCount,
      faultCount: faultCount,
      warningCount: warningCount,
      problematicCount: problematicCount,
      subsystemCounts: subsystemCounts,
      problematicEntries: problematicEntries,
      allEntries: entries
    )
  }
}
