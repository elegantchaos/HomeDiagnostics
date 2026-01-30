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
# View errors from recent minutes
home-diagnostics --minutes 30 --errors-only

# View recent errors (last 6 hours)
home-diagnostics --hours 6 --errors-only

# Diagnose specific device
home-diagnostics --days 7 --filter "hue" --errors-only --dedupe

# Get summary statistics
home-diagnostics --days 14 --summary
```

## Command-Line Options

### Time Windows

```bash
--days <n>, -d <n>    # Number of days to look back (default: 14)
--hours <n>           # Number of hours to look back
--minutes <n>         # Number of minutes to look back
```

**Note**: Cannot specify more than one of `--days`, `--hours`, or `--minutes`.

### Filtering

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

### Output Modes

```bash
--summary         # Show summary statistics only
--dedupe          # Deduplicate entries and show counts
--raw             # Output unprocessed logs
--verbose, -v     # Enable diagnostic output (to stderr)
--detailed        # Include debug-level logs (slower)
```

### Other Options

```bash
--version         # Show version
--help, -h        # Show help
```

## Common Commands

```bash
# Recent problems
home-diagnostics --minutes 15 --errors-only --summary

# Recent problems (last 2 hours)
home-diagnostics --hours 2 --errors-only --summary

# Device diagnosis with deduplication
home-diagnostics --days 7 --filter "device-name" --errors-only --dedupe

# Export for analysis
home-diagnostics --days 14 --raw > logs.txt

# Comprehensive troubleshooting
home-diagnostics --days 7 --detailed --dedupe
```

## Requirements

- **macOS**: 15.0+ (Sequoia or later)
- **Swift**: 6.2+ (for building)
- **Xcode**: 16.0+ (for development)

## Documentation

### User Guides
- **[Output Reference](Extras/Documentation/Output.md)** - Understanding output format, deduplication, and log levels
- **[Usage Guide](Extras/Documentation/Usage.md)** - Common workflows, filter patterns, and troubleshooting
- **[Performance Guide](Extras/Documentation/Performance.md)** - Execution times and optimization tips

### Developer Guides
- **[Development Guide](Extras/Documentation/Development.md)** - Architecture, building, testing, and contributing
- **[Engineering Principles](Extras/Guidelines/Principles.md)** - Design patterns and coding standards
- 

## License

MIT License - see [LICENSE.md](LICENSE.md) for details.
