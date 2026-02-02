import Foundation
import Subprocess
import System

/// Runs the macOS unified log subprocess for a subsystem.
public struct SystemLogRunner: Sendable {
  /// The subsystem identifier to query.
  public let subsystem: String

  /// The time interval to look back.
  public let timeInterval: String

  /// Whether to include debug-level logs.
  public let includeDebug: Bool

  /// Optional callback for debug logging.
  public let debugLogger: (@Sendable (String) -> Void)?

  /// Creates a new system log runner.
  public init(
    subsystem: String,
    timeInterval: String,
    includeDebug: Bool,
    debugLogger: (@Sendable (String) -> Void)? = nil
  ) {
    self.subsystem = subsystem
    self.timeInterval = timeInterval
    self.includeDebug = includeDebug
    self.debugLogger = debugLogger
  }

  /// Returns the log command arguments for this runner.
  public func makeArguments() -> [String] {
    let levelPredicate = includeDebug ? "--info --debug" : "--info"

    return [
      "show",
      "--style", "json",
      "--last", timeInterval,
    ] + levelPredicate.components(separatedBy: " ") + [
      "--predicate", "subsystem == \"\(subsystem)\"",
    ]
  }

  /// Returns the syslog output for this runner.
  public func rawLogs() async throws -> String {
    let levelPredicate = includeDebug ? "--info --debug" : "--info"
    let arguments =
      [
        "show",
        "--style", "syslog",
        "--last", timeInterval,
      ] + levelPredicate.components(separatedBy: " ") + [
        "--predicate", "subsystem == \"\(subsystem)\"",
      ]

    let result = try await Subprocess.run(
      .path(FilePath("/usr/bin/log")),
      arguments: Arguments(arguments),
      output: .string(limit: 100 * 1024 * 1024),
      error: .discarded
    )

    return result.standardOutput ?? ""
  }

  /// Returns an async byte stream from the log subprocess.
  public func bytes() async throws -> AsyncThrowingStream<UInt8, Error> {
    let arguments = makeArguments()
    debugLogger?("Executing: /usr/bin/log \(arguments.joined(separator: " "))")

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let result = try await Subprocess.run(
            .path(FilePath("/usr/bin/log")),
            arguments: Arguments(arguments),
            error: .discarded
          ) { _, outputSequence in
            for try await line in outputSequence.lines() {
              for byte in line.utf8 {
                continuation.yield(byte)
              }
              continuation.yield(UInt8(ascii: "\n"))
            }
          }

          if case .exited(let code) = result.terminationStatus, code != 0 {
            debugLogger?("log command returned non-zero exit code: \(code) for \(subsystem)")
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  /// Captures logs to a file on disk.
  public func capture(to outputURL: URL) async throws {
    let arguments = makeArguments()
    debugLogger?("Capturing: /usr/bin/log \(arguments.joined(separator: " "))")

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
      debugLogger?("log command returned non-zero exit code: \(code) for \(subsystem)")
    }
  }
}
