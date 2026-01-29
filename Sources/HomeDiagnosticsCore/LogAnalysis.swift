import Foundation

/// Statistical analysis results from log entry examination.
///
/// Contains counts and categorizations of log entries, including breakdowns
/// by severity level, subsystem, and problematic conditions.
public struct LogAnalysis: Sendable {
  /// The total number of log entries analyzed.
  public let totalEntries: Int

  /// The number of error-level log entries.
  public let errorCount: Int

  /// The number of fault-level log entries.
  public let faultCount: Int

  /// The number of warning-level log entries.
  public let warningCount: Int

  /// The number of entries identified as potentially problematic.
  ///
  /// Includes errors, faults, and messages containing failure keywords.
  public let problematicCount: Int

  /// The count of log entries grouped by subsystem identifier.
  public let subsystemCounts: [String: Int]

  /// Log entries that indicate problems or failure conditions.
  public let problematicEntries: [LogEntry]

  /// All log entries that were analyzed.
  public let allEntries: [LogEntry]

  /// Creates a new log analysis result.
  ///
  /// - Parameters:
  ///   - totalEntries: Total number of log entries.
  ///   - errorCount: Number of error-level entries.
  ///   - faultCount: Number of fault-level entries.
  ///   - warningCount: Number of warning-level entries.
  ///   - problematicCount: Number of potentially problematic entries.
  ///   - subsystemCounts: Counts by subsystem.
  ///   - problematicEntries: Entries identified as problematic.
  ///   - allEntries: All analyzed entries.
  public init(
    totalEntries: Int,
    errorCount: Int,
    faultCount: Int,
    warningCount: Int,
    problematicCount: Int,
    subsystemCounts: [String: Int],
    problematicEntries: [LogEntry],
    allEntries: [LogEntry]
  ) {
    self.totalEntries = totalEntries
    self.errorCount = errorCount
    self.faultCount = faultCount
    self.warningCount = warningCount
    self.problematicCount = problematicCount
    self.subsystemCounts = subsystemCounts
    self.problematicEntries = problematicEntries
    self.allEntries = allEntries
  }
}

/// Represents a group of duplicate log entries for deduplication display.
///
/// Contains a representative example of the log entry along with occurrence
/// counts and time range information.
public struct GroupedLogEntry: Sendable {
  /// A representative example (typically the first occurrence) of this log type.
  public let example: LogEntry

  /// The total number of occurrences of this log entry type.
  public let count: Int

  /// The timestamp of the first occurrence.
  public let firstSeen: Date

  /// The timestamp of the last occurrence.
  public let lastSeen: Date

  /// Creates a new grouped log entry.
  ///
  /// - Parameters:
  ///   - example: A representative log entry.
  ///   - count: Number of occurrences.
  ///   - firstSeen: Timestamp of first occurrence.
  ///   - lastSeen: Timestamp of last occurrence.
  public init(
    example: LogEntry,
    count: Int,
    firstSeen: Date,
    lastSeen: Date
  ) {
    self.example = example
    self.count = count
    self.firstSeen = firstSeen
    self.lastSeen = lastSeen
  }
}
