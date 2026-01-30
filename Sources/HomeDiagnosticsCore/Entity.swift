import Foundation

/// Represents a resolved entity with type, names, uuids, matter ids, and optional owner.
public final class Entity: @unchecked Sendable, Hashable {
  public var name: String { names.first ?? "" }
  public var type: NameType
  public var names: Set<String>
  public var uuids: Set<String>
  public var matterIDs: Set<String>
  public var spiIDs: Set<String>
  public weak var owner: Entity?


  public init(name: String, type: NameType, uuids: [String], spiIDs: [String] = []) {
    self.names = [name]
    self.type = type
    self.uuids = Set(uuids)
    self.matterIDs = []
    self.spiIDs = Set(spiIDs)
    self.owner = nil
  }

  public init(type: NameType) {
    self.names = []
    self.type = type
    self.uuids = []
    self.matterIDs = []
    self.spiIDs = []
    self.owner = nil
  }

  public static func == (lhs: Entity, rhs: Entity) -> Bool {
    lhs === rhs
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  /// Returns a new Entity with an additional UUID.
  public func adding(uuid: String) -> Entity {
    let copy = Entity(type: self.type)
    copy.names = self.names
    copy.uuids = self.uuids.union([uuid])
    copy.matterIDs = self.matterIDs
    copy.spiIDs = self.spiIDs
    copy.owner = self.owner
    return copy
  }

  /// Returns a new Entity merging UUIDs from another entity.
  public func merging(uuidsFrom other: Entity) -> Entity {
    let copy = Entity(type: self.type)
    copy.names = self.names.union(other.names)
    copy.uuids = self.uuids.union(other.uuids)
    copy.matterIDs = self.matterIDs.union(other.matterIDs)
    copy.spiIDs = self.spiIDs.union(other.spiIDs)
    copy.owner = self.owner ?? other.owner
    return copy
  }
}
