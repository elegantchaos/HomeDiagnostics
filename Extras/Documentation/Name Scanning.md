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
# Pattern scanning only (no permissions required)
home-diagnostics --entity-source patterns

# HomeKit API only (requires authorization)
home-diagnostics --entity-source api

# Both approaches (maximum coverage)
home-diagnostics --entity-source both
```

**Default Behavior**: `both` when HomeKit is available; otherwise it falls back to `patterns`.

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

## Current Status

- Pattern-based scanning is implemented and used by default.
- Optional HomeKit API enrichment is implemented behind `--entity-source api|both`.
- Default behavior is `both` when HomeKit is available; otherwise it falls back to `patterns`.
- Entity naming uses type-scoped uniqueness (devices and scenes can share names).
- UUID substitution is enabled unless `--no-names` is set.

## Future Enhancements

Potential improvements for future consideration:

- **Incremental HomeKit updates** - Use delegate callbacks to update entities without full re-query
- **Entity caching** - Cache HomeKit entities to avoid repeated authorization prompts
- **Room/Zone association** - Display device room assignments in UUID summary
- **Service enumeration** - Show device services and characteristics
- **Historical entity tracking** - Maintain database of entities seen over time
- **Confidence scoring** - Rank entity matches by data source reliability
- **Custom patterns** - User-configurable regex patterns for specialized log formats
