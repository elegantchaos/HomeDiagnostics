import Foundation

/// Protocol for abstracting log data sources during testing.
///
/// In production, `SystemLogDataSource` queries the macOS unified logging system.
/// In tests, mock implementations can provide predetermined JSON data without
/// executing system commands.
public protocol LogDataSource: Sendable {
  /// Fetches raw JSON log data for a specific subsystem.
  ///
  /// - Parameter subsystem: The subsystem identifier (e.g., "com.apple.HomeKit").
  /// - Returns: JSON string containing log entries from the unified logging system.
  /// - Throws: An error if log collection fails.
  func fetchJSONLogs(subsystem: String) async throws -> String
}
