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

/// A source of log data for a specific subsystem, provided as an async stream of text lines.
///
/// Used for testing and replay functionality to inject log data without executing system commands.
public struct LogInput: Sendable {
  /// The subsystem identifier (e.g., "com.apple.HomeKit").
  public let subsystem: String
  
  /// A closure that produces an async stream of text lines (JSON log output).
  public let lines: @Sendable () -> AsyncThrowingStream<String, Error>
  
  /// Creates a new log input for a subsystem.
  ///
  /// - Parameters:
  ///   - subsystem: The subsystem identifier.
  ///   - lines: A closure that returns an async stream of text lines.
  public init(subsystem: String, lines: @escaping @Sendable () -> AsyncThrowingStream<String, Error>) {
    self.subsystem = subsystem
    self.lines = lines
  }
  
  /// Creates a log input from a complete JSON string (convenience for testing).
  ///
  /// Splits the JSON into lines and streams them.
  ///
  /// - Parameters:
  ///   - subsystem: The subsystem identifier.
  ///   - json: A complete JSON string containing log entries.
  public static func fromJSON(subsystem: String, json: String) -> LogInput {
    LogInput(subsystem: subsystem) {
      AsyncThrowingStream { continuation in
        for line in json.components(separatedBy: "\n") {
          continuation.yield(line)
        }
        continuation.finish()
      }
    }
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

  /// Maximum number of log entries to read from each log (nil = unlimited)
  public let entryLimit: Int?

  /// Optional test/replay log inputs mapped by subsystem name.
  ///
  /// When provided, these inputs are used instead of querying the system log.
  /// Each input provides an async stream of text lines for a specific subsystem.
  private let logInputs: [String: LogInput]?

  /// Callback for debug logging (required to integrate with main executable logging).
  public let debugLogger: (@Sendable (String) -> Void)?

  /// Callback for error logging (required to integrate with main executable logging).
  public let errorLogger: (@Sendable (String) -> Void)?

  /// Callback for progress reporting during log collection.
  ///
  /// Called periodically with the current entry count and subsystem name.
  /// Used to show progress to the user during long-running operations.
  public let progressLogger: (@Sendable (Int, String) -> Void)?

  /// Optional directory path for capturing raw JSON log data.
  ///
  /// When provided, the raw JSON output from `/usr/bin/log` is written to files
  /// in this directory, one file per subsystem (e.g., `com.apple.HomeKit.json`).
  /// The directory is created if it doesn't exist.
  public let captureDirectory: String?

  /// Creates a new log collector with specified configuration.
  ///
  /// - Parameters:
  ///   - timeInterval: Time range string (e.g., "14d", "6h").
  ///   - includeDebug: Whether to include debug-level logs.
  ///   - entryLimit: Maximum number of log entries to read from each log (nil = unlimited).
  ///   - logInputs: Optional array of log inputs for testing/replay (one per subsystem).
  ///   - debugLogger: Optional debug message callback.
  ///   - errorLogger: Optional error message callback.
  ///   - progressLogger: Optional progress reporting callback.
  ///   - captureDirectory: Optional directory path for capturing raw JSON log data.
  public init(
    timeInterval: String,
    includeDebug: Bool,
    entryLimit: Int? = nil,
    logInputs: [LogInput]? = nil,
    debugLogger: (@Sendable (String) -> Void)? = nil,
    errorLogger: (@Sendable (String) -> Void)? = nil,
    progressLogger: (@Sendable (Int, String) -> Void)? = nil,
    captureDirectory: String? = nil
  ) {
    self.timeInterval = timeInterval
    self.includeDebug = includeDebug
    self.entryLimit = entryLimit
    self.logInputs = logInputs?.reduce(into: [:]) { $0[$1.subsystem] = $1 }
    self.debugLogger = debugLogger
    self.errorLogger = errorLogger
    self.progressLogger = progressLogger
    self.captureDirectory = captureDirectory
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
    return entries.map { LogEntry($0) }
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
    return entry
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
          // If we have a log input for this subsystem, stream from it
          if let logInput = logInputs?[subsystem] {
            let decoder = makeEntryDecoder()
            var parser = JSONStreamParser()
            var totalParsed = 0
            var yielded = 0
            
            outer: for try await line in logInput.lines() {
              let completeObjects = parser.processLine(line)
              
              for jsonString in completeObjects {
                if let limit = entryLimit, yielded >= limit { break outer }
                totalParsed += 1
                
                if let entry = parseJSONEntryLoggingErrors(jsonString, decoder: decoder) {
                  continuation.yield(entry)
                  yielded += 1
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
            var yielded = 0

            // Accumulate JSON objects for capture if directory is specified
            var capturedObjects: [String] = []
            let shouldCapture = captureDirectory != nil

            outer: for try await line in outputSequence.lines() {
              let completeObjects = parser.processLine(line)

              for jsonString in completeObjects {
                if let limit = entryLimit, yielded >= limit { break outer }
                totalParsed += 1

                // Capture the raw JSON object if capture is enabled
                if shouldCapture {
                  capturedObjects.append(jsonString)
                }

                if let entry = parseJSONEntryLoggingErrors(jsonString, decoder: decoder) {
                  continuation.yield(entry)
                  yielded += 1
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

            // Write captured JSON to file if capture is enabled
            if let captureDir = captureDirectory, !capturedObjects.isEmpty {
              do {
                try writeCapturedJSON(capturedObjects, subsystem: subsystem, to: captureDir)
              } catch {
                errorLogger?("[ERROR] Failed to write captured JSON for \(subsystem): \(error)")
              }
            }
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
  /// Writes captured JSON objects to a file in the specified directory.
  ///
  /// Creates the directory if it doesn't exist, then writes the JSON objects
  /// as a properly formatted JSON array to a file named `{subsystem}.json`.
  ///
  /// - Parameters:
  ///   - objects: Array of JSON object strings to write.
  ///   - subsystem: The subsystem name, used for the filename.
  ///   - directory: The directory path to write to.
  /// - Throws: An error if directory creation or file writing fails.
  func writeCapturedJSON(_ objects: [String], subsystem: String, to directory: String) throws {
    let fileManager = FileManager.default
    let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)

    // Create the directory if it doesn't exist
    if !fileManager.fileExists(atPath: directory) {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      debugLogger?("Created capture directory: \(directory)")
    }

    // Build the JSON array string
    let jsonArray = "[\n" + objects.joined(separator: ",\n") + "\n]"

    // Write to file
    let filename = "\(subsystem).json"
    let fileURL = directoryURL.appending(path: filename)
    try jsonArray.write(to: fileURL, atomically: true, encoding: .utf8)
    debugLogger?("Captured \(objects.count) JSON objects to \(fileURL.path)")
  }

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

          collectedLines.append(line)
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
