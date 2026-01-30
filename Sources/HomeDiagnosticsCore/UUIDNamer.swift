import Foundation

/// Type categorization for named entities.
///
/// Identifies what kind of entity a name represents (device, home, action set, etc.).
public enum NameType: String, Sendable, Comparable {
  /// A HomeKit home.
  case home = "Home"
  
  /// A HomeKit device or accessory.
  case device = "Device"
  
  /// A HomeKit action set (scene).
  case actionSet = "Action Set"
  
  /// Unable to categorize the entity type.
  case unknown = "Unknown"
  
  /// Compares two name types for sorting.
  ///
  /// Orders types as: home, device, actionSet, unknown.
  ///
  /// - Parameters:
  ///   - lhs: The left-hand name type.
  ///   - rhs: The right-hand name type.
  /// - Returns: `true` if `lhs` should appear before `rhs`.
  public static func < (lhs: NameType, rhs: NameType) -> Bool {
    let order: [NameType] = [.home, .device, .actionSet, .unknown]
    guard let lhsIndex = order.firstIndex(of: lhs),
          let rhsIndex = order.firstIndex(of: rhs)
    else {
      return false
    }
    return lhsIndex < rhsIndex
  }
}

/// A named entity with its type classification.
///
/// Represents a human-readable name associated with a UUID, along with
/// metadata about what type of entity it represents.
public struct NamedEntity: Sendable, Hashable {
  /// The human-readable name.
  public let name: String
  
  /// The type of entity this name represents.
  public let type: NameType
  
  /// Creates a new named entity.
  ///
  /// - Parameters:
  ///   - name: The human-readable name.
  ///   - type: The entity type classification.
  public init(name: String, type: NameType) {
    self.name = name
    self.type = type
  }
}

/// Manages UUID-to-name mappings extracted from log entries.
///
/// Scans log messages for patterns that associate UUIDs with human-readable
/// names, such as [Home/Device/UUID] paths and structured action set data.
/// Tracks multiple names per UUID when ambiguity exists, along with type
/// information. Provides substitution functionality to replace UUIDs in
/// messages with their display names.
public struct UUIDNamer: Sendable {
  /// Mapping from normalized UUID to all named entities discovered for it.
  ///
  /// UUIDs are normalized to uppercase for case-insensitive matching.
  /// Multiple named entities may exist for a single UUID if it appears in
  /// different contexts throughout the logs.
  private var uuidToEntities: [String: Set<NamedEntity>]
  
  /// Set of home names seen in path patterns.
  ///
  /// Extracted from path-based patterns where the first component is the
  /// home name. Used as fallback if direct extraction patterns don't appear.
  private var seenHomeNames: Set<String>
  
  /// Mapping from device/action set UUID to home name.
  ///
  /// Temporarily tracks which home name each device was seen with in path
  /// patterns. After home names are associated with UUIDs, this is converted
  /// to entityToHomeUUID mappings.
  private var entityToHomeName: [String: String]
  
  /// Mapping from device/action set UUID to home UUID.
  ///
  /// Tracks which home each device or action set belongs to, extracted
  /// from path patterns and kHomeUUID fields. Used to organize output
  /// by home.
  private var entityToHomeUUID: [String: String]
  
  /// Mapping from home spiID to internal ID.
  ///
  /// HomeKit uses two UUIDs per home: an internal ID (used in device paths)
  /// and a spiID (used in "found homes" lists). This tracks the relationship
  /// between them.
  private var homeSpiIDToInternalID: [String: String]
  
  /// Mapping from UUID to Matter ID.
  ///
  /// Tracks Matter IDs for devices/homes when detected in logs.
  private var uuidToMatterID: [String: String]
  
  /// Creates a new UUID namer with empty mappings.
  public init() {
    self.uuidToEntities = [:]
    self.seenHomeNames = []
    self.entityToHomeName = [:]
    self.entityToHomeUUID = [:]
    self.homeSpiIDToInternalID = [:]
    self.uuidToMatterID = [:]
  }
  
