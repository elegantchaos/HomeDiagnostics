# Usage Examples and Output Reference

This document provides detailed examples of HomeDiagnostics usage patterns and sample output.

## Table of Contents

- [Common Use Cases](#common-use-cases)
- [Output Format Reference](#output-format-reference)
- [Filter Examples](#filter-examples)
- [Troubleshooting Workflows](#troubleshooting-workflows)

## Common Use Cases

### Diagnosing Non-Responsive Devices

#### Philips Hue Devices

```bash
# Check for Hue issues in the last week
home-diagnostics --days 7 --filter "hue|philips|bridge" --errors-only --dedupe

# Check if Hue issues are ongoing
home-diagnostics --hours 2 --filter "hue" --errors-only
```

#### Nanoleaf Devices

```bash
home-diagnostics --days 7 --filter "nanoleaf" --errors-only --dedupe
```

#### Device by Name

```bash
# Search by room or accessory name
home-diagnostics --days 7 --filter "Living Room Lamp" --errors-only

# Search multiple names
home-diagnostics --filter "Kitchen|Bedroom|Bathroom"
```

### Finding Specific Problems

#### Timeout Issues

```bash
home-diagnostics --days 7 --filter "timeout" --errors-only --dedupe
```

#### Connection Failures

```bash
home-diagnostics --days 7 --filter "connect.*fail|unreachable" --errors-only
```

#### Authentication Problems

```bash
home-diagnostics --days 7 --filter "auth.*fail|pairing.*fail" --errors-only
```

#### Null/Invalid Values

```bash
home-diagnostics --days 7 --filter "null|nil|invalid" --errors-only
```

### Monitoring Home Stability

#### Daily Error Check

```bash
# Quick summary of today's errors
home-diagnostics --days 1 --errors-only --summary
```

#### Identify Recurring Issues

```bash
# Show most frequent problems over the last month
home-diagnostics --days 30 --errors-only --dedupe
```

#### Recent Activity

```bash
# Check what happened in the last 2 hours
home-diagnostics --hours 2 --errors-only
```

### Exporting for External Analysis

#### Export Raw Logs

```bash
# All logs
home-diagnostics --days 14 --raw > home-logs.txt

# Only errors
home-diagnostics --days 14 --errors-only --raw > errors.txt

# Specific device
home-diagnostics --days 7 --filter "hue" --raw > hue-logs.txt
```

#### Process with Unix Tools

```bash
# Find bridge-related entries
home-diagnostics --days 7 --raw | grep -i "bridge"

# Count occurrences of specific errors
home-diagnostics --days 7 --raw | grep -i "timeout" | wc -l

# Extract timestamps
home-diagnostics --days 7 --raw | awk '{print $1, $2}'
```

### Troubleshooting with Apple Support

```bash
# Comprehensive logs
home-diagnostics --days 7 --detailed > support-logs.txt

# Summary statistics
home-diagnostics --days 7 --summary > support-summary.txt

# Recent errors only
home-diagnostics --days 3 --errors-only --dedupe > recent-errors.txt
```

## Output Format Reference

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

[925x] [01/28 09:20 - 01/29 15:36] [Home]
refresh(homeManager:timeout:) finished successfully

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

### Color Coding

- **Errors/Faults**: Red text (bold)
- **Warnings**: Yellow text (bold)
- **Metadata**: Gray/dimmed (timestamps, subsystems, counts)
- **Info/Debug**: Normal text

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

### Date Format

Timestamps use compact format to save space:
- Format: `MM/dd HH:mm`
- Example: `01/29 14:30`
- No year shown (assumes current year)
- No seconds (not needed for most diagnostics)

## Filter Examples

### By Device Manufacturer

```bash
# Philips Hue
home-diagnostics --filter "hue|philips|bridge"

# Nanoleaf
home-diagnostics --filter "nanoleaf"

# Eve/Elgato
home-diagnostics --filter "eve|elgato"

# Aqara
home-diagnostics --filter "aqara"

# LIFX
home-diagnostics --filter "lifx"

# Lutron Caseta
home-diagnostics --filter "lutron|caseta"

# Logitech Harmony
home-diagnostics --filter "logitech|harmony"

# August/Yale locks
home-diagnostics --filter "august|yale"
```

### By Problem Type

```bash
# Timeouts
home-diagnostics --filter "timeout"

# Connection issues
home-diagnostics --filter "connect.*fail|unreachable|not.responding"

# Authentication/pairing
home-diagnostics --filter "auth|pairing|credential"

# Null values
home-diagnostics --filter "null|nil"

# Database issues
home-diagnostics --filter "database|corruption"

# Firmware updates
home-diagnostics --filter "firmware|update"

# Network errors
home-diagnostics --filter "network|dns|socket"

# Thread/Matter issues
home-diagnostics --filter "thread|matter|border.router"
```

### By Room or Accessory Name

```bash
# Specific room
home-diagnostics --filter "Living Room|Bedroom"

# Specific accessory
home-diagnostics --filter "Front Door Lock"

# Device type
home-diagnostics --filter "lamp|light|switch|sensor"

# Multiple device types
home-diagnostics --filter "thermostat|camera|doorbell"
```

### Advanced Regex Patterns

```bash
# Messages starting with "Error"
home-diagnostics --filter "^Error"

# Failed operations
home-diagnostics --filter "fail(ed|ure)?"

# Any connection-related issue
home-diagnostics --filter "(dis)?connect(ion|ed)?"

# Timeout with context
home-diagnostics --filter "timeout.*accessory|accessory.*timeout"

# Multiple error codes
home-diagnostics --filter "code[:\s]+(52|54|56)"
```

## Troubleshooting Workflows

### Workflow 1: Device Suddenly Stopped Responding

```bash
# Step 1: Check recent errors for the device
home-diagnostics --hours 6 --filter "Device Name" --errors-only

# Step 2: Look at broader timeframe to find pattern
home-diagnostics --days 7 --filter "Device Name" --errors-only --dedupe

# Step 3: Check if it's a manufacturer-wide issue
home-diagnostics --days 7 --filter "manufacturer" --errors-only --dedupe

# Step 4: Check connection infrastructure
home-diagnostics --days 7 --filter "bridge|hub|router" --errors-only
```

### Workflow 2: Identifying Network vs Device Issues

```bash
# Check for network/connection problems
home-diagnostics --days 3 --filter "network|unreachable|timeout" --errors-only --dedupe

# Check for device-specific errors
home-diagnostics --days 3 --filter "characteristic|property|value.*null" --errors-only
```

### Workflow 3: After iOS/Home App Update

```bash
# Check for new errors since update
home-diagnostics --days 1 --errors-only --dedupe

# Compare to previous week
home-diagnostics --days 7 --errors-only --dedupe

# Look for authentication issues (common after updates)
home-diagnostics --days 2 --filter "auth|pairing|key" --errors-only
```

### Workflow 4: Multiple Devices Acting Up

```bash
# Check if it's a hub/bridge issue
home-diagnostics --days 3 --filter "bridge|hub" --errors-only

# Check primary resident issues
home-diagnostics --days 3 --filter "resident|reachable" --errors-only

# Check iCloud sync
home-diagnostics --days 3 --filter "sync|cloud" --errors-only
```

### Workflow 5: Intermittent Issues

```bash
# Look for patterns over time
home-diagnostics --days 14 --errors-only --dedupe

# Check for time-of-day patterns (export and analyze)
home-diagnostics --days 7 --raw > logs.txt
grep "unreachable" logs.txt | cut -d' ' -f2 | sort | uniq -c

# Check for recurring error spikes
home-diagnostics --days 30 --summary
```

## Understanding Common Error Messages

### Connection Issues

**"unreachable duration for <private> is X seconds"**
- Device was unreachable for X seconds
- May indicate network issues or device being powered off
- Check device power, network, and bridge connectivity

**"Failed to activate Rapport client"**
- Communication failure with remote devices (when away from home)
- Usually indicates network or iCloud issues

**"Timeout waiting for response"**
- Device didn't respond within expected time
- Could be slow network, busy device, or device malfunction

### Pairing/Authentication Issues

**"Failed to save public key"**
- Security credential storage failure
- May require re-pairing the device

**"Missing HH2 Controller Key"**
- Home Key (Matter/Thread) related issue
- Common with newer smart lock or Thread devices

### Data/State Issues

**"characteristic (null): UUID '(null)' length needs to be 8"**
- Device reported invalid characteristic data
- Usually indicates device firmware issue or communication corruption

**"Active transition count value: (null) is not of type NSNumber"**
- Device sent wrong data type for a property
- Common with lights during transitions

### Infrastructure Issues

**"Message failed over rapport"**
- Inter-device communication failure
- Check if all Apple devices (iPads, HomePods, Apple TV) are on same network

**"Unable to determine destination for event router client"**
- Event routing issue, usually during iCloud sync
- May resolve itself after a few minutes

## Performance Notes

### Typical Execution Times

| Command | Typical Duration |
|---------|------------------|
| `--days 7` | 10-20 seconds |
| `--days 7 --detailed` | 2-5 minutes |
| `--days 14` | 15-30 seconds |
| `--days 14 --detailed` | 5-10 minutes |
| `--hours 6` | 5-10 seconds |
| `--summary` | Same as regular (analysis is fast) |
| `--dedupe` | +2-5 seconds (additional grouping) |

### Performance Tips

1. **Start with shorter time windows**: Use `--hours` or `--days 1` first
2. **Avoid `--detailed` unless needed**: Debug logs are voluminous
3. **Use filters**: Reduces processing and output
4. **Use `--summary` for quick checks**: Fastest option
5. **Use `--errors-only`**: Filters before analysis (faster)
