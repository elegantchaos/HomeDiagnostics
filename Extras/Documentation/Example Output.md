# HomeDiagnostics - Example Output

This document shows example outputs from various HomeDiagnostics commands to help you understand what to expect.

## Example 1: Filtering for Philips Hue Devices

**Command:**
```bash
home-diagnostics --days 7 --filter "hue" --errors-only --dedupe
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
- 3 unique errors found matching "hue" (case-insensitive)
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

## Example 2: Using Regex to Match Multiple Patterns

**Command:**
```bash
home-diagnostics --days 7 --filter "hue|philips|bridge" --errors-only --summary
```

**Purpose:** Find all Hue/Philips/Bridge related errors using regex alternation.

**Example Output:**
```
SUMMARY
=======

Total log entries: 3
Errors: 3
Faults: 0
Warnings: 0
Potentially problematic: 3

Entries by subsystem:
  com.apple.HomeKit: 3
```

**What it shows:**
- Regex pattern `"hue|philips|bridge"` matches any of the three terms
- Same results as plain "hue" in this case
- Useful for catching manufacturer-specific terms

---

## Example 3: Finding Timeout Issues

**Command:**
```bash
home-diagnostics --days 7 --filter "timeout" --errors-only --dedupe
```

**Purpose:** Find all timeout-related problems across all devices.

**Example Output:**
```
SUMMARY
=======

Total log entries: 15
Errors: 12
Faults: 0
Warnings: 3
Potentially problematic: 15
Unique entry types: 5

Entries by subsystem:
  com.apple.HomeKit: 10
  com.apple.Home: 5


ALL ENTRIES
===========

Showing 5 unique entry types (out of 15 total)

[8x] [01/23 08:00 - 01/29 14:30] [Error] [com.apple.HomeKit]
Connection timeout to accessory [Living Room Lamp]

[3x] [01/25 10:15 - 01/28 16:20] [Warning] [com.apple.Home]
Operation timeout while refreshing home data

[2x] [01/26 12:30 - 01/27 09:45] [Error] [com.apple.HomeKit]
Read timeout for characteristic [Power State]

[1x] [01/28 18:00] [Error] [com.apple.HomeKit]
Write timeout for accessory [Bedroom Switch]

[1x] [01/29 11:15] [Warning] [com.apple.Home]
Scene activation timeout: Good Morning
```

**What it shows:**
- 5 different types of timeout issues
- "Living Room Lamp" has recurring connection timeouts (8 times over 6 days)
- Multiple devices affected
- Both read and write operations timing out

---

## Example 4: Quick Summary

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

... (additional entries)

[01/29 15:00] [Error] [com.apple.Home]
monitorAttributesAndUpdateEntities(...) No matching HMHome found in entities
```

**What it shows:**
- High activity (1555 entries in 1 hour)
- 202 "problematic" entries (includes "failed" keyword matches)
- Most activity from HomeKit framework
- Regular refresh cycles
- One actual error about missing HMHome

---

## Example 5: Deduplication Shows Patterns

**Command:**
```bash
home-diagnostics --days 30 --filter "timeout|unreachable|failed" --dedupe
```

**Purpose:** Identify recurring patterns over a month using regex.

**Example Output:**
```
SUMMARY
=======

Total log entries: 147
Errors: 35
Faults: 0
Warnings: 12
Potentially problematic: 147
Unique entry types: 18

Entries by subsystem:
  com.apple.HomeKit: 98
  com.apple.Home: 49


ALL ENTRIES
===========

Showing 18 unique entry types (out of 147 total)

[35x] [01/02 14:23 - 01/29 09:15] [Error] [com.apple.HomeKit]
Connection timeout to accessory [Living Room Lamp]

[22x] [01/05 08:30 - 01/28 12:45] [Info] [com.apple.HomeKit]
Failed to connect to accessory [Bedroom Light]

[15x] [01/10 15:30 - 01/25 09:12] [Error] [com.apple.HomeKit]
Bridge unreachable: timeout after 10s

... (additional entries)
```

