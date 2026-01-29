import ArgumentParser
import Foundation
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

struct StandardError: TextOutputStream, Sendable {
  private static let handle = FileHandle.standardError

  public func write(_ string: String) {
    Self.handle.write(Data(string.utf8))
  }
}

nonisolated(unsafe) private var stderr = StandardError()

/// Print to stderr
private func printErr(_ message: String) {
  print(message, to: &stderr)
}

/// Print debug message to stderr (only when verbose is enabled)
private func debug(_ message: String) {
  if isVerbose {
    printErr("[DEBUG] \(message)")
  }
}

/// Print info message to stderr (only when verbose is enabled)
private func info(_ message: String) {
  if isVerbose {
    printErr("[INFO] \(message)")
  }
}

/// Whether verbose output is enabled
nonisolated(unsafe) private var isVerbose = false

/// Command-line tool for diagnosing Apple Home and HomeKit issues
@main
struct HomeDiagnostics: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "home-diagnostics",
    abstract: "Collect and analyze Apple Home and HomeKit logs",
    version: "1.0.0"
  )

  @Option(name: .shortAndLong, help: "Number of days to look back (default: 14)")
  var days: Int?

  @Option(name: .long, help: "Number of hours to look back")
  var hours: Int?

  @Flag(name: .long, help: "Filter for Hue-related entries only")
  var hueOnly: Bool = false

  @Flag(name: .long, help: "Show summary statistics")
  var summary: Bool = false

  @Flag(name: .shortAndLong, help: "Enable verbose output")
  var verbose: Bool = false

  @Flag(name: .long, help: "Include debug-level logs (slower, more comprehensive)")
  var detailed: Bool = false

  @Flag(name: .long, help: "De-duplicate log entries and show one example of each unique type")
  var dedupe: Bool = false

  @Flag(name: .long, help: "Output raw log data without parsing or analysis")
  var raw: Bool = false

  @Flag(name: .long, help: "Show only errors, faults, and warnings (filter out info/debug)")
  var errorsOnly: Bool = false

  mutating func run() async throws {
    // Configure verbose output
    isVerbose = verbose

    // Validate flag combinations
    if raw && (summary || dedupe) {
      printErr("[ERROR] --raw cannot be combined with --summary or --dedupe")
      throw ExitCode.validationFailure
    }

    if raw && errorsOnly {
      printErr("[ERROR] --raw cannot be combined with --errors-only")
      throw ExitCode.validationFailure
    }

    if days != nil && hours != nil {
      printErr("[ERROR] Cannot specify both --days and --hours")
      throw ExitCode.validationFailure
    }

    // Determine time interval
    let timeInterval: String
    let timeDescription: String

    if let hours = hours {
      timeInterval = "\(hours)h"
      timeDescription = "\(hours) hour(s)"
    } else {
      let daysValue = days ?? 14
      timeInterval = "\(daysValue)d"
      timeDescription = "\(daysValue) day(s)"
    }

    do {
      info("Starting HomeDiagnostics - Apple Home Log Analyzer")
      
      if !raw {
        printErr("HomeDiagnostics - Apple Home Log Analyzer")
        printErr("==========================================\n")
      }

      let collector = LogCollector(
        timeInterval: timeInterval,
        includeDebug: detailed,
        hueOnly: hueOnly,
        errorsOnly: errorsOnly
      )

      if !raw {
        printErr("Collecting logs from the last \(timeDescription)...")
        if detailed {
          printErr("(Including debug-level logs - this may take a while)")
        }
        if errorsOnly {
          printErr("(Filtering for errors, faults, and warnings only)")
        }
        printErr("")
      }

      debug("Beginning log collection")

      // Raw mode: output unprocessed logs directly
      if raw {
        let rawOutput = try await collector.collectRawLogs()
        print(rawOutput)
        info("HomeDiagnostics raw output completed successfully")
        return
      }

      // Normal mode: parse and analyze logs
      let logs = try await collector.collectLogs()
      info("Collected \(logs.count) log entries")

      debug("Analyzing logs")
      let analyzer = LogAnalyzer(entries: logs)
      let analysis = analyzer.analyze()

      debug("Formatting output")
      let formatter = OutputFormatter(
        analysis: analysis,
        showSummary: summary,
        deduplicate: dedupe
      )

      let outputText = formatter.format()

      print(outputText)

      info("HomeDiagnostics completed successfully")
    } catch {
      printErr("[ERROR] Fatal error occurred: \(error)")
      printErr("\nError: \(error.localizedDescription)")
      throw error
    }
  }
}