  /// Extracts UUID-name associations from a log entry message.
  ///
  /// Scans the message for multiple pattern types:
  /// - Path-based: [Home/Device/UUID] - extracts device names and home names
  /// - Action sets: kActionSetName and kActionSetUUID in structured data
  /// - Home lists: found homes [UUID1, UUID2, ...] - registers home spiIDs
  /// - HMDHome objects: <HMDHome, ID = ..., spiID = ..., NM = ...> - direct home info
  /// - Matter snapshots: new matter snapshot for 'UUID', updateType:home(Name)
  ///
  /// - Parameter message: The log message to scan for UUID-name associations.
  public mutating func extractNames(from message: String) {
    extractPathBasedNames(from: message)
    extractActionSetNames(from: message)
    extractHomeUUIDs(from: message)
    extractHomeFromHMDHomePattern(from: message)
    extractHomeFromMatterSnapshot(from: message)
  }
  
  /// Second-pass extraction: associates home names with home UUIDs.
  ///
  /// After initial extraction, resolves any remaining home name associations.
  /// By this point, most homes should already be named through direct patterns
  /// (HMDHome or Matter snapshot). This method handles edge cases using fallback
  /// heuristics.
  ///
  /// Also uses spiID-to-internal ID mappings to ensure entities are properly
  /// associated with their homes.
  public mutating func associateHomeNames() {
    // First, use spiID-to-internal ID mappings to link homes
    for (spiID, internalID) in homeSpiIDToInternalID {
      // If spiID has a name but internal ID doesn't, copy it
      if let spiIDEntities = uuidToEntities[spiID], !spiIDEntities.isEmpty {
        if uuidToEntities[internalID] == nil || uuidToEntities[internalID]!.isEmpty {
          for entity in spiIDEntities {
            addName(entity.name, for: internalID, type: entity.type)
          }
        }
      }
      
      // If internal ID has a name but spiID doesn't, copy it
      if let internalEntities = uuidToEntities[internalID], !internalEntities.isEmpty {
        if uuidToEntities[spiID] == nil || uuidToEntities[spiID]!.isEmpty {
          for entity in internalEntities {
            addName(entity.name, for: spiID, type: entity.type)
          }
        }
      }
    }
    
    // Fallback heuristic: for unnamed home UUIDs, try alphabetical matching
    // This only runs if we have unnamed homes after direct extraction
    let unnamedHomeUUIDs =
    uuidToEntities
      .filter { $0.value.isEmpty }
      .map { $0.key }
      .sorted()
    
    // Find home names that haven't been associated yet
    let usedNames = Set(
      uuidToEntities.values.flatMap { entities in
        entities.filter { $0.type == .home }.map { $0.name }
      })
    let unusedHomeNames = seenHomeNames.subtracting(usedNames).sorted()
    
    // Only use alphabetical matching if counts match (very uncertain heuristic)
    if unnamedHomeUUIDs.count == unusedHomeNames.count && !unnamedHomeUUIDs.isEmpty {
      var homeNameToUUID: [String: String] = [:]
      for (uuid, homeName) in zip(unnamedHomeUUIDs, unusedHomeNames) {
        addName(homeName, for: uuid, type: .home)
        homeNameToUUID[homeName] = uuid
      }
      
      // Resolve entity-to-home mappings for these fallback names
      for (entityUUID, homeName) in entityToHomeName {
        if let homeUUID = homeNameToUUID[homeName] {
          if entityToHomeUUID[entityUUID] == nil {
            entityToHomeUUID[entityUUID] = homeUUID
          }
        }
      }
    }
    
    // Resolve any remaining entities using spiID mappings
    for (entityUUID, homeUUID) in entityToHomeUUID {
      // If entity points to a spiID, convert to internal ID
      if let internalID = homeSpiIDToInternalID[homeUUID] {
        entityToHomeUUID[entityUUID] = internalID
      }
    }
  }
  
