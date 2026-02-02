import Foundation
import Subprocess

/// Log input that provides data from an in-memory string.
///
/// Useful for testing with predetermined JSON data.
public struct StringLogInput: LogInput {
  /// The byte stream type used to create an async line sequence.
  public typealias ByteSequence = AsyncStream<UInt8>

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

  /// Returns an async sequence of text lines from this input.
  public func lines() async throws -> AsyncLineSequence<AsyncStream<UInt8>> {
    let byteStream = AsyncStream<UInt8> { continuation in
      for byte in json.utf8 {
        continuation.yield(byte)
      }
      continuation.finish()
    }
    return byteStream.lines
  }
}
