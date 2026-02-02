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

// MARK: - Shared Option Groups

/// Options for specifying the time range to look back in logs.
struct TimeOptions: ParsableArguments {
  /// Number of days to look back in logs.
  @Option(name: .shortAndLong, help: "Number of days to look back (default: 14)")
  var days: Int?

  /// Number of hours to look back in logs.
  @Option(name: .long, help: "Number of hours to look back")
  var hours: Int?

  /// Number of minutes to look back in logs.
  @Option(name: .long, help: "Number of minutes to look back")
  var minutes: Int?

  /// Validates that only one time option is specified.
  ///
  /// - Throws: `ValidationError` if more than one time option is provided.
  func validate() throws {
    let timeOptionCount = [days, hours, minutes].compactMap { $0 }.count
    if timeOptionCount > 1 {
      throw ValidationError("Cannot specify more than one of --days, --hours, or --minutes")
    }
  }

  /// Returns the time interval string for the log command.
  var timeInterval: String {
    if let minutes = minutes {
      return "\(minutes)m"
    } else if let hours = hours {
      return "\(hours)h"
    } else {
      let daysValue = days ?? 14
      return "\(daysValue)d"
    }
  }

  /// Returns a human-readable description of the time range.
  var timeDescription: String {
    if let minutes = minutes {
      return "\(minutes) minute(s)"
    } else if let hours = hours {
      return "\(hours) hour(s)"
    } else {
      let daysValue = days ?? 14
      return "\(daysValue) day(s)"
    }
  }
}

/// Options for controlling log collection behavior.
struct CollectionOptions: ParsableArguments {
  /// Whether to enable verbose output.
  @Flag(name: .shortAndLong, help: "Enable verbose output")
  var verbose: Bool = false

  /// Whether to include debug-level logs.
  @Flag(name: .long, help: "Include debug-level logs (slower, more comprehensive)")
  var detailed: Bool = false

  /// Maximum number of log entries to read from each log (nil = unlimited).
  @Option(name: .long, help: "Limit the number of log entries to read from each log (default: unlimited)")
  var entries: Int?
}

/// Options for controlling output formatting and filtering.
struct OutputOptions: ParsableArguments {
  /// Filter pattern for log messages (plain text or regex).
  @Option(name: .shortAndLong, help: "Filter log messages (plain text or regex pattern)")
  var filter: String?

  /// Whether to show only summary statistics.
  @Flag(name: .long, help: "Show summary statistics")
  var summary: Bool = false

  /// Whether to deduplicate log entries.
  @Flag(name: .long, help: "De-duplicate log entries and show one example of each unique type")
  var dedupe: Bool = false

  /// Whether to show only errors, faults, and warnings.
  @Flag(name: .long, help: "Show only errors, faults, and warnings (filter out info/debug)")
  var errorsOnly: Bool = false

  /// Whether to disable UUID name substitution.
  @Flag(name: .long, help: "Disable UUID name substitution (show raw UUIDs)")
  var noNames: Bool = false

  /// Entity discovery method (patterns, api, or both).
  @Option(
    name: .long,
    help: "Entity discovery method: patterns, api, or both (default)")
  var entitySource: EntitySource = .both
}

// MARK: - Root Command

/// Command-line tool for diagnosing Apple Home and HomeKit issues.
///
/// Provides subcommands for analyzing live logs, capturing logs for later replay,
/// and replaying previously captured sessions.
@main
struct HomeDiagnostics: AsyncParsableCommand {
  /// Configuration for the command-line tool.
  static let configuration = CommandConfiguration(
    commandName: "home-diagnostics",
    abstract: "Collect and analyze Apple Home and HomeKit logs",
    version: "1.0.0",
    subcommands: [AnalyzeCommand.self, CaptureCommand.self, ReplayCommand.self],
    defaultSubcommand: AnalyzeCommand.self
  )
}

// MARK: - Shared Helpers

/// Collects entity annotations from the HomeKit API if available and requested.
///
/// - Parameter entitySource: The entity discovery method to use.
/// - Returns: Array of entity annotations, or empty array if not available/requested.
func collectEntityAnnotations(entitySource: EntitySource) async -> [EntityAnnotation] {
  var additionalAnnotations: [EntityAnnotation] = []

  #if canImport(HomeKit)
    if entitySource == .api || entitySource == .both {
      do {
        debug("Collecting entities from HomeKit API")
        let homekitCollector = HomeKitAPICollector()
        additionalAnnotations = try await homekitCollector.collect()
        debug("HomeKit API returned \(additionalAnnotations.count) annotations")
      } catch {
        cliLogger.error("HomeKit collection failed: \(error.localizedDescription)")
        printErr("[WARNING] HomeKit API collection failed: \(error.localizedDescription)")
        printErr("Continuing with pattern scanning only...")
      }
    }
  #else
    if entitySource == .api || entitySource == .both {
      printErr("[WARNING] HomeKit framework not available on this platform")
      printErr("Continuing with pattern scanning only...")
    }
  #endif

  return additionalAnnotations
}
