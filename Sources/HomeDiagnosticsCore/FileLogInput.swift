import Foundation

/// Log input that reads from a JSON file on disk.
///
/// Streams the file contents line by line, suitable for replaying captured log sessions.
public struct FileLogInput: LogInput {
  /// The path to the JSON file.
  public let filePath: String
  
  /// A descriptive name for this input.
  public let name: String
  
  /// Creates a new file log input.
  ///
  /// - Parameters:
  ///   - filePath: Path to the JSON file.
  ///   - name: A descriptive name (defaults to the file path).
  public init(filePath: String, name: String? = nil) {
    self.filePath = filePath
    self.name = name ?? filePath
  }
  
  public func lines() -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          let fileURL = URL(fileURLWithPath: filePath)
          
          guard FileManager.default.fileExists(atPath: filePath) else {
            // Return empty array if file doesn't exist
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
