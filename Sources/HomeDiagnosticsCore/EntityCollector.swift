import Foundation

/// Trims whitespace from a name while preserving case.
private func trimName(_ name: String) -> String {
  name.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Normalizes a UUID for entity association (trims and lowercases).
private func normalizeUUID(_ uuid: String) -> String {
  uuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

public struct EntityCollector: Sendable {
  public private(set) var annotations: [EntityAnnotation]

  public init() {
    self.annotations = []
  }

  public mutating func add(_ annotation: EntityAnnotation) {
    annotations.append(annotation)
  }

  /// Add all annotations extracted from a LogEntry.
  ///
  /// Scans the message for multiple pattern types:
  /// - Path-based: [Home/Device/UUID] - extracts device names and home names
  /// - Action sets: kActionSetName and kActionSetUUID in structured data
  /// - Home lists: found homes [UUID1, UUID2, ...] - registers home spiIDs
  /// - HMDHome objects: <HMDHome, ID = ..., spiID = ..., NM = ...> - direct home info
  /// - Matter snapshots: new matter snapshot for 'UUID', updateType:home(Name)
  public mutating func add(entry: LogEntry) {
    let message = entry.message
    extractPaths(from: message)
    extractBracketedNames(from: message)
    extractActionSets(from: message)
    extractHomeLists(from: message)
    extractHMDHomeObjects(from: message)
    extractMatterSnapshots(from: message)
  }

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

  /// Returns whether a name likely represents a system context rather than a home.
  private func isSystemContextName(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasSpaces = trimmed.contains(" ")
    if hasSpaces {
      return false
    }
    let systemPrefixPattern = /^(HMD|HM|HMF)[A-Z]/
    return trimmed.contains(systemPrefixPattern)
  }

  private mutating func extractPaths(from message: String) {
    let pathPattern = /\[([^\/\]]+)\/([^\/\]]+)\/([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\]/
    for match in message.matches(of: pathPattern) {
      let homeName = trimName(String(match.1))
      let deviceName = trimName(String(match.2))
      let uuid = normalizeUUID(String(match.3))
      if isValidHumanReadableName(deviceName) {
        annotations.append(EntityAnnotation(kind: .name(uuid: uuid, name: deviceName, type: .device)))
      }
      // Create ownership by home name if the home name is valid
      if isValidHumanReadableName(homeName) && !isSystemContextName(homeName) {
        annotations.append(EntityAnnotation(kind: .ownerByName(childUUID: uuid, ownerName: homeName, ownerType: .home)))
      }
    }
  }

  /// Extracts name/UUID pairs from bracketed messages without a home prefix.
  private mutating func extractBracketedNames(from message: String) {
    let bracketPattern = /\[([^\/\]]+)\/([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\]/
    for match in message.matches(of: bracketPattern) {
      let name = trimName(String(match.1))
      let uuid = normalizeUUID(String(match.2))
      if isValidHumanReadableName(name) {
        annotations.append(EntityAnnotation(kind: .name(uuid: uuid, name: name, type: .unknown)))
      }
    }
  }

  private mutating func extractActionSets(from message: String) {
    if message.contains("Add action set finished") {
      let namePattern = /kActionSetName\s*=\s*"([^\"]+)"/
      let actionSetName = message.firstMatch(of: namePattern).map { trimName(String($0.1)) }
      let actionSetUUIDPattern = /kActionSetUUID\s*=\s*"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"/
      if let actionSetMatch = message.firstMatch(of: actionSetUUIDPattern) {
        let uuid = normalizeUUID(String(actionSetMatch.1))
        if let name = actionSetName, isValidHumanReadableName(name) {
          annotations.append(EntityAnnotation(kind: .name(uuid: uuid, name: name, type: .actionSet)))
        }
        let homeUUIDPattern = /kHomeUUID\s*=\s*"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"/
        if let homeMatch = message.firstMatch(of: homeUUIDPattern) {
          let homeUUID = normalizeUUID(String(homeMatch.1))
          annotations.append(EntityAnnotation(kind: .register(uuid: homeUUID, type: .home)))
          annotations.append(EntityAnnotation(kind: .owner(childUUID: uuid, ownerUUID: homeUUID)))
        }
      }
    }
  }

  private mutating func extractHomeLists(from message: String) {
    let foundHomesPattern = /found homes \[([^\]]+)\]/
    if let match = message.firstMatch(of: foundHomesPattern) {
      let uuidList = String(match.1)
      let uuidRegex = try? Regex<Substring>("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
      for uuid in uuidList.split(separator: ",") {
        let cleaned = normalizeUUID(uuid.trimmingCharacters(in: .whitespaces))
        if let uuidRegex, cleaned.wholeMatch(of: uuidRegex) != nil {
          // These are home spiIDs, but we can't annotate a name yet
          annotations.append(EntityAnnotation(kind: .register(uuid: cleaned, type: .home)))
        }
      }
    }
  }

  private mutating func extractHMDHomeObjects(from message: String) {
    let hmdHomePattern = /<HMDHome, ID = ([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}), spiID = ([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}), NM = ([^>]+)>/
    for match in message.matches(of: hmdHomePattern) {
      let internalID = normalizeUUID(String(match.1))
      let spiID = normalizeUUID(String(match.2))
      let name = trimName(String(match.3))
      if isValidHumanReadableName(name) {
        annotations.append(EntityAnnotation(kind: .name(uuid: internalID, name: name, type: .home)))
        annotations.append(EntityAnnotation(kind: .name(uuid: spiID, name: name, type: .home)))
        annotations.append(EntityAnnotation(kind: .spiID(uuid: internalID, spiID: spiID)))
      }
    }
  }

  private mutating func extractMatterSnapshots(from message: String) {
    let matterPattern = /new matter snapshot for '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})', updateType:home\(([^)]+)\)/
    for match in message.matches(of: matterPattern) {
      let uuid = normalizeUUID(String(match.1))
      let name = trimName(String(match.2))
      if isValidHumanReadableName(name) {
        annotations.append(EntityAnnotation(kind: .name(uuid: uuid, name: name, type: .home)))
      }
    }
  }
}
