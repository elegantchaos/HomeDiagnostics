import Foundation

/// Creates log inputs from a previously captured session directory.
///
/// Reads JSON files created by the `--capture` option, enabling replay of
/// captured log data for analysis without querying the system log again.
/// Each subsystem's data is stored in a file named `{subsystem}.json`.
public struct CapturedSession: Sendable {
  /// The directory path containing captured JSON files.
  private let directoryPath: String
  
  /// The subsystems to read from the captured session.
  public static let defaultSubsystems = [
    "com.apple.Home",
    "com.apple.HomeKit",
    "com.apple.homed",
  ]
  
  /// Creates a new captured session.
  ///
  /// - Parameter directoryPath: Path to the directory containing captured JSON files.
  public init(directoryPath: String) {
    self.directoryPath = directoryPath
  }
  
  /// Creates log inputs for all subsystems in the captured session.
  ///
  /// - Parameter subsystems: The subsystem identifiers to create inputs for.
  ///   Defaults to the standard Home/HomeKit subsystems.
  /// - Returns: An array of `LogInput` objects for use with `LogCollector`.
  public func logInputs(for subsystems: [String] = defaultSubsystems) -> [LogInput] {
    subsystems.map { subsystem in
      let path = directoryPath
      return LogInput(subsystem: subsystem) {
        AsyncThrowingStream { continuation in
          Task {
            do {
              let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
              let filename = "\(subsystem).json"
              let fileURL = directoryURL.appending(path: filename)
              
              guard FileManager.default.fileExists(atPath: fileURL.path) else {
                // Return empty array if subsystem file doesn't exist
                continuation.yield("[]")
                continuation.finish()
                return
              }
              
              let content = try String(contentsOf: fileURL, encoding: .utf8)
              for line in content.components(separatedBy: "\n") {
                continuation.yield(line)
              }
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
        }
      }
    }
  }
}
