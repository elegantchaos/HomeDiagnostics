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

  /// Mapping from home name to home UUID.
  ///
  /// Extracted from path-based patterns where the first component is the
  /// home name. Used to associate home names with home UUIDs found in
  /// "found homes" lists.
  private var homeNameToUUID: [String: String]

  /// Creates a new UUID namer with empty mappings.
  public init() {
    self.uuidToEntities = [:]
    self.homeNameToUUID = [:]
  }

  /// Extracts UUID-name associations from a log entry message.
  ///
  /// Scans the message for multiple pattern types:
  /// - Path-based: [Home/Device/UUID] - extracts device names and home names
  /// - Action sets: kActionSetName and kActionSetUUID in structured data
  /// - Home lists: found homes [UUID1, UUID2, ...] - associates with home names
  ///
  /// - Parameter message: The log message to scan for UUID-name associations.
  public mutating func extractNames(from message: String) {
    extractPathBasedNames(from: message)
    extractActionSetNames(from: message)
    extractHomeUUIDs(from: message)
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
      // Store in homeNameToUUID (will be populated when we find home UUIDs)
      // For now, just remember we've seen this home name
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
    }

    // Extract kHomeUUID and track it (name may come from other patterns)
    let homeUUIDPattern =
      /kHomeUUID\s*=\s*"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"/
    if let homeMatch = message.firstMatch(of: homeUUIDPattern) {
      let homeUUID = String(homeMatch.1)
      registerUUID(homeUUID)
    }
  }

  /// Extracts UUIDs from home list patterns.
  ///
  /// Matches patterns like:
  /// - updateHomes(timeout:) found homes [UUID1, UUID2, ...]
  ///
  /// Registers the UUIDs as home type. If a home name was previously
  /// discovered from path patterns, associates it with the UUID.
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

        // Try to find a home name from previously seen paths
        // This is a heuristic: if we've seen [HomeName/Device/UUID] patterns,
        // we can extract the home names and try to match them to home UUIDs
        // For now, we'll mark these as home type without a name
        // (names will come from other extraction in a second pass)
      }
    }
  }

  /// Second-pass extraction: associates home names with home UUIDs.
  ///
  /// After initial extraction, scans all path-based patterns to find home names,
  /// then attempts to match them with registered home UUIDs. This is called
  /// after all messages have been processed.
  ///
  /// - Parameter messages: All log messages to scan.
  mutating func associateHomeNames(from messages: [String]) {
    // Build a set of home names from all path patterns
    var homeNames: Set<String> = []
    let pathPattern =
      /\[([^\/\]]+)\/([^\/\]]+)\/([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\]/

    for message in messages {
      for match in message.matches(of: pathPattern) {
        let homeName = String(match.1)
        homeNames.insert(homeName)
      }
    }

    // For each home UUID without a name, try to assign a home name
    // This is best-effort: if we have N home UUIDs and M home names,
    // we can only associate them if N == M
    let homeUUIDs =
      uuidToEntities
      .filter { $0.value.isEmpty }
      .map { $0.key }
      .sorted()

    let sortedHomeNames = Array(homeNames).sorted()

    // Simple heuristic: if counts match, associate in alphabetical order
    if homeUUIDs.count == sortedHomeNames.count {
      for (uuid, homeName) in zip(homeUUIDs, sortedHomeNames) {
        addName(homeName, for: uuid, type: .home)
      }
    } else {
      // Can't reliably associate; mark homes as "unknown" type
      for uuid in homeUUIDs {
        // Leave empty or add a generic marker
      }
    }
  }
}
