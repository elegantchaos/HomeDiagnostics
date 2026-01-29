import Foundation
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

/// Collects and parses logs from the macOS unified logging system.
///
/// Queries multiple Home/HomeKit subsystems and aggregates their log entries.
/// Supports filtering by text/regex patterns, error-only mode, and test data injection.
/// Uses `/usr/bin/log` command for JSON-formatted output to ensure accurate metadata.
public struct LogCollector {
  /// The time interval to look back (e.g., "14d", "6h").
  public let timeInterval: String

  /// Whether to include debug-level logs in collection.
  public let includeDebug: Bool

  /// Optional filter pattern (plain text or regex) to match log messages.
  public let filter: String?

  /// Whether to filter for only errors, faults, and warnings.
  public let errorsOnly: Bool

  /// Optional data source for dependency injection during testing.
  ///
  /// When `nil`, uses the system log command. When provided, uses the
  /// injected source for testing without executing system commands.
  public let dataSource: LogDataSource?

  /// Callback for debug logging (required to integrate with main executable logging).
  public let debugLogger: ((String) -> Void)?

  /// Callback for error logging (required to integrate with main executable logging).
  public let errorLogger: ((String) -> Void)?

  /// Creates a new log collector with specified configuration.
  ///
  /// - Parameters:
  ///   - timeInterval: Time range string (e.g., "14d", "6h").
  ///   - includeDebug: Whether to include debug-level logs.
  ///   - filter: Optional text or regex pattern to filter messages.
  ///   - errorsOnly: Whether to show only errors, faults, and warnings.
  ///   - dataSource: Optional data source for testing.
  ///   - debugLogger: Optional debug message callback.
  ///   - errorLogger: Optional error message callback.
  public init(
    timeInterval: String,
    includeDebug: Bool,
    filter: String? = nil,
    errorsOnly: Bool = false,
    dataSource: LogDataSource? = nil,
    debugLogger: ((String) -> Void)? = nil,
    errorLogger: ((String) -> Void)? = nil
  ) {
    self.timeInterval = timeInterval
    self.includeDebug = includeDebug
    self.filter = filter
    self.errorsOnly = errorsOnly
    self.dataSource = dataSource
    self.debugLogger = debugLogger
    self.errorLogger = errorLogger
  }

  /// Collects and parses logs from all Home and HomeKit subsystems.
  ///
  /// Queries com.apple.Home, com.apple.HomeKit, and com.apple.homed subsystems,
  /// parses their JSON output, applies filters, and returns sorted log entries.
  ///
  /// - Returns: Array of log entries sorted by timestamp.
  /// - Throws: An error if log collection fails (though individual subsystem failures are logged and skipped).
  public func collectLogs() async throws -> [LogEntry] {
    var allEntries: [LogEntry] = []

    let subsystems = [
      "com.apple.Home",
      "com.apple.HomeKit",
      "com.apple.homed",
    ]

    for subsystem in subsystems {
      do {
        debugLogger?("Collecting logs for subsystem: \(subsystem)")
        let entries = try await collectLogsForSubsystem(subsystem)
        debugLogger?("Collected \(entries.count) entries from \(subsystem)")
        allEntries.append(contentsOf: entries)
      } catch {
        errorLogger?("[ERROR] Failed to collect logs for subsystem \(subsystem): \(error)")
        // Continue with other subsystems even if one fails
      }
    }

    // Sort by timestamp
    allEntries.sort { $0.timestamp < $1.timestamp }

    return allEntries
  }

  /// Collects raw, unparsed log output in syslog format.
  ///
  /// Used for `--raw` mode to output logs without JSON parsing or analysis.
  /// Queries all subsystems and returns concatenated syslog-format output.
  ///
  /// - Returns: Raw syslog-formatted log output.
  /// - Throws: An error if log collection fails.
  public func collectRawLogs() async throws -> String {
    var allOutput: [String] = []

    let subsystems = [
      "com.apple.Home",
      "com.apple.HomeKit",
      "com.apple.homed",
    ]

    for subsystem in subsystems {
      do {
        debugLogger?("Collecting raw logs for subsystem: \(subsystem)")
        let output = try await collectRawLogsForSubsystem(subsystem)
        debugLogger?("Collected \(output.count) characters from \(subsystem)")

        if !output.isEmpty {
          allOutput.append(output)
        }
      } catch {
        errorLogger?("[ERROR] Failed to collect logs for subsystem \(subsystem): \(error)")
        // Continue with other subsystems even if one fails
      }
    }

    return allOutput.joined(separator: "\n")
  }

