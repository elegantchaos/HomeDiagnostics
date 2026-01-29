# HomeDiagnostics

A macOS command-line tool for collecting and analyzing Apple Home and HomeKit logs to diagnose smart home issues.

## Overview

HomeDiagnostics queries the macOS unified logging system to extract and analyze logs from Apple Home, HomeKit, and the Home daemon. It helps diagnose issues with smart home devices that become non-responsive by providing filtered, deduplicated views of error conditions.

**Key Features:**
- **Intelligent deduplication** - Groups similar errors (98% reduction in unique messages)
- **Flexible filtering** - Plain text or regex patterns to focus on specific devices/issues
- **Multiple output modes** - Summary, raw, or analyzed views
- **Color-coded output** - Errors in red, warnings in yellow, metadata dimmed
- **Accurate parsing** - JSON-based log parsing for zero false positives

## Quick Start

### Installation

```bash
# Build from source
cd ~/Developer/Projects/HomeDiagnostics
swift build --target home-diagnostics

# Run
.build/debug/home-diagnostics --help
```

### Basic Usage

```bash
# View recent errors
home-diagnostics --hours 6 --errors-only

# Diagnose specific device
home-diagnostics --days 7 --filter "hue" --errors-only --dedupe

# Get summary statistics
home-diagnostics --days 14 --summary
```

## Usage

### Command-Line Options

#### Time Windows

```bash
--days <n>, -d <n>    # Number of days to look back (default: 14)
--hours <n>           # Number of hours to look back
```

**Note**: Cannot specify both `--days` and `--hours`.

#### Filtering

```bash
--filter <pattern>, -f <pattern>  # Filter by plain text or regex
--errors-only                     # Show only errors, faults, and warnings
```

**Filter examples:**
```bash
--filter "hue|philips"           # Regex: Philips Hue devices
--filter "timeout"               # Plain text: timeout issues
--filter "Living Room"           # Plain text: room name
```

#### Output Modes

```bash
--summary         # Show summary statistics only
--dedupe          # Deduplicate entries and show counts
--raw             # Output unprocessed logs
--verbose, -v     # Enable diagnostic output (to stderr)
--detailed        # Include debug-level logs (slower)
```

#### Other Options

```bash
--version         # Show version
--help, -h        # Show help
```

### Common Commands

```bash
# Recent problems
home-diagnostics --hours 2 --errors-only --summary

# Device diagnosis with deduplication
home-diagnostics --days 7 --filter "device-name" --errors-only --dedupe

# Export for analysis
home-diagnostics --days 14 --raw > logs.txt

# Comprehensive troubleshooting
home-diagnostics --days 7 --detailed --dedupe
```

## Understanding Output

### Deduplication

With `--dedupe`, similar messages are grouped:

```
[255x] [01/29 09:02 - 01/29 09:03] [Error] [HomeKit]
API Misuse: hmf_objectForKey with a nil key.
```

- `[255x]` - Occurred 255 times
- `[01/29 09:02 - 01/29 09:03]` - Time range
- Message normalized (UUIDs, MACs, numbers replaced with placeholders)

### Log Levels

| Level | Description |
|-------|-------------|
| **Fault** | Critical errors requiring immediate attention |
| **Error** | Errors indicating failures |
| **Warning** | Potential issues |
| **Info** | Informational (default) |
| **Debug** | Debug details (requires `--detailed`) |

### Subsystems

- `com.apple.Home` - Home app
- `com.apple.HomeKit` - HomeKit framework
- `com.apple.homed` - Home daemon (background service)

### Color Coding

- **Red** - Errors and faults
- **Yellow** - Warnings
- **Gray** - Metadata (timestamps, subsystems)
- **Normal** - Info and debug messages

## Example Workflows

### Diagnose Non-Responsive Device

```bash
# 1. Check recent activity
home-diagnostics --hours 6 --filter "device-name" --errors-only

# 2. Look for patterns over last week
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

## Performance

**Typical execution times:**
- `--days 7`: 10-20 seconds
- `--days 7 --detailed`: 2-5 minutes
- `--hours 6`: 5-10 seconds

**Tips for faster execution:**
- Use shorter time windows (`--hours` instead of `--days`)
- Avoid `--detailed` unless necessary
- Use `--summary` for quick checks
- Apply `--filter` to reduce data volume

## Requirements

- **macOS**: 15.0+ (Sequoia or later)
- **Swift**: 6.2+ (for building)
- **Xcode**: 16.0+ (for development)

## Documentation

- **[Usage Examples & Output Reference](Extras/Documentation/Examples.md)** - Detailed examples, filter patterns, and output format guide
- **[Development Guide](Extras/Documentation/Development.md)** - Architecture, building, testing, and contributing
- **[Engineering Principles](Extras/Documentation/Principles Glossary.md)** - Design patterns and coding standards

## Deduplication Technology

HomeDiagnostics uses intelligent pattern-based normalization to group similar error messages:

- **98.1% reduction** in unique message types on real-world data
- **Phase 1 normalization**: Replaces UUIDs, MAC addresses, numbers, timestamps, and other variable values with placeholders
- **Fast execution**: O(n) time complexity, handles thousands of entries in seconds
- **Accuracy**: Preserves message structure while grouping variations

**Example transformation:**
```
Before: [UUID1/MAC1+123/NO] Failed to save public key...Error...0x12345678
        [UUID2/MAC2+456/YES] Failed to save public key...Error...0xabcdef01
        (20 more variations...)

After:  [10x] [<prefix>] Failed to save public key...Error Domain=<domain>...
```

## Troubleshooting

### No Logs Collected

- Increase time window (`--days 30`)
- Add `--detailed` to include debug logs
- Remove `--filter` temporarily
- Ensure Home app is active and syncing

### Permission Issues

The tool uses standard `log show` command which should work without special permissions. Ensure you're running from Terminal.

### Slow Performance

- Use shorter time windows
- Avoid `--detailed` flag
- Use `--errors-only` to reduce volume
- Try `--summary` for quick statistics

## Contributing

Contributions welcome! See [Development Guide](Extras/Documentation/Development.md) for:
- Architecture overview
- Build instructions
- Testing requirements
- Coding standards (see also `AGENTS.md`)

## License

This tool is provided as-is for personal diagnostic use.

## Acknowledgments

Built to help diagnose smart home device issues in Apple Home.
