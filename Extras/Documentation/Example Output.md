# HomeDiagnostics - Example Output

This document shows example outputs from various HomeDiagnostics commands to help you understand what to expect.

## Example 1: Diagnosing Hue Errors

**Command:**
```bash
home-diagnostics --days 7 --hue-only --errors-only --dedupe
```

**Purpose:** Find unique Hue-related errors from the last week.

**Example Output:**
```
SUMMARY
=======

Total log entries: 3
Errors: 3
Faults: 0
Warnings: 0
Hue-related: 3
Potentially problematic: 3
Unique entry types: 3

Entries by subsystem:
  com.apple.HomeKit: 3


ALL ENTRIES
===========

Showing 3 unique entry types (out of 3 total)

[1x] [01/29 09:02] [Error] [com.apple.HomeKit]
[Bank Street/Hue color lamp/...] Active transition count value: (null) is not of type NSNumber

[1x] [01/29 09:02] [Error] [com.apple.HomeKit]
[Bank Street/Hue color lamp/...] Supported Value Transition Configuration Characteristic value: (null) is not of expected type NSData

[1x] [01/29 09:02] [Error] [com.apple.HomeKit]
[Bank Street/Hue color lamp/...] Value Transition Control Characteristic value is not of type data: (null)
```

**What it shows:**
- 3 unique errors found
- All related to a Hue color lamp
- All occurred at the same time (09:02)
- All involve HomeKit characteristics returning null values
- No PROBLEMATIC ENTRIES section (would be identical to ALL ENTRIES with `--errors-only`)

**Interpretation:**
These errors indicate the Hue lamp is not properly reporting HomeKit characteristics, likely due to:
- Bridge connectivity issues
- Firmware problems
- HomeKit integration errors

---

## Example 2: Quick Summary

**Command:**
```bash
home-diagnostics --hours 1 --summary
```

**Purpose:** Get quick statistics for recent activity.

**Example Output:**
```
SUMMARY
=======

Total log entries: 1555
Errors: 3
Faults: 0
Warnings: 0
Hue-related: 39
Potentially problematic: 202

Entries by subsystem:
  com.apple.HomeKit: 847
  com.apple.Home: 708


PROBLEMATIC ENTRIES
===================

[01/29 15:00] [Info] [com.apple.Home]
refresh(homeManager:timeout:) starting refresh

[01/29 15:00] [Info] [com.apple.Home]
refresh(homeManager:timeout:) finished successfully

... (multiple entries showing Home app refresh cycles)

[01/29 15:00] [Info] [com.apple.Home]
monitorActionSetsAndUpdateEntitiesWithCachedValues(...) Failed action sets: <private>

[01/29 15:00] [Error] [com.apple.Home]
monitorAttributesAndUpdateEntities(...) No matching HMHome found in entities
```

**What it shows:**
- High activity (1555 entries in 1 hour)
- 202 "problematic" entries (includes "failed" keyword matches)
- Most activity from HomeKit framework
- Regular refresh cycles
- One actual error about missing HMHome

**Interpretation:**
- System is actively syncing
- One configuration error present
- Most "problematic" entries are routine operational messages containing "failed" in context (not actual failures)

---

## Example 3: Deduplication Shows Patterns

**Command:**
```bash
home-diagnostics --days 30 --dedupe --hue-only
```

**Purpose:** Identify recurring patterns over a month.