  /// Returns the display name for a UUID, handling ambiguity.
  ///
  /// Generates a display name by combining all discovered names with the
  /// first 8 characters of the UUID. If multiple names exist, they are
  /// joined with "/" to show ambiguity. If no name is found, returns nil.
  ///
  /// Examples:
  /// - Single name: "Garage Camera-9FEA624C"
  /// - Multiple names: "Garage Camera/Living Room Camera-9FEA624C"
  ///
  /// - Parameter uuid: The UUID to look up (case-insensitive).
  /// - Returns: Display name with UUID prefix, or nil if no name found.
  public func displayName(for uuid: String) -> String? {
    guard let entities = uuidToEntities[uuid.uppercased()], !entities.isEmpty else {
      return nil
    }
    
    let sortedNames = entities.map { $0.name }.sorted()
    let prefix = String(uuid.prefix(8))
    
    if sortedNames.count == 1 {
      // Single name: "Garage Camera-9FEA624C"
      return "\(sortedNames[0])-\(prefix)"
    } else {
      // Multiple names: "Garage Camera/Living Room Camera-9FEA624C"
      return "\(sortedNames.joined(separator: "/"))-\(prefix)"
    }
  }
  
  /// Substitutes all UUIDs in a message with their display names.
  ///
  /// Searches the message for UUID patterns (8-4-4-4-12 hex format) and
  /// replaces them with display names when available. Processes matches
  /// in reverse order to maintain correct string indices during replacement.
  ///
  /// - Parameter message: The message to process.
  /// - Returns: Message with UUIDs replaced by display names where available.
  public func substitute(in message: String) -> String {
    var result = message
    
    // UUID pattern: 8-4-4-4-12 format
    let uuidPattern =
    /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/
    
    // Process matches in reverse to maintain indices
    for match in message.matches(of: uuidPattern).reversed() {
      let uuid = String(match.0)
      if let displayName = displayName(for: uuid) {
        let range = match.range
        result.replaceSubrange(range, with: displayName)
      }
    }
    
    return result
  }
  
  /// Returns all UUIDs that have been assigned names, grouped by type.
  ///
  /// Returns an array of tuples containing UUID, named entities, and primary type.
  /// Only includes UUIDs that have at least one named entity. Results are sorted
  /// by type first, then by UUID.
  ///
  /// - Returns: Array of (uuid, entities, primaryType) tuples, sorted by type and UUID.
  public func namedUUIDs() -> [(uuid: String, entities: Set<NamedEntity>, primaryType: NameType)]
  {
    return uuidToEntities
      .filter { !$0.value.isEmpty }
      .map { uuid, entities in
        // Determine primary type (prefer most specific: home > device > actionSet > unknown)
        let primaryType = entities.map { $0.type }.min() ?? .unknown
        return (uuid: uuid, entities: entities, primaryType: primaryType)
      }
      .sorted { lhs, rhs in
        // Sort by type first, then by UUID
        if lhs.primaryType != rhs.primaryType {
          return lhs.primaryType < rhs.primaryType
        }
        return lhs.uuid < rhs.uuid
      }
  }
  
  /// Returns all UUIDs organized by their home.
  ///
  /// Groups devices and action sets under their respective home UUIDs.
  /// Returns a dictionary mapping home UUID to arrays of entity UUIDs that belong
  /// to that home, along with standalone home UUIDs and entities with unknown homes.
  ///
  /// - Returns: Tuple containing:
  ///   - homeToEntities: Dictionary mapping home UUID to child entity UUIDs
  ///   - standaloneHomes: Array of home UUIDs without children
  ///   - unknownHomeEntities: Array of entity UUIDs not associated with any home
  public func entitiesByHome() -> (
    homeToEntities: [String: [String]], standaloneHomes: [String], unknownHomeEntities: [String]
  ) {
    // Get all home UUIDs
    let homeUUIDs = Set(
      uuidToEntities
        .filter { entities in
          entities.value.contains(where: { $0.type == .home })
        }
        .map { $0.key }
    )
    
    // Build mapping of home UUID to child entities
    var homeToEntities: [String: [String]] = [:]
    var unknownHomeEntities: [String] = []
    
    for (entityUUID, entities) in uuidToEntities {
      // Skip homes themselves
      if entities.contains(where: { $0.type == .home }) {
        continue
      }
      
      // Skip entities without names
      if entities.isEmpty {
        continue
      }
      
      // Find which home this entity belongs to
      if let homeUUID = entityToHomeUUID[entityUUID], homeUUIDs.contains(homeUUID) {
        homeToEntities[homeUUID, default: []].append(entityUUID)
      } else {
        unknownHomeEntities.append(entityUUID)
      }
    }
    
    // Sort all arrays
    for key in homeToEntities.keys {
      homeToEntities[key]?.sort()
    }
    unknownHomeEntities.sort()
    
    // Get standalone homes (homes without children)
    let standaloneHomes = homeUUIDs.sorted().filter { homeUUID in
      homeToEntities[homeUUID] == nil || homeToEntities[homeUUID]!.isEmpty
    }
    
    return (homeToEntities, standaloneHomes, unknownHomeEntities)
  }
  