  /// Parses JSON log output into structured log entries.
  ///
  /// Exposed as public for testing purposes. Parses the JSON array format
  /// returned by `/usr/bin/log --style json`, extracting timestamp, level,
  /// message, and metadata. Applies filters during parsing.
  ///
  /// - Parameters:
  ///   - output: JSON string from unified logging system.
  ///   - subsystem: The subsystem identifier for these logs.
  /// - Returns: Array of parsed and filtered log entries.
  public func parseJSONLogOutput(_ output: String, subsystem: String) -> [LogEntry] {
    guard let data = output.data(using: .utf8) else {
      debugLogger?("Failed to convert output to UTF-8 data")
      return []
    }

    var entries: [LogEntry] = []

    do {
      guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
      else {
        debugLogger?("Failed to parse JSON as array of dictionaries")
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
          debugLogger?("Failed to parse timestamp: \(timestamp)")
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
          case "Warning":
            level = .warning
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

        // Apply filter if provided
        if let filter = filter {
          shouldInclude = shouldInclude && matchesFilter(entry.message, pattern: filter)
        }

        if shouldInclude {
          entries.append(entry)
        }
      }

      debugLogger?(
        "Parsed \(entries.count) entries from \(jsonArray.count) JSON objects for \(subsystem)")
    } catch {
      debugLogger?("JSON parsing error: \(error)")
    }

    return entries
  }

  /// Checks if text matches a filter pattern (plain text or regex).
  ///
  /// Exposed as public for testing purposes. Attempts to compile the pattern
  /// as a case-insensitive regex first. If regex compilation fails, falls back
  /// to plain text search using localized string comparison.
  ///
  /// - Parameters:
  ///   - text: The text to search within.
  ///   - pattern: The search pattern (regex or plain text).
  /// - Returns: `true` if the text matches the pattern.
  public func matchesFilter(_ text: String, pattern: String) -> Bool {
    // Try as regex first
    if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
      let range = NSRange(text.startIndex..., in: text)
      return regex.firstMatch(in: text, range: range) != nil
    }

    // Fall back to plain text search (case-insensitive)
    return text.localizedStandardContains(pattern)
  }
}

// MARK: - Private Helpers

private extension LogCollector {
  /// Collects raw logs for a specific subsystem in syslog format.
  ///
  /// Used by `collectRawLogs()` to fetch unformatted log output.
  ///
  /// - Parameter subsystem: The subsystem identifier.
  /// - Returns: Raw syslog-formatted output.
  /// - Throws: An error if subprocess execution fails.
  func collectRawLogsForSubsystem(_ subsystem: String) async throws -> String {
    let levelPredicate = includeDebug ? "--info --debug" : "--info"

    let arguments =
      [
        "show",
        "--style", "syslog",
        "--last", timeInterval,
      ] + levelPredicate.components(separatedBy: " ") + [
        "--predicate", "subsystem == \"\(subsystem)\"",
      ]

    debugLogger?("Executing: /usr/bin/log \(arguments.joined(separator: " "))")

    do {
      let result = try await Subprocess.run(
        .path(FilePath("/usr/bin/log")),
        arguments: Arguments(arguments),
        output: .string(limit: 100 * 1024 * 1024),
        error: .string(limit: 1024 * 1024)
      )

      if case .exited(let code) = result.terminationStatus, code != 0 {
        debugLogger?("log command returned non-zero exit code: \(code) for \(subsystem)")
        if let errorOutput = result.standardError {
          debugLogger?("Error output: \(errorOutput)")
        }
      }

      var output = result.standardOutput ?? ""

      if let filter = filter {
        let lines = output.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
          matchesFilter(line, pattern: filter)
        }
        output = filteredLines.joined(separator: "\n")
      }

      return output
    } catch {
      errorLogger?("[ERROR] Subprocess execution failed for \(subsystem): \(error)")
      throw error
    }
  }

  /// Collects logs for a specific subsystem in JSON format.
  ///
  /// Uses either the injected data source (for testing) or executes the
  /// system log command. Returns raw JSON output for parsing.
  ///
  /// - Parameter subsystem: The subsystem identifier.
  /// - Returns: JSON-formatted log output.
  /// - Throws: An error if log collection fails.
  func collectLogsForSubsystem(_ subsystem: String) async throws -> [LogEntry] {
    let output: String
    if let dataSource = dataSource {
      output = try await dataSource.fetchJSONLogs(subsystem: subsystem)
    } else {
      let levelPredicate = includeDebug ? "--info --debug" : "--info"

      let arguments =
        [
          "show",
          "--style", "json",
          "--last", timeInterval,
        ] + levelPredicate.components(separatedBy: " ") + [
          "--predicate", "subsystem == \"\(subsystem)\"",
        ]

      debugLogger?("Executing: /usr/bin/log \(arguments.joined(separator: " "))")

      do {
        let result = try await Subprocess.run(
          .path(FilePath("/usr/bin/log")),
          arguments: Arguments(arguments),
          output: .string(limit: 100 * 1024 * 1024),
          error: .string(limit: 1024 * 1024)
        )

        if case .exited(let code) = result.terminationStatus, code != 0 {
          debugLogger?("log command returned non-zero exit code: \(code) for \(subsystem)")
          if let errorOutput = result.standardError {
            debugLogger?("Error output: \(errorOutput)")
          }
        }

        output = result.standardOutput ?? ""
        debugLogger?("Received \(output.count) characters from \(subsystem)")
      } catch {
        errorLogger?("[ERROR] Subprocess execution failed for \(subsystem): \(error)")
        throw error
      }
    }

    return parseJSONLogOutput(output, subsystem: subsystem)
  }
}
