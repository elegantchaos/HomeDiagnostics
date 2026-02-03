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

  /// The category of the log entry (e.g., "Networking", "Accessory").
  public let category: String?

  /// Format string associated with the log entry, if available.
  /// Used for deduplication and normalization.
  public let formatString: String?

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
  ///   - category: The category of the log entry (default: nil).
  ///   - formatString: The format string associated with the log entry (default: nil).
  ///   - level: The severity level.
  ///   - message: The log message content.
  public init(
    timestamp: Date,
    subsystem: String,
    process: String,
    category: String? = nil,
    formatString: String? = nil,
    level: LogLevel,
    message: String
  ) {
    self.timestamp = timestamp
    self.subsystem = subsystem
    self.process = process
    self.category = category
    self.formatString = formatString
    self.level = level
    self.message = message
  }

  /// Whether this entry indicates an error or problem condition.
  ///
  /// Returns `true` if the log level is error or fault, or if the message
  /// contains keywords indicating failure conditions (failed, timeout,
  /// unreachable, not responding).
  public var isProblematic: Bool {
    level == .error || level == .fault || level == .warning
      || message.localizedStandardContains("failed")
      || message.localizedStandardContains("timeout")
      || message.localizedStandardContains("unreachable")
      || message.localizedStandardContains("not responding")
  }

  /// The message with variable values replaced by placeholders for deduplication.
  ///
  /// Normalizes the message by replacing variable values with generic placeholders
  /// to enable grouping of similar log messages. Applies multiple normalization passes:
  /// 1. Structural patterns (bracket prefixes, object descriptions)
  /// 2. Variable values (UUIDs, MACs, durations, timestamps, hex addresses, numbers)
  /// 3. Boolean literals (YES/NO)
  /// 4. Error domains
  /// 5. Whitespace normalization
  /// This creates less specific messages that are more likely to match,
  /// improving deduplication effectiveness.
  public var normalizedMessage: String {
    var normalized = message

    // Phase 1: Structural patterns (applied first for maximum generalization)

    // Replace bracket prefixes: [UUID/MAC+NUMBER/BOOL] → [<prefix>]
    // Example: [D3AAD67C-68AB-4261-86AC-7AB8969C6203/0B:10:14:18:2B:E3+1/NO] → [<prefix>]
    let prefixPattern =
      /\[[0-9A-Fa-f-]+\/[0-9A-Fa-f:]+\+\d+\/(YES|NO|yes|no)\]/
    normalized = normalized.replacing(prefixPattern, with: "[<prefix>]")

    // Replace object descriptions with memory addresses: <ClassName: 0xADDRESS> → <obj>
    // Example: <HMFMessage: 0x813f244b0> → <obj>
    let objectPattern = /<[A-Z][A-Za-z0-9]*:\s*0x[0-9A-Fa-f]+>/
    normalized = normalized.replacing(objectPattern, with: "<obj>")

    // Phase 2: Variable values (specific to general order to prevent false matches)

    // Replace UUIDs (8-4-4-4-12 format) with <id>
    let uuidPattern =
      /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/
    normalized = normalized.replacing(uuidPattern, with: "<id>")

    // Replace MAC addresses (6 pairs of hex digits separated by colons) with <mac>
    let macPattern =
      /[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}/
    normalized = normalized.replacing(macPattern, with: "<mac>")

    // Replace duration values (e.g., "1.234 seconds", "5.0 ms") with <duration>
    let durationPattern = /\d+\.?\d*\s*(seconds?|milliseconds?|ms|s)\b/
    normalized = normalized.replacing(durationPattern, with: "<duration>")

    // Replace timestamps (common formats) with <timestamp>
    let timestampPattern = /\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+/
    normalized = normalized.replacing(timestampPattern, with: "<timestamp>")

    // Replace hex addresses (0x followed by hex digits) with <addr>
    let hexPattern = /0x[0-9A-Fa-f]+/
    normalized = normalized.replacing(hexPattern, with: "<addr>")

    // Replace remaining floating point and integer numbers with <n>
    // This catches standalone numbers like "123", "45.67", etc.
    let numberPattern = /\b\d+\.?\d*\b/
    normalized = normalized.replacing(numberPattern, with: "<n>")

    // Phase 3: Boolean and error domain normalization

    // Replace boolean literals (YES/NO, yes/no, true/false) with <bool>
    let boolPattern = /\b(YES|NO|yes|no|true|false)\b/
    normalized = normalized.replacing(boolPattern, with: "<bool>")

    // Replace error domain names: Error Domain=SomeDomain → Error Domain=<domain>
    let errorDomainPattern = /Error Domain=[A-Za-z][A-Za-z0-9]*/
    normalized = normalized.replacing(errorDomainPattern, with: "Error Domain=<domain>")

    // Phase 4: Whitespace normalization

    // Collapse multiple spaces into single space
    let multiSpacePattern = /\s+/
    normalized = normalized.replacing(multiSpacePattern, with: " ")

    // Trim leading and trailing whitespace
    normalized = normalized.trimmingCharacters(in: .whitespaces)

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

  /// A format-string-based key used as a first-pass deduplication bucket.
  ///
  /// Uses the log's format string when present and falls back to the normalized
  /// message when the format string is missing or empty. The key includes the
  /// subsystem and log level for stability across sources.
  public var formatStringKey: String {
    let trimmed = formatString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmed.isEmpty {
      return "\(subsystem)|\(level.rawValue)|\(trimmed)"
    }
    return deduplicationKey
  }
}
