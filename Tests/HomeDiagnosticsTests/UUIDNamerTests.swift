import Foundation
import Testing

@testable import HomeDiagnosticsCore

// MARK: - UUID Namer Tests

@Suite("UUID Namer Tests")
struct UUIDNamerTests {
  /// Tests that merging does not overwrite information if the same UUID or name appears in both namers.
  @Test("Merging preserves all names for shared UUIDs")
  func testMergePreservesAllNamesForSharedUUIDs() async throws {
    var namer1 = UUIDNamer()
    var namer2 = UUIDNamer()

    // Both namers see the same UUID but with different names
    namer1.extractNames(from: "[Home1/DeviceA/11111111-1111-1111-1111-111111111111] Test")
    namer2.extractNames(from: "[Home2/DeviceB/11111111-1111-1111-1111-111111111111] Test")

    // Merge namer2 into namer1
    namer1.merge(with: namer2)

    // The display name should include both names, sorted alphabetically
    let displayName = namer1.displayName(for: "11111111-1111-1111-1111-111111111111")
    let valid1 = displayName == "DeviceA/DeviceB-11111111"
    let valid2 = displayName == "DeviceB/DeviceA-11111111"
    #expect(valid1 || valid2)

    // Check that both names are associated with the UUID, and that each NamedEntity.uuids contains the UUID
    let entities = namer1.entities(for: "11111111-1111-1111-1111-111111111111")
    #expect(entities.contains { $0.name == "DeviceA" && $0.uuids.contains("11111111-1111-1111-1111-111111111111".uppercased()) })
    #expect(entities.contains { $0.name == "DeviceB" && $0.uuids.contains("11111111-1111-1111-1111-111111111111".uppercased()) })
  }
  /// Tests that merging two UUIDNamer instances preserves all data from both.
  @Test("Merging preserves all data")
  func testMergePreservesAllData() async throws {
    var namer1 = UUIDNamer()
    var namer2 = UUIDNamer()

    // Populate namer1 with one device and home
    namer1.extractNames(from: "[Home1/DeviceA/11111111-1111-1111-1111-111111111111] Test")
    namer1.extractNames(from: "updateHomes(timeout:) found homes [AAAA1111-1111-1111-1111-111111111111]")

    // Populate namer2 with a different device, home, and action set
    namer2.extractNames(from: "[Home2/DeviceB/22222222-2222-2222-2222-222222222222] Test")
    namer2.extractNames(from: "Add action set finished. { kActionSetName = \"Scene\"; kActionSetUUID = \"33333333-3333-3333-3333-333333333333\"; kHomeUUID = \"AAAA2222-2222-2222-2222-222222222222\"; }")
    namer2.extractNames(from: "updateHomes(timeout:) found homes [AAAA2222-2222-2222-2222-222222222222]")

    // Merge namer2 into namer1
    namer1.merge(with: namer2)

    // All device and action set names should be present
    let deviceA = namer1.displayName(for: "11111111-1111-1111-1111-111111111111")
    let deviceB = namer1.displayName(for: "22222222-2222-2222-2222-222222222222")
    let actionSet = namer1.displayName(for: "33333333-3333-3333-3333-333333333333")
    let home1 = namer1.displayName(for: "AAAA1111-1111-1111-1111-111111111111")
    let home2 = namer1.displayName(for: "AAAA2222-2222-2222-2222-222222222222")

    #expect(deviceA == "DeviceA-11111111")
    #expect(deviceB == "DeviceB-22222222")
    #expect(actionSet == "Scene-33333333")
    #expect(home1 == nil)  // Only registered, no name
    #expect(home2 == nil)  // Only registered, no name

    // Check that the NamedEntity.uuids property is correct for each entity
    let entitiesA = namer1.entities(for: "11111111-1111-1111-1111-111111111111")
    #expect(entitiesA.contains { $0.name == "DeviceA" && $0.uuids.contains("11111111-1111-1111-1111-111111111111".uppercased()) })
    let entitiesB = namer1.entities(for: "22222222-2222-2222-2222-222222222222")
    #expect(entitiesB.contains { $0.name == "DeviceB" && $0.uuids.contains("22222222-2222-2222-2222-222222222222".uppercased()) })
    let entitiesScene = namer1.entities(for: "33333333-3333-3333-3333-333333333333")
    #expect(entitiesScene.contains { $0.name == "Scene" && $0.uuids.contains("33333333-3333-3333-3333-333333333333".uppercased()) })

    // Now merge in the other direction and check again
    var namer3 = UUIDNamer()
    namer3.merge(with: namer1)
    #expect(namer3.displayName(for: "11111111-1111-1111-1111-111111111111") == "DeviceA-11111111")
    #expect(namer3.displayName(for: "22222222-2222-2222-2222-222222222222") == "DeviceB-22222222")
    #expect(namer3.displayName(for: "33333333-3333-3333-3333-333333333333") == "Scene-33333333")
    let entitiesA3 = namer3.entities(for: "11111111-1111-1111-1111-111111111111")
    #expect(entitiesA3.contains { $0.name == "DeviceA" && $0.uuids.contains("11111111-1111-1111-1111-111111111111".uppercased()) })
    let entitiesB3 = namer3.entities(for: "22222222-2222-2222-2222-222222222222")
    #expect(entitiesB3.contains { $0.name == "DeviceB" && $0.uuids.contains("22222222-2222-2222-2222-222222222222".uppercased()) })
    let entitiesScene3 = namer3.entities(for: "33333333-3333-3333-3333-333333333333")
    #expect(entitiesScene3.contains { $0.name == "Scene" && $0.uuids.contains("33333333-3333-3333-3333-333333333333".uppercased()) })
  }

