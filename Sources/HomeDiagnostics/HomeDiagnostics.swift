import ArgumentParser
import Foundation
import HomeDiagnosticsCore


/// Command-line tool for diagnosing Apple Home and HomeKit issues.
///
/// Collects and analyzes logs from the unified logging system, filtering and
/// formatting them for troubleshooting smart home device problems. Supports
/// various output modes including summary-only, raw logs, and deduplicated entries.
@main
struct HomeDiagnostics: AsyncParsableCommand {
  /// Configuration for the command-line tool.
  static let configuration = CommandConfiguration(
    commandName: "home-diagnostics",
    abstract: "Collect and analyze Apple Home and HomeKit logs",
    version: "1.0.0"
  )

  /// Number of days to look back in logs.
  @Option(name: .shortAndLong, help: "Number of days to look back (default: 14)")
  var days: Int?

  /// Number of hours to look back in logs.
  @Option(name: .long, help: "Number of hours to look back")
  var hours: Int?

  /// Filter pattern for log messages (plain text or regex).
  @Option(name: .shortAndLong, help: "Filter log messages (plain text or regex pattern)")
  var filter: String?

  /// Whether to show only summary statistics.
  @Flag(name: .long, help: "Show summary statistics")
  var summary: Bool = false

  /// Whether to enable verbose output.
  @Flag(name: .shortAndLong, help: "Enable verbose output")
  var verbose: Bool = false

  /// Whether to include debug-level logs.
  @Flag(name: .long, help: "Include debug-level logs (slower, more comprehensive)")
  var detailed: Bool = false

  /// Whether to deduplicate log entries.
  @Flag(name: .long, help: "De-duplicate log entries and show one example of each unique type")
  var dedupe: Bool = false

  /// Whether to output raw, unparsed log data.
  @Flag(name: .long, help: "Output raw log data without parsing or analysis")
  var raw: Bool = false

  /// Whether to show only errors, faults, and warnings.
  @Flag(name: .long, help: "Show only errors, faults, and warnings (filter out info/debug)")
  var errorsOnly: Bool = false

  /// Whether to disable UUID name substitution.
  @Flag(name: .long, help: "Disable UUID name substitution (show raw UUIDs)")
  var noNames: Bool = false

  /// Main entry point for the command execution.
  ///
  /// Validates arguments, configures log collection parameters, and runs the
  /// appropriate collection and analysis workflow.
  ///
  /// - Throws: An error if validation fails or log collection encounters issues.
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
        filter: filter,
        errorsOnly: errorsOnly,
        debugLogger: { debug($0) },
        errorLogger: { printErr($0) },
        progressLogger: { count, subsystem in
          // Always show progress (not just in verbose mode) since collection can take a long time
          let shortName = subsystem.replacingOccurrences(of: "com.apple.", with: "")
          printErr("  Collected \(count) entries from \(shortName)...")
        }
      )

      if !raw {
        printErr("Collecting logs from the last \(timeDescription)...")
        if detailed {
          printErr("(Including debug-level logs - this may take a while)")
        }
        if let filter = filter {
          printErr("(Filtering for: \"\(filter)\")")
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
        deduplicate: dedupe,
        errorsOnly: errorsOnly,
        substituteNames: !noNames
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