**What it shows:**
- Regex `"timeout|unreachable|failed"` catches multiple problem types
- 147 entries collapsed into 18 unique types
- Date ranges show when issues first/last occurred
- Occurrence counts show frequency
- "Living Room Lamp" has persistent timeout issues (35 times over 27 days)

---

## Example 6: Raw Output for Piping

**Command:**
```bash
home-diagnostics --days 7 --filter "bridge" --raw | head -5
```

**Purpose:** Export filtered raw logs for custom processing with Unix tools.

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
- Only lines matching filter ("bridge")
- No parsing or analysis
- All metadata preserved
- Ready for external tools

---

## Example 7: Filtering by Device Name

**Command:**
```bash
home-diagnostics --days 7 --filter "Living Room" --errors-only
```

**Purpose:** Find all errors related to a specific room or device.

**Example Output:**
```
SUMMARY
=======

Total log entries: 12
Errors: 10
Faults: 2
Warnings: 0
Potentially problematic: 12

Entries by subsystem:
  com.apple.HomeKit: 12


ALL ENTRIES
===========

[01/23 08:15] [Error] [com.apple.HomeKit]
Connection timeout to accessory [Living Room Lamp]

[01/23 14:30] [Fault] [com.apple.HomeKit]
Failed to establish connection: Living Room Switch

[01/24 09:00] [Error] [com.apple.HomeKit]
Living Room Sensor not responding to requests

... (additional entries)
```

**What it shows:**
- Plain text filter matches "Living Room" in any message
- 12 errors across devices in that room
- Mix of lamps, switches, and sensors
- Suggests room-wide connectivity issue

---

## Example 8: Complex Regex Pattern

**Command:**
```bash
home-diagnostics --days 7 --filter "connect.*fail|auth.*error|pairing" --errors-only --dedupe
```

**Purpose:** Find connection, authentication, and pairing issues using advanced regex.

**Example Output:**
```
SUMMARY
=======

Total log entries: 8
Errors: 6
Faults: 2
Warnings: 0
Potentially problematic: 8
Unique entry types: 4

Entries by subsystem:
  com.apple.HomeKit: 8


ALL ENTRIES
===========

Showing 4 unique entry types (out of 8 total)

[3x] [01/24 10:00 - 01/28 15:30] [Error] [com.apple.HomeKit]
Failed to connect to accessory: authentication error

[2x] [01/25 14:15 - 01/26 09:00] [Fault] [com.apple.HomeKit]
Pairing attempt failed: device not responding

[2x] [01/27 11:30 - 01/29 08:45] [Error] [com.apple.HomeKit]
Connection failed: unable to resolve hostname

[1x] [01/29 16:20] [Error] [com.apple.HomeKit]
Authentication error during pairing: invalid credentials
```

**What it shows:**
- Complex regex: `"connect.*fail|auth.*error|pairing"`
  - `connect.*fail` - "connect" followed by "fail"
  - `auth.*error` - "auth" followed by "error"
  - `pairing` - the word "pairing"
- Catches multiple related problem types
- 4 distinct error patterns identified

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

# Step 2: Focus on affected device
home-diagnostics --days 7 --filter "Device Name" --errors-only --dedupe

# Step 3: Check for specific problems (timeouts, connection issues)
home-diagnostics --days 7 --filter "Device Name|timeout|unreachable" --dedupe

# Step 4: Get full context around errors
home-diagnostics --days 7 --filter "Device Name" --detailed > full-logs.txt
```

### Workflow 2: Manufacturer-Specific Issues

```bash
# Philips Hue
home-diagnostics --days 14 --filter "hue|philips|bridge" --errors-only --dedupe

# Nanoleaf
home-diagnostics --days 14 --filter "nanoleaf" --errors-only --dedupe

# LIFX
home-diagnostics --days 14 --filter "lifx" --errors-only --dedupe

# Any manufacturer
home-diagnostics --days 14 --filter "manufacturer-name" --errors-only --dedupe
```

### Workflow 3: Daily Health Check

```bash
# Quick morning check
home-diagnostics --hours 24 --errors-only --summary

# If issues found, investigate
home-diagnostics --hours 24 --errors-only --dedupe

