import Foundation

/// Logging severity levels for Home and HomeKit diagnostic messages.
///
/// Represents the severity of a log entry, from least to most severe.
/// Conforms to `Comparable` to allow sorting by severity.
public enum LogLevel: String, Comparable, Sendable {
  /// Debug-level message, typically verbose implementation details.
  case debug = "Debug"

  /// Informational message about normal operations.
  case info = "Info"

  /// Warning message indicating a potential issue.
  case warning = "Warning"

  /// Error message indicating a failure condition.
  case error = "Error"

  /// Fault message indicating a critical system failure.
  case fault = "Fault"

  /// Compares two log levels by severity.
  ///
  /// - Parameters:
  ///   - lhs: The left-hand log level.
  ///   - rhs: The right-hand log level.
  /// - Returns: `true` if `lhs` is less severe than `rhs`.
  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    let order: [LogLevel] = [.debug, .info, .warning, .error, .fault]
    guard let lhsIndex = order.firstIndex(of: lhs),
      let rhsIndex = order.firstIndex(of: rhs)
    else {
      return false
    }
    return lhsIndex < rhsIndex
  }
}
