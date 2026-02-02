import ArgumentParser
import Foundation
import HomeDiagnosticsCore
import OSLog

/// Logger for CLI operations.
let cliLogger = Logger(subsystem: "com.elegantchaos.HomeDiagnostics", category: "CLI")

/// Entity discovery method selection.
///
/// Controls which approach(es) are used to discover HomeKit entities.
enum EntitySource: String, ExpressibleByArgument {
  /// Use pattern scanning of log messages (default, no permissions required).
  case patterns

  /// Use HomeKit API queries (requires HomeKit entitlements and authorization).
  case api

  /// Use both pattern scanning and HomeKit API (maximum coverage).
  case both
}

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

  /// Number of minutes to look back in logs.
  @Option(name: .long, help: "Number of minutes to look back")
  var minutes: Int?

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


  /// Maximum number of log entries to read from each log (nil = unlimited)
  @Option(name: .long, help: "Limit the number of log entries to read from each log (default: unlimited)")
  var entries: Int?

  /// Whether to disable UUID name substitution.
  @Flag(name: .long, help: "Disable UUID name substitution (show raw UUIDs)")
  var noNames: Bool = false

  /// Entity discovery method (patterns, api, or both).
  @Option(
    name: .long,
    help: "Entity discovery method: patterns, api, or both (default)")
  var entitySource: EntitySource = .both

  /// Directory path for capturing raw JSON log data.
  @Option(
    name: .long,
    help: "Capture raw JSON log data to the specified directory")
  var capture: String?

  /// Directory path for replaying a previously captured session.
  @Option(
    name: .long,
    help: "Replay logs from a previously captured session directory")
  var session: String?

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

    if capture != nil && session != nil {
      printErr("[ERROR] --capture and --session cannot be used together")
      throw ExitCode.validationFailure
    }

    if session != nil && raw {
      printErr("[ERROR] --session cannot be combined with --raw")
      throw ExitCode.validationFailure
    }

    let timeOptionCount = [days, hours, minutes].compactMap { $0 }.count
    if timeOptionCount > 1 {
      printErr("[ERROR] Cannot specify more than one of --days, --hours, or --minutes")
      throw ExitCode.validationFailure
    }

    // Determine time interval
    let timeInterval: String
    let timeDescription: String

    if let minutes = minutes {
      timeInterval = "\(minutes)m"
      timeDescription = "\(minutes) minute(s)"
    } else if let hours = hours {
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

      // Create data source from session directory if specified
      let dataSource: LogDataSource? =
        if let sessionDir = session {
          CapturedSessionDataSource(directoryPath: sessionDir)
        } else {
          nil
        }

      let collector = LogCollector(
        timeInterval: timeInterval,
        includeDebug: detailed,
        entryLimit: entries,
        dataSource: dataSource,
        debugLogger: { debug($0) },
        errorLogger: { printErr($0) },
        progressLogger: { count, subsystem in
          // Always show progress (not just in verbose mode) since collection can take a long time
          let shortName = subsystem.replacingOccurrences(of: "com.apple.", with: "")
          printErr("  Collected \(count) entries from \(shortName)...")
        },
        captureDirectory: capture
      )

      if !raw {
        if let sessionDir = session {
          printErr("Replaying logs from captured session: \"\(sessionDir)\"")
        } else {
          printErr("Collecting logs from the last \(timeDescription)...")
        }
        if detailed {
          printErr("(Including debug-level logs - this may take a while)")
        }
        if let filter = filter {
          printErr("(Filtering for: \"\(filter)\")")
        }
        if errorsOnly {
          printErr("(Filtering for errors, faults, and warnings only)")
        }
        if let captureDir = capture {
          printErr("(Capturing raw JSON to: \"\(captureDir)\")")
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
      let logStream = collector.collectLogs()

      // Collect entity annotations from HomeKit API if requested
      var additionalAnnotations: [EntityAnnotation] = []
      #if canImport(HomeKit)
        if entitySource == .api || entitySource == .both {
          do {
            debug("Collecting entities from HomeKit API")
            let homekitCollector = HomeKitAPICollector()
            additionalAnnotations = try await homekitCollector.collect()
            debug("HomeKit API returned \\(additionalAnnotations.count) annotations")
          } catch {
            cliLogger.error("HomeKit collection failed: \\(error.localizedDescription)")
            printErr("[WARNING] HomeKit API collection failed: \\(error.localizedDescription)")
            printErr("Continuing with pattern scanning only...")
          }
        }
      #else
        if entitySource == .api || entitySource == .both {
          printErr("[WARNING] HomeKit framework not available on this platform")
          printErr("Continuing with pattern scanning only...")
        }
      #endif

      debug("Analyzing logs")
      let analyzer = LogAnalyzer(stream: logStream)
      let analysis = try await analyzer.analyzeStream(
        additionalAnnotations: additionalAnnotations)

      debug("Formatting output")
      let formatter = OutputFormatter(
        analysis: analysis,
        showSummary: summary,
        deduplicate: dedupe,
        errorsOnly: errorsOnly,
        filter: filter,
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