**Example Output:**
```
SUMMARY
=======

Total log entries: 25,234
Errors: 12
Faults: 0
Warnings: 0
Hue-related: 25,234
Potentially problematic: 47
Unique entry types: 156

Entries by subsystem:
  com.apple.Home: 24,891
  com.apple.HomeKit: 343


PROBLEMATIC ENTRIES
===================

Showing 8 unique problematic entry types (out of 47 total)

[12x] [01/02 14:23 - 01/28 09:15] [Error] [com.apple.HomeKit]
[Bank Street/Hue color lamp/...] Value Transition Control Characteristic value is not of type data: (null)

[8x] [01/05 08:30 - 01/29 12:45] [Info] [com.apple.Home]
Timeout waiting for Hue bridge response

[15x] [01/01 10:00 - 01/29 18:22] [Info] [com.apple.HomeKit]
Failed to connect to accessory [Hue white lamp]

[4x] [01/10 15:30 - 01/25 09:12] [Error] [com.apple.HomeKit]
Bridge connection unreachable: timeout after 10s


ALL ENTRIES
===========

Showing 156 unique entry types (out of 25,234 total)

[24,891x] [01/01 00:05 - 01/29 23:58] [Info] [com.apple.Home]
widgetTileInfos(from:uuids:...) for accessory <private>

... (additional entries)
```

**What it shows:**
- 25k+ entries collapsed into 156 unique types
- Error patterns repeating over the month
- Date ranges show when issues first/last occurred
- Occurrence counts show frequency

**Interpretation:**
- Recurring null characteristic error (12 times over 26 days = intermittent)
- Bridge timeout issues (8 times = network/bridge issue)
- Connection failures (15 times = reliability problem)
- These patterns suggest bridge or network instability

---

## Example 4: Raw Output for Piping

**Command:**
```bash
home-diagnostics --days 7 --raw | grep -i "bridge" | head -5
```

**Purpose:** Export raw logs for custom processing with Unix tools.

**Example Output:**
```
2026-01-23 08:15:42.123456+0000 Home[1234] [com.apple.Home] Connecting to Hue bridge at 192.168.1.100
2026-01-23 08:15:43.234567+0000 homed[5678] [com.apple.homed] Bridge responded: firmware 1.54.0
2026-01-24 14:22:15.345678+0000 Home[1234] [com.apple.Home] Bridge connection timeout
2026-01-25 09:30:22.456789+0000 HomeKit[9012] [com.apple.HomeKit] Bridge pairing verified
2026-01-26 16:45:33.567890+0000 Home[1234] [com.apple.Home] Lost connection to bridge
```

**What it shows:**
- Standard syslog format
- No parsing or analysis
- All metadata preserved
- Ready for external tools

**Use cases:**
- Custom analysis scripts
- Long-term log archival
- Integration with log aggregators
- Searching with grep/awk/sed

---

## Example 5: Errors Only (No Deduplication)

**Command:**
```bash
home-diagnostics --days 1 --errors-only
```

**Purpose:** See all errors chronologically without grouping.

**Example Output:**
```
SUMMARY
=======

Total log entries: 8
Errors: 6
Faults: 2
Warnings: 0
Hue-related: 3
Potentially problematic: 8

Entries by subsystem:
  com.apple.HomeKit: 5
  com.apple.Home: 3


ALL ENTRIES
===========

[01/29 08:15] [Error] [com.apple.HomeKit]
Connection timeout to accessory [Living Room Lamp]

[01/29 09:02] [Error] [com.apple.HomeKit]
[Hue color lamp/...] Value Transition Control Characteristic value is not of type data: (null)

[01/29 12:45] [Fault] [com.apple.homed]
Critical: Home database corruption detected

[01/29 14:20] [Error] [com.apple.Home]
Failed to sync with iCloud: network unavailable

[01/29 15:30] [Error] [com.apple.HomeKit]
Accessory [Bedroom Light] not responding

[01/29 16:10] [Fault] [com.apple.Home]
Unable to initialize HomeManager: database locked

[01/29 18:45] [Error] [com.apple.HomeKit]
Authentication failed for [Office Light]

[01/29 20:30] [Error] [com.apple.Home]
Scene activation timeout: Evening Scene
```

**What it shows:**
- Chronological error list
- Mix of error types and severity
- Each occurrence shown separately
- Timestamps show error distribution throughout day