  /// Tests path-based UUID extraction: [Home/Device/UUID]
  @Test("Extract names from path-based patterns")
  func testPathBasedExtraction() async throws {
    var namer = UUIDNamer()
    let message =
      "[Bank Street/Hue color lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Active transition count value: (null) is not of type NSNumber"

    namer.extractNames(from: message)

    let displayName = namer.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    // Now only uses the device name (not Home/Device)
    #expect(displayName == "Hue color lamp-4A8856A0")
  }

  /// Tests multiple path-based patterns in a single message
  @Test("Extract multiple path-based names from same message")
  func testMultiplePathBasedExtraction() async throws {
    var namer = UUIDNamer()
    let message =
      "[Bank Street/Device1/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] connected to [Bank Street/Device2/CBD9ADE0-29ED-5945-A6A9-6E1750392F3D]"

    namer.extractNames(from: message)

    let name1 = namer.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    let name2 = namer.displayName(for: "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D")
    // Now only uses device names
    #expect(name1 == "Device1-4A8856A0")
    #expect(name2 == "Device2-CBD9ADE0")
  }

  /// Tests action set name extraction
  @Test("Extract names from action set structured data")
  func testActionSetExtraction() async throws {
    var namer = UUIDNamer()
    let message = """
      [3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852] Add action set finished. Responding to clients with : {
          kActionSetName = "Good Morning";
          kActionSetType = HMActionSetTypeWakeUp;
          kActionSetUUID = "8006AFD6-5739-53CB-8175-DA40FF2BFCD2";
          kHomeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852";
      }
      """

    namer.extractNames(from: message)

    let actionSetName = namer.displayName(for: "8006AFD6-5739-53CB-8175-DA40FF2BFCD2")
    // Action set names should have the action set name only
    #expect(actionSetName == "Good Morning-8006AFD6")

    // Home UUID should be registered but may not have a name yet
    let homeName = namer.displayName(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")
    // Since it's only registered (no name), displayName returns nil
    #expect(homeName == nil)
  }

  /// Tests home UUID list extraction
  @Test("Extract UUIDs from home list patterns")
  func testHomeListExtraction() async throws {
    var namer = UUIDNamer()
    let message =
      "updateHomes(timeout:) found homes [3B23B284-673A-5FFF-A863-8F62C42711C0, 92759DC3-97B6-5A09-95CC-1070E16D9260]"

    namer.extractNames(from: message)

    // UUIDs should be registered but have no names
    let name1 = namer.displayName(for: "3B23B284-673A-5FFF-A863-8F62C42711C0")
    let name2 = namer.displayName(for: "92759DC3-97B6-5A09-95CC-1070E16D9260")

    #expect(name1 == nil)
    #expect(name2 == nil)
  }

  /// Tests ambiguity handling when a UUID has multiple names
  @Test("Handle UUID with multiple names")
  func testMultipleNamesForSameUUID() async throws {
    var namer = UUIDNamer()

    // Same UUID appears in different contexts
    let message1 =
      "[Bank Street/Living Room/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Error message"
    let message2 =
      "[Plantation Road/Bedroom/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Another error"

    namer.extractNames(from: message1)
    namer.extractNames(from: message2)

    let displayName = namer.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")

    // Should show both device names, sorted alphabetically (now only device names, not home/device)
    #expect(displayName == "Bedroom/Living Room-4A8856A0")
  }

  /// Tests case-insensitive UUID matching
  @Test("UUID matching is case-insensitive")
  func testCaseInsensitiveMatching() async throws {
    var namer = UUIDNamer()
    let message =
      "[Bank Street/Device/4a8856a0-38e3-5af4-ac52-8390ffe944a2] Test message"

    namer.extractNames(from: message)

    // Try with uppercase - should work and use the prefix from the input UUID
    let name1 = namer.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    // Try with lowercase - should work and use the prefix from the input UUID
    let name2 = namer.displayName(for: "4a8856a0-38e3-5af4-ac52-8390ffe944a2")
    // Try with mixed case - should work and use the prefix from the input UUID
    let name3 = namer.displayName(for: "4A8856a0-38E3-5aF4-aC52-8390FfE944A2")

    // All should return the same name (device only), just with different prefix casing
    #expect(name1 == "Device-4A8856A0")
    #expect(name2 == "Device-4a8856a0")
    #expect(name3 == "Device-4A8856a0")
  }

  /// Tests UUID substitution in messages
  @Test("Substitute UUIDs in messages")
  func testUUIDSubstitution() async throws {
    var namer = UUIDNamer()
    let extractMessage =
      "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Configuration"

    namer.extractNames(from: extractMessage)

    let testMessage = "Device 4A8856A0-38E3-5AF4-AC52-8390FFE944A2 is unreachable"
    let result = namer.substitute(in: testMessage)

    #expect(result == "Device Lamp-4A8856A0 is unreachable")
  }

  /// Tests substitution with multiple UUIDs
  @Test("Substitute multiple UUIDs in one message")
  func testMultipleUUIDSubstitution() async throws {
    var namer = UUIDNamer()

    namer.extractNames(
      from: "[Home1/Device1/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")
    namer.extractNames(
      from: "[Home2/Device2/CBD9ADE0-29ED-5945-A6A9-6E1750392F3D] Test")

    let testMessage =
      "Connection from 4A8856A0-38E3-5AF4-AC52-8390FFE944A2 to CBD9ADE0-29ED-5945-A6A9-6E1750392F3D failed"
    let result = namer.substitute(in: testMessage)

    #expect(
      result == "Connection from Device1-4A8856A0 to Device2-CBD9ADE0 failed"
    )
  }

