# HomeDiagnostics

A macOS command-line tool for collecting and analyzing Apple Home and HomeKit logs to diagnose smart home issues.

## Overview

HomeDiagnostics queries the macOS unified logging system to extract, parse, and analyze logs from:
- `com.apple.Home`
- `com.apple.HomeKit`
- `com.apple.homed`

The tool is useful for diagnosing issues with smart home devices that become non-responsive, with flexible filtering to focus on specific devices, manufacturers, or patterns.

## Features

- **Accurate Log Collection**: Uses JSON format for precise log level detection (no false positives)
- **Flexible Time Windows**: Query by days or hours
- **Pattern Filtering**: Filter log messages using plain text or regular expressions
- **Severity Filtering**: Show only errors, faults, and warnings
- **Deduplication**: Group identical log entries and show occurrence counts
- **Multiple Output Modes**: Analyzed, raw, summary, or deduplicated views
- **Color Output**: Visual hierarchy with errors in red, warnings in yellow, metadata dimmed
- **Statistics**: Summary of log counts by subsystem and severity

## Installation

### Building from Source

```bash
cd ~/Developer/Projects/HomeDiagnostics
swift build --target home-diagnostics
```

The compiled binary will be at `.build/debug/home-diagnostics`.

### Release Build

```bash
swift build -c release --target home-diagnostics
```

The optimized binary will be at `.build/release/home-diagnostics`.

### Installing to PATH (Optional)

```bash
# Copy to a directory in your PATH
sudo cp .build/release/home-diagnostics /usr/local/bin/

# Or create an alias in your shell profile
alias home-diagnostics='~/Developer/Projects/HomeDiagnostics/.build/debug/home-diagnostics'
```

## Usage

### Basic Usage

```bash
# Collect logs from the last 14 days (default)
home-diagnostics

# Collect logs from the last 7 days
home-diagnostics --days 7

# Collect logs from the last 6 hours
home-diagnostics --hours 6
```

### Filtering Options

```bash
# Filter by plain text (case-insensitive)
home-diagnostics --filter "hue"
home-diagnostics --filter "timeout"
home-diagnostics --filter "bridge"

# Filter using regular expressions
home-diagnostics --filter "hue|philips|bridge"
home-diagnostics --filter "timeout.*accessory"
home-diagnostics --filter "^Error.*HomeKit"

# Show only errors, faults, and warnings
home-diagnostics --errors-only

# Combine filters: device-specific errors from last 24 hours
home-diagnostics --hours 24 --filter "hue" --errors-only
home-diagnostics --hours 24 --filter "nanoleaf" --errors-only
```

### Output Modes

```bash
# Show summary statistics only
home-diagnostics --summary

# Deduplicate entries and show occurrence counts
home-diagnostics --dedupe

# Raw output (unprocessed logs for piping to other tools)
home-diagnostics --raw

# Verbose diagnostic output (on stderr)
home-diagnostics --verbose
```

### Advanced Examples

```bash
# Diagnose Philips Hue issues: show unique error types from last week
home-diagnostics --days 7 --filter "hue|philips|bridge" --errors-only --dedupe

# Find timeout issues across all devices
home-diagnostics --days 7 --filter "timeout" --errors-only --dedupe

# Quick check for recent problems
home-diagnostics --hours 2 --errors-only --summary

# Export raw logs for external processing
home-diagnostics --days 30 --raw > home-logs.txt

# Find logs matching a specific device name
home-diagnostics --days 7 --filter "Living Room" --dedupe

# Comprehensive analysis with debug logs (slower)
home-diagnostics --days 1 --detailed --dedupe

# Monitor recent activity verbosely
home-diagnostics --hours 1 --verbose --detailed

# Find connection issues with regex
home-diagnostics --days 7 --filter "connect.*fail|unreachable|timeout" --errors-only
```

## Command-Line Options

### Time Window Options

| Option | Description | Default |
|--------|-------------|---------|
| `--days <n>`, `-d <n>` | Number of days to look back | 14 |
| `--hours <n>` | Number of hours to look back | - |

**Note**: Cannot specify both `--days` and `--hours`.

### Filtering Options

| Option | Description |
|--------|-------------|
| `--filter <pattern>`, `-f <pattern>` | Filter log messages (plain text or regex) |
| `--errors-only` | Show only errors, faults, and warnings (filter out info/debug) |