  /// Returns the entities for a given UUID.
  ///
  /// - Parameter uuid: The UUID to look up (case-insensitive).
  /// - Returns: The set of named entities, or empty set if not found.
  public func entities(for uuid: String) -> Set<NamedEntity> {
    return uuidToEntities[uuid.uppercased()] ?? []
  }
  
  /// Returns the Matter ID for a given UUID, if available.
  ///
  /// - Parameter uuid: The UUID to look up (case-insensitive).
  /// - Returns: The Matter ID, or nil if not found.
  public func matterID(for uuid: String) -> String? {
    return uuidToMatterID[uuid.uppercased()]
  }
  
  /// Returns the internal home ID for a given spiID, if available.
  ///
  /// HomeKit uses two UUIDs per home. This method converts a spiID
  /// (from "found homes" lists) to the internal ID (used in device paths).
  ///
  /// - Parameter spiID: The spiID to look up (case-insensitive).
  /// - Returns: The internal ID, or nil if not found.
  public func internalHomeID(for spiID: String) -> String? {
    return homeSpiIDToInternalID[spiID.uppercased()]
  }
  
  /// Adds a named entity for a UUID to the mapping.
  ///
  /// UUIDs are normalized to uppercase for case-insensitive matching.
  /// Names are trimmed and validated. If the UUID already has entities,
  /// the new entity is added to the set.
  ///
  /// Names that appear to be UUIDs, integers, hex numbers, or hashes are
  /// rejected to avoid polluting the mapping with non-human-readable values.
  ///
  /// - Parameters:
  ///   - name: The human-readable name to associate.
  ///   - uuid: The UUID identifier.
  ///   - type: The type of entity this name represents.
  private mutating func addName(_ name: String, for uuid: String, type: NameType) {
    let normalizedUUID = uuid.uppercased()
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    
    // Skip empty names
    guard !trimmedName.isEmpty else { return }
    
    // Skip names that look like technical identifiers
    guard isValidHumanReadableName(trimmedName) else { return }
    
    let entity = NamedEntity(name: trimmedName, type: type)
    
    if uuidToEntities[normalizedUUID] != nil {
      uuidToEntities[normalizedUUID]?.insert(entity)
    } else {
      uuidToEntities[normalizedUUID] = [entity]
    }
  }
  
  /// Checks if a name appears to be human-readable.
  ///
  /// Rejects names that look like:
  /// - UUIDs (8-4-4-4-12 hex format)
  /// - Pure integers
  /// - Pure hexadecimal strings
  /// - Mixed alphanumeric hashes (e.g., "a1b2c3d4")
  ///
  /// - Parameter name: The name to validate.
  /// - Returns: `true` if the name appears human-readable.
  private func isValidHumanReadableName(_ name: String) -> Bool {
    // Reject UUID patterns
    let uuidPattern =
    /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/
    if name.contains(uuidPattern) {
      return false
    }
    
    // Reject pure integers
    if Int(name) != nil {
      return false
    }
    
    // Reject pure hexadecimal (no spaces, all hex chars)
    let hexPattern = /^[0-9A-Fa-f]+$/
    if name.count > 6 && name.contains(hexPattern) {
      return false
    }
    
    // Reject mixed alphanumeric that looks like a hash
    // (all alphanumeric, no spaces, mix of letters and numbers, length > 8)
    let alphanumericOnly = name.allSatisfy { $0.isLetter || $0.isNumber }
    let hasLetters = name.contains(where: { $0.isLetter })
    let hasNumbers = name.contains(where: { $0.isNumber })
    
    if alphanumericOnly && hasLetters && hasNumbers && name.count > 8 {
      return false
    }
    
    return true
  }
  
