import Foundation
import OSLog

/// Logger for entity resolution operations.
let logger = Logger(subsystem: "com.elegantchaos.HomeDiagnostics", category: "EntityResolver")

/// Resolves entity annotations into a unified entity graph.
///
/// Merges annotations from multiple sources (pattern scanning, HomeKit API) to create
/// a consistent entity model. Entities are uniquely identified by UUID, with names
/// scoped by entity type to allow same names across different types.
public struct EntityResolver: Sendable {
  /// Maps UUIDs (lowercased) to their entities.
  public private(set) var uuidToEntity: [String: Entity] = [:]

  /// Maps "type:name" keys to entities for type-scoped name lookup.
  public private(set) var nameToEntity: [String: Entity] = [:]

  /// All unique entities discovered during resolution.
  public private(set) var allEntities: Set<Entity> = []

  /// Ownership relationships to establish during resolve().
  private var ownershipAnnotations: [(childUUID: String, ownerUUID: String)] = []

  /// Name-based ownership relationships to establish during resolve().
  private var nameBasedOwnershipAnnotations: [(childUUID: String, ownerName: String, ownerType: NameType)] = []

  /// Creates an entity resolver from annotations.
  ///
  /// Processes annotations to build the entity graph. When the same UUID appears with
  /// different names, the first-encountered name is kept and a warning is logged.
  ///
  /// - Parameter annotations: Array of entity annotations from various sources.
  public init(annotations: [EntityAnnotation]) {
    for annotation in Self.orderedAnnotations(annotations) {
      switch annotation.kind {
        case .name(let uuid, let name, let type):
          guard !name.isEmpty else { break }
          let nameKey = Self.nameKey(name: name, type: type)
          let existingByUUID = uuidToEntity[uuid]
          let existingByName = nameToEntity[nameKey]
          let entity: Entity
          if let existingByUUID, let existingByName, existingByUUID !== existingByName {
            existingByName.uuids.formUnion(existingByUUID.uuids)
            existingByName.matterIDs.formUnion(existingByUUID.matterIDs)
            existingByName.spiIDs.formUnion(existingByUUID.spiIDs)
            if existingByName.owner == nil { existingByName.owner = existingByUUID.owner }
            if existingByName.type == .unknown && existingByUUID.type != .unknown {
              existingByName.type = existingByUUID.type
            }
            allEntities.remove(existingByUUID)
            for mergedUUID in existingByUUID.uuids {
              uuidToEntity[mergedUUID] = existingByName
            }
            entity = existingByName
          } else {
            entity = existingByUUID ?? existingByName ?? Entity(type: type)
          }
          entity.uuids.insert(uuid)
          // Check for name conflict
          if !entity.name.isEmpty && entity.name != name {
            logger.warning("UUID \(uuid) has conflicting names: '\(entity.name)' vs '\(name)'. Keeping first.")
          } else if entity.name.isEmpty {
            entity.name = name
          }
          if type != .unknown || entity.type == .unknown {
            entity.type = type
          }
          uuidToEntity[uuid] = entity
          nameToEntity[nameKey] = entity
          allEntities.insert(entity)
        case .uuid(let name, let uuid, let type):
          guard !name.isEmpty else { break }
          let nameKey = Self.nameKey(name: name, type: type)
          let existingByUUID = uuidToEntity[uuid]
          let existingByName = nameToEntity[nameKey]
          let entity: Entity
          if let existingByUUID, let existingByName, existingByUUID !== existingByName {
            existingByName.uuids.formUnion(existingByUUID.uuids)
            existingByName.matterIDs.formUnion(existingByUUID.matterIDs)
            existingByName.spiIDs.formUnion(existingByUUID.spiIDs)
            if existingByName.owner == nil { existingByName.owner = existingByUUID.owner }
            if existingByName.type == .unknown && existingByUUID.type != .unknown {
              existingByName.type = existingByUUID.type
            }
            allEntities.remove(existingByUUID)
            for mergedUUID in existingByUUID.uuids {
              uuidToEntity[mergedUUID] = existingByName
            }
            entity = existingByName
          } else {
            entity = existingByUUID ?? existingByName ?? Entity(type: type)
          }
          entity.uuids.insert(uuid)
          // Check for name conflict
          if !entity.name.isEmpty && entity.name != name {
            logger.warning("UUID \(uuid) has conflicting names: '\(entity.name)' vs '\(name)'. Keeping first.")
          } else if entity.name.isEmpty {
            entity.name = name
          }
          if type != .unknown || entity.type == .unknown {
            entity.type = type
          }
          uuidToEntity[uuid] = entity
          nameToEntity[nameKey] = entity
          allEntities.insert(entity)
        case .matterID(let uuid, let matterID):
          let entity = uuidToEntity[uuid] ?? Entity(type: .unknown)
          entity.uuids.insert(uuid)
          entity.matterIDs.insert(matterID)
          uuidToEntity[uuid] = entity
          allEntities.insert(entity)
        case .owner(let childUUID, let ownerUUID):
          // Defer ownership resolution until resolve() is called
          ownershipAnnotations.append((childUUID: childUUID, ownerUUID: ownerUUID))
        case .ownerByName(let childUUID, let ownerName, let ownerType):
          // Defer name-based ownership resolution until resolve() is called
          nameBasedOwnershipAnnotations.append((childUUID: childUUID, ownerName: ownerName, ownerType: ownerType))
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

  /// Returns annotations in a deterministic processing order.
  ///
  /// Prioritizes name registration before identity links and ownership,
  /// so entities are merged before attaching child relationships.
  ///
  /// - Parameter annotations: The annotations to order.
  /// - Returns: An ordered list of annotations.
  private static func orderedAnnotations(_ annotations: [EntityAnnotation]) -> [EntityAnnotation] {
    annotations.sorted { lhs, rhs in
      let lhsKey = annotationSortKey(lhs)
      let rhsKey = annotationSortKey(rhs)
      return lhsKey < rhsKey
    }
  }

  /// Returns a stable sort key for an annotation.
  ///
  /// - Parameter annotation: The annotation to key.
  /// - Returns: A tuple suitable for ordering annotations.
  private static func annotationSortKey(_ annotation: EntityAnnotation) -> (Int, String) {
    switch annotation.kind {
      case .name(let uuid, let name, let type):
        return (0, "name|\(type.rawValue)|\(name.lowercased())|\(uuid)")
      case .uuid(let name, let uuid, let type):
        return (1, "uuid|\(type.rawValue)|\(name.lowercased())|\(uuid)")
      case .register(let uuid, let type):
        return (2, "register|\(type.rawValue)|\(uuid)")
      case .spiID(let uuid, let spiID):
        return (3, "spiID|\(uuid)|\(spiID)")
      case .matterID(let uuid, let matterID):
        return (4, "matterID|\(uuid)|\(matterID)")
      case .owner(let childUUID, let ownerUUID):
        return (5, "owner|\(childUUID)|\(ownerUUID)")
      case .ownerByName(let childUUID, let ownerName, let ownerType):
        return (6, "ownerByName|\(ownerType.rawValue)|\(ownerName.lowercased())|\(childUUID)")
    }
  }

  /// Resolves and merges entities, ensuring all UUIDs and home relationships are fully connected.
  ///
  /// Performs deduplication by merging entities with shared UUIDs. When merging entities
  /// with different names, the first-encountered name is preserved and a warning is logged.
  /// This should be called after all annotations are collected.
  public mutating func resolve() {
    // 1. Merge entities with the same UUID (deduplication)
    var mergedEntities: [String: Entity] = [:]
    for entity in allEntities {
      for uuid in entity.uuids {
        if let existing = mergedEntities[uuid] {
          // Log warning if names differ
          if !entity.name.isEmpty && existing.name != entity.name {
            logger.warning("Merging entities with different names for UUID \(uuid): '\(existing.name)' vs '\(entity.name)'. Keeping first.")
          }
          // Merge UUIDs, Matter IDs, and SPI IDs (name stays with existing)
          existing.uuids.formUnion(entity.uuids)
          existing.matterIDs.formUnion(entity.matterIDs)
          existing.spiIDs.formUnion(entity.spiIDs)
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

    // 2. Merge home entities that are linked via spiID
    for entity in allEntities where entity.type == .home {
      for spiID in entity.spiIDs {
        guard let spiEntity = uuidToEntity[spiID], spiEntity !== entity else { continue }
        entity.uuids.formUnion(spiEntity.uuids)
        entity.matterIDs.formUnion(spiEntity.matterIDs)
        entity.spiIDs.formUnion(spiEntity.spiIDs)
        if entity.name.isEmpty { entity.name = spiEntity.name }
        if entity.owner == nil { entity.owner = spiEntity.owner }
        if entity.type == .unknown && spiEntity.type != .unknown { entity.type = spiEntity.type }
        for mergedUUID in spiEntity.uuids {
          uuidToEntity[mergedUUID] = entity
        }
        allEntities.remove(spiEntity)
      }
    }

    // 3. Establish ownership relationships now that all entities are created
    for (childUUID, ownerUUID) in ownershipAnnotations {
      if let child = uuidToEntity[childUUID], let owner = uuidToEntity[ownerUUID] {
        child.owner = owner
      }
    }

    // 4. Establish name-based ownership relationships
    for (childUUID, ownerName, ownerType) in nameBasedOwnershipAnnotations {
      if let child = uuidToEntity[childUUID] {
        let nameKey = Self.nameKey(name: ownerName, type: ownerType)
        if let owner = nameToEntity[nameKey] {
          child.owner = owner
        }
      }
    }
  }

  /// Returns the display name for a UUID.
  ///
  /// Uses the resolved entity name as-is when available.
  ///
  /// - Parameter uuid: The UUID to look up (case-insensitive).
  /// - Returns: Display name, or nil if no name found.
  public func displayName(for uuid: String) -> String? {
    guard let entity = uuidToEntity[uuid.lowercased()], !entity.name.isEmpty else {
      return nil
    }
    return entity.name
  }

  /// Substitutes UUIDs in a message with human-readable display names.
  ///
  /// Finds all UUID patterns in the message and replaces them with their
  /// corresponding display names (if available).
  ///
  /// - Parameter message: The message containing UUIDs to substitute.
  /// - Returns: Message with UUIDs replaced by display names.
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

  /// Creates a type-scoped name key for lookups.
  ///
  /// Allows entities of different types to share the same name.
  /// Names are normalized to lowercase for case-insensitive matching.
  ///
  /// - Parameters:
  ///   - name: The entity name (will be lowercased for matching).
  ///   - type: The entity type.
  /// - Returns: Key string in "type:name" format with lowercase name.
  private static func nameKey(name: String, type: NameType) -> String {
    "\(type.rawValue):\(name.lowercased())"
  }

  /// Returns all entities that have both a name and at least one UUID.
  ///
  /// Useful for determining which entities can be displayed in output summaries.
  ///
  /// - Returns: Set of named entities with UUIDs.
  public var namedUUIDs: Set<Entity> {
    allEntities.filter { !$0.name.isEmpty && !$0.uuids.isEmpty }
  }

  /// Organizes entities by their home ownership.
  ///
  /// Groups entities into three categories:
  /// - Homes with child entities (devices, scenes)
  /// - Standalone homes (no children)
  /// - Entities with no home owner
  ///
  /// Home entities are indexed by ALL their UUIDs (both internal ID and spiID), so you can
  /// look up a home using any of its UUIDs. Each UUID points to the same set of children.
  ///
  /// - Returns: Tuple containing:
  ///   - homeToEntities: Map of home UUIDs to their child entity UUIDs
  ///   - standaloneHomes: Set of home UUIDs with no children
  ///   - unknownHomeEntities: Set of entity UUIDs with no home owner
  public func entitiesByHome() -> (
    homeToEntities: [String: Set<String>],
    standaloneHomes: Set<String>,
    unknownHomeEntities: Set<String>
  ) {
    var homeToEntities: [String: Set<String>] = [:]
    var standaloneHomes: Set<String> = []
    var unknownHomeEntities: Set<String> = []

    // Find all home entities - add all their UUIDs to standalone initially
    let homes = allEntities.filter { $0.type == .home }
    for home in homes {
      for homeUUID in home.uuids {
        standaloneHomes.insert(homeUUID)
      }
    }

    // Find all non-home entities
    let nonHomes = allEntities.filter { $0.type != .home }
    for entity in nonHomes {
      guard let entityUUID = entity.uuids.first else { continue }

      if let owner = entity.owner {
        // Entity has a home owner - add under ALL the home's UUIDs
        for homeUUID in owner.uuids {
          homeToEntities[homeUUID, default: []].insert(entityUUID)
          standaloneHomes.remove(homeUUID)  // Home has children
        }
      } else {
        // Entity has no home owner
        unknownHomeEntities.insert(entityUUID)
      }
    }

    return (homeToEntities, standaloneHomes, unknownHomeEntities)
  }

  /// Returns the first Matter ID associated with the given UUID.
  ///
  /// - Parameter uuid: The UUID to look up (case-insensitive).
  /// - Returns: Matter ID string if found, nil otherwise.
  public func matterID(for uuid: String) -> String? {
    entity(for: uuid)?.matterIDs.first
  }

  /// Returns the entity for a given UUID.
  ///
  /// - Parameter uuid: The UUID to look up (case-insensitive).
  /// - Returns: The entity if found, nil otherwise.
  public func entity(for uuid: String) -> Entity? {
    uuidToEntity[uuid.lowercased()]
  }
}
