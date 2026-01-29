# HomeDiagnostics

A Swift command-line tool for collecting and analyzing Apple Home and HomeKit logs on macOS.

## Overview

HomeDiagnostics helps diagnose issues with Apple Home by collecting logs from the macOS unified logging system and analyzing them for problems, with special support for Philips Hue devices.

## Building

```bash
cd ~/Developer/Projects/HomeDiagnostics
swift build -c release
```

The compiled binary will be at `.build/release/HomeDiagnostics`.

## Installation (Optional)

To install the tool for system-wide use:

```bash
swift build -c release
cp .build/release/HomeDiagnostics /usr/local/bin/home-diagnostics
```

## Usage

### Basic usage

Collect logs from the last 14 days (default):

```bash
.build/release/HomeDiagnostics
```

### Filter for Hue devices only

```bash
.build/release/HomeDiagnostics --hue-only --summary
```

### Include debug logs (verbose)

**Note**: Including debug logs can take several minutes to process, as the macOS unified logging system contains a large volume of debug-level messages.

```bash
.build/release/HomeDiagnostics --debug --hue-only
```

### Look back fewer days for faster results

```bash
.build/release/HomeDiagnostics --days 7 --summary
```

### Save output to a file

```bash
.build/release/HomeDiagnostics --days 14 --hue-only -o ~/Desktop/home-logs.txt
```

## Options

- `-d, --days <days>`: Number of days to look back (default: 14)
- `--debug`: Include debug-level logs (verbose, slower)
- `-o, --output <output>`: Save output to file instead of stdout
- `--hue-only`: Filter for Hue-related entries only
- `--summary`: Show summary statistics
- `-h, --help`: Show help information
- `--version`: Show version

## What It Collects

The tool collects logs from these subsystems:

- `com.apple.Home` - The Home app
- `com.apple.HomeKit` - The HomeKit framework
- `com.apple.homed` - The Home daemon

## Understanding the Output

### Summary Section

Shows:
- Total number of log entries found
- Count of errors, faults, and warnings
- Number of Hue-related entries
- Potentially problematic entries
- Breakdown by subsystem

### Problematic Entries Section

Displays log entries that may indicate issues:
- Errors and faults
- Messages containing "failed", "timeout", "unreachable", or "not responding"
- Each entry shows timestamp, log level, subsystem, and message

### All Entries Section (when not using --summary)

Shows every log entry collected, sorted chronologically.

## Performance Notes

- Without `--debug`: Usually completes in 10-30 seconds
- With `--debug`: Can take 2-5 minutes or more due to volume of debug logs
- Fewer days (`--days 7` or less) will be faster
- Using `--hue-only` reduces output size but doesn't speed up collection

## Troubleshooting

### The tool is very slow

- Try reducing the number of days: `--days 7` or `--days 3`
- Avoid using `--debug` unless you need detailed diagnostic information
- Be patient - the macOS log system can be slow when querying large time ranges

### No logs found

- Ensure the Home app has been running during the time period
- Try a longer time range: `--days 30`
- Check that you have Home devices set up in the Home app
- Make sure you're not filtering too aggressively (remove `--hue-only` to see all entries)

### Permission issues

The tool uses the standard `log show` command, which should work without special permissions. If you encounter permission issues, ensure you're running from a standard Terminal session.

## Example Session

```bash
# Quick check of recent Hue issues
.build/release/HomeDiagnostics --days 7 --hue-only --summary

# Full diagnostic output saved to file
.build/release/HomeDiagnostics --days 14 -o ~/Desktop/home-diagnostics.txt

# Deep dive with debug logs (be patient)
.build/release/HomeDiagnostics --days 3 --debug --hue-only -o ~/Desktop/debug-logs.txt
```

## Common Issues to Look For

When reviewing the output, look for:

1. **Timeout messages** - Devices not responding in time
2. **Connection failures** - Unable to reach device or bridge
3. **Authentication errors** - Issues with device credentials
4. **Network errors** - Problems communicating over the network
5. **Hue bridge issues** - Specific references to the Philips Hue bridge being unreachable

## Tips for Hue Issues

If you're experiencing Hue device problems:

1. Run: `.build/release/HomeDiagnostics --days 14 --hue-only --summary`
2. Look for entries mentioning:
   - "bridge" - Your Hue bridge connection
   - "timeout" - Devices not responding
   - "unreachable" - Network connectivity issues
3. Common fixes:
   - Restart the Hue bridge
   - Check your network connectivity
   - Remove and re-add problematic accessories in the Home app
   - Update Hue bridge firmware

## License

This tool is provided as-is for personal diagnostic use.