**Filter pattern behavior:**
- Attempts regex first (e.g., `"hue|philips"`, `"timeout.*accessory"`)
- Falls back to case-insensitive plain text search if regex is invalid
- Applied to the log message content

### Output Options

| Option | Description |
|--------|-------------|
| `--summary` | Show summary statistics only |
| `--dedupe` | Deduplicate log entries and show occurrence counts |
| `--raw` | Output raw log data without parsing or analysis |
| `--verbose`, `-v` | Enable verbose output (diagnostic messages to stderr) |
| `--detailed` | Include debug-level logs (slower, more comprehensive) |

### Other Options

| Option | Description |
|--------|-------------|
| `--version` | Show version information |
| `--help`, `-h` | Show help message |

## Flag Combinations

### Valid Combinations

Most flags can be combined freely:

```bash
# ✓ Filter device errors and deduplicate
home-diagnostics --filter "hue" --errors-only --dedupe

# ✓ Show summary with verbose diagnostics
home-diagnostics --summary --verbose

# ✓ Detailed logs with deduplication and filtering
home-diagnostics --detailed --dedupe --filter "timeout"
```

### Invalid Combinations

Some flags are mutually exclusive:

```bash
# ✗ Cannot use both --days and --hours
home-diagnostics --days 7 --hours 24

# ✗ Cannot combine --raw with analysis flags
home-diagnostics --raw --summary
home-diagnostics --raw --dedupe
home-diagnostics --raw --errors-only
```

## Output Format

### Standard Output (Analyzed Mode)

```
SUMMARY
=======

Total log entries: 843
Errors: 3
Faults: 0
Warnings: 0
Potentially problematic: 3
Unique entry types: 41

Entries by subsystem:
  com.apple.Home: 803
  com.apple.HomeKit: 40


PROBLEMATIC ENTRIES
===================

Showing 3 unique problematic entry types (out of 3 total)

[1x] [01/29 09:02] [Error] [com.apple.HomeKit]
[Bank Street/Hue color lamp/...] Active transition count value: (null) is not of type NSNumber


ALL ENTRIES
===========

Showing 41 unique entry types (out of 843 total)

[803x] [01/28 08:01 - 01/29 15:06] [Info] [com.apple.Home]
widgetTileInfos(from:uuids:...) for accessory <private>
```

### Color Coding

- **Errors/Faults**: Red and bold
- **Warnings**: Yellow and bold
- **Metadata** (timestamps, subsystem, level): Gray/dimmed
- **Info/Debug**: Normal text

### Date Format

Timestamps use a compact format: `MM/dd HH:mm` (e.g., `01/29 14:30`)

### Deduplication Format

When using `--dedupe`, identical log entries are grouped:

```
[803x] [01/28 08:01 - 01/29 15:06] [Info] [com.apple.Home]
Message text...
```

- `[803x]`: Number of occurrences
- `[01/28 08:01 - 01/29 15:06]`: Time range (first to last occurrence)

## Understanding the Output

### Log Levels

| Level | Description |
|-------|-------------|
| **Fault** | Critical errors requiring immediate attention |
| **Error** | Errors indicating failures or problems |
| **Warning** | Warnings about potential issues |
| **Info** | Informational messages (default) |
| **Debug** | Debug-level details (requires `--detailed`) |

### Problematic Entries

The tool identifies entries as "problematic" if they:
- Are at Error or Fault level, OR
- Contain keywords: "failed", "timeout", "unreachable", "not responding"

**Note**: When using `--errors-only`, the PROBLEMATIC ENTRIES section is skipped since it would be identical to ALL ENTRIES.

### Subsystems

- `com.apple.Home`: Home app itself
- `com.apple.HomeKit`: HomeKit framework
- `com.apple.homed`: Home daemon (background service)

## Use Cases

### Diagnosing Non-Responsive Devices

```bash
# Philips Hue devices
home-diagnostics --days 7 --filter "hue|philips|bridge" --errors-only --dedupe

# Nanoleaf devices
home-diagnostics --days 7 --filter "nanoleaf" --errors-only --dedupe

# Any device by name
home-diagnostics --days 7 --filter "Living Room Lamp" --errors-only

# Check if issues are ongoing
home-diagnostics --hours 2 --filter "hue" --errors-only
```

### Finding Specific Problems

