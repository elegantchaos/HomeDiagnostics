import ArgumentParser
import Foundation

/// Command-line tool for diagnosing Apple Home and HomeKit issues
@main
struct HomeDiagnostics: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "home-diagnostics",
    abstract: "Collect and analyze Apple Home and HomeKit logs",
    version: "1.0.0"
  )

  @Option(name: .shortAndLong, help: "Number of days to look back (default: 14)")
  var days: Int = 14

  @Flag(name: .long, help: "Include debug-level logs (verbose)")
  var debug: Bool = false

  @Option(name: .shortAndLong, help: "Output file path (default: stdout)")
  var output: String?

  @Flag(name: .long, help: "Filter for Hue-related entries only")
  var hueOnly: Bool = false

  @Flag(name: .long, help: "Show summary statistics")
  var summary: Bool = false

  mutating func run() throws {
    print("HomeDiagnostics - Apple Home Log Analyzer")
    print("==========================================\n")

    let collector = LogCollector(
      daysBack: days,
      includeDebug: debug,
      hueOnly: hueOnly
    )

    print("Collecting logs from the last \(days) day(s)...")
    if debug {
      print("(Including debug-level logs - this may take a while)")
    }
    print()

    let logs = try collector.collectLogs()

    let analyzer = LogAnalyzer(entries: logs)
    let analysis = analyzer.analyze()

    let formatter = OutputFormatter(
      analysis: analysis,
      showSummary: summary
    )

    let output = formatter.format()

    if let outputPath = self.output {
      try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
      print("Results written to: \(outputPath)")
    } else {
      print(output)
    }
  }
}

/// Collects logs from the macOS unified logging system
struct LogCollector {
  /// Number of days to look back
  let daysBack: Int

  /// Whether to include debug-level logs
  let includeDebug: Bool

  /// Whether to filter for Hue-related entries only
  let hueOnly: Bool

  /// Collects Home and HomeKit logs
  func collectLogs() throws -> [LogEntry] {
    var allEntries: [LogEntry] = []

    // Collect from different subsystems
    let subsystems = [
      "com.apple.Home",
      "com.apple.HomeKit",
      "com.apple.homed",
    ]

    for subsystem in subsystems {
      let entries = try collectLogsForSubsystem(subsystem)
      allEntries.append(contentsOf: entries)
    }

    // Sort by timestamp
    allEntries.sort { $0.timestamp < $1.timestamp }

    return allEntries
  }

  /// Collects logs for a specific subsystem
  private func collectLogsForSubsystem(_ subsystem: String) throws -> [LogEntry] {
    let timeInterval = "\(daysBack)d"
    let levelPredicate = includeDebug ? "--info --debug" : "--info"

    // Build the log command
    let command = """
      log show --style syslog --last \(timeInterval) \(levelPredicate) \
      --predicate 'subsystem == "\(subsystem)"' 2>&1
      """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["sh", "-c", command]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
      return []
    }

    return parseLogOutput(output, subsystem: subsystem)
  }

  /// Parses log output into structured entries
  private func parseLogOutput(_ output: String, subsystem: String) -> [LogEntry] {
    let lines = output.components(separatedBy: .newlines)
    var entries: [LogEntry] = []

    for line in lines {
      guard !line.isEmpty else { continue }

      // Skip header lines
      if line.hasPrefix("Timestamp") || line.hasPrefix("---") {
        continue
      }

      // Parse syslog format: timestamp process[pid] (subsystem): message
      let entry = parseLogLine(line, subsystem: subsystem)

      // Filter for Hue if requested
      if hueOnly {
        if entry.containsHueReference {
          entries.append(entry)
        }
      } else {
        entries.append(entry)
      }
    }

    return entries
  }

  /// Parses a single log line
  private func parseLogLine(_ line: String, subsystem: String) -> LogEntry {
    // Simple parsing - extract timestamp, level, and message
    var timestamp = Date()
    var level = LogLevel.info
    let process = ""
    let message = line

    // Try to extract timestamp (first component before a space)
    let components = line.components(separatedBy: " ")
    if components.count >= 3 {
      // Format: YYYY-MM-DD HH:MM:SS.mmm...
      let dateString = components[0] + " " + components[1]
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      if let parsed = formatter.date(from: String(dateString.prefix(19))) {
        timestamp = parsed
      }
    }

    // Detect log level from message content
    if line.localizedStandardContains("error") {
      level = .error
    } else if line.localizedStandardContains("warning") {
      level = .warning
    } else if line.localizedStandardContains("debug") {
      level = .debug
    } else if line.localizedStandardContains("fault") {
      level = .fault
    }

    return LogEntry(
      timestamp: timestamp,
      subsystem: subsystem,
      process: process,
      level: level,
      message: message
    )
  }
}

/// Represents a single log entry
struct LogEntry {
  /// When the log entry was created
  let timestamp: Date

  /// The subsystem that generated the log
  let subsystem: String

  /// The process that generated the log
  let process: String

  /// The log level
  let level: LogLevel

