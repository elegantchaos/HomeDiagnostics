import Foundation

/// Log data source that reads from a previously captured session directory.
///
/// Reads JSON files created by the `--capture` option, enabling replay of
/// captured log data for analysis without querying the system log again.
/// Each subsystem's data is stored in a file named `{subsystem}.json`.
public struct CapturedSessionDataSource: LogDataSource {
  /// The directory path containing captured JSON files.
  private let directoryPath: String

  /// Creates a new captured session data source.
  ///
  /// - Parameter directoryPath: Path to the directory containing captured JSON files.
  public init(directoryPath: String) {
    self.directoryPath = directoryPath
  }

  /// Fetches raw JSON log data for a specific subsystem from a captured file.
  ///
  /// Reads the JSON file named `{subsystem}.json` from the session directory.
  ///
  /// - Parameter subsystem: The subsystem identifier (e.g., "com.apple.HomeKit").
  /// - Returns: JSON string containing log entries from the captured file.
  /// - Throws: An error if the file doesn't exist or cannot be read.
  public func fetchJSONLogs(subsystem: String) async throws -> String {
    let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
    let filename = "\(subsystem).json"
    let fileURL = directoryURL.appending(path: filename)

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      // Return empty array if subsystem file doesn't exist
      return "[]"
    }

    return try String(contentsOf: fileURL, encoding: .utf8)
  }
}
