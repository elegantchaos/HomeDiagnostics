import Foundation

/// Log input that wraps an existing async stream of strings.
///
/// Useful for custom streaming scenarios or adapting other async sources.
public struct StreamLogInput: LogInput {
  /// A descriptive name for this input.
  public let name: String
  
  /// A closure that produces the async stream.
  private let streamFactory: @Sendable () -> AsyncThrowingStream<String, Error>
  
  /// Creates a new stream log input.
  ///
  /// - Parameters:
  ///   - name: A descriptive name for this input.
  ///   - stream: A closure that returns an async stream of text lines.
  public init(name: String, stream: @escaping @Sendable () -> AsyncThrowingStream<String, Error>) {
    self.name = name
    self.streamFactory = stream
  }
  
  public func lines() -> AsyncThrowingStream<String, Error> {
    streamFactory()
  }
}
