import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - Message Similarity Tests

@Suite("Message Similarity Tests")
struct MessageSimilarityTests {

  /// Tests that significant tokens are extracted correctly.
  @Test("Extract significant tokens from message")
  func testSignificantTokens() async throws {
    let testCases: [(String, Set<String>)] = [
      // Simple message
      (
        "Device failed to connect",
        ["device", "failed", "connect"]
      ),
      // Message with stop words
      (
        "The device has failed and is not responding",
        ["device", "failed", "responding"]
      ),
      // Message with placeholders (should be filtered)
      (
        "Device [<id>] MAC <mac> at <addr> failed",
        ["device", "failed"]
      ),
      // Message with numbers and punctuation
      (
        "Error Code=123 Device!@#$%failed",
        ["error", "code", "device", "failed"]
      ),
      // Empty message
      (
        "",
        []
      ),
      // Message with only stop words
      (
        "the a an is are was",
        []
      ),
    ]

    for (input, expected) in testCases {
      let tokens = MessageSimilarity.significantTokens(from: input)
      #expect(tokens == expected)
    }
  }

  /// Tests Jaccard similarity calculation.
  @Test("Calculate Jaccard similarity between messages")
  func testSimilarityCalculation() async throws {
    // Identical messages
    let sim1 = MessageSimilarity.similarity(
      between: "Device failed to connect",
      and: "Device failed to connect"
    )
    #expect(sim1 == 1.0)

    // Completely different messages
    let sim2 = MessageSimilarity.similarity(
      between: "Device failed to connect",
      and: "Timeout occurred during operation"
    )
    #expect(sim2 < 0.5)

    // Similar but not identical
    let sim3 = MessageSimilarity.similarity(
      between: "Device failed to connect to network",
      and: "Device failed to connect to server"
    )
    #expect(sim3 > 0.5 && sim3 < 1.0)

    // Both empty
    let sim4 = MessageSimilarity.similarity(
      between: "",
      and: ""
    )
    #expect(sim4 == 1.0)

    // One empty
    let sim5 = MessageSimilarity.similarity(
      between: "Device failed",
      and: ""
    )
    #expect(sim5 == 0.0)
  }

  /// Tests similarity threshold detection.
  @Test("Determine if messages are similar based on threshold")
  func testAreSimilar() async throws {
    // High similarity (should be similar with default threshold 0.75)
    let similar1 = MessageSimilarity.areSimilar(
      "Failed to save public key pairing username error",
      "Failed to save public key pairing password error"
    )
    #expect(similar1 == true)

    // Low similarity (should not be similar)
    let similar2 = MessageSimilarity.areSimilar(
      "Failed to save public key",
      "Device unreachable timeout"
    )
    #expect(similar2 == false)

    // Medium similarity with custom threshold
    let similar3 = MessageSimilarity.areSimilar(
      "Failed to connect to device",
      "Failed to disconnect from device",
      threshold: 0.5
    )
    #expect(similar3 == true)
  }

  /// Tests grouping entries by similarity.
  @Test("Group log entries by message similarity")
  func testGroupBySimilarity() async throws {
    let entries = [
      // Group 1: "Failed to save" messages (similar)
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Failed to save public key for device"
      ),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Failed to save public key for accessory"
      ),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Failed to save public key for controller"
      ),

      // Group 2: "Timeout" messages (similar)
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Timeout waiting for response from device"
      ),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Timeout waiting for response from accessory"
      ),

      // Group 3: Different message (not similar to others)
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message: "Database corruption detected"
      ),
    ]

    let groups = MessageSimilarity.groupBySimilarity(entries, threshold: 0.6)

    // Should have 3 groups
    #expect(groups.count == 3)

    // Find the "Failed to save" group (should have 3 entries)
    let saveGroup = groups.first { group in
      group.first?.message.contains("save") ?? false
    }
    #expect(saveGroup?.count == 3)

    // Find the "Timeout" group (should have 2 entries)
    let timeoutGroup = groups.first { group in
      group.first?.message.contains("Timeout") ?? false
    }
    #expect(timeoutGroup?.count == 2)

    // Find the "Database" group (should have 1 entry)
    let dbGroup = groups.first { group in
      group.first?.message.contains("Database") ?? false
    }
    #expect(dbGroup?.count == 1)
  }

  /// Tests real-world scenario: normalized messages with different UUIDs should group.
  @Test("Real-world: Normalized messages with variable values group correctly")
  func testRealWorldNormalizedGrouping() async throws {
    let entries = [
      // These will normalize to the same message after UUID/MAC/Number replacement
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message:
          "[A1B2C3D4-E5F6-7890-ABCD-EF1234567890/AA:BB:CC:DD:EE:FF+123/NO] Failed to save"
      ),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message:
          "[11111111-2222-3333-4444-555555555555/11:22:33:44:55:66+456/NO] Failed to save"
      ),
      LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .error,
        message:
          "[99999999-8888-7777-6666-555555555555/99:88:77:66:55:44+789/YES] Failed to save"
      ),
    ]

    let groups = MessageSimilarity.groupBySimilarity(entries, threshold: 0.75)

    // All three should group together (they normalize to the same message)
    #expect(groups.count == 1)
    #expect(groups[0].count == 3)
  }

  /// Tests edge case: messages that differ only in structure words.
  @Test("Edge case: Messages with different structure words")
  func testStructuralDifferences() async throws {
    // These messages have similar significant words but different structure
    let msg1 = "Failed to connect to the device network"
    let msg2 = "Device network connection has failed completely"

    let similarity = MessageSimilarity.similarity(between: msg1, and: msg2)

    // Should have decent similarity (both mention "failed", "connect", "device", "network")
    #expect(similarity >= 0.5)
  }

  /// Tests performance with many entries.
  @Test("Performance: Group large number of entries")
  func testPerformanceGrouping() async throws {
    // Create 100 entries with 10 different message patterns
    var entries: [LogEntry] = []
    let patterns = [
      "Failed to save public key",
      "Timeout waiting for response",
      "Device unreachable",
      "Connection lost",
      "Invalid configuration",
      "Permission denied",
      "Resource not found",
      "Network error",
      "Database error",
      "Unknown error",
    ]

    for _ in 0..<10 {
      for pattern in patterns {
        entries.append(
          LogEntry(
            timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed",
            level: .error,
            message: "\(pattern) \(UUID().uuidString)"
          ))
      }
    }

    // Measure grouping performance
    let start = Date()
    let groups = MessageSimilarity.groupBySimilarity(entries, threshold: 0.75)
    let duration = Date().timeIntervalSince(start)

    // Should complete quickly (under 1 second)
    #expect(duration < 1.0)

    // Should create approximately 10 groups (one per pattern)
    // Allowing some flexibility as similar patterns might group
    #expect(groups.count <= 15)
  }
}
