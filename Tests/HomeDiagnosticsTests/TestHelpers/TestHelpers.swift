import Foundation
import HomeDiagnosticsCore
import Testing

/// Helper for easily creating a LogCollector for tests
func makeTestCollector(entryLimit: Int? = nil) -> LogCollector {
  LogCollector(entryLimit: entryLimit)
}

/// Parses a JSON array string into [LogEntry] using StringLogInput
func parseEntries(_ json: String, name: String = "test") async throws -> [LogEntry] {
  let collector = makeTestCollector()
  let input = StringLogInput(json: json, name: name)
  var entries: [LogEntry] = []
  for try await entry in collector.streamEntries(from: input) {
    entries.append(entry)
  }
  return entries
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
