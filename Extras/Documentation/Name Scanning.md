# Name Scanning

This document describes the entity discovery and naming system in HomeDiagnostics, which identifies HomeKit devices, homes, and action sets (scenes) and associates them with their UUIDs for improved log readability.

## Overview

HomeDiagnostics provides two complementary approaches to discovering HomeKit entities:

1. **Pattern Scanning** - Extracts entity information from log message patterns (default)
2. **HomeKit API** - Queries the HomeKit framework directly for authoritative entity data

Both approaches can be used simultaneously to maximize entity coverage: pattern scanning discovers entities mentioned in logs (including historical entities and Matter IDs), while the HomeKit API provides complete, current entity data with guaranteed accuracy.

## Entity Model

### Entity Structure

Each entity represents a HomeKit object (home, device, or action set) and contains:

- **name** - Single human-readable name (e.g., "Living Room Camera")
- **type** - Entity type: `.home`, `.device`, `.actionSet`, or `.unknown`
- **uuids** - Set of associated UUIDs (case-insensitive)
- **matterIDs** - Set of Matter protocol identifiers
- **spiIDs** - Set of server process identifiers (for homes)
- **owner** - Parent entity reference (e.g., device → home)

### Type-Based Name Uniqueness

Each entity has exactly one name. The naming constraint is **type-scoped**, meaning:

