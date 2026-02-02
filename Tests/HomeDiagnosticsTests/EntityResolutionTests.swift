import Foundation
import Testing

@testable import HomeDiagnosticsCore

/// Tests for EntityCollector pattern extraction and EntityResolver entity resolution.
///
/// These tests verify that the entity discovery system correctly extracts entity information
/// from log messages and resolves them into a unified entity graph.
@Suite("Entity Resolution Tests")
struct EntityResolutionTests {

  // MARK: - Pattern Extraction Tests

  /// Tests path-based UUID extraction: [Home/Device/UUID]
  @Test("Extract names from path-based patterns")
  func testPathBasedExtraction() async throws {
    var collector = EntityCollector()
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message:
        "[Bank Street/Hue color lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Active transition count value: (null) is not of type NSNumber"
    )

    collector.add(entry: entry)
    let resolver = EntityResolver(annotations: collector.annotations)

    let displayName = resolver.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    #expect(displayName == "Hue color lamp-4A8856A0")
  }

  /// Tests multiple path-based patterns in a single message
  @Test("Extract multiple path-based names from same message")
  func testMultiplePathBasedExtraction() async throws {
    var collector = EntityCollector()
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message:
        "[Bank Street/Device1/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] connected to [Bank Street/Device2/CBD9ADE0-29ED-5945-A6A9-6E1750392F3D]"
    )

    collector.add(entry: entry)
    let resolver = EntityResolver(annotations: collector.annotations)

    let name1 = resolver.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    let name2 = resolver.displayName(for: "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D")

    #expect(name1 == "Device1-4A8856A0")
    #expect(name2 == "Device2-CBD9ADE0")
  }

  /// Tests action set name extraction
  @Test("Extract names from action set structured data")
  func testActionSetExtraction() async throws {
    var collector = EntityCollector()
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: """
        [3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852] Add action set finished. Responding to clients with : {
            kActionSetName = "Good Morning";
            kActionSetType = HMActionSetTypeWakeUp;
            kActionSetUUID = "8006AFD6-5739-53CB-8175-DA40FF2BFCD2";
            kHomeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852";
        }
        """
    )

    collector.add(entry: entry)
    var resolver = EntityResolver(annotations: collector.annotations)
    resolver.resolve()

    let actionSetName = resolver.displayName(for: "8006AFD6-5739-53CB-8175-DA40FF2BFCD2")
    #expect(actionSetName == "Good Morning-8006AFD6")

    // Home UUID should be registered
    let homeEntity = resolver.entity(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")
    #expect(homeEntity != nil)
  }

  /// Tests home UUID list extraction
  @Test("Extract UUIDs from home list patterns")
  func testHomeListExtraction() async throws {
    var collector = EntityCollector()
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message:
        "updateHomes(timeout:) found homes [3B23B284-673A-5FFF-A863-8F62C42711C0, 92759DC3-97B6-5A09-95CC-1070E16D9260]"
    )

    collector.add(entry: entry)
    let resolver = EntityResolver(annotations: collector.annotations)

    // UUIDs should be registered
    let entity1 = resolver.entity(for: "3B23B284-673A-5FFF-A863-8F62C42711C0")
    let entity2 = resolver.entity(for: "92759DC3-97B6-5A09-95CC-1070E16D9260")

    #expect(entity1 != nil)
    #expect(entity2 != nil)
    #expect(entity1?.type == .home)
    #expect(entity2?.type == .home)
  }

  /// Tests first-encountered name is kept for conflicting names
  @Test("Handle UUID with conflicting names - keeps first encountered")
  func testConflictingNames() async throws {
    var collector = EntityCollector()

    // Same UUID appears with different names
    let entry1 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "[Bank Street/Living Room/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Error message"
    )
    let entry2 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message:
        "[Plantation Road/Bedroom/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Another error"
    )

    collector.add(entry: entry1)
    collector.add(entry: entry2)

    let resolver = EntityResolver(annotations: collector.annotations)
    let displayName = resolver.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")

    // Should keep first encountered name (Living Room)
    #expect(displayName == "Living Room-4A8856A0")
  }

  /// Tests case-insensitive UUID matching
  @Test("UUID matching is case-insensitive")
  func testCaseInsensitiveMatching() async throws {
    var collector = EntityCollector()
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "[Bank Street/Device/4a8856a0-38e3-5af4-ac52-8390ffe944a2] Test message"
    )

    collector.add(entry: entry)
    let resolver = EntityResolver(annotations: collector.annotations)

    // Try with uppercase - should work and use the prefix from the input UUID
    let name1 = resolver.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    // Try with lowercase - should work and use the prefix from the input UUID
    let name2 = resolver.displayName(for: "4a8856a0-38e3-5af4-ac52-8390ffe944a2")
    // Try with mixed case - should work and use the prefix from the input UUID
    let name3 = resolver.displayName(for: "4A8856a0-38E3-5aF4-aC52-8390FfE944A2")

    // All should return the same name, just with different prefix casing
    #expect(name1 == "Device-4A8856A0")
    #expect(name2 == "Device-4a8856a0")
    #expect(name3 == "Device-4A8856a0")
  }

  // MARK: - UUID Substitution Tests

  /// Tests UUID substitution in messages
  @Test("Substitute UUIDs in messages")
  func testUUIDSubstitution() async throws {
    var collector = EntityCollector()
    let entry = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Configuration"
    )

    collector.add(entry: entry)
    let resolver = EntityResolver(annotations: collector.annotations)

    let testMessage = "Device 4A8856A0-38E3-5AF4-AC52-8390FFE944A2 is unreachable"
    let result = resolver.substitute(in: testMessage)

    #expect(result == "Device Lamp-4A8856A0 is unreachable")
  }

  /// Tests substitution with multiple UUIDs
  @Test("Substitute multiple UUIDs in one message")
  func testMultipleUUIDSubstitution() async throws {
    var collector = EntityCollector()

    let entry1 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "[Home1/Device1/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test"
    )
    let entry2 = LogEntry(
      timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
      message: "[Home2/Device2/CBD9ADE0-29ED-5945-A6A9-6E1750392F3D] Test"
    )

    collector.add(entry: entry1)
    collector.add(entry: entry2)

    let resolver = EntityResolver(annotations: collector.annotations)

    let testMessage =
      "Connection from 4A8856A0-38E3-5AF4-AC52-8390FFE944A2 to CBD9ADE0-29ED-5945-A6A9-6E1750392F3D failed"
    let result = resolver.substitute(in: testMessage)

    #expect(result == "Connection from Device1-4A8856A0 to Device2-CBD9ADE0 failed")
  }

  /// Tests that unknown UUIDs are left unchanged
  @Test("Unknown UUIDs remain unchanged in substitution")
  func testUnknownUUIDsUnchanged() async throws {
    let resolver = EntityResolver(annotations: [])

    let testMessage = "Unknown device 4A8856A0-38E3-5AF4-AC52-8390FFE944A2"
    let result = resolver.substitute(in: testMessage)

    // UUID should remain unchanged since no name was extracted
    #expect(result == testMessage)
  }

  /// Tests extraction and substitution with real sample data
  @Test("Extract and substitute with sample log data")
  func testRealSampleData() async throws {
    var collector = EntityCollector()

    // Real examples from sample logs
    let messages = [
      "[Bank Street/Hue color lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Active transition count value: (null) is not of type NSNumber",
      "[Bank Street/Corner Spot/949F68CF-5065-5F7E-8DBC-4D6BE20F2BD6] Ignoring Value Transition Control",
      "[Plantation Road/Living Room/691505B0-F56B-5989-8EAF-6C721322655C] Value is not of expected type",
    ]

    for message in messages {
      collector.add(
        entry: LogEntry(
          timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
          message: message)
      )
    }

    let resolver = EntityResolver(annotations: collector.annotations)

    // Test substitution
    let testMessage =
      "Error in 4A8856A0-38E3-5AF4-AC52-8390FFE944A2 and 949F68CF-5065-5F7E-8DBC-4D6BE20F2BD6"
    let result = resolver.substitute(in: testMessage)

    #expect(result == "Error in Hue color lamp-4A8856A0 and Corner Spot-949F68CF")
  }

  // MARK: - Combined Pattern Tests

  /// Tests combined extraction from multiple message types
  @Test("Combined extraction from multiple pattern types")
  func testCombinedExtraction() async throws {
    var collector = EntityCollector()

    // Path-based
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")
    )

    // Action set
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: """
          Add action set finished. {
              kActionSetName = "Morning";
              kActionSetUUID = "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D";
          }
          """
      )
    )

    // Home list
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "found homes [3B23B284-673A-5FFF-A863-8F62C42711C0]")
    )

    let resolver = EntityResolver(annotations: collector.annotations)

    let name1 = resolver.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    let name2 = resolver.displayName(for: "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D")
    let entity3 = resolver.entity(for: "3B23B284-673A-5FFF-A863-8F62C42711C0")

    #expect(name1 == "Lamp-4A8856A0")
    #expect(name2 == "Morning-CBD9ADE0")
    #expect(entity3 != nil)  // Only registered, no name
    #expect(entity3?.name.isEmpty == true)
  }

  /// Tests that display name uses first 8 characters of UUID
  @Test("Display name uses UUID prefix correctly")
  func testUUIDPrefixLength() async throws {
    var collector = EntityCollector()
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Home/Device/12345678-1234-5678-9ABC-123456789ABC] Test")
    )

    let resolver = EntityResolver(annotations: collector.annotations)
    let displayName = resolver.displayName(for: "12345678-1234-5678-9ABC-123456789ABC")

    #expect(displayName?.hasSuffix("-12345678") == true)
    #expect(displayName == "Device-12345678")
  }

  /// Tests that technical-looking names are filtered out
  @Test("Filter out UUID-like and hash-like names")
  func testNameFiltering() async throws {
    var collector = EntityCollector()

    // These should all be rejected as non-human-readable
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message:
          "[Home/12345678-1234-5678-9ABC-123456789ABC/12345678-1234-5678-9ABC-123456789ABC] Test"
      ))  // UUID as device name
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Home/12345/12345678-1234-5678-9ABC-123456789ABC] Test"))  // Pure integer
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Home/ABCDEF123456/12345678-1234-5678-9ABC-123456789ABC] Test"))  // Hex hash
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Home/a1b2c3d4e5f6/12345678-1234-5678-9ABC-123456789ABC] Test"))
    // Alphanumeric hash

    // This should be accepted as human-readable
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Bank Street/Living Room Lamp/12345678-1234-5678-9ABC-123456789ABC] Test")
    )

    let resolver = EntityResolver(annotations: collector.annotations)
    let displayName = resolver.displayName(for: "12345678-1234-5678-9ABC-123456789ABC")

    // Should only have the valid human-readable name
    #expect(displayName == "Living Room Lamp-12345678")
  }

  // MARK: - HMDHome Pattern Tests

  /// Tests HMDHome pattern extraction with both internal ID and spiID
  @Test("Extract home from HMDHome pattern")
  func testHMDHomePatternExtraction() async throws {
    var collector = EntityCollector()

    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message:
          "<HMDHome, ID = 3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852, spiID = 3B23B284-673A-5FFF-A863-8F62C42711C0, NM = Bank Street>"
      )
    )

    let resolver = EntityResolver(annotations: collector.annotations)

    // Both internal ID and spiID should have the home name
    let internalName = resolver.displayName(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")
    let spiName = resolver.displayName(for: "3B23B284-673A-5FFF-A863-8F62C42711C0")

    #expect(internalName == "Bank Street-3C0F85CD")
    #expect(spiName == "Bank Street-3B23B284")
  }

  /// Tests Matter snapshot pattern extraction
  @Test("Extract home from Matter snapshot pattern")
  func testMatterSnapshotExtraction() async throws {
    var collector = EntityCollector()

    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message:
          "new matter snapshot for '3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852', updateType:home(Bank Street), didChange:true"
      )
    )

    let resolver = EntityResolver(annotations: collector.annotations)
    let homeName = resolver.displayName(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")

    #expect(homeName == "Bank Street-3C0F85CD")
  }

  // MARK: - Type-Based Uniqueness Tests

  /// Tests that entities of different types can share the same name
  @Test("Different entity types can have the same name")
  func testTypeBasedNameUniqueness() async throws {
    var collector = EntityCollector()

    // Device named "Kitchen"
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Home/Kitchen/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")
    )

    // Action set (scene) named "Kitchen"
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: """
          Add action set finished. {
              kActionSetName = "Kitchen";
              kActionSetUUID = "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D";
          }
          """
      )
    )

    let resolver = EntityResolver(annotations: collector.annotations)

    // Both should exist with their own UUIDs
    let deviceName = resolver.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    let actionSetName = resolver.displayName(for: "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D")

    #expect(deviceName == "Kitchen-4A8856A0")
    #expect(actionSetName == "Kitchen-CBD9ADE0")

    // Verify types are different
    let deviceEntity = resolver.entity(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    let actionSetEntity = resolver.entity(for: "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D")

    #expect(deviceEntity?.type == .device)
    #expect(actionSetEntity?.type == .actionSet)
  }

  // MARK: - Entity Relationship Tests

  /// Tests action set home association from kHomeUUID
  @Test("Associate action sets with homes via kHomeUUID")
  func testActionSetHomeAssociation() async throws {
    var collector = EntityCollector()

    // Extract action set with kHomeUUID
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: """
          Add action set finished. {
              kActionSetName = "Good Morning";
              kActionSetUUID = "8006AFD6-5739-53CB-8175-DA40FF2BFCD2";
              kHomeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852";
          }
          """
      ))

    // Register the home with a name
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message:
          "<HMDHome, ID = 3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852, spiID = 3B23B284-673A-5FFF-A863-8F62C42711C0, NM = Bank Street>"
      ))

    var resolver = EntityResolver(annotations: collector.annotations)
    resolver.resolve()

    // Verify action set is associated with home
    let actionSetEntity = resolver.entity(for: "8006AFD6-5739-53CB-8175-DA40FF2BFCD2")
    let homeEntity = resolver.entity(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")

    #expect(actionSetEntity?.owner === homeEntity)
  }

  /// Tests entitiesByHome grouping
  @Test("entitiesByHome correctly groups entities")
  func testEntitiesByHome() async throws {
    var collector = EntityCollector()

    // Home
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message:
          "<HMDHome, ID = 3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852, spiID = 3B23B284-673A-5FFF-A863-8F62C42711C0, NM = Bank Street>"
      ))

    // Device with home ownership
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")
    )

    // Action set with home ownership
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: """
          Add action set finished. {
              kActionSetName = "Morning";
              kActionSetUUID = "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D";
              kHomeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852";
          }
          """
      ))

    // Orphaned device (no home)
    collector.add(
      entry: LogEntry(
        timestamp: Date(), subsystem: "com.apple.HomeKit", process: "homed", level: .info,
        message: "[Unknown/Orphan/12345678-1234-5678-9ABC-123456789ABC] Test")
    )

    var resolver = EntityResolver(annotations: collector.annotations)
    resolver.resolve()

    let (homeToEntities, _, unknownHomeEntities) = resolver.entitiesByHome()

    // Home should have 2 children (device + action set)
    let homeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852".lowercased()
    #expect(homeToEntities[homeUUID]?.count == 2)

    // Orphaned device should be in unknown home list
    #expect(unknownHomeEntities.count == 1)
    #expect(
      unknownHomeEntities.contains("12345678-1234-5678-9ABC-123456789ABC".lowercased()))
  }
}
