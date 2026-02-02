import Foundation

/// Creates log inputs from a previously captured session directory.
///
/// Reads JSON files created by the `--capture` option, enabling replay of
/// captured log data for analysis without querying the system log again.
/// Each subsystem's data is stored in a file named `{subsystem}.json`.
public struct CapturedSession: Sendable {
  /// The directory path containing captured JSON files.
  private let directoryPath: String
  
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
  /// - Returns: An array of `FileLogInput` instances for use with `LogCollector`.
  public func logInputs(for subsystems: [String] = defaultHomeKitSubsystems) -> [any LogInput] {
    subsystems.map { subsystem in
      let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
      let filename = "\(subsystem).json"
      let fileURL = directoryURL.appending(path: filename)
      return FileLogInput(filePath: fileURL.path, name: subsystem)
    }
  }
}
