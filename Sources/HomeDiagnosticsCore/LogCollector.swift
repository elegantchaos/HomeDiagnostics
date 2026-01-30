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

  /// Callback for progress reporting during log collection.
  ///
  /// Called periodically with the current entry count and subsystem name.
  /// Used to show progress to the user during long-running operations.
  public let progressLogger: ((Int, String) -> Void)?

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
  ///   - progressLogger: Optional progress reporting callback.
  public init(
    timeInterval: String,
    includeDebug: Bool,
    filter: String? = nil,
    errorsOnly: Bool = false,
    dataSource: LogDataSource? = nil,
    debugLogger: ((String) -> Void)? = nil,
    errorLogger: ((String) -> Void)? = nil,
    progressLogger: ((Int, String) -> Void)? = nil
  ) {
    self.timeInterval = timeInterval
    self.includeDebug = includeDebug
    self.filter = filter
    self.errorsOnly = errorsOnly
    self.dataSource = dataSource
    self.debugLogger = debugLogger
    self.errorLogger = errorLogger
    self.progressLogger = progressLogger
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
    do {
      let regex = try Regex(pattern).ignoresCase()
      return text.contains(regex)
    } catch {
      // Fall back to plain text search (case-insensitive)
      return text.localizedStandardContains(pattern)
    }
  }

  /// Parses a single JSON object string into a LogEntry.
  ///
  /// Exposed as public for testing purposes only.
  /// Applies filtering during parsing for efficiency.
  ///
  /// - Parameters:
  ///   - jsonString: JSON object string (without array brackets).
  ///   - subsystem: The subsystem identifier for this log entry.
  /// - Returns: Parsed and filtered log entry, or `nil` if it should be filtered out or parsing fails.
  public func parseJSONObject(_ jsonString: String, subsystem: String) -> LogEntry? {
    guard let data = jsonString.data(using: .utf8) else {
      debugLogger?("Failed to convert JSON string to UTF-8 data")
      return nil
    }

    do {
      guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        debugLogger?("Failed to parse JSON object")
        return nil
      }

      guard let timestamp = jsonObject["timestamp"] as? String,
        let messageType = jsonObject["messageType"] as? String,
        let eventMessage = jsonObject["eventMessage"] as? String,
        let processImagePath = jsonObject["processImagePath"] as? String
      else {
        return nil
      }

      // Parse timestamp (format: "2026-01-29 14:25:34.202233+0000")
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      guard let date = formatter.date(from: timestamp) else {
        debugLogger?("Failed to parse timestamp: \(timestamp)")
        return nil
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

      return shouldInclude ? entry : nil
    } catch {
      debugLogger?("JSON parsing error: \(error)")
      return nil
    }
  }
}

// MARK: - JSON Stream Parser

/// State machine for parsing JSON objects from a line-by-line stream.
///
/// The unified logging system outputs JSON as a single array `[{...}, {...}, ...]`.
/// This parser tracks bracket depth and string boundaries to detect complete JSON objects
/// as they arrive in the stream, allowing incremental parsing without buffering the entire output.
private struct JSONStreamParser {
  /// Current bracket nesting depth (0 = outside all objects).
  private var bracketDepth: Int = 0

  /// Whether we're currently inside a string literal.
  private var inString: Bool = false

  /// Whether the previous character was an escape backslash.
  private var escaped: Bool = false

  /// Accumulated text for the current JSON object being parsed.
  private var currentObject: String = ""

  /// Whether we've encountered the opening array bracket.
  private var seenArrayStart: Bool = false

  /// Processes a single line from the stream and extracts any complete JSON objects.
  ///
  /// Tracks JSON structure across multiple lines, handling:
  /// - The opening `[` of the array
  /// - Complete JSON objects `{...}`
  /// - String literals with escaped quotes
  /// - Nested objects and arrays within log entries
  ///
  /// - Parameter line: A line from the log output stream.
  /// - Returns: Array of complete JSON object strings ready for parsing. Empty if no complete objects yet.
  mutating func processLine(_ line: String) -> [String] {
    var completeObjects: [String] = []

    for char in line {
      // Handle escape sequences in strings
      if escaped {
        currentObject.append(char)
        escaped = false
        continue
      }

      if char == "\\" && inString {
        currentObject.append(char)
        escaped = true
        continue
      }

      // Handle string boundaries
      if char == "\"" {
        inString.toggle()
        currentObject.append(char)
        continue
      }

      // If we're in a string, just accumulate
      if inString {
        currentObject.append(char)
        continue
      }

      // Track brackets outside of strings
      switch char {
      case "[":
        seenArrayStart = true
        bracketDepth += 1
        // Don't include array brackets in objects
        if bracketDepth > 1 {
          currentObject.append(char)
        }

      case "{":
        bracketDepth += 1
        currentObject.append(char)

      case "}":
        currentObject.append(char)
        bracketDepth -= 1

        // If we're back to array level (depth 1), we have a complete object
        if bracketDepth == 1 && seenArrayStart {
          let trimmed = currentObject.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
            completeObjects.append(trimmed)
          }
          currentObject = ""
        }

      case "]":
        bracketDepth -= 1
        // Don't include array brackets in objects
        if bracketDepth > 0 {
          currentObject.append(char)
        }

      default:
        // Only accumulate if we're inside an object
        if bracketDepth > 1 || (bracketDepth == 1 && !seenArrayStart) {
          currentObject.append(char)
        } else if bracketDepth == 1 && seenArrayStart && !char.isWhitespace && char != "," {
          // Start of a new object
          currentObject.append(char)
        }
      }
    }

