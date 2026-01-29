import Foundation

/// A single log entry from the unified logging system.
///
/// Represents a parsed log message with metadata including timestamp, subsystem,
/// process name, severity level, and the message content. Provides computed
/// properties for identifying problematic entries and normalizing messages
/// for deduplication.
public struct LogEntry: Sendable {
  /// The timestamp when the log entry was created.
  public let timestamp: Date

  /// The subsystem that generated the log (e.g., "com.apple.HomeKit").
  public let subsystem: String

  /// The process name that generated the log (e.g., "homed", "Home").
  public let process: String

  /// The severity level of this log entry.
  public let level: LogLevel

  /// The log message content.
  public let message: String

  /// Creates a new log entry with the specified metadata and message.
  ///
  /// - Parameters:
  ///   - timestamp: When the log entry was created.
  ///   - subsystem: The subsystem that generated the log.
  ///   - process: The process name that generated the log.
  ///   - level: The severity level.
  ///   - message: The log message content.
  public init(
    timestamp: Date,
    subsystem: String,
    process: String,
    level: LogLevel,
    message: String
  ) {
    self.timestamp = timestamp
    self.subsystem = subsystem
    self.process = process
    self.level = level
    self.message = message
  }

  /// Whether this entry indicates an error or problem condition.
  ///
  /// Returns `true` if the log level is error or fault, or if the message
  /// contains keywords indicating failure conditions (failed, timeout,
  /// unreachable, not responding).
  public var isProblematic: Bool {
    level == .error || level == .fault
      || message.localizedStandardContains("failed")
      || message.localizedStandardContains("timeout")
      || message.localizedStandardContains("unreachable")
      || message.localizedStandardContains("not responding")
  }

  /// The message with variable values replaced by placeholders for deduplication.
  ///
  /// Normalizes the message by replacing UUIDs, hex addresses, and timestamps
  /// with placeholder tokens. This allows grouping similar log messages that
  /// differ only in specific identifiers or time values.
  public var normalizedMessage: String {
    var normalized = message

    // Remove UUIDs (8-4-4-4-12 format)
    let uuidPattern =
      #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    if let regex = try? NSRegularExpression(pattern: uuidPattern) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = regex.stringByReplacingMatches(
        in: normalized,
        range: range,
        withTemplate: "<UUID>"
      )
    }

    // Remove hex addresses (0x followed by hex digits)
    let hexPattern = #"0x[0-9A-Fa-f]+"#
    if let regex = try? NSRegularExpression(pattern: hexPattern) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = regex.stringByReplacingMatches(
        in: normalized,
        range: range,
        withTemplate: "<ADDR>"
      )
    }

    // Remove timestamps (common formats)
    let timestampPattern = #"\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+"#
    if let regex = try? NSRegularExpression(pattern: timestampPattern) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = regex.stringByReplacingMatches(
        in: normalized,
        range: range,
        withTemplate: "<TIMESTAMP>"
      )
    }

    return normalized
  }

  /// A unique key for grouping duplicate entries.
  ///
  /// Combines subsystem, log level, and normalized message to create a
  /// deduplication key. Entries with the same key represent the same
  /// type of log message with different variable values.
  public var deduplicationKey: String {
    "\(subsystem)|\(level.rawValue)|\(normalizedMessage)"
  }
}