/// Collects logs from the macOS unified logging system
struct LogCollector {
  /// Time interval to look back (e.g., "14d", "6h")
  let timeInterval: String

  /// Whether to include debug-level logs
  let includeDebug: Bool

  /// Whether to filter for Hue-related entries only
  let hueOnly: Bool

  /// Whether to filter for errors, faults, and warnings only
  let errorsOnly: Bool

  /// Collects Home and HomeKit logs
  func collectLogs() async throws -> [LogEntry] {
    var allEntries: [LogEntry] = []

    // Collect from different subsystems
    let subsystems = [
      "com.apple.Home",
      "com.apple.HomeKit",
      "com.apple.homed",
    ]

    for subsystem in subsystems {
      do {
        debug("Collecting logs for subsystem: \(subsystem)")
        let entries = try await collectLogsForSubsystem(subsystem)
        debug("Collected \(entries.count) entries from \(subsystem)")
        allEntries.append(contentsOf: entries)
      } catch {
        printErr("[ERROR] Failed to collect logs for subsystem \(subsystem): \(error)")
        // Continue with other subsystems even if one fails
      }
    }

    // Sort by timestamp
    allEntries.sort { $0.timestamp < $1.timestamp }

    return allEntries
  }

  /// Collects raw log output without parsing
  func collectRawLogs() async throws -> String {
    var allOutput: [String] = []

    // Collect from different subsystems
    let subsystems = [
      "com.apple.Home",
      "com.apple.HomeKit",
      "com.apple.homed",
    ]

    for subsystem in subsystems {
      do {
        debug("Collecting raw logs for subsystem: \(subsystem)")
        let output = try await collectRawLogsForSubsystem(subsystem)
        debug("Collected \(output.count) characters from \(subsystem)")
        
        if !output.isEmpty {
          allOutput.append(output)
        }
      } catch {
        printErr("[ERROR] Failed to collect logs for subsystem \(subsystem): \(error)")
        // Continue with other subsystems even if one fails
      }
    }

    return allOutput.joined(separator: "\n")
  }

