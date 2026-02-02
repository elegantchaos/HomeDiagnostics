import ArgumentParser
import Foundation
import HomeDiagnosticsCore

/// Captures raw JSON log data to a directory for later replay.
///
/// Saves the raw JSON output from each subsystem to separate files,
/// enabling offline analysis or sharing of log data.
struct CaptureCommand: AsyncParsableCommand {
  /// Configuration for the capture subcommand.
  static let configuration = CommandConfiguration(
    commandName: "capture",
    abstract: "Capture raw JSON log data to a directory for later replay"
  )

  /// Time range options.
  @OptionGroup var time: TimeOptions

  /// Log collection options.
  @OptionGroup var collection: CollectionOptions

  /// The directory path to save captured JSON files.
  @Argument(help: "Directory path to save captured JSON files (default: Output/<timestamp>)")
  var directory: String?

  /// Generates a default capture directory path based on the current date and time.
  ///
  /// Creates a path in the format `Output/YYYY-MM-DD HH:MM`.
  ///
  /// - Returns: The default directory path string.
  private static func defaultCaptureDirectory() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    let timestamp = formatter.string(from: Date())
    return "Output/\(timestamp)"
  }

  /// Executes the capture command.
  ///
  /// - Throws: An error if log collection or file writing fails.
  func run() async throws {
    isVerbose = collection.verbose

    let outputDirectory = directory ?? Self.defaultCaptureDirectory()

    do {
      info("Starting HomeDiagnostics - Capture Mode")

      printErr("HomeDiagnostics - Capture Mode")
      printErr("==============================\n")

      let collector = LogCollector(
        timeInterval: time.timeInterval,
        includeDebug: collection.detailed,
        entryLimit: collection.entries,
        debugLogger: { debug($0) },
        errorLogger: { printErr($0) },
        progressLogger: { count, subsystem in
          let shortName = subsystem.replacingOccurrences(of: "com.apple.", with: "")
          printErr("  Collected \(count) entries from \(shortName)...")
        },
        captureDirectory: outputDirectory
      )

      printErr("Capturing logs from the last \(time.timeDescription)...")
      printErr("Output directory: \"\(outputDirectory)\"")
      if collection.detailed {
        printErr("(Including debug-level logs - this may take a while)")
      }
      printErr("")

      debug("Beginning log capture")

      // Stream logs to trigger capture (entries are written to files as a side effect)
      let logStream = collector.collectLogs()
      var entryCount = 0
      for try await _ in logStream {
        entryCount += 1
      }

      printErr("")
      printErr("Capture complete!")
      printErr("Total entries captured: \(entryCount)")
      printErr("Files written to: \(outputDirectory)")

      info("HomeDiagnostics capture completed successfully")
    } catch {
      printErr("[ERROR] Fatal error occurred: \(error)")
      printErr("\nError: \(error.localizedDescription)")
      throw error
    }
  }
}
