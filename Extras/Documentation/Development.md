# Development Guide

This document covers architecture, building, testing, and contributing to HomeDiagnostics.

## Table of Contents

- [Architecture](#architecture)
- [Building](#building)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [Deduplication System](#deduplication-system)
- [Contributing](#contributing)
- [Dependencies](#dependencies)

## Architecture

### Overview

HomeDiagnostics is built as a Swift command-line tool using a modular package architecture:

- **Package-based design**: Core logic separated into `HomeDiagnosticsCore` package
- **Thin CLI layer**: Main executable handles argument parsing and I/O
- **JSON-based parsing**: Uses `log show --style json` for accurate metadata
- **Stream separation**: Analysis output to stdout, diagnostics to stderr
- **Sendable types**: Full Swift 6 strict concurrency support

### Component Diagram

```
┌─────────────────────────────────────┐
│   home-diagnostics (executable)     │
│   - Argument parsing                │
│   - I/O coordination                │
└──────────────┬──────────────────────┘
               │
               ├─→ HomeDiagnosticsCore Package
               │   ├─→ LogCollector (data source abstraction)
               │   │   ├─→ SystemLogDataSource (log show command)
               │   │   └─→ LogDataSource (protocol)
               │   │
               │   ├─→ LogEntry (data model)
               │   │   ├─→ normalizedMessage (pattern-based deduplication)
               │   │   └─→ deduplicationKey (grouping key)
               │   │
               │   ├─→ MessageSimilarity (token-based similarity)
               │   │   ├─→ significantTokens() (stop word filtering)
               │   │   ├─→ similarity() (Jaccard coefficient)
               │   │   └─→ groupBySimilarity() (clustering)
               │   │
               │   ├─→ LogAnalyzer (statistical analysis)
               │   │   └─→ analyze() (counts, grouping, filtering)
               │   │
               │   ├─→ OutputFormatter (presentation layer)
               │   │   ├─→ format() (main output)
               │   │   ├─→ formatSummary()
               │   │   ├─→ formatProblematicEntries()
               │   │   └─→ formatAllEntries()
               │   │
               │   └─→ Supporting Types
               │       ├─→ LogLevel (enum)
               │       ├─→ LogAnalysis (struct)
               │       ├─→ GroupedLogEntry (struct)
               │       └─→ TerminalColor (constants)
               │
               └─→ Dependencies
                   ├─→ ArgumentParser (CLI framework)
                   └─→ Subprocess (process execution)
```

### Data Flow

```
1. User Input
   └─→ ArgumentParser validates flags
       └─→ HomeDiagnostics.run()

2. Log Collection
   └─→ LogCollector.collectLogs()
       └─→ SystemLogDataSource.fetchLogs()
           └─→ Subprocess runs `log show --style json`
               └─→ Parse JSON → [LogEntry]

3. Analysis
   └─→ LogAnalyzer.analyze()
       └─→ Count by level/subsystem
       └─→ Filter problematic entries
       └─→ Return LogAnalysis

4. Formatting
   └─→ OutputFormatter.format()
       ├─→ formatSummary() (optional)
       ├─→ formatProblematicEntries() (with deduplication)
       └─→ formatAllEntries() (with deduplication)

5. Output
   └─→ Print to stdout (analysis)
   └─→ Print to stderr (diagnostics if --verbose)
```

### Key Design Decisions

#### JSON Parsing (Not Text Matching)

**Problem**: Text-based parsing of `log show` output was unreliable for log levels.

**Solution**: Use `--style json` for structured data with accurate metadata.

**Benefits**:
- Zero false positives on log level detection
- Accurate timestamp parsing
- Reliable subsystem identification
- Future-proof against format changes

#### Two-Phase Deduplication

**Phase 1: Pattern-Based Normalization** (Enabled)
- Replaces variable values with placeholders
- UUIDs → `<id>`, MACs → `<mac>`, numbers → `<n>`, etc.
- Fast: O(n) where n = number of entries
- Achieves 98.1% reduction on real-world data

**Phase 2: Token-Based Similarity** (Implemented, Not Enabled)
- Groups messages with similar significant words
- Uses Jaccard similarity coefficient
- Slower: O(n²) comparisons
- Available for future use if needed

**Why Phase 2 is disabled**: Phase 1 alone achieves 98.1% deduplication (target was 73%), making Phase 2 unnecessary for current use cases while avoiding O(n²) performance cost.

#### Package-Based Architecture

**Why packages over single file**:
- Faster incremental compilation
- Better test isolation (package test targets)
- Improved SwiftUI preview performance (if UI added later)
- Clearer module boundaries
- Easier to extract for reuse

## Building

### Requirements

- macOS 15.0+ (Sequoia or later)
- Swift 6.2+
- Xcode 16.0+ (for development)

### Debug Build

```bash
# Build package only (verify dependencies)
swift build --target HomeDiagnosticsCore

# Build full executable
swift build --target home-diagnostics

# Run directly
.build/debug/home-diagnostics --help
```

### Release Build

```bash
# Optimized build
swift build -c release --target home-diagnostics

# Executable location
.build/release/home-diagnostics
```

### Installing

```bash
# Copy to PATH
sudo cp .build/release/home-diagnostics /usr/local/bin/

# Or create alias
echo 'alias home-diagnostics="~/Developer/Projects/HomeDiagnostics/.build/debug/home-diagnostics"' >> ~/.zshrc
source ~/.zshrc
```

### Build Verification

After changes, verify both macOS and the core package:

```bash
# 1. Build package for macOS
swift build --target HomeDiagnosticsCore

# 2. Build full application
swift build

# 3. Run tests
swift test

# 4. Format check
swift format lint --recursive Sources Tests
```

## Testing

### Running Tests

```bash
# Run all tests
swift test

# Run specific suite
swift test --filter DeduplicationTests
swift test --filter MessageSimilarityTests

# Verbose output
swift test --verbose
```

### Test Structure

```
Tests/
└── HomeDiagnosticsTests/
    ├── DeduplicationTests.swift      (18 tests - normalization patterns)
    ├── MessageSimilarityTests.swift  (7 tests - token similarity)
    ├── LogParsingTests.swift         (parsing logic)
    ├── FilteringTests.swift          (filter functionality)
    ├── FormattingTests.swift         (output formatting)
    ├── AnalysisTests.swift           (statistical analysis)
    ├── IntegrationTests.swift        (end-to-end tests)
    └── MockLogDataSource.swift       (test doubles)
```

### Test Coverage

Current coverage: 49 tests across 7 suites

| Suite | Tests | Coverage |
|-------|-------|----------|
| DeduplicationTests | 18 | Pattern normalization, real-world cases |
| MessageSimilarityTests | 7 | Token extraction, similarity, grouping |
| LogParsingTests | 6 | JSON parsing, date handling |
| FilteringTests | 5 | Plain text, regex, errors-only |
| FormattingTests | 4 | Color codes, date format, metadata |
| AnalysisTests | 3 | Counting, grouping, statistics |
| IntegrationTests | 6 | End-to-end workflows |

### Writing Tests

Follow Swift Testing conventions:

```swift
import Testing
@testable import HomeDiagnosticsCore

@Suite("My Test Suite")
struct MyTests {
  
  /// Tests the specific functionality X.
  @Test("Description of what is being tested")
  func testSomething() async throws {
    let result = functionUnderTest()
    #expect(result == expectedValue)
  }
}
```

**Guidelines**:
- Use descriptive test names
- Document what is being tested in doc comments
- Test edge cases and error conditions
- Use `@testable import` sparingly (prefer public API testing)
- Add tests for any new functionality
- Update tests when fixing bugs

## Project Structure

```
HomeDiagnostics/
├── Sources/
│   ├── HomeDiagnostics/              # Main executable
│   │   └── main.swift                # CLI entry point
│   │
│   └── HomeDiagnosticsCore/          # Core package
│       ├── LogCollector.swift        # Log collection orchestration
│       ├── LogEntry.swift            # Log data model & normalization
│       ├── LogLevel.swift            # Log severity enum
│       ├── LogAnalyzer.swift         # Statistical analysis
│       ├── LogAnalysis.swift         # Analysis result types
│       ├── OutputFormatter.swift     # Output generation
│       ├── MessageSimilarity.swift   # Token-based similarity
│       ├── SystemLogDataSource.swift # System log integration
│       ├── LogDataSource.swift       # Data source protocol
│       └── TerminalColor.swift       # ANSI color codes
│
├── Tests/
│   └── HomeDiagnosticsTests/         # Test suite
│       └── (test files)
│
├── Extras/
│   └── Documentation/                # Extended documentation
│       ├── Examples.md               # Usage examples & output reference
│       ├── Development.md            # This file
│       └── Principles Glossary.md    # Engineering principles
│
├── Package.swift                     # Swift Package Manager manifest
├── README.md                         # Main documentation
└── AGENTS.md                         # AI coding agent guidelines
```

## Deduplication System

### Phase 1: Pattern-Based Normalization

Located in: `Sources/HomeDiagnosticsCore/LogEntry.swift:68-131`

**Normalization Pipeline**:

```swift
var normalizedMessage: String {
  var normalized = message

  // 1. Structural patterns (most specific first)
  normalized = normalized.replacing(prefixPattern, with: "[<prefix>]")
  normalized = normalized.replacing(objectPattern, with: "<obj>")

  // 2. Variable values
  normalized = normalized.replacing(uuidPattern, with: "<id>")
  normalized = normalized.replacing(macPattern, with: "<mac>")
  normalized = normalized.replacing(durationPattern, with: "<duration>")
  normalized = normalized.replacing(timestampPattern, with: "<timestamp>")
  normalized = normalized.replacing(hexPattern, with: "<addr>")
  normalized = normalized.replacing(numberPattern, with: "<n>")

  // 3. Boolean and domain normalization
  normalized = normalized.replacing(boolPattern, with: "<bool>")
  normalized = normalized.replacing(errorDomainPattern, with: "Error Domain=<domain>")

  // 4. Whitespace normalization
  normalized = normalized.replacing(multiSpacePattern, with: " ")
  normalized = normalized.trimmingCharacters(in: .whitespaces)

  return normalized
}
```

**Pattern Table**:

| Pattern | Regex | Replacement | Example |
|---------|-------|-------------|---------|
| Bracket prefix | `/\[[0-9A-Fa-f-]+\/[0-9A-Fa-f:]+\+\d+\/(YES\|NO)\]/` | `[<prefix>]` | `[UUID/MAC+1/NO]` → `[<prefix>]` |
| Object description | `/<[A-Z][A-Za-z0-9]*:\s*0x[0-9A-Fa-f]+>/` | `<obj>` | `<HMFMessage: 0x123>` → `<obj>` |
| UUID | `/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-...{12}/` | `<id>` | `A1B2-C3D4-...` → `<id>` |
| MAC address | `/[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:...{2}/` | `<mac>` | `AA:BB:CC:DD:EE:FF` → `<mac>` |
| Duration | `/\d+\.?\d*\s*(seconds?\|ms\|...)/` | `<duration>` | `1.5 seconds` → `<duration>` |
| Timestamp | `/\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+/` | `<timestamp>` | `2026-01-29 10:30:15.123` → `<timestamp>` |
| Hex address | `/0x[0-9A-Fa-f]+/` | `<addr>` | `0xdeadbeef` → `<addr>` |
| Number | `/\b\d+\.?\d*\b/` | `<n>` | `123` or `45.67` → `<n>` |
| Boolean | `/\b(YES\|NO\|true\|false)\b/` | `<bool>` | `YES` → `<bool>` |
| Error domain | `/Error Domain=[A-Za-z][A-Za-z0-9]*/` | `Error Domain=<domain>` | `Error Domain=HMErrorDomain` → `Error Domain=<domain>` |

**Deduplication Key**:

```swift
var deduplicationKey: String {
  "\(subsystem)|\(level.rawValue)|\(normalizedMessage)"
}
```

Groups entries by: subsystem + level + normalized message

### Phase 2: Token-Based Similarity

Located in: `Sources/HomeDiagnosticsCore/MessageSimilarity.swift`

**Components**:

1. **Stop Word Filtering**: Removes common words (a, the, is, are, etc.)
2. **Token Extraction**: Splits on non-alphanumeric, filters short words and placeholders
3. **Jaccard Similarity**: `|A ∩ B| / |A ∪ B|`
4. **Grouping**: Clusters messages with similarity ≥ threshold (default: 0.75)

**Algorithm**:

```swift
func groupBySimilarity(_ entries: [LogEntry], threshold: Double) -> [[LogEntry]] {
  // 1. Group by normalized message (Phase 1)
  let messageGroups = Dictionary(grouping: entries) { $0.normalizedMessage }
  
  // 2. For each unique message
  for message1 in uniqueMessages {
    // 3. Find similar messages
    for message2 in remainingMessages {
      if similarity(message1, message2) >= threshold {
        // 4. Merge groups
        merge(group1, group2)
      }
    }
  }
  
  return groups
}
```

**Status**: Implemented and tested, but not enabled in production due to O(n²) performance cost.

### Performance Comparison

| Approach | Time Complexity | Real-world Performance (3766 entries) | Reduction |
|----------|----------------|--------------------------------------|-----------|
| Phase 1 only | O(n) | ~2 seconds | 98.1% (3765 → 71) |
| Phase 1 + Phase 2 | O(n²) | ~2 minutes (timeout) | Unknown (not measured) |

### Pull Request Checklist

Before submitting a pull request:

- [ ] Code builds without warnings (`swift build`)
- [ ] All tests pass (`swift test`)
- [ ] New tests added for new functionality
- [ ] Code formatted (`swift format --in-place --recursive Sources Tests`)
- [ ] Documentation updated (README, usage guides, inline comments)
- [ ] No secrets or credentials in code
- [ ] Commit messages follow format guidelines

### Commit Message Format

Use conventional commit format:

```
<type>: <short description>

<detailed description>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring without behavior change
- `perf`: Performance improvements
- `chore`: Build, dependencies, or tooling changes

**Example:**

```
feat: add MAC address normalization to deduplication

Enhances Phase 1 normalization to replace MAC addresses with <mac>
placeholder, improving deduplication of device-specific messages.

Addresses #123
```

### Code Review Guidelines

When reviewing code:

1. **Correctness**: Does it work as intended?
2. **Tests**: Are there adequate tests?
3. **Clarity**: Is the code easy to understand?
4. **Performance**: Are there obvious performance issues?
5. **Documentation**: Are changes documented?
6. **Style**: Does it follow project conventions?

### Engineering Principles

See [Principles Glossary](Principles Glossary.md) for:
- Code organization patterns
- Error handling strategies
- Testing philosophy
- Performance considerations
- Decision-making heuristics

## Dependencies

### Direct Dependencies

#### swift-argument-parser (1.3.0+)

**Purpose**: Command-line argument parsing  
**Repository**: https://github.com/apple/swift-argument-parser  
**License**: Apache 2.0

**Usage**:
```swift
@main
struct HomeDiagnostics: AsyncParsableCommand {
  @Option(name: .shortAndLong, help: "Number of days...")
  var days: Int?
  
  @Flag(name: .long, help: "Enable...")
  var dedupe: Bool = false
}
```

#### swift-subprocess (0.0.1+)

**Purpose**: Safe process execution  
**Repository**: https://github.com/swiftlang/swift-subprocess  
**License**: Apache 2.0

**Usage**:
```swift
import Subprocess

let result = try await Subprocess.run(
  .named("log"),
  arguments: ["show", "--style", "json", ...]
)
```

### Approved Dependencies

Only dependencies listed in `Extras/Documentation/Approved Dependencies.md` may be added to the project.

Current approved list:
- swift-argument-parser
- swift-subprocess

**To propose a new dependency**: Open an issue with justification.

## Development Workflow

### Making Changes

```bash
# 1. Create feature branch
git checkout -b feature/my-feature

# 2. Make changes
# ...edit files...

# 3. Format code
swift format --in-place --recursive Sources Tests

# 4. Build and test
swift build
swift test

# 5. Commit
git add .
git commit -m "feat: add my feature"

# 6. Push
git push origin feature/my-feature
```

### Testing Changes

```bash
# Unit tests
swift test

# Manual testing
.build/debug/home-diagnostics --days 1 --dedupe

# Performance testing (large dataset)
time .build/debug/home-diagnostics --days 30 --dedupe

# Integration testing (real environment)
.build/debug/home-diagnostics --hours 6 --errors-only
```

### Debugging

```bash
# Verbose mode (diagnostic output)
.build/debug/home-diagnostics --verbose --days 1

# Xcode debugging
open Package.swift  # Opens in Xcode
# Set breakpoints, run scheme: home-diagnostics
```

## Troubleshooting Development Issues

### Build Failures

**"Cannot find type 'X' in scope"**
- Check Package.swift dependencies
- Ensure target has correct dependencies
- Run `swift package resolve`

**"Module 'X' not found"**
- Clean build: `swift package clean`
- Rebuild: `swift build`

### Test Failures

**"Test timed out"**
- Check for blocking operations
- Use `async/await` properly
- Increase timeout if legitimately slow

**"LSP errors in test files"**
- Usually transient, ignore if tests pass
- Try: `swift package clean && swift build`

### Performance Issues

**Slow log collection**
- Reduce time window (`--days` or `--hours`)
- Avoid `--detailed` (includes debug logs)
- Use `--errors-only` to filter early

**Slow deduplication**
- Phase 1 should be fast (<5 seconds)
- If slow, check regex patterns aren't backtracking
- Profile with Instruments if needed

## Contributing

### Getting Started

Contributions are welcome! Before contributing:

1. Read this development guide
2. Review the [Engineering Principles](Principles Glossary.md)
3. Follow the Swift coding standards in `AGENTS.md`
4. Ensure all tests pass

### Contribution Workflow

1. **Fork and clone** the repository
2. **Create a feature branch**: `git checkout -b feature/my-feature`
3. **Make changes** following the guidelines below
4. **Add tests** for new functionality
5. **Run tests**: `swift test`
6. **Format code**: `swift format --in-place --recursive Sources Tests`
7. **Commit changes**: Follow commit message format below
8. **Push to your fork**: `git push origin feature/my-feature`
9. **Open a pull request** with clear description

### Code Guidelines

1. **Follow Swift 6 conventions**: See `AGENTS.md` for detailed coding standards
2. **Write tests**: All new functionality must have test coverage
3. **Document code**: Use `///` doc comments for all public APIs and implementations
4. **Format code**: Run `swift format` before committing
5. **Update docs**: Keep README and guide docs in sync with changes

### Testing Requirements

- All new code must have unit tests
- Use Swift Testing framework (not XCTest)
- Maintain or improve test coverage
- Test edge cases and error conditions
- Add integration tests for user-facing features

### Documentation Requirements

- Update relevant documentation files
- Add inline code comments for complex logic
- Update README.md if user-facing behavior changes
- Add examples to Usage.md for new features
- Update Output.md if output format changes
