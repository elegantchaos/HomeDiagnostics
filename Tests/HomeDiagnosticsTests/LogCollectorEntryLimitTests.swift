import Foundation
import Testing

@testable import HomeDiagnosticsCore

@Suite("LogCollector Entry Limit")
struct LogCollectorEntryLimitTests {
    @Test("Entry limit is respected in streamLogsForSubsystem with mock data source")
    func testEntryLimitWithMockDataSource() async throws {
        let jsonInput = """
        [
            { "timestamp": "2026-01-29 14:30:15.123456+0000", "messageType": "Info", "eventMessage": "A", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
            { "timestamp": "2026-01-29 14:30:16.123456+0000", "messageType": "Info", "eventMessage": "B", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
            { "timestamp": "2026-01-29 14:30:17.123456+0000", "messageType": "Info", "eventMessage": "C", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" }
        ]
        """
        let mockDataSource = MockLogDataSource(jsonData: jsonInput)
        let collector = LogCollector(
            timeInterval: "1d",
            includeDebug: false,
            entryLimit: 2,
            dataSource: mockDataSource
        )
        var yielded: [LogEntry] = []
        for try await entry in collector.streamLogsForSubsystem("com.apple.HomeKit") {
            yielded.append(entry)
        }
        #expect(yielded.count == 2)
        #expect(yielded[0].message == "A")
        #expect(yielded[1].message == "B")
    }

    @Test("Entry limit is respected in streamLogs for all subsystems")
    func testEntryLimitWithMultipleSubsystems() async throws {
        let jsonInput = """
        [
            { "timestamp": "2026-01-29 14:30:15.123456+0000", "messageType": "Info", "eventMessage": "A", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
            { "timestamp": "2026-01-29 14:30:16.123456+0000", "messageType": "Info", "eventMessage": "B", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
            { "timestamp": "2026-01-29 14:30:17.123456+0000", "messageType": "Info", "eventMessage": "C", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" }
        ]
        """
        let mockDataSource = MockLogDataSource(jsonData: jsonInput)
        let collector = LogCollector(
            timeInterval: "1d",
            includeDebug: false,
            entryLimit: 1,
            dataSource: mockDataSource
        )
        var yielded: [LogEntry] = []
        for try await entry in collector.streamLogs(subsystems: ["com.apple.HomeKit", "com.apple.Home"]) {
            yielded.append(entry)
        }
        // Should yield 1 entry per subsystem (total 2)
        #expect(yielded.count == 2)
    }

    @Test("Unlimited entry limit yields all entries")
    func testUnlimitedEntryLimit() async throws {
        let jsonInput = """
        [
            { "timestamp": "2026-01-29 14:30:15.123456+0000", "messageType": "Info", "eventMessage": "A", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
            { "timestamp": "2026-01-29 14:30:16.123456+0000", "messageType": "Info", "eventMessage": "B", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" },
            { "timestamp": "2026-01-29 14:30:17.123456+0000", "messageType": "Info", "eventMessage": "C", "subsystem": "com.apple.HomeKit", "processImagePath": "/usr/libexec/homed" }
        ]
        """
        let mockDataSource = MockLogDataSource(jsonData: jsonInput)
        let collector = LogCollector(
            timeInterval: "1d",
            includeDebug: false,
            entryLimit: nil,
            dataSource: mockDataSource
        )
        var yielded: [LogEntry] = []
        for try await entry in collector.streamLogsForSubsystem("com.apple.HomeKit") {
            yielded.append(entry)
        }
        #expect(yielded.count == 3)
    }
}