# Export for tracking
home-diagnostics --hours 24 --errors-only > daily-errors-$(date +%Y%m%d).txt
```

### Workflow 4: Problem Type Analysis

```bash
# Timeout issues
home-diagnostics --days 7 --filter "timeout" --errors-only --dedupe

# Connection failures
home-diagnostics --days 7 --filter "connect.*fail|unreachable" --errors-only --dedupe

# Authentication problems
home-diagnostics --days 7 --filter "auth|pairing|credential" --errors-only --dedupe

# Null/invalid values
home-diagnostics --days 7 --filter "null|nil|invalid" --errors-only --dedupe
```

### Workflow 5: Preparing for Support

```bash
# Comprehensive log collection
home-diagnostics --days 14 --detailed > support-comprehensive.txt

# Summary for quick review
home-diagnostics --days 14 --summary > support-summary.txt

# Device-specific errors
home-diagnostics --days 14 --filter "Device Name" --errors-only --dedupe > support-device-errors.txt

# Raw logs for Apple Support
home-diagnostics --days 14 --raw > support-raw.txt
```

---

## Tips for Interpreting Output

1. **High occurrence counts** (100+) usually indicate routine operational messages, not problems
2. **Low occurrence counts** (1-5) of errors may indicate transient issues
3. **Time ranges spanning days/weeks** suggest persistent problems
4. **Clusters of errors at same timestamp** often share a root cause
5. **"Null" or "nil" values** in HomeKit characteristics typically mean device/bridge communication issues
6. **Timeout messages** point to network or device availability problems
7. **Authentication errors** suggest device pairing needs attention
8. **Database errors** (Faults) are serious and may need Home app reset

---

## Common Filter Patterns and Their Meanings

| Filter Pattern | What It Finds | Use Case |
|----------------|---------------|----------|
| `"hue\|philips\|bridge"` | Philips Hue devices | Hue-specific issues |
| `"timeout"` | Any timeout | Device responsiveness |
| `"timeout\|unreachable"` | Connection issues | Network problems |
| `"connect.*fail"` | Connection failures | Pairing/setup issues |
| `"auth\|pairing"` | Authentication | Credential problems |
| `"null\|nil"` | Invalid values | Data corruption |
| `"Living Room"` | Specific room | Room-wide issues |
| `"lamp\|light"` | Lighting devices | Lighting problems |
| `"sensor"` | Sensor devices | Sensor issues |
| `"lock"` | Lock devices | Security devices |
| `"^Error.*HomeKit"` | Lines starting with "Error" in HomeKit | Critical HomeKit errors |
| `"database.*corrupt"` | Database issues | System corruption |

---

## Regex Quick Reference

For advanced filtering:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `\|` | OR (alternation) | `"hue\|bridge"` matches either |
| `.` | Any character | `"con.ect"` matches "connect" |
| `.*` | Zero or more characters | `"timeout.*lamp"` |
| `^` | Start of line | `"^Error"` |
| `$` | End of line | `"failed$"` |
| `[abc]` | Any of a, b, or c | `"[Hh]ue"` |
| `\d` | Any digit | `"timeout\d+"` |
| `\s` | Whitespace | `"error\s+message"` |

**Note**: If your regex is invalid, the tool automatically falls back to plain text search.

---

## Common Patterns and Their Meanings

| Pattern Seen | Likely Cause | Action |
|--------------|--------------|--------|
| Repeated "(null) is not of type..." | Device not reporting characteristics | Restart bridge/device |
| "timeout" + device name | Network/device unreachable | Check connectivity |
| "bridge" + "unreachable" | Hub offline | Check bridge power/network |
| "Failed to sync with iCloud" | Network/iCloud issues | Check internet connection |
| "Authentication failed" | Pairing issue | Re-pair device in Home app |
| "database" + "Fault" | Home database corruption | May need Home app reset |
| High refresh counts | Normal operation | No action needed |
| "No matching HMHome" | Configuration mismatch | Check Home app setup |
| "pairing.*fail" | Cannot establish connection | Reset and re-pair device |