  /// Registers a UUID without a name for tracking purposes.
  ///
  /// Used when we encounter a UUID that we want to track but don't yet
  /// have a name for (e.g., in home UUID lists). This allows us to
  /// potentially associate a name later.
  ///
  /// - Parameter uuid: The UUID to register.
  private mutating func registerUUID(_ uuid: String) {
    let normalizedUUID = uuid.uppercased()
    if uuidToEntities[normalizedUUID] == nil {
      uuidToEntities[normalizedUUID] = []
    }
  }
  
  /// Merges another UUIDNamer into this one, combining all mappings and sets.
  ///
  /// Used for parallel batch processing, where each batch produces a local UUIDNamer.
  /// After merging, run associateHomeNames() once on the final result.
  public mutating func merge(with other: UUIDNamer) {
    // Merge uuidToEntities
    for (uuid, entities) in other.uuidToEntities {
      if let existing = self.uuidToEntities[uuid] {
        self.uuidToEntities[uuid] = existing.union(entities)
      } else {
        self.uuidToEntities[uuid] = entities
      }
    }
    // Merge seenHomeNames
    self.seenHomeNames.formUnion(other.seenHomeNames)
    // Merge entityToHomeName
    for (uuid, name) in other.entityToHomeName {
      self.entityToHomeName[uuid] = name
    }
    // Merge entityToHomeUUID
    for (uuid, homeUUID) in other.entityToHomeUUID {
      self.entityToHomeUUID[uuid] = homeUUID
    }
    // Merge homeSpiIDToInternalID
    for (spiID, internalID) in other.homeSpiIDToInternalID {
      self.homeSpiIDToInternalID[spiID] = internalID
    }
    // Merge uuidToMatterID
    for (uuid, matterID) in other.uuidToMatterID {
      self.uuidToMatterID[uuid] = matterID
    }
  }
}

// MARK: - Pattern Extraction

private extension UUIDNamer {
  /// Extracts names from path-based patterns: [Home/Device/UUID].
  ///
  /// Matches patterns like:
  /// - [Bank Street/Hue color lamp/4A8856A0-38E3-5AF4-AC52-8390FFE944A2]
  /// - [Plantation Road/Garage Camera/9FEA624C-904C-5D88-B50E-90FFA8FCBE53]
  ///
  /// Associates the UUID with the device name (final non-UUID component).
  /// Tracks the home name for later association with home UUIDs.
  ///
  /// - Parameter message: The message to scan.
  mutating func extractPathBasedNames(from message: String) {
    // Pattern: [Home/Device/UUID]
    let pattern =
    /\[([^\/\]]+)\/([^\/\]]+)\/([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\]/
    
    for match in message.matches(of: pattern) {
      let homeName = String(match.1)
      let deviceName = String(match.2)
      let uuid = String(match.3)
      
      // Add device name (only the final non-UUID part)
      addName(deviceName, for: uuid, type: .device)
      
      // Track home name for later association with home UUIDs
      seenHomeNames.insert(homeName)
      
      // Track which home this device belongs to (by name, will be resolved to UUID later)
      entityToHomeName[uuid.uppercased()] = homeName
    }
  }
  