**Interpretation:**
- Database issues (corruption, locked) are serious (Faults)
- Multiple accessory communication failures
- Network/iCloud sync problems
- Patterns suggest systemic issues beyond individual devices

---

## Color Coding Reference

When viewing output in a terminal, you'll see:

- **Red, bold text**: Errors and Faults (requires attention)
- **Yellow, bold text**: Warnings (potential issues)
- **Gray/dimmed text**: Metadata (timestamps, subsystems, log levels)
- **Normal text**: Info and Debug messages

Example visualization:
```
[gray metadata] [01/29 14:30] [Error] [com.apple.HomeKit] [/gray]
[red bold] Connection timeout to accessory [Living Room] [/red bold]
```

---

## Understanding Occurrence Counts

When using `--dedupe`, occurrence counts appear as `[Nx]`:

```
[1x]      - Happened once (unique incident)
[5x]      - Happened 5 times (occasional)
[50x]     - Happened 50 times (frequent)
[1000x]   - Happened 1000 times (very common)
```

**Time ranges** show when the pattern started and ended:
```
[12x] [01/02 14:23 - 01/28 09:15]  - 12 occurrences over 26 days (intermittent)
[50x] [01/29 08:00 - 01/29 09:00]  - 50 occurrences in 1 hour (rapid)
[1x]  [01/29 12:00]                - Single occurrence
```

---

## Practical Workflow Examples

### Workflow 1: Investigating Device Non-Responsiveness

```bash
# Step 1: Check for recent errors
home-diagnostics --hours 6 --errors-only --summary

# Step 2: Focus on affected device type
home-diagnostics --days 7 --hue-only --errors-only --dedupe

# Step 3: Get full context around errors
home-diagnostics --days 7 --hue-only --detailed > full-logs.txt

# Step 4: Search for specific patterns
home-diagnostics --days 30 --raw | grep -i "unreachable"
```

### Workflow 2: Daily Health Check

```bash
# Quick morning check
home-diagnostics --hours 24 --errors-only --summary

# If issues found, investigate
home-diagnostics --hours 24 --errors-only --dedupe

# Export for tracking
home-diagnostics --hours 24 --errors-only > daily-errors-$(date +%Y%m%d).txt
```

### Workflow 3: Preparing for Support

```bash
# Comprehensive log collection
home-diagnostics --days 14 --detailed > support-comprehensive.txt

# Summary for quick review
home-diagnostics --days 14 --summary > support-summary.txt

# Errors only for focus
home-diagnostics --days 14 --errors-only --dedupe > support-errors.txt

# Raw logs for Apple Support
home-diagnostics --days 14 --raw > support-raw.txt
```

---

## Tips for Interpreting Output

1. **High occurrence counts** (100+) usually indicate routine operational messages, not problems
2. **Low occurrence counts** (1-5) of errors may indicate transient issues
3. **Time ranges spanning days/weeks** suggest persistent problems
4. **Clusters of errors at same timestamp** often share a root cause
5. **"Null" values in HomeKit characteristics** typically mean device/bridge communication issues
6. **Timeout messages** point to network or device availability problems
7. **Authentication errors** suggest device pairing needs attention
8. **Database errors** (Faults) are serious and may need Home app reset

---

## Common Patterns and Their Meanings

| Pattern | Likely Cause | Action |
|---------|--------------|--------|
| Repeated "(null) is not of type..." | Device not reporting characteristics | Restart bridge/device |
| "timeout" + device name | Network/device unreachable | Check connectivity |
| "bridge" + "unreachable" | Hue bridge offline | Check bridge power/network |
| "Failed to sync with iCloud" | Network/iCloud issues | Check internet connection |
| "Authentication failed" | Pairing issue | Re-pair device in Home app |
| "database" + "Fault" | Home database corruption | May need Home app reset |
| High refresh counts | Normal operation | No action needed |
| "No matching HMHome" | Configuration mismatch | Check Home app setup |