  /// Tests that unknown UUIDs are left unchanged
  @Test("Unknown UUIDs remain unchanged in substitution")
  func testUnknownUUIDsUnchanged() async throws {
    let namer = UUIDNamer()

    let testMessage = "Unknown device 4A8856A0-38E3-5AF4-AC52-8390FFE944A2"
    let result = namer.substitute(in: testMessage)

    // UUID should remain unchanged since no name was extracted
    #expect(result == testMessage)
  }

  /// Tests extraction and substitution with real sample data
  @Test("Extract and substitute with sample log data")
  func testRealSampleData() async throws {
    var namer = UUIDNamer()

    // Real examples from sample_output.txt
    let messages = [
      "[Bank Street/Hue color lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Active transition count value: (null) is not of type NSNumber",
      "[Bank Street/Corner Spot/949F68CF-5065-5F7E-8DBC-4D6BE20F2BD6] Ignoring Value Transition Control",
      "[Plantation Road/Living Room/691505B0-F56B-5989-8EAF-6C721322655C] Value is not of expected type",
    ]

    for message in messages {
      namer.extractNames(from: message)
    }

    // Test substitution
    let testMessage =
      "Error in 4A8856A0-38E3-5AF4-AC52-8390FFE944A2 and 949F68CF-5065-5F7E-8DBC-4D6BE20F2BD6"
    let result = namer.substitute(in: testMessage)

    #expect(
      result
        == "Error in Hue color lamp-4A8856A0 and Corner Spot-949F68CF"
    )
  }

  /// Tests that empty names are not added
  @Test("Empty names are ignored")
  func testEmptyNamesIgnored() async throws {
    var namer = UUIDNamer()
    // Test with empty path components - the pattern uses [^/\]]+ which requires
    // at least one character that's not / or ], so this won't match
    let message1 = "[//4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test"
    namer.extractNames(from: message1)

    let displayName1 = namer.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    // Should be nil because the pattern requires non-empty home and device parts
    #expect(displayName1 == nil)

    // Test that actual empty trimmed names don't get added even if pattern matches
    // In practice, the regex [^/\]]+ won't match empty strings, so this validates
    // the pattern is working correctly
  }

  /// Tests combined extraction from multiple message types
  @Test("Combined extraction from multiple pattern types")
  func testCombinedExtraction() async throws {
    var namer = UUIDNamer()

    // Path-based
    namer.extractNames(
      from: "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")

    // Action set
    namer.extractNames(
      from: """
        Add action set finished. {
            kActionSetName = "Morning";
            kActionSetUUID = "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D";
        }
        """)

    // Home list
    namer.extractNames(
      from: "found homes [3B23B284-673A-5FFF-A863-8F62C42711C0]")

    let name1 = namer.displayName(for: "4A8856A0-38E3-5AF4-AC52-8390FFE944A2")
    let name2 = namer.displayName(for: "CBD9ADE0-29ED-5945-A6A9-6E1750392F3D")
    let name3 = namer.displayName(for: "3B23B284-673A-5FFF-A863-8F62C42711C0")

    #expect(name1 == "Lamp-4A8856A0")
    #expect(name2 == "Morning-CBD9ADE0")
    #expect(name3 == nil)  // Only registered, no name
  }

  /// Tests that display name uses first 8 characters of UUID
  @Test("Display name uses UUID prefix correctly")
  func testUUIDPrefixLength() async throws {
    var namer = UUIDNamer()
    namer.extractNames(
      from: "[Home/Device/12345678-1234-5678-9ABC-123456789ABC] Test")

    let displayName = namer.displayName(for: "12345678-1234-5678-9ABC-123456789ABC")
    #expect(displayName?.hasSuffix("-12345678") == true)
    #expect(displayName?.count == "Device-12345678".count)
  }

  /// Tests that technical-looking names are filtered out
  @Test("Filter out UUID-like and hash-like names")
  func testNameFiltering() async throws {
    var namer = UUIDNamer()

    // These should all be rejected as non-human-readable
    namer.extractNames(
      from: "[Home/12345678-1234-5678-9ABC-123456789ABC/12345678-1234-5678-9ABC-123456789ABC] Test"
    )  // UUID as device name
    namer.extractNames(from: "[Home/12345/12345678-1234-5678-9ABC-123456789ABC] Test")  // Pure integer
    namer.extractNames(from: "[Home/ABCDEF123456/12345678-1234-5678-9ABC-123456789ABC] Test")
    // Hex hash
    namer.extractNames(
      from: "[Home/a1b2c3d4e5f6/12345678-1234-5678-9ABC-123456789ABC] Test")  // Alphanumeric hash

    // This should be accepted as human-readable
    namer.extractNames(
      from: "[Bank Street/Living Room Lamp/12345678-1234-5678-9ABC-123456789ABC] Test")

    let displayName = namer.displayName(for: "12345678-1234-5678-9ABC-123456789ABC")

    // Should only have the valid human-readable name
    #expect(displayName == "Living Room Lamp-12345678")
  }

  /// Tests home name association from path patterns and home lists
  @Test("Associate home names with home UUIDs")
  func testHomeNameAssociation() async throws {
    var namer = UUIDNamer()

    // Extract devices with home names
    namer.extractNames(
      from: "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")
    namer.extractNames(
      from: "[Bank Street/Camera/CBD9ADE0-29ED-5945-A6A9-6E1750392F3D] Test")

    // Register home UUID
    namer.extractNames(
      from: "updateHomes(timeout:) found homes [3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852]")

    // Associate home names with home UUIDs
    namer.associateHomeNames()

    // Home should now have a name
    let homeName = namer.displayName(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")
    #expect(homeName == "Bank Street-3C0F85CD")

    // Verify entitiesByHome groups devices under home
    let (homeToEntities, _, _) = namer.entitiesByHome()
    let homeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852".uppercased()
    #expect(homeToEntities[homeUUID]?.count == 2)
    #expect(
      homeToEntities[homeUUID]?
        .contains("4A8856A0-38E3-5AF4-AC52-8390FFE944A2".uppercased()) == true)
    #expect(
      homeToEntities[homeUUID]?
        .contains("CBD9ADE0-29ED-5945-A6A9-6E1750392F3D".uppercased()) == true)
  }

  /// Tests entities with unknown homes are properly categorized
  @Test("Entities without home association go to unknown home")
  func testUnknownHomeEntities() async throws {
    var namer = UUIDNamer()

    // Extract device without registering its home
    namer.extractNames(
      from: "[Some Home/Orphan Device/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")

    // Associate (but no home UUIDs registered, so device remains orphaned)
    namer.associateHomeNames()

    let (homeToEntities, _, unknownHomeEntities) = namer.entitiesByHome()

    // Should have no home associations
    #expect(homeToEntities.isEmpty)

    // Device should be in unknown home list
    #expect(unknownHomeEntities.count == 1)
    #expect(
      unknownHomeEntities.contains("4A8856A0-38E3-5AF4-AC52-8390FFE944A2".uppercased()))
  }

  /// Tests action set home association from kHomeUUID
  @Test("Associate action sets with homes via kHomeUUID")
  func testActionSetHomeAssociation() async throws {
    var namer = UUIDNamer()

    // Extract action set with kHomeUUID
    namer.extractNames(
      from: """
        Add action set finished. {
            kActionSetName = "Good Morning";
            kActionSetUUID = "8006AFD6-5739-53CB-8175-DA40FF2BFCD2";
            kHomeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852";
        }
        """)

    // Register the home
    namer.extractNames(
      from: "[Bank Street/Device/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")
    namer.extractNames(
      from: "updateHomes(timeout:) found homes [3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852]")

    namer.associateHomeNames()

    // Verify action set is associated with home
    let (homeToEntities, _, _) = namer.entitiesByHome()
    let homeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852".uppercased()
    #expect(homeToEntities[homeUUID]?.count == 2)  // Device + Action set
    #expect(
      homeToEntities[homeUUID]?
        .contains("8006AFD6-5739-53CB-8175-DA40FF2BFCD2".uppercased()) == true)
  }

  /// Tests HMDHome pattern extraction with both internal ID and spiID
  @Test("Extract home from HMDHome pattern")
  func testHMDHomePatternExtraction() async throws {
    var namer = UUIDNamer()

    // Extract from HMDHome pattern
    namer.extractNames(
      from:
        "<HMDHome, ID = 3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852, spiID = 3B23B284-673A-5FFF-A863-8F62C42711C0, NM = Bank Street>"
    )

    // Both internal ID and spiID should have the home name
    let internalName = namer.displayName(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")
    let spiName = namer.displayName(for: "3B23B284-673A-5FFF-A863-8F62C42711C0")

    #expect(internalName == "Bank Street-3C0F85CD")
    #expect(spiName == "Bank Street-3B23B284")

    // Verify internal ID lookup
    let internalID = namer.internalHomeID(for: "3B23B284-673A-5FFF-A863-8F62C42711C0")
    #expect(internalID == "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852".uppercased())
  }

  /// Tests Matter snapshot pattern extraction
  @Test("Extract home from Matter snapshot pattern")
  func testMatterSnapshotExtraction() async throws {
    var namer = UUIDNamer()

    // Extract from Matter snapshot pattern
    namer.extractNames(
      from:
        "new matter snapshot for '3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852', updateType:home(Bank Street), didChange:true"
    )

    let homeName = namer.displayName(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")
    #expect(homeName == "Bank Street-3C0F85CD")
  }

  /// Tests device association with home using HMDHome pattern
  @Test("Associate devices with home via HMDHome pattern")
  func testDeviceAssociationWithHMDHome() async throws {
    var namer = UUIDNamer()

    // Extract device with home name
    namer.extractNames(
      from: "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")

    // Extract HMDHome pattern
    namer.extractNames(
      from:
        "<HMDHome, ID = 3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852, spiID = 3B23B284-673A-5FFF-A863-8F62C42711C0, NM = Bank Street>"
    )

    // Device should be automatically associated with internal ID
    let (homeToEntities, _, unknownHomeEntities) = namer.entitiesByHome()
    let homeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852".uppercased()

    #expect(homeToEntities[homeUUID]?.count == 1)
    #expect(
      homeToEntities[homeUUID]?
        .contains("4A8856A0-38E3-5AF4-AC52-8390FFE944A2".uppercased()) == true)
    #expect(unknownHomeEntities.isEmpty)
  }

  /// Tests real-world scenario with spiID from found homes and internal ID from paths
  @Test("Real-world: spiID in found homes, internal ID in device paths")
  func testRealWorldHomeScenario() async throws {
    var namer = UUIDNamer()

    // Extract devices with home names (uses internal ID)
    namer.extractNames(
      from: "[Bank Street/Lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2] Test")
    namer.extractNames(
      from: "[Plantation Road/Camera/CBD9ADE0-29ED-5945-A6A9-6E1750392F3D] Test")

    // Extract found homes (uses spiID)
    namer.extractNames(
      from:
        "updateHomes(timeout:) found homes [3B23B284-673A-5FFF-A863-8F62C42711C0, 92759DC3-97B6-5A09-95CC-1070E16D9260]"
    )

    // Extract HMDHome patterns (links internal ID and spiID)
    namer.extractNames(
      from:
        "<HMDHome, ID = 3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852, spiID = 3B23B284-673A-5FFF-A863-8F62C42711C0, NM = Bank Street>"
    )
    namer.extractNames(
      from:
        "<HMDHome, ID = 1C10D9FC-AE61-4600-A21A-932051BED77D, spiID = 92759DC3-97B6-5A09-95CC-1070E16D9260, NM = Plantation Road>"
    )

    namer.associateHomeNames()

    // Both homes should have names
    let bankStreet = namer.displayName(for: "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852")
    let plantationRoad = namer.displayName(for: "1C10D9FC-AE61-4600-A21A-932051BED77D")

    #expect(bankStreet == "Bank Street-3C0F85CD")
    #expect(plantationRoad == "Plantation Road-1C10D9FC")

    // Devices should be associated with correct homes
    let (homeToEntities, _, unknownHomeEntities) = namer.entitiesByHome()

    let bankStreetUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852".uppercased()
    let plantationRoadUUID = "1C10D9FC-AE61-4600-A21A-932051BED77D".uppercased()

    #expect(homeToEntities[bankStreetUUID]?.count == 1)
    #expect(homeToEntities[plantationRoadUUID]?.count == 1)
    #expect(unknownHomeEntities.isEmpty)
  }
}
