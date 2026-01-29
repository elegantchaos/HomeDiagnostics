import Foundation
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

/// Production log data source that queries the macOS unified logging system.
///
/// Uses the `/usr/bin/log` command with JSON output style to collect log entries
/// for a specific time interval and log level configuration. This is the default
/// data source used in production.
public struct SystemLogDataSource: LogDataSource {
  /// The time interval to look back (e.g., "14d", "6h").
  public let timeInterval: String

  /// Whether to include debug-level logs in the output.
  public let includeDebug: Bool

  /// Creates a new system log data source.
  ///
  /// - Parameters:
  ///   - timeInterval: Time interval string (e.g., "14d", "6h").
  ///   - includeDebug: Whether to include debug-level logs.
  public init(timeInterval: String, includeDebug: Bool) {
    self.timeInterval = timeInterval
    self.includeDebug = includeDebug
  }

  /// Fetches raw JSON log data for a specific subsystem from the unified logging system.
  ///
  /// Executes `/usr/bin/log show --style json` with appropriate predicates to
  /// retrieve log entries. The command filters by subsystem and time range.
  ///
  /// - Parameter subsystem: The subsystem identifier (e.g., "com.apple.HomeKit").
  /// - Returns: JSON string containing log entries.
  /// - Throws: An error if the subprocess execution fails.
  public func fetchJSONLogs(subsystem: String) async throws -> String {
    let levelPredicate = includeDebug ? "--info --debug" : "--info"

    let arguments =
      [
        "show",
        "--style", "json",
        "--last", timeInterval,
      ] + levelPredicate.components(separatedBy: " ") + [
        "--predicate", "subsystem == \"\(subsystem)\"",
      ]

    // Note: Debug logging happens via global function in main executable
    // debug("Executing: /usr/bin/log \(arguments.joined(separator: " "))")

    let result = try await Subprocess.run(
      .path(FilePath("/usr/bin/log")),
      arguments: Arguments(arguments),
      output: .string(limit: 100 * 1024 * 1024),
      error: .string(limit: 1024 * 1024)
    )

    if case .exited(let code) = result.terminationStatus, code != 0 {
      // Note: Debug logging happens via global function in main executable
      // debug("log command returned non-zero exit code: \(code) for \(subsystem)")
      if let errorOutput = result.standardError {
        // debug("Error output: \(errorOutput)")
        _ = errorOutput  // Silence unused warning
      }
    }

    return result.standardOutput ?? ""
  }
}
