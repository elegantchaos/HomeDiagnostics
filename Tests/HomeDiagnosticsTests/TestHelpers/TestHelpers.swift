import Foundation
import HomeDiagnosticsCore
import Testing

/// Helper for easily creating a LogCollector for tests
func makeTestCollector(timeInterval: String = "1d", includeDebug: Bool = false, logInputs: [LogInput]? = nil) -> LogCollector {
  LogCollector(
    timeInterval: timeInterval,
    includeDebug: includeDebug,
    logInputs: logInputs
  )
}

/// Parses a JSON array string into [LogEntry] for the given subsystem
func parseEntries(_ json: String, subsystem: String, collector: LogCollector? = nil) throws -> [LogEntry] {
  let collector = collector ?? makeTestCollector()
  return try collector.parseJSONEntries(json, subsystem: subsystem)
}

/// Parses a single JSON object string into LogEntry?
func parseSingleEntry(_ json: String, collector: LogCollector? = nil) throws -> LogEntry? {
  let collector = collector ?? makeTestCollector()
  let decoder = collector.makeEntryDecoder()
  return try collector.parseJSONEntry(json, decoder: decoder)
}

/// Asserts that a log entry matches expected properties
func assertEntry(_ entry: LogEntry, expectedMessage: String? = nil, expectedLevel: LogLevel? = nil, expectedSubsystem: String? = nil, expectedProcess: String? = nil) {
  #if canImport(Testing)
    if let msg = expectedMessage { #expect(entry.message == msg) }
    if let lvl = expectedLevel { #expect(entry.level == lvl) }
    if let subsys = expectedSubsystem { #expect(entry.subsystem == subsys) }
    if let proc = expectedProcess { #expect(entry.process == proc) }
  #endif
}
