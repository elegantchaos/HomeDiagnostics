import Foundation

@testable import HomeDiagnosticsCore

/// Mock log data source that returns predefined JSON data (for testing purposes only)
struct MockLogDataSource: LogDataSource {
  /// The JSON data to return
  let jsonData: String

  /// Fetches predefined JSON log data for a subsystem
  func fetchJSONLogs(subsystem: String) async throws -> String {
    return jsonData
  }
}
