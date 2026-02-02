import Foundation
import OSLog

#if canImport(HomeKit)
  import HomeKit
#endif

#if canImport(HomeKit)

  /// Logger for HomeKit API collection operations.
  let homekitLogger = Logger(
    subsystem: "com.elegantchaos.HomeDiagnostics", category: "HomeKitAPICollector")

  /// Collects HomeKit entity information using the HomeKit framework API.
  ///
  /// Queries `HMHomeManager` to enumerate all configured homes, accessories (devices),
  /// action sets (scenes), rooms, and zones. Converts HomeKit objects to entity annotations
  /// that can be merged with pattern-scanned entities.
  ///
  /// Requires HomeKit entitlements and user authorization. Returns empty annotations
  /// if HomeKit is unavailable or authorization is denied.
  @MainActor
  public final class HomeKitAPICollector: NSObject, HMHomeManagerDelegate {
    /// The HomeKit home manager for querying HomeKit configuration.
    private let homeManager = HMHomeManager()

    /// Continuation for waiting on homes to load asynchronously.
    private var continuation: CheckedContinuation<Void, Never>?

    /// Creates a new HomeKit API collector.
    public override init() {
      super.init()
    }

    /// Collects entity annotations from the HomeKit framework.
    ///
    /// Waits for HomeKit homes to load, then enumerates all homes, accessories,
    /// action sets, rooms, and zones. Creates entity annotations with names, UUIDs,
    /// types, and owner relationships.
    ///
    /// Performance is logged for monitoring collection time and entity count.
    ///
    /// - Returns: Array of entity annotations from HomeKit API.
    /// - Throws: Only if an unexpected error occurs (currently returns empty on failure).
    public func collect() async throws -> [EntityAnnotation] {
      let startTime = Date()
      homekitLogger.debug("HomeKit collection started at \(startTime.ISO8601Format())")

      // Set delegate and wait for homes to load
      homeManager.delegate = self
      await waitForHomesLoaded()

      var annotations: [EntityAnnotation] = []

      // Enumerate all homes
      for home in homeManager.homes {
        let homeUUID = home.uniqueIdentifier.uuidString
        let homeName = home.name

        // Add home entity
        annotations.append(
          EntityAnnotation(
            kind: .name(uuid: homeUUID, name: homeName, type: .home)
          ))

        // Enumerate accessories (devices)
        for accessory in home.accessories {
          let accessoryUUID = accessory.uniqueIdentifier.uuidString
          let accessoryName = accessory.name

          // Add accessory entity
          annotations.append(
            EntityAnnotation(
              kind: .name(uuid: accessoryUUID, name: accessoryName, type: .device)
            ))

          // Link accessory to home
          annotations.append(
            EntityAnnotation(
              kind: .owner(childUUID: accessoryUUID, ownerUUID: homeUUID)
            ))
        }

        // Enumerate action sets (scenes)
        for actionSet in home.actionSets {
          let actionSetUUID = actionSet.uniqueIdentifier.uuidString
          let actionSetName = actionSet.name

          // Add action set entity
          annotations.append(
            EntityAnnotation(
              kind: .name(uuid: actionSetUUID, name: actionSetName, type: .actionSet)
            ))

          // Link action set to home
          annotations.append(
            EntityAnnotation(
              kind: .owner(childUUID: actionSetUUID, ownerUUID: homeUUID)
            ))
        }

        // Enumerate rooms (optional, treated as devices for now)
        for room in home.rooms {
          let roomUUID = room.uniqueIdentifier.uuidString
          let roomName = room.name

          // Add room entity as device type
          annotations.append(
            EntityAnnotation(
              kind: .name(uuid: roomUUID, name: roomName, type: .device)
            ))

          // Link room to home
          annotations.append(
            EntityAnnotation(
              kind: .owner(childUUID: roomUUID, ownerUUID: homeUUID)
            ))
        }

        // Enumerate zones (optional, treated as devices for now)
        for zone in home.zones {
          let zoneUUID = zone.uniqueIdentifier.uuidString
          let zoneName = zone.name

          // Add zone entity as device type
          annotations.append(
            EntityAnnotation(
              kind: .name(uuid: zoneUUID, name: zoneName, type: .device)
            ))

          // Link zone to home
          annotations.append(
            EntityAnnotation(
              kind: .owner(childUUID: zoneUUID, ownerUUID: homeUUID)
            ))
        }
      }

      let duration = Date().timeIntervalSince(startTime)
      homekitLogger.debug(
        "HomeKit collection completed in \(String(format: "%.2f", duration))s, found \(annotations.count) annotations from \(self.homeManager.homes.count) home(s)"
      )

      return annotations
    }

    /// Waits for the HomeKit home manager to load homes.
    ///
    /// Creates a continuation that is resumed when the delegate callback fires.
    private func waitForHomesLoaded() async {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        // If homes are already loaded, resume immediately
        if homeManager.homes.isEmpty == false {
          continuation.resume()
          self.continuation = nil
        }
      }
    }

    // MARK: - HMHomeManagerDelegate

    /// Called when the home manager updates its list of homes.
    ///
    /// Resumes the waiting continuation to signal that homes are loaded.
    ///
    /// - Parameter manager: The home manager that updated.
    public nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
      Task { @MainActor in
        continuation?.resume()
        continuation = nil
      }
    }
  }

#endif
