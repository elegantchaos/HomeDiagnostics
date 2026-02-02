import Foundation

/// Represents a resolved entity with a single name, type, UUIDs, Matter IDs, and optional owner.
///
/// Each entity has exactly one name. The uniqueness constraint is type-scoped: entities
/// of different types can share the same name (e.g., a device "Kitchen" and an action set "Kitchen").
public final class Entity: @unchecked Sendable, Hashable {
  /// The human-readable name for this entity.
  public var name: String

  /// The type of entity (home, device, action set, or unknown).
  public var type: NameType

  /// The set of UUIDs associated with this entity (case-insensitive).
  public var uuids: Set<String>

  /// The set of Matter protocol identifiers associated with this entity.
  public var matterIDs: Set<String>

  /// The set of server process identifiers associated with this entity (homes only).
  public var spiIDs: Set<String>

  /// The parent entity that owns this entity (e.g., device → home, scene → home).
  public weak var owner: Entity?

  /// Creates an entity with a name, type, UUIDs, and optional SPI IDs.
  ///
  /// - Parameters:
  ///   - name: The human-readable name for the entity.
  ///   - type: The entity type.
  ///   - uuids: Array of UUID strings to associate with the entity.
  ///   - spiIDs: Array of server process ID strings (for homes).
  public init(name: String, type: NameType, uuids: [String], spiIDs: [String] = []) {
    self.name = name
    self.type = type
    self.uuids = Set(uuids)
    self.matterIDs = []
    self.spiIDs = Set(spiIDs)
    self.owner = nil
  }

  /// Creates an entity with a type but no name or identifiers.
  ///
  /// - Parameter type: The entity type.
  public init(type: NameType) {
    self.name = ""
    self.type = type
    self.uuids = []
    self.matterIDs = []
    self.spiIDs = []
    self.owner = nil
  }

  /// Checks equality based on object identity.
  ///
  /// - Parameters:
  ///   - lhs: The left-hand side entity.
  ///   - rhs: The right-hand side entity.
  /// - Returns: Whether the entities are the same object.
  public static func == (lhs: Entity, rhs: Entity) -> Bool {
    lhs === rhs
  }

  /// Hashes the entity based on object identity.
  ///
  /// - Parameter hasher: The hasher to use.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  /// Returns a new entity with an additional UUID added.
  ///
  /// - Parameter uuid: The UUID to add.
  /// - Returns: A new entity with the UUID added to the UUIDs set.
  public func adding(uuid: String) -> Entity {
    let copy = Entity(type: self.type)
    copy.name = self.name
    copy.uuids = self.uuids.union([uuid])
    copy.matterIDs = self.matterIDs
    copy.spiIDs = self.spiIDs
    copy.owner = self.owner
    return copy
  }

  /// Returns a new entity merging UUIDs and identifiers from another entity.
  ///
  /// The name is preserved from the current entity (first-encountered wins).
  ///
  /// - Parameter other: The other entity to merge from.
  /// - Returns: A new entity with merged UUIDs, Matter IDs, and SPI IDs.
  public func merging(uuidsFrom other: Entity) -> Entity {
    let copy = Entity(type: self.type)
    copy.name = self.name  // Keep first-encountered name
    copy.uuids = self.uuids.union(other.uuids)
    copy.matterIDs = self.matterIDs.union(other.matterIDs)
    copy.spiIDs = self.spiIDs.union(other.spiIDs)
    copy.owner = self.owner ?? other.owner
    return copy
  }
}
