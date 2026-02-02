import Foundation

/// Log input that provides data from an in-memory string.
///
/// Useful for testing with predetermined JSON data.
public struct StringLogInput: LogInput {
  /// The JSON string containing log entries.
  public let json: String
  
  /// A descriptive name for this input.
  public let name: String
  
  /// Creates a new string log input.
  ///
  /// - Parameters:
  ///   - json: The JSON string containing log entries.
  ///   - name: A descriptive name for this input.
  public init(json: String, name: String) {
    self.json = json
    self.name = name
  }
  
  public func lines() -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      for line in json.components(separatedBy: "\n") {
        continuation.yield(line)
      }
      continuation.finish()
    }
  }
}