  /// Extracts names from action set structured data.
  ///
  /// Looks for patterns in messages containing "Add action set finished":
  /// - kActionSetName = "Good Morning";
  /// - kActionSetUUID = "8006AFD6-5739-53CB-8175-DA40FF2BFCD2";
  /// - kHomeUUID = "3C0F85CD-3FE6-43BD-B4B5-C9B07FF97852";
  ///
  /// Associates the action set UUID with its name.
  /// Tracks home UUIDs for later association with home names.
  ///
  /// - Parameter message: The message to scan.
  mutating func extractActionSetNames(from message: String) {
    // Only process messages that contain action set data
    guard message.contains("Add action set finished") else { return }
    
    // Extract kActionSetName
    let namePattern = /kActionSetName\s*=\s*"([^"]+)"/
    let actionSetName = message.firstMatch(of: namePattern).map { String($0.1) }
    
    // Extract kActionSetUUID
    let actionSetUUIDPattern =
    /kActionSetUUID\s*=\s*"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"/
    if let actionSetMatch = message.firstMatch(of: actionSetUUIDPattern) {
      let uuid = String(actionSetMatch.1)
      if let name = actionSetName {
        addName(name, for: uuid, type: .actionSet)
      }
      
      // Extract kHomeUUID and associate this action set with the home
      let homeUUIDPattern =
      /kHomeUUID\s*=\s*"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"/
      if let homeMatch = message.firstMatch(of: homeUUIDPattern) {
        let homeUUID = String(homeMatch.1)
        registerUUID(homeUUID)
        entityToHomeUUID[uuid.uppercased()] = homeUUID.uppercased()
      }
    }
  }
  
  /// Extracts UUIDs from home list patterns.
  ///
  /// Matches patterns like:
  /// - updateHomes(timeout:) found homes [UUID1, UUID2, ...]
  ///
  /// Registers the UUIDs as home spiIDs. These will be linked to internal IDs
  /// through HMDHome pattern extraction or fallback heuristics.
  ///
  /// - Parameter message: The message to scan.
  mutating func extractHomeUUIDs(from message: String) {
    // Pattern: found homes [UUID1, UUID2, ...]
    let pattern = /found homes \[([^\]]+)\]/
    
    if let match = message.firstMatch(of: pattern) {
      let uuidList = String(match.1)
      for uuid in uuidList.split(separator: ",") {
        let cleaned = uuid.trimmingCharacters(in: .whitespaces)
        registerUUID(cleaned)
      }
    }
  }
  
  /// Extracts home information from HMDHome object description patterns.
  ///
  /// Matches patterns like:
  /// - <HMDHome, ID = 3C0F85CD-..., spiID = 3B23B284-..., NM = Bank Street>
  ///
  /// This is the most reliable pattern as it contains:
  /// - Internal ID (used in device paths)
  /// - SPI ID (used in "found homes" lists)
  /// - Home name
  ///
  /// - Parameter message: The message to scan.
  mutating func extractHomeFromHMDHomePattern(from message: String) {
    // Pattern: <HMDHome, ID = UUID1, spiID = UUID2, NM = Name>
    let pattern =
    /<HMDHome, ID = ([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}), spiID = ([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}), NM = ([^>]+)>/
    
    for match in message.matches(of: pattern) {
      let internalID = String(match.1)
      let spiID = String(match.2)
      let name = String(match.3)
      
      // Add name to both UUIDs
      addName(name, for: internalID, type: .home)
      addName(name, for: spiID, type: .home)
      
      // Track the spiID-to-internal ID relationship
      homeSpiIDToInternalID[spiID.uppercased()] = internalID.uppercased()
      
      // Mark entities that belong to this home (by name) as belonging to internal ID
      for (entityUUID, homeName) in entityToHomeName where homeName == name {
        entityToHomeUUID[entityUUID] = internalID.uppercased()
      }
    }
  }
  
  /// Extracts home information from Matter snapshot patterns.
  ///
  /// Matches patterns like:
  /// - new matter snapshot for '3C0F85CD-...', updateType:home(Bank Street)
  ///
  /// This pattern provides the internal ID (used in device paths) and home name.
  /// Acts as a backup if HMDHome pattern is not found.
  ///
  /// - Parameter message: The message to scan.
  mutating func extractHomeFromMatterSnapshot(from message: String) {
    // Pattern: new matter snapshot for 'UUID', updateType:home(Name)
    let pattern =
    /new matter snapshot for '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})', updateType:home\(([^)]+)\)/
    
    for match in message.matches(of: pattern) {
      let uuid = String(match.1)
      let name = String(match.2)
      
      // Add name to internal ID
      addName(name, for: uuid, type: .home)
      
      // Associate entities with this home by name
      for (entityUUID, homeName) in entityToHomeName where homeName == name {
        entityToHomeUUID[entityUUID] = uuid.uppercased()
      }
    }
  }
}
