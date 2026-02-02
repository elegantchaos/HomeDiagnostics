import ArgumentParser
import Foundation
import HomeDiagnosticsCore

/// Analyzes logs from the macOS unified logging system.
///
/// Collects and analyzes logs from Home, HomeKit, and homed subsystems,
/// providing filtering, deduplication, and entity name resolution.
struct AnalyzeCommand: AsyncParsableCommand {
  /// Configuration for the analyze subcommand.
  static let configuration = CommandConfiguration(
    commandName: "analyze",
    abstract: "Analyze logs from the system log (default command)"
  )

  /// Time range options.
  @OptionGroup var time: TimeOptions

  /// Log collection options.
  @OptionGroup var collection: CollectionOptions

  /// Output formatting options.
  @OptionGroup var output: OutputOptions

  /// Whether to output raw, unparsed log data.
  @Flag(name: .long, help: "Output raw log data without parsing or analysis")
  var raw: Bool = false

  /// Validates the command options.
  ///
  /// - Throws: `ValidationError` if incompatible options are combined.
  func validate() throws {
    if raw && (output.summary || output.dedupe) {
      throw ValidationError("--raw cannot be combined with --summary or --dedupe")
    }

    if raw && output.errorsOnly {
      throw ValidationError("--raw cannot be combined with --errors-only")
    }
  }

  /// Executes the analyze command.
  ///
  /// - Throws: An error if log collection or analysis fails.
  func run() async throws {
    isVerbose = collection.verbose

    do {
      info("Starting HomeDiagnostics - Apple Home Log Analyzer")

      if !raw {
        printErr("HomeDiagnostics - Apple Home Log Analyzer")
        printErr("==========================================\n")
      }

      let logInputs = LogCollector<SystemLogInput>.makeSystemLogInputs(
        timeInterval: time.timeInterval,
        includeDebug: collection.detailed,
        debugLogger: { debug($0) }
      )

      let collector = LogCollector<SystemLogInput>(
        entryLimit: collection.entries,
        debugLogger: { debug($0) },
        errorLogger: { printErr($0) },
        progressLogger: { count, inputName in
          let shortName = inputName.replacingOccurrences(of: "com.apple.", with: "")
          printErr("  Collected \(count) entries from \(shortName)...")
        }
      )

      if !raw {
        printErr("Collecting logs from the last \(time.timeDescription)...")
        if collection.detailed {
          printErr("(Including debug-level logs - this may take a while)")
        }
        if let filter = output.filter {
          printErr("(Filtering for: \"\(filter)\")")
        }
        if output.errorsOnly {
          printErr("(Filtering for errors, faults, and warnings only)")
        }
        printErr("")
      }

      debug("Beginning log collection")

      // Raw mode: output unprocessed logs directly
      if raw {
        let rawOutput = try await collectRawLogs(
          timeInterval: time.timeInterval,
          includeDebug: collection.detailed
        )
        print(rawOutput)
        info("HomeDiagnostics raw output completed successfully")
        return
      }

      // Normal mode: parse and analyze logs
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

      info("HomeDiagnostics completed successfully")
    } catch {
      printErr("[ERROR] Fatal error occurred: \(error)")
      printErr("\nError: \(error.localizedDescription)")
      throw error
    }
  }
}

/// Collects raw logs in syslog format (for --raw mode).
private func collectRawLogs(timeInterval: String, includeDebug: Bool) async throws -> String {
  var allOutput: [String] = []

  for subsystem in LogCollector<SystemLogInput>.defaultHomeKitSubsystems {
    do {
      debug("Collecting raw logs for subsystem: \(subsystem)")
      let runner = SystemLogRunner(
        subsystem: subsystem,
        timeInterval: timeInterval,
        includeDebug: includeDebug,
        debugLogger: { debug($0) }
      )
      let output = try await runner.rawLogs()
      debug("Collected \(output.count) characters from \(subsystem)")

      if !output.isEmpty {
        allOutput.append(output)
      }
    } catch {
      printErr("[ERROR] Failed to collect logs for subsystem \(subsystem): \(error)")
    }
  }

  return allOutput.joined(separator: "\n")
}
