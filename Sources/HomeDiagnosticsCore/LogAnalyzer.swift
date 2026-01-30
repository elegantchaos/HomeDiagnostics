/// Analyzes collected log entries to produce statistical summaries.
///
/// Examines log entries to count occurrences by severity level, identify
/// problematic entries, and group entries by subsystem. Produces a
/// `LogAnalysis` struct containing all computed statistics.
import Foundation

public struct LogAnalyzer {
  public let stream: AsyncThrowingStream<LogEntry, Error>

  public init(stream: AsyncThrowingStream<LogEntry, Error>) {
    self.stream = stream
  }

  public func analyzeStream() async throws -> LogAnalysis {
    let batchSize = 500
    var batch: [LogEntry] = []
    var batchTasks: [Task<(EntityCollector, [LogEntry], Int, Int, Int, Int, [String: Int]), Never>] = []

    func processBatch(_ entries: [LogEntry]) -> Task<(EntityCollector, [LogEntry], Int, Int, Int, Int, [String: Int]), Never> {
      Task {
        var collector = EntityCollector()
        var allEntries: [LogEntry] = []
        var totalCount = 0
        var errorCount = 0
        var faultCount = 0
        var warningCount = 0
        var subsystemCounts: [String: Int] = [:]
        for entry in entries {
          collector.add(entry: entry)
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
        return (collector, allEntries, totalCount, errorCount, faultCount, warningCount, subsystemCounts)
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

    var allCollectors: [EntityCollector] = []
    var mergedAllEntries: [LogEntry] = []
    var mergedTotalCount = 0
    var mergedErrorCount = 0
    var mergedFaultCount = 0
    var mergedWarningCount = 0
    var mergedSubsystemCounts: [String: Int] = [:]

    for task in batchTasks {
      let (collector, allEntries, totalCount, errorCount, faultCount, warningCount, subsystemCounts) = await task.value
      allCollectors.append(collector)
      mergedAllEntries.append(contentsOf: allEntries)
      mergedTotalCount += totalCount
      mergedErrorCount += errorCount
      mergedFaultCount += faultCount
      mergedWarningCount += warningCount
      for (subsystem, count) in subsystemCounts {
        mergedSubsystemCounts[subsystem, default: 0] += count
      }
    }

    // Merge all annotations from all collectors
    let allAnnotations = allCollectors.flatMap { $0.annotations }
    let nameResolver = EntityResolver(annotations: allAnnotations)
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
      uuidNameResolver: nameResolver
    )
  }
}
