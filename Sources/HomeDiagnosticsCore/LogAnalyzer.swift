import Foundation

/// Analyzes collected log entries to produce statistical summaries.
///
/// Examines log entries to count occurrences by severity level, identify
/// problematic entries, and group entries by subsystem. Produces a
/// `LogAnalysis` struct containing all computed statistics.
public struct LogAnalyzer {
  /// The log entries to be analyzed.
  public let stream: AsyncThrowingStream<LogEntry, Error>

  /// Creates a new log analyzer to analyze entries from the given stream.
  ///
  /// - Parameter stream: An async stream of log entries.
  public init(stream: AsyncThrowingStream<LogEntry, Error>) {
    self.stream = stream
  }


  /// Performs statistical analysis by consuming a stream of log entries.
  ///
  /// Iterates the async stream, updating counts and UUID naming incrementally,
  /// and accumulates entries for formatting and grouping.
  ///
  /// - Returns: Analysis results containing counts and categorizations.
  public func analyzeStream() async throws -> LogAnalysis {
    var uuidNamer = UUIDNamer()

    var allEntries: [LogEntry] = []
    var totalCount = 0
    var errorCount = 0
    var faultCount = 0
    var warningCount = 0
    var subsystemCounts: [String: Int] = [:]

    for try await entry in stream {
      // Extract names as we go
      uuidNamer.extractNames(from: entry.message)

      // Accumulate
      allEntries.append(entry)
      totalCount += 1
      subsystemCounts[entry.subsystem, default: 0] += 1

      switch entry.level {
      case .error: errorCount += 1
      case .fault: faultCount += 1
      case .warning: warningCount += 1
      default: break
      }
    }

    // Associate home names after collecting all messages
    uuidNamer.associateHomeNames()

    let problematicEntries = allEntries.filter { $0.isProblematic }

    return LogAnalysis(
      totalEntries: totalCount,
      errorCount: errorCount,
      faultCount: faultCount,
      warningCount: warningCount,
      problematicCount: problematicEntries.count,
      subsystemCounts: subsystemCounts,
      problematicEntries: problematicEntries,
      allEntries: allEntries,
      uuidNamer: uuidNamer
    )
  }
}
