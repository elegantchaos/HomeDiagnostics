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

/// Collects and parses logs from one or more `LogInput` sources.
///
/// Processes multiple inputs in parallel and yields `LogEntry` objects as an async stream.
/// Supports entry limits and progress reporting.
public struct LogCollector<Input: LogInput>: Sendable {
  /// Maximum number of log entries to read from each input (nil = unlimited).
  public let entryLimit: Int?

  /// Callback for debug logging.
  public let debugLogger: (@Sendable (String) -> Void)?

  /// Callback for error logging.
  public let errorLogger: (@Sendable (String) -> Void)?

  /// Callback for progress reporting during log collection.
  ///
  /// Called periodically with the current entry count and input name.
  public let progressLogger: (@Sendable (Int, String) -> Void)?

  /// Creates a new log collector.
  ///
  /// - Parameters:
  ///   - entryLimit: Maximum entries per input (nil = unlimited).
  ///   - debugLogger: Optional debug message callback.
  ///   - errorLogger: Optional error message callback.
  ///   - progressLogger: Optional progress reporting callback.
  public init(
    entryLimit: Int? = nil,
    debugLogger: (@Sendable (String) -> Void)? = nil,
    errorLogger: (@Sendable (String) -> Void)? = nil,
    progressLogger: (@Sendable (Int, String) -> Void)? = nil
  ) {
    self.entryLimit = entryLimit
    self.debugLogger = debugLogger
    self.errorLogger = errorLogger
    self.progressLogger = progressLogger
  }

  /// Creates a JSON decoder configured for parsing log entries.
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

  /// Collects and parses logs from multiple inputs in parallel.
  ///
  /// Streams entries from all inputs concurrently and yields `LogEntry` items as they arrive.
  ///
  /// - Parameter inputs: The log inputs to process.
  /// - Returns: An async throwing stream of `LogEntry` objects.
  public func collectLogs(from inputs: [Input]) -> AsyncThrowingStream<LogEntry, Error> {
    AsyncThrowingStream { continuation in
      // Launch one task per input to stream concurrently
      let tasks = inputs.map { input in
        Task.detached(priority: nil) {
          do {
            for try await entry in streamEntries(from: input) {
              continuation.yield(entry)
            }
          } catch {
            // Propagate the first error and let others be cancelled
            continuation.finish(throwing: error)
          }
        }
      }

      // A supervisor task waits for all input tasks to finish then completes the stream
      let supervisor = Task.detached(priority: nil) {
        for task in tasks {
          _ = await task.result
        }
        continuation.finish()
      }

      continuation.onTermination = { @Sendable _ in
        for task in tasks { task.cancel() }
        supervisor.cancel()
      }
    }
  }