  /// The log message
  let message: String

  /// Whether this entry contains a reference to Hue devices
  var containsHueReference: Bool {
    let lowercased = message.lowercased()
    return lowercased.contains("hue")
      || lowercased.contains("philips")
      || lowercased.contains("bridge")
  }

  /// Whether this entry indicates an error or problem
  var isProblematic: Bool {
    level == .error || level == .fault
      || message.localizedStandardContains("failed")
      || message.localizedStandardContains("timeout")
      || message.localizedStandardContains("unreachable")
      || message.localizedStandardContains("not responding")
  }
}

/// Log level severity
enum LogLevel: String, Comparable {
  case debug = "Debug"
  case info = "Info"
  case warning = "Warning"
  case error = "Error"
  case fault = "Fault"

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    let order: [LogLevel] = [.debug, .info, .warning, .error, .fault]
    guard let lhsIndex = order.firstIndex(of: lhs),
      let rhsIndex = order.firstIndex(of: rhs)
    else {
      return false
    }
    return lhsIndex < rhsIndex
  }
}

/// Analyzes collected log entries
struct LogAnalyzer {
  /// The log entries to analyze
  let entries: [LogEntry]

  /// Performs analysis on the log entries
  func analyze() -> LogAnalysis {
    let totalCount = entries.count
    let errorCount = entries.filter { $0.level == .error }.count
    let faultCount = entries.filter { $0.level == .fault }.count
    let warningCount = entries.filter { $0.level == .warning }.count

    let hueRelatedCount = entries.filter { $0.containsHueReference }.count
    let problematicCount = entries.filter { $0.isProblematic }.count

    let subsystemCounts = Dictionary(grouping: entries) { $0.subsystem }
      .mapValues { $0.count }

    let problematicEntries = entries.filter { $0.isProblematic }

    return LogAnalysis(
      totalEntries: totalCount,
      errorCount: errorCount,
      faultCount: faultCount,
      warningCount: warningCount,
      hueRelatedCount: hueRelatedCount,
      problematicCount: problematicCount,
      subsystemCounts: subsystemCounts,
      problematicEntries: problematicEntries,
      allEntries: entries
    )
  }
}

/// Results of log analysis
struct LogAnalysis {
  /// Total number of log entries
  let totalEntries: Int

  /// Number of error-level entries
  let errorCount: Int

  /// Number of fault-level entries
  let faultCount: Int

  /// Number of warning-level entries
  let warningCount: Int

  /// Number of Hue-related entries
  let hueRelatedCount: Int

  /// Number of potentially problematic entries
  let problematicCount: Int

  /// Count of entries per subsystem
  let subsystemCounts: [String: Int]

  /// Entries that indicate problems
  let problematicEntries: [LogEntry]

  /// All log entries
  let allEntries: [LogEntry]
}

/// Formats analysis results for output
struct OutputFormatter {
  /// The analysis results to format
  let analysis: LogAnalysis

  /// Whether to show a summary
  let showSummary: Bool

  /// Formats the analysis as a string
  func format() -> String {
    var output = ""

    if showSummary || analysis.totalEntries < 100 {
      output += formatSummary()
      output += "\n\n"
    }

    if analysis.problematicCount > 0 {
      output += formatProblematicEntries()
      output += "\n\n"
    }

    if !showSummary {
      output += formatAllEntries()
    }

    return output
  }

  /// Formats the summary section
  private func formatSummary() -> String {
    var summary = "SUMMARY\n"
    summary += "=======\n\n"
    summary += "Total log entries: \(analysis.totalEntries)\n"
    summary += "Errors: \(analysis.errorCount)\n"
    summary += "Faults: \(analysis.faultCount)\n"
    summary += "Warnings: \(analysis.warningCount)\n"
    summary += "Hue-related: \(analysis.hueRelatedCount)\n"
    summary += "Potentially problematic: \(analysis.problematicCount)\n\n"

    summary += "Entries by subsystem:\n"
    for (subsystem, count) in analysis.subsystemCounts.sorted(by: { $0.value > $1.value }) {
      summary += "  \(subsystem): \(count)\n"
    }

    return summary
  }

  /// Formats the problematic entries section
  private func formatProblematicEntries() -> String {
    var output = "PROBLEMATIC ENTRIES\n"
    output += "===================\n\n"

    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium

    for entry in analysis.problematicEntries {
      output += "[\(formatter.string(from: entry.timestamp))] "
      output += "[\(entry.level.rawValue)] "
      output += "[\(entry.subsystem)]\n"
      output += "  \(entry.message)\n\n"
    }

    return output
  }

  /// Formats all entries
  private func formatAllEntries() -> String {
    var output = "ALL ENTRIES\n"
    output += "===========\n\n"

    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium

    for entry in analysis.allEntries {
      output += "[\(formatter.string(from: entry.timestamp))] "
      output += "[\(entry.level.rawValue)] "
      output += "[\(entry.subsystem)]\n"
      output += "  \(entry.message)\n\n"
    }

    return output
  }
}
