# Output Reference

This document explains HomeDiagnostics output formats, deduplication technology, and how to interpret results.

## Table of Contents

- [Understanding Output](#understanding-output)
- [Deduplication Technology](#deduplication-technology)
- [Log Levels](#log-levels)
- [Subsystems](#subsystems)
- [Color Coding](#color-coding)
- [Date Format](#date-format)

## Understanding Output

### Standard Output (Analyzed Mode)

```
HomeDiagnostics - Apple Home Log Analyzer
==========================================

Collecting logs from the last 7 day(s)...

PROBLEMATIC ENTRIES
===================

Showing 71 unique problematic entry types (out of 3766 total)

[1100x] [01/28 09:20 - 01/29 15:36] [Home]
updateHomes(timeout:) found homes [<id>, <id>]

[925x] [01/28 09:20 - 01/29 15:36] [Home]
refresh(homeManager:timeout:) starting refresh

[255x] [01/29 09:02 - 01/29 09:03] [Error] [HomeKit]
API Misuse: hmf_objectForKey with a nil key.

[63x] [01/29 09:02 - 01/29 09:02] [Error] [HomeKit]
characteristic (null): UUID '(null)' length needs to be 8
```

### Deduplication Format

When using `--dedupe`, entries show:

```
[COUNT×] [FIRST_TIME - LAST_TIME] [LEVEL] [SUBSYSTEM]
Message text...
```

**Components:**
- `[COUNT×]`: Number of occurrences (e.g., `[255x]`)
- `[FIRST_TIME - LAST_TIME]`: Time range from first to last occurrence
  - Single occurrence: `[01/29 09:02]`
  - Multiple: `[01/28 09:20 - 01/29 15:36]`
- `[LEVEL]`: Log level (Error, Fault, Warning) - Info/Debug omitted
- `[SUBSYSTEM]`: Shortened subsystem name (HomeKit, Home, homed)

### Summary Output

```
SUMMARY
=======

Total log entries: 35039
Errors: 677
Faults: 0
Warnings: 0
Potentially problematic: 3766
Unique entry types: 71

Entries by subsystem:
  com.apple.HomeKit: 24694
  com.apple.Home: 10344
  com.apple.homed: 1
```

**Note**: "Unique entry types" appears only with `--dedupe` flag.

## UUID Naming Summary

When name substitution is enabled (default), a UUID naming summary is appended to the end of the output. It groups entities by home and shows devices/scenes with their UUID prefixes.

You can disable this section and UUID substitution with `--no-names`.

## Deduplication Technology

HomeDiagnostics uses intelligent pattern-based normalization to group similar error messages:

- **98.1% reduction** in unique message types on real-world data
- **Phase 1 normalization**: Replaces UUIDs, MAC addresses, numbers, timestamps, and other variable values with placeholders
- **Fast execution**: O(n) time complexity, handles thousands of entries in seconds
- **Accuracy**: Preserves message structure while grouping variations

### Example Transformation

**Before (20 variations):**
```
[D3AAD67C-68AB-4261-86AC-7AB8969C6203/0B:10:14:18:2B:E3+1/NO] Failed to save public key...Error Domain=HMErrorDomain Code=52...0x814188330
[4C2778CE-E310-4C51-BACB-766111A6D729/60:97:3C:21:F9:6F+1/NO] Failed to save public key...Error Domain=HMErrorDomain Code=52...0x813f84b10
... (18 more with different UUIDs, MACs, hex addresses)
```

**After (1 deduplicated entry):**
```
[10x] [01/29 09:02 - 01/29 09:02] [HomeKit]
[<prefix>] Failed to save public key(<private>) pairing username(<private>): Error Domain=<domain> Code=<n>...
```

### Normalization Patterns

| Pattern | Example Before | Example After |
|---------|---------------|---------------|
| UUIDs | `A1B2-C3D4-E5F6-...` | `<id>` |
| MAC addresses | `AA:BB:CC:DD:EE:FF` | `<mac>` |
| Bracket prefixes | `[UUID/MAC+1/NO]` | `[<prefix>]` |
| Object descriptions | `<HMFMessage: 0x123>` | `<obj>` |
| Numbers | `123` or `45.67` | `<n>` |
| Durations | `1.5 seconds` | `<duration>` |
| Timestamps | `2026-01-29 10:30:15.123` | `<timestamp>` |
| Hex addresses | `0xdeadbeef` | `<addr>` |
| Booleans | `YES` / `NO` | `<bool>` |
| Error domains | `Error Domain=HMErrorDomain` | `Error Domain=<domain>` |

### How It Works

**Deduplication Key Formula:**
```
{subsystem} | {level} | {normalizedMessage}
```

Entries are grouped by subsystem + level + normalized message text.

**Processing Pipeline:**
1. Structural patterns (bracket prefixes, object descriptions)
2. Variable values (UUIDs, MACs, numbers, durations)
3. Keywords (booleans, error domains)
4. Whitespace normalization

Pattern order matters: specific patterns are applied before general ones to prevent premature matches.

## Log Levels

| Level | Description |
|-------|-------------|
| **Fault** | Critical errors requiring immediate attention |
| **Error** | Errors indicating failures |
| **Warning** | Potential issues |
| **Info** | Informational (default) |
| **Debug** | Debug details (requires `--detailed`) |

## Subsystems

- `com.apple.Home` - Home app
- `com.apple.HomeKit` - HomeKit framework
- `com.apple.homed` - Home daemon (background service)

## Color Coding

When viewing output in a terminal:

- **Red** - Errors and faults
- **Yellow** - Warnings
- **Gray** - Metadata (timestamps, subsystems)
- **Normal** - Info and debug messages

## Date Format

Timestamps use compact format to save space:
- Format: `MM/dd HH:mm`
- Example: `01/29 14:30`
- No year shown (assumes current year)
- No seconds (not needed for most diagnostics)

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

## Interpreting Results

1. **High occurrence counts** (100+) usually indicate routine operational messages, not problems
2. **Low occurrence counts** (1-5) of errors may indicate transient issues
3. **Time ranges spanning days/weeks** suggest persistent problems
4. **Clusters of errors at same timestamp** often share a root cause
5. **"Null" or "nil" values** in HomeKit characteristics typically mean device/bridge communication issues
6. **Timeout messages** point to network or device availability problems
7. **Authentication errors** suggest device pairing needs attention
8. **Database errors** (Faults) are serious and may need Home app reset
