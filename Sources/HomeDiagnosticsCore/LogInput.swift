import Foundation

/// A source of log data that provides an async stream of text lines.
///
/// Implementations provide log data from various sources:
/// - `SystemLogInput`: Queries the macOS unified logging system via subprocess
/// - `FileLogInput`: Reads from a JSON file on disk
/// - `StringLogInput`: Provides data from an in-memory string
/// - `StreamLogInput`: Wraps an existing async stream
public protocol LogInput: Sendable {
  /// A descriptive name for this input (e.g., subsystem name or file path).
  var name: String { get }
  
  /// Returns an async stream of text lines from this input.
  ///
  /// Each call returns a fresh stream that can be iterated independently.
  /// The stream yields individual lines of JSON log output.
  func lines() -> AsyncThrowingStream<String, Error>
}

// MARK: - Default Subsystems

/// Standard Home/HomeKit subsystems to query.
public let defaultHomeKitSubsystems = [
  "com.apple.Home",
  "com.apple.HomeKit",
  "com.apple.homed",
]

/// Creates system log inputs for all default HomeKit subsystems.
///
/// - Parameters:
///   - timeInterval: Time range string (e.g., "14d", "6h").
///   - includeDebug: Whether to include debug-level logs.
///   - debugLogger: Optional debug message callback.
///   - captureDirectory: Optional directory for capturing raw JSON.
/// - Returns: Array of `SystemLogInput` instances for each subsystem.
public func makeSystemLogInputs(
  timeInterval: String,
  includeDebug: Bool,
  debugLogger: (@Sendable (String) -> Void)? = nil,
  captureDirectory: String? = nil
) -> [any LogInput] {
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
