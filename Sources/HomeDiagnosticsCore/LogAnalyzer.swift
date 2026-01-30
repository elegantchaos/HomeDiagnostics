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
    let batchSize = 500
    var batch: [LogEntry] = []
    var batchTasks: [Task<(UUIDNamer, [LogEntry], Int, Int, Int, Int, [String: Int]), Never>] = []
    
    func processBatch(_ entries: [LogEntry]) -> Task<(UUIDNamer, [LogEntry], Int, Int, Int, Int, [String: Int]), Never> {
      Task {
        var uuidNamer = UUIDNamer()
        var allEntries: [LogEntry] = []
        var totalCount = 0
        var errorCount = 0
        var faultCount = 0
        var warningCount = 0
        var subsystemCounts: [String: Int] = [:]
        for entry in entries {
          uuidNamer.extractNames(from: entry.message)
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
        return (uuidNamer, allEntries, totalCount, errorCount, faultCount, warningCount, subsystemCounts)
      }
    }
    
    for try await entry in stream {
      batch.append(entry)
      if batch.count == batchSize {
        batchTasks.append(processBatch(batch))
        batch = []
      }
    }
    if !batch.isEmpty {
      batchTasks.append(processBatch(batch))
    }
    
    var mergedUUIDNamer = UUIDNamer()
    var mergedAllEntries: [LogEntry] = []
    var mergedTotalCount = 0
    var mergedErrorCount = 0
    var mergedFaultCount = 0
    var mergedWarningCount = 0
    var mergedSubsystemCounts: [String: Int] = [:]
    
    for task in batchTasks {
      let (uuidNamer, allEntries, totalCount, errorCount, faultCount, warningCount, subsystemCounts) = await task.value
      mergedUUIDNamer.merge(with: uuidNamer)
      mergedAllEntries.append(contentsOf: allEntries)
      mergedTotalCount += totalCount
      mergedErrorCount += errorCount
      mergedFaultCount += faultCount
      mergedWarningCount += warningCount
      for (subsystem, count) in subsystemCounts {
        mergedSubsystemCounts[subsystem, default: 0] += count
      }
    }
    
    mergedUUIDNamer.associateHomeNames()
    let problematicEntries = mergedAllEntries.filter { $0.isProblematic }
    return LogAnalysis(
      totalEntries: mergedTotalCount,
      errorCount: mergedErrorCount,
      faultCount: mergedFaultCount,
      warningCount: mergedWarningCount,
      problematicCount: problematicEntries.count,
      subsystemCounts: mergedSubsystemCounts,
      problematicEntries: problematicEntries,
      allEntries: mergedAllEntries,
      uuidNamer: mergedUUIDNamer
    )
  }
}
