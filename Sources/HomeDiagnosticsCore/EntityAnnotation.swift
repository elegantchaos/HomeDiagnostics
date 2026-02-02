import Foundation

/// An annotation associating a name or uuid with a name, uuid, type, or owner.
public struct EntityAnnotation: Sendable, Hashable {
  public enum Kind: Sendable, Hashable {
    case name(uuid: String, name: String, type: NameType)
    case uuid(name: String, uuid: String, type: NameType)
    case matterID(uuid: String, matterID: String)
    case owner(childUUID: String, ownerUUID: String)
    case ownerByName(childUUID: String, ownerName: String, ownerType: NameType)
    case register(uuid: String, type: NameType)
    case spiID(uuid: String, spiID: String)
  }
  public let kind: Kind
}