```bash
# Timeout issues
home-diagnostics --days 7 --filter "timeout" --errors-only --dedupe

# Connection failures
home-diagnostics --days 7 --filter "connect.*fail|unreachable" --errors-only

# Authentication problems
home-diagnostics --days 7 --filter "auth.*fail|pairing.*fail" --errors-only
```

### Monitoring Home Stability

```bash
# Daily error check
home-diagnostics --days 1 --errors-only --summary

# Identify recurring issues
home-diagnostics --days 30 --errors-only --dedupe
```

### Exporting for External Analysis

```bash
# Export raw logs
home-diagnostics --days 14 --raw > home-logs.txt

# Export only errors
home-diagnostics --days 14 --errors-only --raw > errors.txt

# Filter and export for specific device
home-diagnostics --days 7 --filter "hue" --raw > hue-logs.txt

# Process with grep, awk, etc.
home-diagnostics --days 7 --raw | grep -i "bridge"
```

### Troubleshooting with Apple Support

```bash
# Collect comprehensive logs with timestamps
home-diagnostics --days 7 --detailed > support-logs.txt

# Get summary statistics
home-diagnostics --days 7 --summary > support-summary.txt
```

## Common Filter Examples

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

# Lutron
home-diagnostics --filter "lutron|caseta"
```

### By Problem Type

```bash
# Timeouts
home-diagnostics --filter "timeout"

# Connection issues
home-diagnostics --filter "connect.*fail|unreachable|not.responding"

# Authentication
home-diagnostics --filter "auth|pairing|credential"

# Null values
home-diagnostics --filter "null|nil"

# Database issues
home-diagnostics --filter "database|corruption"
```

### By Room or Accessory Name

```bash
# Specific room
home-diagnostics --filter "Living Room|Bedroom"

# Specific accessory
home-diagnostics --filter "Front Door Lock"

# Device type
home-diagnostics --filter "lamp|light|switch|sensor"
```

## Common Issues

### No Logs Collected

If you see 0 entries:
- Ensure you're running on macOS
- Try increasing the time window (`--days 30`)
- Try adding `--detailed` to include debug logs
- Check if Home app is active and syncing
- Remove `--filter` temporarily to check if filter is too restrictive

### Permission Issues

The tool requires access to system logs. If you encounter permission errors:
- The tool uses the standard `log show` command, which should work without special permissions
- Ensure you're running from a standard Terminal session
- Check Console.app access in System Settings > Privacy & Security

### Performance

For large time windows:
- Use `--summary` for quick statistics
- Avoid `--detailed` unless necessary (includes debug logs)
- Use `--errors-only` to reduce output volume
- Consider shorter time windows (`--hours` instead of `--days`)

**Typical performance**:
- Without `--detailed`: 10-30 seconds
- With `--detailed`: 2-5 minutes or more (large volume of debug logs)
- Fewer days (`--days 7` or less) will be faster

## Requirements

- **macOS**: 15.0+ (Sequoia or later)
- **Swift**: 6.2+
- **Xcode**: 16.0+ (for building)

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) (1.3.0+)
- [swift-subprocess](https://github.com/swiftlang/swift-subprocess) (0.0.1+)

## Architecture

- **Single-file design**: All code in `Sources/HomeDiagnostics/main.swift`
- **JSON parsing**: Uses `--style json` for accurate log level detection
- **Zero false positives**: Switched from text matching to metadata-based parsing
- **Stream separation**: Analysis output to stdout, diagnostics to stderr
- **Flexible filtering**: Supports both plain text and regex patterns

## Common Issues to Look For

When reviewing the output, look for:

1. **Timeout messages** - Devices not responding in time
2. **Connection failures** - Unable to reach device or bridge
3. **Authentication errors** - Issues with device credentials
4. **Network errors** - Problems communicating over the network
5. **Bridge issues** - Hub devices (Hue, Lutron, etc.) being unreachable
6. **Null values** - HomeKit characteristics returning null/invalid values
7. **Pairing failures** - Devices unable to establish connection

## Contributing

Contributions are welcome! Please follow the guidelines in `AGENTS.md` for:
- Swift coding conventions
- Testing requirements
- Documentation standards

See `Extras/Documentation/Principles Glossary.md` for engineering principles.

## License

This tool is provided as-is for personal diagnostic use.

## Acknowledgments

Built to help diagnose issues with smart home devices in Apple Home.
