import Foundation
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif


private struct RawLogEntry: Codable {
  let timestamp: Date
  let messageType: LogLevel
  let eventMessage: String
  let subsystem: String
  let processImagePath: String
}

private extension LogEntry {
  init(_ raw: RawLogEntry) {
    timestamp = raw.timestamp
    subsystem = raw.subsystem
    process = (raw.processImagePath as NSString).lastPathComponent
    level = raw.messageType
    message = raw.eventMessage
  }
}

/// Collects and parses logs from the macOS unified logging system.
///
/// Queries multiple Home/HomeKit subsystems and aggregates their log entries.
/// Supports filtering by text/regex patterns, error-only mode, and test data injection.
/// Uses `/usr/bin/log` command for JSON-formatted output to ensure accurate metadata.
public struct LogCollector: Sendable {
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
  public let debugLogger: (@Sendable (String) -> Void)?

  /// Callback for error logging (required to integrate with main executable logging).
  public let errorLogger: (@Sendable (String) -> Void)?

  /// Callback for progress reporting during log collection.
  ///
  /// Called periodically with the current entry count and subsystem name.
  /// Used to show progress to the user during long-running operations.
  public let progressLogger: (@Sendable (Int, String) -> Void)?

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
    debugLogger: (@Sendable (String) -> Void)? = nil,
    errorLogger: (@Sendable (String) -> Void)? = nil,
    progressLogger: (@Sendable (Int, String) -> Void)? = nil
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

  public func makeEntryDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ"
    decoder.dateDecodingStrategy = JSONDecoder.DateDecodingStrategy.custom {
      let container = try $0.singleValueContainer()
      let string = try container.decode(String.self)
      if let date = formatter.date(from: string) {
        return date
      }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
    }

    return decoder
  }

  /// Collects and parses logs from all Home and HomeKit subsystems as a stream.
  ///
  /// Streams entries from com.apple.Home, com.apple.HomeKit, and com.apple.homed concurrently,
  /// applies filters during parsing, and yields `LogEntry` items as they arrive.
  ///
  /// - Returns: An async throwing stream of `LogEntry` objects.
  public func collectLogs() -> AsyncThrowingStream<LogEntry, Error> {
    // Delegate to the concurrent streaming implementation.
    // Consumers should iterate the stream and process entries incrementally.
    streamLogs()
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

  /// Parses a JSON list of entries.
  /// For testing purposes only.
  public func parseJSONEntries(_ output: String, subsystem: String) throws -> [LogEntry] {
    let data = output.data(using: .utf8)!
    let decoder = makeEntryDecoder()
    let entries = try decoder.decode([RawLogEntry].self, from: data)
    return entries.compactMap { filteredEntry(LogEntry($0)) }
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

  public func parseJSONEntryLoggingErrors(_ jsonString: String, decoder: JSONDecoder) -> LogEntry? {
    do {
      return try parseJSONEntry(jsonString, decoder: decoder)
    } catch {
      debugLogger?("Failed to parse JSON object \(error)")
      return nil
    }
  }

  public func parseJSONEntry(_ jsonString: String, decoder: JSONDecoder) throws -> LogEntry? {
    guard let data = jsonString.data(using: .utf8) else {
      throw NSError(domain: "LogCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to UTF-8 data"])
    }

    let parsed = try decoder.decode(RawLogEntry.self, from: data)
    let entry = LogEntry(parsed)
    return filteredEntry(entry)
  }

  public func filteredEntry(_ entry: LogEntry) -> LogEntry? {
    // Apply filters
    var shouldInclude = true

    // Filter for errors only if requested
    if errorsOnly {
      shouldInclude = shouldInclude && entry.isProblematic
    }

    // Apply filter if provided
    if let filter = filter {
      shouldInclude = shouldInclude && matchesFilter(entry.message, pattern: filter)
    }

    return shouldInclude ? entry : nil
  }


  // MARK: - Public Streaming APIs

  /// Streams log entries asynchronously for all subsystems.
  ///
  /// Provides continuous incremental parsing and filtering of logs as they are streamed,
  /// reporting progress via callbacks. Useful for live or large log collections.
  ///
  /// - Parameter subsystems: Optional array of subsystem identifiers to query.
  ///   If `nil`, defaults to Home/HomeKit subsystems.
  /// - Returns: An async throwing stream of `LogEntry` objects.
  public func streamLogs(subsystems: [String]? = nil) -> AsyncThrowingStream<LogEntry, Error> {
    let subsystemsToUse =
      subsystems ?? [
        "com.apple.Home",
        "com.apple.HomeKit",
        "com.apple.homed",
      ]

    return AsyncThrowingStream { continuation in
      // Launch one task per subsystem to stream concurrently
      let tasks = subsystemsToUse.map { subsystem in
        Task.detached(priority: nil) { [subsystem] in
          do {
            for try await entry in streamLogsForSubsystem(subsystem) {
              continuation.yield(entry)
            }
          } catch {
            // Propagate the first error and let others be cancelled
            continuation.finish(throwing: error)
          }
        }
      }

      // A supervisor task waits for all subsystem tasks to finish then completes the stream
      let supervisor = Task.detached(priority: nil) {
        // Wait for all tasks to finish (ignoring their return values)
        for task in tasks {
          _ = await task.result
        }
        continuation.finish()
      }

      continuation.onTermination = { @Sendable _ in
        // Cancel all child tasks and the supervisor when the stream is terminated
        for task in tasks { task.cancel() }
        supervisor.cancel()
      }
    }
  }

  /// Streams log entries asynchronously for a specific subsystem.
  ///
  /// Runs the `/usr/bin/log` command with JSON output and incrementally parses log entries,
  /// filtering as configured. Reports progress via callbacks.
  ///
  /// - Parameter subsystem: The subsystem identifier to query.
  /// - Returns: An async throwing stream of `LogEntry` objects.
  public func streamLogsForSubsystem(_ subsystem: String) -> AsyncThrowingStream<LogEntry, Error> {
    AsyncThrowingStream { continuation in
      let task = Task.detached(priority: nil) { [subsystem] in
        do {
          // If we have a test data source, simulate streaming by parsing all at once
          if let dataSource = dataSource {
            let output = try await dataSource.fetchJSONLogs(subsystem: subsystem)
            let entries = try! parseJSONEntries(output, subsystem: subsystem)
            for entry in entries {
              continuation.yield(entry)
            }
            continuation.finish()
            return
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

          let decoder = makeEntryDecoder()
          let result = try await Subprocess.run(
            .path(FilePath("/usr/bin/log")),
            arguments: Arguments(arguments),
            error: .discarded
          ) { execution, outputSequence in
            var parser = JSONStreamParser()
            var totalParsed = 0

            for try await line in outputSequence.lines() {
              let completeObjects = parser.processLine(line)

              for jsonString in completeObjects {
                totalParsed += 1

                if let entry = parseJSONEntryLoggingErrors(jsonString, decoder: decoder) {
                  continuation.yield(entry)
                }

                if totalParsed % 1000 == 0 {
                  progressLogger?(totalParsed, subsystem)
                }
              }
            }

            if let remaining = parser.finalize() {
              debugLogger?("Warning: Incomplete JSON object at end of stream: \(remaining.prefix(100))...")
            }

            progressLogger?(totalParsed, subsystem)
          }

          if case .exited(let code) = result.terminationStatus, code != 0 {
            debugLogger?("log command returned non-zero exit code: \(code) for \(subsystem)")
          }

          continuation.finish()
        } catch {
          errorLogger?("[ERROR] Subprocess execution failed for \(subsystem): \(error)")
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
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


}
