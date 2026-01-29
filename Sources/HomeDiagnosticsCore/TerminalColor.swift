import Foundation

/// ANSI color codes for terminal output.
///
/// Provides escape sequences for coloring and styling terminal text output.
/// Used to highlight errors, warnings, and metadata in the diagnostic output.
enum TerminalColor {
  /// Resets all formatting to terminal default.
  static let reset = "\u{001B}[0m"

  /// Makes text bright or bold.
  static let bold = "\u{001B}[1m"

  /// Makes text dim or faint.
  static let dim = "\u{001B}[2m"

  /// Colors text red, typically used for errors and faults.
  static let red = "\u{001B}[31m"

  /// Colors text yellow, typically used for warnings.
  static let yellow = "\u{001B}[33m"

  /// Colors text gray, typically used for metadata and timestamps.
  static let gray = "\u{001B}[90m"
}
