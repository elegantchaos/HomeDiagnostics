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
