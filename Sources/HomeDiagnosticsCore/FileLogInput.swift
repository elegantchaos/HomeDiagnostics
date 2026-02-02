import Foundation
import Subprocess

/// Log input that reads from a JSON file on disk.
///
/// Streams the file contents line by line, suitable for replaying captured log sessions.
public struct FileLogInput: LogInput {
  /// The byte stream type used to create an async line sequence.
  public typealias ByteSequence = URLSession.AsyncBytes

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

  /// Returns an async byte stream from this input.
  public func bytes() async throws -> URLSession.AsyncBytes {
    let fileURL = URL(fileURLWithPath: filePath)
    let (stream, _) = try await URLSession.shared.bytes(from: fileURL)
    return stream
  }
}