- ✅ A device named "Kitchen" and an action set named "Kitchen" can coexist as separate entities
- ❌ Two devices named "Kitchen" with different UUIDs is a conflict (logs warning, keeps first)
- ✅ The same UUID can have multiple entity types (e.g., a home that's also referenced as a device in logs)

This design balances simplicity with real-world HomeKit naming patterns where users often name scenes after rooms.

### Conflict Resolution

When the same UUID appears with different names:

- **Strategy**: Keep first-encountered name
- **Rationale**: Predictable, deterministic behavior
- **Logging**: Warning logged for visibility into data quality issues

Example scenario:
```
Log entry 1: [Home/Living Room Camera/UUID-123]
Log entry 2: [Home/Garage Camera/UUID-123]
```
Result: Entity keeps "Living Room Camera", warning logged about name conflict.

## Pattern Scanning Approach

### EntityCollector

The `EntityCollector` class scans log messages using regex patterns to extract entity information. This passive discovery approach finds entities mentioned in logs without requiring HomeKit framework access.

### Extraction Patterns

**1. Path-Based Patterns**
```
[HomeName/DeviceName/UUID]
[HomeName/SceneName/UUID]
```
Extracts hierarchical entity relationships from structured log paths.

**2. Action Set Patterns**
```
kActionSetName = SceneName
kActionSetUUID = UUID
kHomeUUID = UUID
```
Parses structured action set data, establishing scene-to-home ownership.

**3. Home List Patterns**
```
found homes [UUID1, UUID2, UUID3]
```
Discovers home UUIDs from enumeration messages.

**4. HMDHome Object Patterns**
```
<HMDHome, ID = UUID, spiID = SPI-UUID, NM = HomeName>
```
Extracts both internal and server process IDs along with home names.

**5. Matter Snapshot Patterns**
```
new matter snapshot for 'UUID', updateType:home(HomeName)
new matter snapshot for 'UUID', updateType:device
```
Links Matter protocol identifiers to entities and extracts home names.

### Name Validation

To prevent false positives, extracted names are validated:

- ❌ Reject pure UUIDs
- ❌ Reject hexadecimal strings (likely identifiers)
- ❌ Reject pure numbers
- ❌ Reject very short strings (< 3 chars)
- ✅ Accept natural language names

### Advantages

- **No permissions required** - Works without HomeKit entitlements
- **Historical data** - Discovers entities from logs even if no longer in HomeKit
- **Matter IDs** - Captures Matter protocol identifiers not exposed by HomeKit API
- **Passive** - No impact on HomeKit system performance

### Limitations

- **Incomplete coverage** - Only finds entities mentioned in logs
- **No validation** - Cannot verify entity still exists or data is current
- **Pattern-dependent** - Relies on log message formats (may break with OS updates)

## HomeKit API Approach

### HomeKitAPICollector

The `HomeKitAPICollector` class queries the HomeKit framework using `HMHomeManager` to enumerate all configured HomeKit entities. This active discovery approach provides authoritative, complete entity data.

### Discovery Process

**1. Initialize HMHomeManager**
```swift
let homeManager = HMHomeManager()
```
Requires main actor isolation and delegate pattern.

**2. Wait for Homes Loaded**
```swift
func homeManagerDidUpdateHomes(_ manager: HMHomeManager)
```
Asynchronous callback when HomeKit data is available.

**3. Enumerate Entities**

For each home in `homeManager.homes`:
- Extract home name and UUID
- Enumerate `home.accessories` (devices)
  - Extract accessory name, UUID, and home ownership
- Enumerate `home.actionSets` (scenes)
  - Extract action set name, UUID, and home ownership
- Enumerate `home.rooms` (optional)
  - Extract room name and UUID
- Enumerate `home.zones` (optional)
  - Extract zone name and UUID

**4. Create Annotations**

Convert HomeKit objects to `EntityAnnotation` instances:
```swift
.name(uuid: home.uniqueIdentifier.uuidString, name: home.name, type: .home)
.name(uuid: accessory.uniqueIdentifier.uuidString, name: accessory.name, type: .device)
.owner(childUUID: accessory.uniqueIdentifier.uuidString, ownerUUID: home.uniqueIdentifier.uuidString)
```

### Performance Logging

All HomeKit API operations are instrumented with debug logging:

```swift
logger.debug("HomeKit collection started at \(Date())")
// ... collection logic ...
logger.debug("HomeKit collection completed in \(duration)s, found \(annotations.count) entities")
```

This allows monitoring of:
- Collection start/end timestamps
- Total duration
- Entity count discovered
- Authorization failures

### Authorization Handling

HomeKit requires user authorization and appropriate entitlements:

**Required Entitlements**
```xml
<key>com.apple.developer.homekit</key>
<true/>
```

**Privacy Usage Description** (Info.plist)
```xml
<key>NSHomeKitUsageDescription</key>
<string>HomeDiagnostics needs access to your HomeKit configuration to provide readable device names in log analysis.</string>
```

**Error Handling**

If HomeKit is unavailable or authorization denied:
- Return empty annotation array (graceful degradation)
- Log error details for troubleshooting
- Fall back to pattern scanning if enabled

### Advantages

- **Complete coverage** - Discovers all configured entities
- **Authoritative data** - Direct from HomeKit framework
- **Guaranteed accuracy** - Names and UUIDs are current
- **Rich metadata** - Access to rooms, zones, services

### Limitations

- **Permissions required** - Needs HomeKit entitlements and user authorization
- **Current state only** - Cannot discover historical entities
- **No Matter IDs** - HomeKit API doesn't expose Matter identifiers
- **Platform constraints** - Command-line tools may have restricted access

## Hybrid Approach (Recommended)

Using both approaches simultaneously provides maximum coverage:

1. **HomeKit API** provides authoritative current entity data
2. **Pattern Scanning** supplements with historical entities and Matter IDs
3. **EntityResolver** merges annotations from both sources

### Merge Strategy

The `EntityResolver` receives annotations from both sources and merges them:

```swift
let allAnnotations = homekitAnnotations + patternScanAnnotations
let resolver = EntityResolver(annotations: allAnnotations)
```

During initialization, `EntityResolver`:
- Creates or updates entities for each annotation
- Merges entities with shared UUIDs
- Maintains first-encountered name for conflicts
- Establishes owner relationships
- Logs warnings for naming conflicts

### Command-Line Control

The `--entity-source` option controls which approach(es) to use:

```bash
# Pattern scanning only (default, no permissions required)
homediagnostics --entity-source patterns

# HomeKit API only (requires authorization)
homediagnostics --entity-source api

# Both approaches (maximum coverage)
homediagnostics --entity-source both
```

**Default Behavior**: `patterns` (no authorization required)

## UUID Substitution

Once entities are resolved, the `EntityResolver.substitute(in:)` method replaces UUIDs in log messages with readable names:

**Before:**
```
Device 4A8856A0-38E3-5AF4-AC52-8390FFE944A2 failed to respond
```

**After:**
```
Device Garage Camera-4A8856A0 failed to respond
```

Format: `{name}-{uuid-prefix}` provides both human readability and unambiguous identification.

## UUID Naming Summary Output

The output formatter includes an optional "UUID NAMING SUMMARY" section showing all discovered entities organized by home:

```
UUID NAMING SUMMARY
===================

Discovered 45 entities.
Discovered 42 named UUID(s):

Bank Street (ID: 1A2B3C4D...)
  [Device] 4A8856A0... → Garage Camera
  [Device] 9FEA624C... → Front Door Lock
  [Scene] B8C3E217... → Good Morning

Plantation Road (ID: 5E6F7G8H...)
  [Device] 3D4E5F6A... → Living Room Light
  
Unknown Home
  [Device] 7H8I9J0K... → Orphaned Device
```

This section is only displayed when `--no-names` flag is not used.

---

## Implementation Plan

This section provides a detailed roadmap for implementing the hybrid entity discovery system.

### Phase 1: Entity Model Refactoring

**Goal**: Simplify Entity from multi-name to single-name with type-based uniqueness.

#### Step 1.1: Update Entity.swift

- [ ] Change `names: Set<String>` to `name: String` stored property
- [ ] Remove computed `name` property (now redundant)
- [ ] Update `init(name:type:)` to set `self.name = name`
- [ ] Update empty `init()` to set `self.name = ""`
- [ ] Update `adding(uuid:)` method to preserve single name
- [ ] Update `merging(uuidsFrom:)` to keep first name (don't merge names)
- [ ] Update all doc comments to reflect single name
- [ ] Update `Equatable` conformance if needed

**Files**: `Sources/HomeDiagnosticsCore/Entity.swift`

#### Step 1.2: Update EntityResolver.swift - Part 1 (Single Name)

- [ ] Add `Logger` at file scope: `Logger(subsystem: "com.elegantchaos.HomeDiagnostics", category: "EntityResolver")`
- [ ] In `init(annotations:)` handling `.name` and `.uuid` cases:
  - When entity already exists with different name, log warning but keep first name
  - Change `entity.names.insert(name)` to conditional check and warning
- [ ] Update `resolve()` method:
  - Change `existing.names.formUnion(entity.names)` to keep existing.name
  - Log warning if merging entities with different names
- [ ] Update `displayName(for:)` method:
  - Use `entity.name` directly (not `.names.sorted()`)
  - Remove slash-joining logic for multiple names
  - Simplify to: `"\(entity.name)-\(prefix)"`

**Files**: `Sources/HomeDiagnosticsCore/EntityResolver.swift`

### Phase 2: Type-Based Name Uniqueness

**Goal**: Allow same name across different entity types (e.g., device "Kitchen" and scene "Kitchen").

#### Step 2.1: Update EntityResolver.swift - Part 2 (Type Scoping)

- [ ] Change `nameToEntity` dictionary from `[String: Entity]` to `[String: Entity]`
- [ ] Create helper method `nameKey(name:type:) -> String` returning `"\(type.rawValue):\(name)"`
- [ ] Update all `nameToEntity` accesses to use `nameKey(name:type:)`
- [ ] Update name-based lookups in annotation processing
- [ ] Update `entity(for uuid:)` and `entity(named:)` methods if they exist

**Files**: `Sources/HomeDiagnosticsCore/EntityResolver.swift`

### Phase 3: HomeKit API Integration

**Goal**: Add HomeKit framework support with async entity collection.

#### Step 3.1: Add HomeKit Framework Dependency

- [ ] Open `Package.swift`
- [ ] Add `.framework("HomeKit")` to `HomeDiagnosticsCore` target `linkerSettings`
- [ ] Add platform condition: `.when(platforms: [.macOS, .iOS])`

**Files**: `Package.swift`

#### Step 3.2: Create HomeKitAPICollector.swift

- [ ] Create `@MainActor final class HomeKitAPICollector`
- [ ] Conform to `HMHomeManagerDelegate`
- [ ] Add `Logger` at file scope for performance logging
- [ ] Add private properties:
  - `private let homeManager = HMHomeManager()`
  - `private var continuation: CheckedContinuation<Void, Never>?`
- [ ] Implement `collect() async throws -> [EntityAnnotation]`:
  - Log start timestamp
  - Create continuation to wait for homes loaded
  - Set `homeManager.delegate = self`
  - Wait for `homeManagerDidUpdateHomes` callback
  - Enumerate all homes, accessories, action sets
  - Create `.name` and `.owner` annotations
  - Log completion with duration and count
  - Return annotations array
- [ ] Implement `homeManagerDidUpdateHomes(_ manager:)`:
  - Resume continuation to signal homes loaded
- [ ] Handle authorization errors gracefully (return empty array)
- [ ] Add doc comments for all members

**Files**: `Sources/HomeDiagnosticsCore/HomeKitAPICollector.swift`

#### Step 3.3: Update LogAnalyzer.swift

- [ ] Add `additionalAnnotations: [EntityAnnotation] = []` parameter to `analyzeStream()` method
- [ ] Prepend additional annotations to merged pattern-scanned annotations:
  - Change: `let allAnnotations = allCollectors.flatMap { $0.annotations }`
  - To: `let allAnnotations = additionalAnnotations + allCollectors.flatMap { $0.annotations }`
- [ ] Update doc comment to document new parameter

**Files**: `Sources/HomeDiagnosticsCore/LogAnalyzer.swift`

### Phase 4: CLI Integration

**Goal**: Add command-line options to control entity discovery sources.

#### Step 4.1: Add EntitySource Enum to HomeDiagnostics.swift

- [ ] Add enum before `HomeDiagnostics` struct:
```swift
/// Entity discovery method selection.
enum EntitySource: String, ExpressibleByArgument {
  /// Use pattern scanning of log messages (default).
  case patterns
  
  /// Use HomeKit API queries.
  case api
  
  /// Use both pattern scanning and HomeKit API.
  case both
}
```

**Files**: `Sources/HomeDiagnostics/HomeDiagnostics.swift`

#### Step 4.2: Add CLI Option to HomeDiagnostics.swift

- [ ] Add `@Option` property to `HomeDiagnostics` struct:
```swift
@Option(name: .long, help: "Entity discovery method: patterns (default), api, or both")
var entitySource: EntitySource = .patterns
```
- [ ] Place after `--no-names` flag for logical grouping

**Files**: `Sources/HomeDiagnostics/HomeDiagnostics.swift`

#### Step 4.3: Update Run Logic in HomeDiagnostics.swift

- [ ] In `run()` method, before creating `LogAnalyzer`:
  - Add conditional HomeKit collection:
```swift
var additionalAnnotations: [EntityAnnotation] = []
if entitySource == .api || entitySource == .both {
  do {
    let collector = HomeKitAPICollector()
    additionalAnnotations = try await collector.collect()
  } catch {
    logger.error("HomeKit collection failed: \(error)")
  }
}
```
- [ ] Pass annotations to analyzer:
  - Change: `let analysis = try await analyzer.analyzeStream()`
  - To: `let analysis = try await analyzer.analyzeStream(additionalAnnotations: additionalAnnotations)`

**Files**: `Sources/HomeDiagnostics/HomeDiagnostics.swift`

### Phase 5: OutputFormatter Completion

**Goal**: Implement missing EntityResolver methods needed by OutputFormatter.

#### Step 5.1: Add Helper Methods to EntityResolver.swift

- [ ] Add `namedUUIDs` computed property:
```swift
/// All entities that have both a name and at least one UUID.
public var namedUUIDs: Set<Entity> {
  allEntities.filter { !$0.name.isEmpty && !$0.uuids.isEmpty }
}
```

- [ ] Add `entitiesByHome()` method:
```swift
/// Organizes entities by their home ownership.
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
  // Implementation here
}
```

- [ ] Add `matterID(for:)` method:
```swift
/// Returns the first Matter ID associated with the given UUID.
///
/// - Parameter uuid: The UUID to look up.
/// - Returns: Matter ID string if found, nil otherwise.
public func matterID(for uuid: String) -> String? {
  entity(for: uuid)?.matterIDs.first
}
```

**Files**: `Sources/HomeDiagnosticsCore/EntityResolver.swift`

#### Step 5.2: Fix OutputFormatter.swift

- [ ] In `format()` method, uncomment and fix UUID summary section:
```swift
if substituteNames {
  output += formatUUIDSummary(resolver: analysis.uuidNameResolver)
}
```
- [ ] In `formatUUIDSummary(resolver:)` method:
  - Remove duplicate line with `uuidNamer`
  - Use `resolver.namedUUIDs` instead of `resolver.namedUUIDs.count`
  - Use `resolver.entitiesByHome()` correctly
  - Remove all references to `uuidNamer` variable
  - Use `entity.name` instead of `entity.names.sorted()`
  - Use `resolver.matterID(for:)` correctly

**Files**: `Sources/HomeDiagnosticsCore/OutputFormatter.swift`

### Phase 6: Testing Updates

**Goal**: Update tests to reflect single-name behavior and add new test coverage.

#### Step 6.1: Update AnalysisTests.swift

- [ ] Find test expecting `"Bedroom/Living Room-4A8856A0"`
- [ ] Update expectation to first-seen name only (e.g., `"Living Room-4A8856A0"`)
- [ ] Add test for name conflict warning logging

**Files**: `Tests/HomeDiagnosticsTests/AnalysisTests.swift`

#### Step 6.2: Update UUIDNamerTests.swift

- [ ] Remove or update tests validating slash-separated multi-name output
- [ ] Update tests to expect single name only
- [ ] Add test verifying warnings logged for conflicting names

**Files**: `Tests/HomeDiagnosticsTests/UUIDNamerTests.swift`

#### Step 6.3: Add Type-Based Uniqueness Tests

- [ ] Add test creating device "Kitchen" and actionSet "Kitchen"
- [ ] Verify both entities coexist with different UUIDs
- [ ] Add test creating two devices named "Kitchen" with different UUIDs
- [ ] Verify second device keeps first UUID's name, warning logged

**Files**: `Tests/HomeDiagnosticsTests/` (new or existing test file)

### Phase 7: Validation and Documentation

**Goal**: Ensure all changes work together correctly.

#### Step 7.1: Build and Test

- [ ] Run `swift build --target HomeDiagnosticsCore` to verify package builds
- [ ] Run `swift test` to execute all unit tests
- [ ] Fix any compilation errors or test failures
- [ ] Verify pattern scanning still works (`--entity-source patterns`)
- [ ] Test HomeKit API if permissions available (`--entity-source api`)
- [ ] Test hybrid mode (`--entity-source both`)

#### Step 7.2: Update README.md

- [ ] Add note about `--entity-source` option
- [ ] Link to Name Scanning.md for details
- [ ] Document HomeKit entitlement requirements if needed

**Files**: `README.md`

---

## Future Enhancements

Potential improvements for future consideration:

- **Incremental HomeKit updates** - Use delegate callbacks to update entities without full re-query
- **Entity caching** - Cache HomeKit entities to avoid repeated authorization prompts
- **Room/Zone association** - Display device room assignments in UUID summary
- **Service enumeration** - Show device services and characteristics
- **Historical entity tracking** - Maintain database of entities seen over time
- **Confidence scoring** - Rank entity matches by data source reliability
- **Custom patterns** - User-configurable regex patterns for specialized log formats
