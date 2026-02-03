# Usage Guide

This document covers common workflows, filter patterns, troubleshooting steps, and practical examples.

## Table of Contents

- [Common Workflows](#common-workflows)
- [Filter Patterns](#filter-patterns)
- [Troubleshooting](#troubleshooting)
- [Common Error Messages](#common-error-messages)
- [Entity Naming](#entity-naming)

## Common Workflows

### Diagnose Non-Responsive Device

```bash
# 1. Check the last few minutes for quick insight
home-diagnostics --minutes 10 --filter "device-name" --errors-only

# 2. Check recent activity (last 6 hours)
home-diagnostics --hours 6 --filter "device-name" --errors-only

# 3. Look for patterns over last week
home-diagnostics --days 7 --filter "device-name" --errors-only --dedupe

# 3. Check if it's a manufacturer-wide issue
home-diagnostics --days 7 --filter "hue|philips" --errors-only --dedupe
```

### Find Specific Problems

```bash
# Timeout issues
home-diagnostics --days 7 --filter "timeout" --errors-only --dedupe

# Connection failures
home-diagnostics --days 7 --filter "unreachable|connect.*fail" --errors-only

# Authentication problems
home-diagnostics --days 7 --filter "pairing|auth" --errors-only
```

### Monitor Home Stability

```bash
# Daily check
home-diagnostics --days 1 --errors-only --summary

# Identify recurring issues
home-diagnostics --days 30 --errors-only --dedupe
```

### Export for Analysis

```bash
# All logs
home-diagnostics --days 14 --raw > home-logs.txt

# Only errors
home-diagnostics --days 14 --errors-only --raw > errors.txt

# Specific device
home-diagnostics --days 7 --filter "hue" --raw > hue-logs.txt
```

### Prepare Logs for Support

```bash
# Comprehensive logs
home-diagnostics --days 7 --detailed > support-logs.txt

# Summary statistics
home-diagnostics --days 7 --summary > support-summary.txt

# Recent errors only
home-diagnostics --days 3 --errors-only --dedupe > recent-errors.txt
```

## Filter Patterns

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

## Troubleshooting

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
rg "unreachable" logs.txt | cut -d' ' -f2 | sort | uniq -c

# Check for recurring error spikes
home-diagnostics --days 30 --summary
```

### Common Issues and Solutions

#### No Logs Collected

- Increase time window (`--days 30`)
- Add `--detailed` to include debug logs
- Remove `--filter` temporarily
- Ensure Home app is active and syncing

#### Permission Issues

The tool uses standard `log show` command which should work without special permissions. Ensure you're running from Terminal.

#### Slow Performance

- Use shorter time windows
- Avoid `--detailed` flag
- Use `--errors-only` to reduce volume
- Try `--summary` for quick statistics

#### Filter Not Working

- Check regex syntax (use `|` for OR, `.*` for wildcards)
- Try plain text search first
- Use `--verbose` to see diagnostic output
- Test filter without `--errors-only` to see all matches

## Common Error Messages

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

## Entity Naming

Entity naming is enabled by default and substitutes UUIDs with human-readable names gathered from logs (and optionally the HomeKit API). You can control the source with `--entity-source`:

```bash
# Pattern scanning only (default)
home-diagnostics --entity-source patterns

# HomeKit API only (requires authorization)
home-diagnostics --entity-source api

# Both sources for maximum coverage
home-diagnostics --entity-source both
```

Disable substitution and the naming summary with:

```bash
home-diagnostics --no-names
```