    return completeObjects
  }

  /// Finalizes parsing and returns any remaining partial object.
  ///
  /// Should be called after all lines have been processed to handle
  /// edge cases where the stream ended mid-object.
  ///
  /// - Returns: The remaining partial object, or `nil` if parsing completed cleanly.
  mutating func finalize() -> String? {
    let trimmed = currentObject.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

// MARK: - Private Helpers

private extension LogCollector {
  /// Collects raw logs for a specific subsystem in syslog format using streaming.
  ///
  /// Streams output line-by-line instead of buffering, eliminating memory limits.
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
        error: .discarded
      ) { execution, outputSequence in
        var collectedLines: [String] = []
        var lineCount = 0

        // Stream lines and apply filtering
        for try await line in outputSequence.lines() {
          lineCount += 1

          // Report progress every 1000 lines
          if lineCount % 1000 == 0 {
            progressLogger?(lineCount, subsystem)
          }

          // Apply filter if present
          if let filter = filter {
            if matchesFilter(line, pattern: filter) {
              collectedLines.append(line)
            }
          } else {
            collectedLines.append(line)
          }
        }

        // Final progress report
        progressLogger?(lineCount, subsystem)

        return collectedLines.joined(separator: "\n")
      }

      if case .exited(let code) = result.terminationStatus, code != 0 {
        debugLogger?("log command returned non-zero exit code: \(code) for \(subsystem)")
      }

      return result.value
    } catch {
      errorLogger?("[ERROR] Subprocess execution failed for \(subsystem): \(error)")
      throw error
    }
  }

  /// Collects logs for a specific subsystem in JSON format using streaming.
  ///
  /// Streams JSON output and parses objects incrementally, eliminating buffer size limits
  /// and enabling progress reporting during long-running log collection.
  ///
  /// - Parameter subsystem: The subsystem identifier.
  /// - Returns: Array of parsed log entries.
  /// - Throws: An error if log collection fails.
  func collectLogsForSubsystem(_ subsystem: String) async throws -> [LogEntry] {
    // If we have a test data source, use the old approach
    if let dataSource = dataSource {
      let output = try await dataSource.fetchJSONLogs(subsystem: subsystem)
      return parseJSONLogOutput(output, subsystem: subsystem)
    }

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
        error: .discarded
      ) { execution, outputSequence in
        return try await parseJSONStream(outputSequence.lines(), subsystem: subsystem)
      }

      if case .exited(let code) = result.terminationStatus, code != 0 {
        debugLogger?("log command returned non-zero exit code: \(code) for \(subsystem)")
      }

      return result.value
    } catch {
      errorLogger?("[ERROR] Subprocess execution failed for \(subsystem): \(error)")
      throw error
    }
  }

  /// Parses JSON log entries from a line-by-line stream.
  ///
  /// Uses `JSONStreamParser` to detect complete JSON objects as they arrive,
  /// parses them immediately, and applies filters during parsing for efficiency.
  ///
  /// - Parameters:
  ///   - lines: Async sequence of lines from the log output.
  ///   - subsystem: The subsystem identifier for these logs.
  /// - Returns: Array of parsed and filtered log entries.
  /// - Throws: An error if streaming fails.
  func parseJSONStream(
    _ lines: AsyncBufferSequence.LineSequence<UTF8>,
    subsystem: String
  ) async throws -> [LogEntry] {
    var parser = JSONStreamParser()
    var entries: [LogEntry] = []
    var totalParsed = 0

    for try await line in lines {
      let completeObjects = parser.processLine(line)

      for jsonString in completeObjects {
        totalParsed += 1

        // Parse individual JSON object
        if let entry = parseJSONObject(jsonString, subsystem: subsystem) {
          entries.append(entry)
        }

        // Report progress every 100 parsed objects
        if totalParsed % 100 == 0 {
          progressLogger?(entries.count, subsystem)
        }
      }
    }

    // Handle any remaining partial object (shouldn't happen with valid JSON)
    if let remaining = parser.finalize() {
      debugLogger?("Warning: Incomplete JSON object at end of stream: \(remaining.prefix(100))...")
    }

    // Final progress report
    progressLogger?(entries.count, subsystem)
    debugLogger?("Parsed \(entries.count) entries from \(totalParsed) JSON objects for \(subsystem)")

    return entries
  }
}