  /// Streams log entries from a single input.
  ///
  /// Parses JSON log entries incrementally as they arrive in the stream.
  ///
  /// - Parameter input: The log input to process.
  /// - Returns: An async throwing stream of `LogEntry` objects.
  public func streamEntries(from input: Input) -> AsyncThrowingStream<LogEntry, Error> {
    AsyncThrowingStream { continuation in
      let task = Task.detached(priority: nil) {
        do {
          let decoder = makeEntryDecoder()
          var parser = JSONStreamParser()
          var totalParsed = 0
          var yielded = 0
          let inputName = input.name

          outer: for try await line in try await input.lines() {
            let completeObjects = parser.processLine(line)

            for jsonString in completeObjects {
              if let limit = entryLimit, yielded >= limit { break outer }
              totalParsed += 1

              if let entry = parseJSONEntryLoggingErrors(jsonString, decoder: decoder) {
                continuation.yield(entry)
                yielded += 1
              }

              if totalParsed % 1000 == 0 {
                progressLogger?(totalParsed, inputName)
              }
            }
          }

          if let remaining = parser.finalize() {
            debugLogger?("Warning: Incomplete JSON object at end of stream: \(remaining.prefix(100))...")
          }

          progressLogger?(totalParsed, inputName)
          continuation.finish()
        } catch {
          errorLogger?("[ERROR] Failed to process input \(input.name): \(error)")
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  /// Captures raw JSON logs for the provided system inputs and writes them to disk.
  ///
  /// - Parameters:
  ///   - inputs: System log inputs to capture.
  ///   - directory: Directory path to write captured log files.
  /// - Returns: The total number of lines captured across all inputs.
  public func captureLogs(from inputs: [Input], to directory: String) async throws -> Int where Input == SystemLogInput {
    let fileManager = FileManager.default
    let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
    if !fileManager.fileExists(atPath: directory) {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    return try await withThrowingTaskGroup(of: Int.self) { group in
      for input in inputs {
        group.addTask {
          let outputURL = directoryURL.appending(path: "\(input.subsystem).json")
          let arguments = input.makeArguments()
          let outputPath = FilePath(outputURL.path)
          let outputFile = try FileDescriptor.open(
            outputPath,
            .writeOnly,
            options: [.create, .truncate],
            permissions: .ownerReadWrite
          )
          defer { try? outputFile.close() }

          let result = try await Subprocess.run(
            .path(FilePath("/usr/bin/log")),
            arguments: Arguments(arguments),
            output: .fileDescriptor(outputFile, closeAfterSpawningProcess: false),
            error: .discarded
          )

          if case .exited(let code) = result.terminationStatus, code != 0 {
            debugLogger?("log command returned non-zero exit code: \(code) for \(input.subsystem)")
          }

          let lineCount = try countLines(in: outputURL)
          progressLogger?(lineCount, input.subsystem)
          return lineCount
        }
      }

      var totalLines = 0
      for try await count in group {
        totalLines += count
      }
      return totalLines
    }
  }

  // MARK: - JSON Parsing Helpers

  /// Parses a JSON list of entries (for testing).
  public func parseJSONEntries(_ output: String, subsystem: String) throws -> [LogEntry] {
    let data = output.data(using: .utf8)!
    let decoder = makeEntryDecoder()
    let entries = try decoder.decode([RawLogEntry].self, from: data)
    return entries.map { LogEntry($0) }
  }

  /// Parses a single JSON entry, logging errors instead of throwing.
  public func parseJSONEntryLoggingErrors(_ jsonString: String, decoder: JSONDecoder) -> LogEntry? {
    do {
      return try parseJSONEntry(jsonString, decoder: decoder)
    } catch {
      debugLogger?("Failed to parse JSON object \(error)")
      return nil
    }
  }

  /// Parses a single JSON entry string into a LogEntry.
  public func parseJSONEntry(_ jsonString: String, decoder: JSONDecoder) throws -> LogEntry? {
    guard let data = jsonString.data(using: .utf8) else {
      throw NSError(domain: "LogCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to UTF-8 data"])
    }
    let parsed = try decoder.decode(RawLogEntry.self, from: data)
    return LogEntry(parsed)
  }
}

/// Helpers for system log capture utilities.
private extension LogCollector where Input == SystemLogInput {
  /// Counts the number of lines in a text file.
  func countLines(in url: URL) throws -> Int {
    let contents = try String(contentsOf: url, encoding: .utf8)
    return contents.split(separator: "\n", omittingEmptySubsequences: false).count
  }
}

// MARK: - JSON Stream Parser

/// State machine for parsing JSON objects from a line-by-line stream.
///
/// The unified logging system outputs JSON as a single array `[{...}, {...}, ...]`.
/// This parser tracks bracket depth and string boundaries to detect complete JSON objects
/// as they arrive in the stream, allowing incremental parsing without buffering the entire output.
struct JSONStreamParser {
  private var bracketDepth: Int = 0
  private var inString: Bool = false
  private var escaped: Bool = false
  private var currentObject: String = ""
  private var seenArrayStart: Bool = false

  /// Processes a single line and extracts any complete JSON objects.
  mutating func processLine(_ line: String) -> [String] {
    var completeObjects: [String] = []

    for char in line {
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

      if char == "\"" {
        inString.toggle()
        currentObject.append(char)
        continue
      }

      if inString {
        currentObject.append(char)
        continue
      }

      switch char {
        case "[":
          seenArrayStart = true
          bracketDepth += 1
          if bracketDepth > 1 {
            currentObject.append(char)
          }

        case "{":
          bracketDepth += 1
          currentObject.append(char)

        case "}":
          currentObject.append(char)
          bracketDepth -= 1
          if bracketDepth == 1 && seenArrayStart {
            let trimmed = currentObject.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
              completeObjects.append(trimmed)
            }
            currentObject = ""
          }

        case "]":
          bracketDepth -= 1
          if bracketDepth > 0 {
            currentObject.append(char)
          }

        default:
          if bracketDepth > 1 || (bracketDepth == 1 && !seenArrayStart) {
            currentObject.append(char)
          } else if bracketDepth == 1 && seenArrayStart && !char.isWhitespace && char != "," {
            currentObject.append(char)
          }
      }
    }

    return completeObjects
  }

  /// Finalizes parsing and returns any remaining partial object.
  mutating func finalize() -> String? {
    let trimmed = currentObject.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
