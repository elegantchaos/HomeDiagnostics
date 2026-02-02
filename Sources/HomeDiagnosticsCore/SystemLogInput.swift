import Foundation

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

  /// The system log runner used to execute the subprocess.
  private let runner: SystemLogRunner

  /// Creates a new system log input.
  ///
  /// - Parameters:
  ///   - subsystem: The subsystem identifier to query.
  ///   - timeInterval: Time range string (e.g., "14d", "6h").
  ///   - includeDebug: Whether to include debug-level logs.
  ///   - debugLogger: Optional debug message callback.
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
    self.runner = SystemLogRunner(
      subsystem: subsystem,
      timeInterval: timeInterval,
      includeDebug: includeDebug,
      debugLogger: debugLogger
    )
  }

  /// A descriptive name for this input.
  public var name: String { subsystem }

  /// Returns an async byte stream from this input.
  public func bytes() async throws -> AsyncThrowingStream<UInt8, Error> {
    try await runner.bytes()
  }
}
