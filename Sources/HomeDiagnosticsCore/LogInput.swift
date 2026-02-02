import Foundation
import Subprocess

/// A source of log data that provides an async byte stream.
///
/// Implementations provide log data from various sources:
/// - `SystemLogInput`: Queries the macOS unified logging system via subprocess
/// - `FileLogInput`: Reads from a JSON file on disk
/// - `StringLogInput`: Provides data from an in-memory string
public protocol LogInput: Sendable {
  associatedtype ByteSequence: AsyncSequence where ByteSequence.Element == UInt8

  /// A descriptive name for this input (e.g., subsystem name or file path).
  var name: String { get }

  /// Returns an async byte stream from this input.
  ///
  /// Each call returns a fresh sequence that can be iterated independently.
  func bytes() async throws -> ByteSequence
}

public extension LogInput {
  /// Returns an async sequence of text lines from this input.
  ///
  /// Each call returns a fresh sequence that can be iterated independently.
  /// The sequence yields individual lines of JSON log output.
  func lines() async throws -> AsyncLineSequence<ByteSequence> {
    try await bytes().lines
  }
}
