import Foundation

public struct EntityResolver: Sendable {
  public private(set) var uuidToEntity: [String: Entity] = [:]
  public private(set) var nameToEntity: [String: Entity] = [:]
  public private(set) var allEntities: Set<Entity> = []

  public init(annotations: [EntityAnnotation]) {
    for annotation in annotations {
      switch annotation.kind {
        case .name(let uuid, let name, let type):
          guard !name.isEmpty else { break }
          let entity = uuidToEntity[uuid] ?? nameToEntity[name] ?? Entity(type: type)
          entity.uuids.insert(uuid)
          entity.names.insert(name)
          entity.type = type
          uuidToEntity[uuid] = entity
          nameToEntity[name] = entity
          allEntities.insert(entity)
        case .uuid(let name, let uuid, let type):
          guard !name.isEmpty else { break }
          let entity = uuidToEntity[uuid] ?? nameToEntity[name] ?? Entity(type: type)
          entity.uuids.insert(uuid)
          entity.names.insert(name)
          entity.type = type
          uuidToEntity[uuid] = entity
          nameToEntity[name] = entity
          allEntities.insert(entity)
        case .matterID(let uuid, let matterID):
          let entity = uuidToEntity[uuid] ?? Entity(type: .unknown)
          entity.uuids.insert(uuid)
          entity.matterIDs.insert(matterID)
          uuidToEntity[uuid] = entity
          allEntities.insert(entity)
        case .owner(let childUUID, let ownerUUID):
          guard let child = uuidToEntity[childUUID], let owner = uuidToEntity[ownerUUID] else { continue }
          child.owner = owner
        case .register(let uuid, let type):
          let entity = uuidToEntity[uuid] ?? Entity(type: type)
          entity.uuids.insert(uuid)
          uuidToEntity[uuid] = entity
          allEntities.insert(entity)
        case .spiID(let uuid, let spiID):
          let entity = uuidToEntity[uuid] ?? Entity(type: .home)
          entity.uuids.insert(uuid)
          entity.spiIDs.insert(spiID)
          uuidToEntity[uuid] = entity
          allEntities.insert(entity)
      }
    }
  }

  /// Resolves and merges entities, ensuring all names, UUIDs, and home relationships are fully connected.
  /// This should be called after all annotations are collected and initial entities are built.
  public mutating func resolve() {
    // 1. Merge entities with the same name/type or uuid/type (deduplication)
    var mergedEntities: [String: Entity] = [:]
    for entity in allEntities {
      for uuid in entity.uuids {
        if let existing = mergedEntities[uuid] {
          // Merge names, uuids, matterIDs, and type
          existing.names.formUnion(entity.names)
          existing.uuids.formUnion(entity.uuids)
          existing.matterIDs.formUnion(entity.matterIDs)
          if entity.type != .unknown { existing.type = entity.type }
          // Merge owner if not already set
          if existing.owner == nil { existing.owner = entity.owner }
        } else {
          mergedEntities[uuid] = entity
        }
      }
    }
    uuidToEntity = mergedEntities
    allEntities = Set(mergedEntities.values)
    // 2. Ensure owner relationships are consistent (spiID/internalID mapping, fallback heuristics, etc.)
    // This is a placeholder for more advanced home association logic as in associateHomeNames().
    // If you have additional context (e.g., spiID/internalID maps, home name fallback), implement here.
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
    guard let entity = uuidToEntity[uuid.lowercased()] else {
      return nil
    }
    let sortedNames = entity.names.sorted()
    let prefix = String(uuid.prefix(8))
    if sortedNames.count == 1 {
      return "\(sortedNames[0])-\(prefix)"
    } else if sortedNames.count > 1 {
      return "\(sortedNames.joined(separator: "/"))-\(prefix)"
    } else {
      return nil
    }
  }

  public func substitute(in message: String) -> String {
    var result = message
    let uuidPattern = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/
    for match in message.matches(of: uuidPattern).reversed() {
      let uuid = String(match.0)
      if let displayName = displayName(for: uuid) {
        let range = match.range
        result.replaceSubrange(range, with: displayName)
      }
    }
    return result
  }

}
