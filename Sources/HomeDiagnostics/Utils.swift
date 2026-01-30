//
//  File.swift
//  HomeDiagnostics
//
//  Created by Sam Deane on 30/01/2026.
//

import Foundation

/// Thread-safe structure for writing to standard error.
struct StandardError: TextOutputStream, Sendable {
  /// The file handle for standard error output.
  private static let handle = FileHandle.standardError
  
  /// Writes a string to standard error.
  ///
  /// - Parameter string: The string to write.
  public func write(_ string: String) {
    Self.handle.write(Data(string.utf8))
  }
}

/// Global standard error stream instance.
nonisolated(unsafe) private var stderr = StandardError()

/// Prints a message to standard error.
///
/// - Parameter message: The message to print.
func printErr(_ message: String) {
  print(message, to: &stderr)
}

/// Prints a debug message to standard error when verbose mode is enabled.
///
/// - Parameter message: The debug message to print.
func debug(_ message: String) {
  if isVerbose {
    printErr("[DEBUG] \(message)")
  }
}

/// Prints an info message to standard error when verbose mode is enabled.
///
/// - Parameter message: The info message to print.
func info(_ message: String) {
  if isVerbose {
    printErr("[INFO] \(message)")
  }
}

/// Global flag indicating whether verbose output is enabled.
nonisolated(unsafe) var isVerbose = false
