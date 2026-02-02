import Foundation
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

/// Log input that queries the macOS unified logging system via `/usr/bin/log`.
///
/// Executes the log command with JSON output and streams the results line by line.
public struct SystemLogInput: LogInput {
  /// The byte stream type used to create an async line sequence.
  public typealias ByteSequence = AsyncThrowingStream<UInt8, Error>

  /// The subsystem identifier to query (e.g., "com.apple.HomeKit").
  public let subsystem: String

  /// The time interval to look back (e.g., "14d", "6h").
  public let timeInterval: String

  /// Whether to include debug-level logs.
  public let includeDebug: Bool

  /// Optional callback for debug logging.
  public let debugLogger: (@Sendable (String) -> Void)?

  /// Optional directory path for capturing raw JSON log data.
  public let captureDirectory: String?

  /// Standard Home/HomeKit subsystems to query.
  public static let defaultHomeKitSubsystems = [
    "com.apple.Home",
    "com.apple.HomeKit",
    "com.apple.homed",
  ]

  /// Creates a new system log input.
  ///
  /// - Parameters:
  ///   - subsystem: The subsystem identifier to query.
  ///   - timeInterval: Time range string (e.g., "14d", "6h").
  ///   - includeDebug: Whether to include debug-level logs.
  ///   - debugLogger: Optional debug message callback.
  ///   - captureDirectory: Optional directory for capturing raw JSON.
  public init(
    subsystem: String,
    timeInterval: String,
    includeDebug: Bool,
    debugLogger: (@Sendable (String) -> Void)? = nil,
    captureDirectory: String? = nil
  ) {
    self.subsystem = subsystem
    self.timeInterval = timeInterval
    self.includeDebug = includeDebug
    self.debugLogger = debugLogger
    self.captureDirectory = captureDirectory
  }

  /// A descriptive name for this input.
  public var name: String { subsystem }

  /// Returns an async sequence of text lines from this input.
  public func lines() async throws -> AsyncLineSequence<AsyncThrowingStream<UInt8, Error>> {
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

    let byteStream = AsyncThrowingStream<UInt8, Error> { continuation in
      let task = Task {
        do {
          let result = try await Subprocess.run(
            .path(FilePath("/usr/bin/log")),
            arguments: Arguments(arguments),
            error: .discarded
          ) { _, outputSequence in
            var capturedLines: [String] = []
            let shouldCapture = captureDirectory != nil

            for try await line in outputSequence.lines() {
              if shouldCapture {
                capturedLines.append(line)
              }
              for byte in line.utf8 {
                continuation.yield(byte)
              }
              continuation.yield(UInt8(ascii: "\n"))
            }

            // Write captured data if capture is enabled
            if let captureDir = captureDirectory, !capturedLines.isEmpty {
              try? writeCapturedLines(capturedLines, to: captureDir)
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

    return byteStream.lines
  }

  private func writeCapturedLines(_ lines: [String], to directory: String) throws {
    let fileManager = FileManager.default
    let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)

    if !fileManager.fileExists(atPath: directory) {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    let content = lines.joined(separator: "\n")
    let filename = "\(subsystem).json"
    let fileURL = directoryURL.appending(path: filename)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    debugLogger?("Captured JSON to \(fileURL.path)")
  }


  /// Creates system log inputs for all default HomeKit subsystems.
  ///
  /// - Parameters:
  ///   - timeInterval: Time range string (e.g., "14d", "6h").
  ///   - includeDebug: Whether to include debug-level logs.
  ///   - debugLogger: Optional debug message callback.
  ///   - captureDirectory: Optional directory for capturing raw JSON.
  /// - Returns: Array of `SystemLogInput` instances for each subsystem.
  public static func makeSystemLogInputs(
    timeInterval: String,
    includeDebug: Bool,
    debugLogger: (@Sendable (String) -> Void)? = nil,
    captureDirectory: String? = nil
  ) -> [SystemLogInput] {
    defaultHomeKitSubsystems.map { subsystem in
      SystemLogInput(
        subsystem: subsystem,
        timeInterval: timeInterval,
        includeDebug: includeDebug,
        debugLogger: debugLogger,
        captureDirectory: captureDirectory
      )
    }
  }
}
