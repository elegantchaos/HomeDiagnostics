import ArgumentParser
import Foundation
import HomeDiagnosticsCore

/// Replays and analyzes logs from a previously captured session.
///
/// Reads JSON files from a captured session directory and performs
/// the same analysis as the analyze command, without querying system logs.
struct ReplayCommand: AsyncParsableCommand {
  /// Configuration for the replay subcommand.
  static let configuration = CommandConfiguration(
    commandName: "replay",
    abstract: "Replay and analyze logs from a previously captured session"
  )

  /// Log collection options.
  @OptionGroup var collection: CollectionOptions

  /// Output formatting options.
  @OptionGroup var output: OutputOptions

  /// The directory path containing captured JSON files.
  @Argument(help: "Directory path containing captured JSON files")
  var directory: String

  /// Executes the replay command.
  ///
  /// - Throws: An error if file reading or analysis fails.
  func run() async throws {
    isVerbose = collection.verbose

    do {
      info("Starting HomeDiagnostics - Replay Mode")

      printErr("HomeDiagnostics - Replay Mode")
      printErr("=============================\n")

      let capturedSession = CapturedSession(directoryPath: directory)
      let logInputs = capturedSession.logInputs()

      let collector = LogCollector<FileLogInput>(
        entryLimit: collection.entries,
        debugLogger: { debug($0) },
        errorLogger: { printErr($0) },
        progressLogger: { count, inputName in
          let shortName = inputName.replacingOccurrences(of: "com.apple.", with: "")
          printErr("  Loaded \(count) entries from \(shortName)...")
        }
      )

      printErr("Replaying logs from captured session: \"\(directory)\"")
      if let filter = output.filter {
        printErr("(Filtering for: \"\(filter)\")")
      }
      if output.errorsOnly {
        printErr("(Filtering for errors, faults, and warnings only)")
      }
      printErr("")

      debug("Beginning log replay")

      // Parse and analyze logs from captured files
      let logStream = collector.collectLogs(from: logInputs)

      // Collect entity annotations from HomeKit API if requested
      let additionalAnnotations = await collectEntityAnnotations(entitySource: output.entitySource)

      debug("Analyzing logs")
      let analyzer = LogAnalyzer(stream: logStream)
      let analysis = try await analyzer.analyzeStream(
        additionalAnnotations: additionalAnnotations)

      debug("Formatting output")
      let formatter = OutputFormatter(
        analysis: analysis,
        showSummary: output.summary,
        deduplicate: output.dedupe,
        errorsOnly: output.errorsOnly,
        filter: output.filter,
        substituteNames: !output.noNames
      )

      let outputText = formatter.format()

      print(outputText)

      info("HomeDiagnostics replay completed successfully")
    } catch {
      printErr("[ERROR] Fatal error occurred: \(error)")
      printErr("\nError: \(error.localizedDescription)")
      throw error
    }
  }
}