  /// Collects raw logs for a specific subsystem without parsing
  private func collectRawLogsForSubsystem(_ subsystem: String) async throws -> String {
    let levelPredicate = includeDebug ? "--info --debug" : "--info"

    // Build the log command arguments
    let arguments =
      [
        "show",
        "--style", "syslog",
        "--last", timeInterval,
      ] + levelPredicate.components(separatedBy: " ") + [
        "--predicate", "subsystem == \"\(subsystem)\"",
      ]

    debug("Executing: /usr/bin/log \(arguments.joined(separator: " "))")

    do {
      // Execute using Subprocess
      let result = try await Subprocess.run(
        .path(FilePath("/usr/bin/log")),
        arguments: Arguments(arguments),
        output: .string(limit: 100 * 1024 * 1024),  // 100MB limit
        error: .string(limit: 1024 * 1024)  // 1MB limit for errors
      )

      // Check exit status
      if case .exited(let code) = result.terminationStatus, code != 0 {
        debug("log command returned non-zero exit code: \(code) for \(subsystem)")
        if let errorOutput = result.standardError {
          debug("Error output: \(errorOutput)")
        }
      }

      // Read output and filter for Hue if requested
      var output = result.standardOutput ?? ""
      
      if hueOnly {
        let lines = output.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
          let lowercased = line.lowercased()
          return lowercased.contains("hue")
            || lowercased.contains("philips")
            || lowercased.contains("bridge")
        }
        output = filteredLines.joined(separator: "\n")
      }

      return output
    } catch {
      printErr("[ERROR] Subprocess execution failed for \(subsystem): \(error)")
      throw error
    }
  }

  /// Collects logs for a specific subsystem
  private func collectLogsForSubsystem(_ subsystem: String) async throws -> [LogEntry] {
    let levelPredicate = includeDebug ? "--info --debug" : "--info"

    // Build the log command arguments - use JSON for accurate metadata
    let arguments =
      [
        "show",
        "--style", "json",
        "--last", timeInterval,
      ] + levelPredicate.components(separatedBy: " ") + [
        "--predicate", "subsystem == \"\(subsystem)\"",
      ]

    debug("Executing: /usr/bin/log \(arguments.joined(separator: " "))")

    do {
      // Execute using Subprocess
      let result = try await Subprocess.run(
        .path(FilePath("/usr/bin/log")),
        arguments: Arguments(arguments),
        output: .string(limit: 100 * 1024 * 1024),  // 100MB limit
        error: .string(limit: 1024 * 1024)  // 1MB limit for errors
      )

      // Check exit status
      if case .exited(let code) = result.terminationStatus, code != 0 {
        debug("log command returned non-zero exit code: \(code) for \(subsystem)")
        if let errorOutput = result.standardError {
          debug("Error output: \(errorOutput)")
        }
      }

      // Read output
      let output = result.standardOutput ?? ""
      debug("Received \(output.count) characters from \(subsystem)")

      return parseJSONLogOutput(output, subsystem: subsystem)
    } catch {
      printErr("[ERROR] Subprocess execution failed for \(subsystem): \(error)")
      throw error
    }
  }

  /// Parses JSON log output into structured entries
  private func parseJSONLogOutput(_ output: String, subsystem: String) -> [LogEntry] {
    guard let data = output.data(using: .utf8) else {
      debug("Failed to convert output to UTF-8 data")
      return []
    }

    var entries: [LogEntry] = []

    do {
      guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
      else {
        debug("Failed to parse JSON as array of dictionaries")
        return []
      }

      for jsonEntry in jsonArray {
        guard let timestamp = jsonEntry["timestamp"] as? String,
          let messageType = jsonEntry["messageType"] as? String,
          let eventMessage = jsonEntry["eventMessage"] as? String,
          let processImagePath = jsonEntry["processImagePath"] as? String
        else {
          continue
        }

        // Parse timestamp (format: "2026-01-29 14:25:34.202233+0000")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: timestamp) else {
          debug("Failed to parse timestamp: \(timestamp)")
          continue
        }

        // Extract process name from path
        let processName = (processImagePath as NSString).lastPathComponent

        // Map messageType to LogLevel
        let level: LogLevel
        switch messageType {
        case "Debug":
          level = .debug
        case "Info":
          level = .info
        case "Default":
          level = .info
        case "Error":
          level = .error
        case "Fault":
          level = .fault
        default:
          level = .info
        }

        let entry = LogEntry(
          timestamp: date,
          subsystem: subsystem,
          process: processName,
          level: level,
          message: eventMessage
        )

        // Apply filters
        var shouldInclude = true

        // Filter for errors only if requested
        if errorsOnly {
          shouldInclude = shouldInclude && (level == .error || level == .fault || level == .warning)
        }

        // Filter for Hue if requested
        if hueOnly {
          shouldInclude = shouldInclude && entry.containsHueReference
        }

        if shouldInclude {
          entries.append(entry)
        }
      }

      debug("Parsed \(entries.count) entries from \(jsonArray.count) JSON objects for \(subsystem)")
    } catch {
      debug("JSON parsing error: \(error)")
    }

    return entries
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

  /// Normalized message with UUIDs removed for deduplication
  var normalizedMessage: String {
    var normalized = message

    // Remove UUIDs (8-4-4-4-12 format)
    let uuidPattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    if let regex = try? NSRegularExpression(pattern: uuidPattern) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = regex.stringByReplacingMatches(
        in: normalized,
        range: range,
        withTemplate: "<UUID>"
      )
    }

    // Remove hex addresses (0x followed by hex digits)
    let hexPattern = #"0x[0-9A-Fa-f]+"#
    if let regex = try? NSRegularExpression(pattern: hexPattern) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = regex.stringByReplacingMatches(
        in: normalized,
        range: range,
        withTemplate: "<ADDR>"
      )
    }

    // Remove timestamps (common formats)
    let timestampPattern = #"\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+"#
    if let regex = try? NSRegularExpression(pattern: timestampPattern) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = regex.stringByReplacingMatches(
        in: normalized,
        range: range,
        withTemplate: "<TIMESTAMP>"
      )
    }

    return normalized
  }

  /// Key for grouping duplicate entries
  var deduplicationKey: String {
    "\(subsystem)|\(level.rawValue)|\(normalizedMessage)"
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

    debug(
      "Analysis complete: \(totalCount) total, \(errorCount) errors, \(faultCount) faults, \(warningCount) warnings"
    )

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

/// Represents a group of duplicate log entries
struct GroupedLogEntry {
  /// Representative entry (first occurrence)
  let example: LogEntry

  /// Number of occurrences
  let count: Int

  /// First occurrence timestamp
  let firstSeen: Date

  /// Last occurrence timestamp
  let lastSeen: Date
}

/// Formats analysis results for output
struct OutputFormatter {
  /// The analysis results to format
  let analysis: LogAnalysis

  /// Whether to show a summary
  let showSummary: Bool

  /// Whether to deduplicate entries
  let deduplicate: Bool

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
    summary += "Potentially problematic: \(analysis.problematicCount)\n"

    if deduplicate {
      let uniqueCount = groupEntries(analysis.allEntries).count
      summary += "Unique entry types: \(uniqueCount)\n"
    }

    summary += "\nEntries by subsystem:\n"
    for (subsystem, count) in analysis.subsystemCounts.sorted(by: { $0.value > $1.value }) {
      summary += "  \(subsystem): \(count)\n"
    }

    return summary
  }

  /// Groups entries by their deduplication key
  private func groupEntries(_ entries: [LogEntry]) -> [GroupedLogEntry] {
    let grouped = Dictionary(grouping: entries) { $0.deduplicationKey }

    return grouped.map { _, entries in
      let sorted = entries.sorted { $0.timestamp < $1.timestamp }
      return GroupedLogEntry(
        example: sorted[0],
        count: entries.count,
        firstSeen: sorted[0].timestamp,
        lastSeen: sorted[sorted.count - 1].timestamp
      )
    }.sorted { $0.count > $1.count }
  }

  /// Formats the problematic entries section
  private func formatProblematicEntries() -> String {
    var output = "PROBLEMATIC ENTRIES\n"
    output += "===================\n\n"

    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium

    if deduplicate {
      let grouped = groupEntries(analysis.problematicEntries)
      output += "Showing \(grouped.count) unique problematic entry types (out of \(analysis.problematicCount) total)\n\n"

      for group in grouped {
        output += "[\(group.count)x] "
        output += "[\(formatter.string(from: group.firstSeen))"
        if group.count > 1 {
          output += " - \(formatter.string(from: group.lastSeen))"
        }
        output += "] "
        output += "[\(group.example.level.rawValue)] "
        output += "[\(group.example.subsystem)]\n"
        output += "  \(group.example.message)\n\n"
      }
    } else {
      for entry in analysis.problematicEntries {
        output += "[\(formatter.string(from: entry.timestamp))] "
        output += "[\(entry.level.rawValue)] "
        output += "[\(entry.subsystem)]\n"
        output += "  \(entry.message)\n\n"
      }
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

    if deduplicate {
      let grouped = groupEntries(analysis.allEntries)
      output += "Showing \(grouped.count) unique entry types (out of \(analysis.totalEntries) total)\n\n"

      for group in grouped {
        output += "[\(group.count)x] "
        output += "[\(formatter.string(from: group.firstSeen))"
        if group.count > 1 {
          output += " - \(formatter.string(from: group.lastSeen))"
        }
        output += "] "
        output += "[\(group.example.level.rawValue)] "
        output += "[\(group.example.subsystem)]\n"
        output += "  \(group.example.message)\n\n"
      }
    } else {
      for entry in analysis.allEntries {
        output += "[\(formatter.string(from: entry.timestamp))] "
        output += "[\(entry.level.rawValue)] "
        output += "[\(entry.subsystem)]\n"
        output += "  \(entry.message)\n\n"
      }
    }

    return output
  }
}
