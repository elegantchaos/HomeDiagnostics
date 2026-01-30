import Foundation

/// Formats log analysis results for terminal output with colors and grouping.
///
/// Takes `LogAnalysis` results and produces formatted text output with ANSI
/// color codes for terminal display. Supports summary-only mode, deduplication,
/// and errors-only mode. Handles both problematic entries and full log listings.
public struct OutputFormatter {
  /// The log analysis results to be formatted.
  public let analysis: LogAnalysis

  /// Whether to show only the summary section.
  public let showSummary: Bool

  /// Whether to deduplicate similar log entries.
  public let deduplicate: Bool

  /// Whether errors-only mode is active.
  ///
  /// When `true`, skips the PROBLEMATIC ENTRIES section since it would
  /// be identical to the ALL ENTRIES section (which already filters to errors).
  public let errorsOnly: Bool

  /// Whether to substitute UUIDs with human-readable names.
  ///
  /// When `false`, UUIDs are left as-is in the output and the UUID naming
  /// summary section is omitted.
  public let substituteNames: Bool

  /// Creates a new output formatter with specified options.
  ///
  /// - Parameters:
  ///   - analysis: The analysis results to format.
  ///   - showSummary: Whether to show only the summary.
  ///   - deduplicate: Whether to group duplicate entries.
  ///   - errorsOnly: Whether errors-only mode is active.
  ///   - substituteNames: Whether to substitute UUIDs with names (default: true).
  public init(
    analysis: LogAnalysis,
    showSummary: Bool,
    deduplicate: Bool,
    errorsOnly: Bool,
    substituteNames: Bool = true
  ) {
    self.analysis = analysis
    self.showSummary = showSummary
    self.deduplicate = deduplicate
    self.errorsOnly = errorsOnly
    self.substituteNames = substituteNames
  }

  /// Generates formatted output from the analysis results.
  ///
  /// Produces a multi-section string with optional summary, problematic entries
  /// section, full log listing, and UUID naming summary. Output includes ANSI
  /// color codes for terminal display.
  ///
  /// - Returns: Formatted string ready for terminal output.
  public func format() -> String {
    var output = ""

    if showSummary || analysis.totalEntries < 100 {
      output += formatSummary()
      output += "\n\n"
    }

    // Skip PROBLEMATIC ENTRIES section when using --errors-only
    // (it would be identical to ALL ENTRIES)
    if analysis.problematicCount > 0 && !errorsOnly {
      output += formatProblematicEntries()
      output += "\n\n"
    }

    if !showSummary {
      output += formatAllEntries()
      output += "\n\n"
    }

    // Add UUID naming summary at the end (only if substitution is enabled)
    if substituteNames {
      let namedUUIDs = analysis.uuidNamer.namedUUIDs()
      if !namedUUIDs.isEmpty {
        output += formatUUIDSummary(namedUUIDs: namedUUIDs)
      }
    }

    return output
  }
}

// MARK: - Private Formatting Helpers

private extension OutputFormatter {
  /// Formats the summary statistics section.
  ///
  /// Generates a text summary showing total counts, severity breakdowns,
  /// and counts by subsystem. Includes unique entry count when deduplication
  /// is enabled.
  ///
  /// - Returns: Formatted summary section.
  func formatSummary() -> String {
    var summary = "SUMMARY\n"
    summary += "=======\n\n"
    summary += "Total log entries: \(analysis.totalEntries)\n"
    summary += "Errors: \(analysis.errorCount)\n"
    summary += "Faults: \(analysis.faultCount)\n"
    summary += "Warnings: \(analysis.warningCount)\n"
    summary += "Potentially problematic: \(analysis.problematicCount)\n"

    if deduplicate {
      let uniqueCount = groupEntries(analysis.allEntries).count
      summary += "Unique entry types: \(uniqueCount)\n"
    }

    summary += "\nEntries by subsystem:\n"
    for (subsystem, count) in analysis.subsystemCounts.sorted(by: { $0.value > $1.value }) {
      summary += "  \(subsystem): \(count)\n"
    }

    return summary
  }

  /// Groups log entries by their deduplication key.
  ///
  /// Uses Phase 1 pattern-based normalization to group entries with identical
  /// normalized messages. Creates `GroupedLogEntry` instances containing
  /// occurrence counts and time ranges. Groups are sorted by occurrence count (descending).
  ///
  /// Note: Phase 2 (token-based similarity) is available but not enabled here due to
  /// performance considerations with large datasets. Phase 1 normalization (pattern replacement
  /// for UUIDs, MACs, addresses, numbers, etc.) provides sufficient deduplication for most cases.
  ///
  /// - Parameter entries: Log entries to group.
  /// - Returns: Array of grouped entries sorted by frequency.
  func groupEntries(_ entries: [LogEntry]) -> [GroupedLogEntry] {
    // Phase 1: Group by exact deduplication key (normalized message)
    let grouped = Dictionary(grouping: entries) { $0.deduplicationKey }

    return grouped.map { _, entries in
      let sorted = entries.sorted { $0.timestamp < $1.timestamp }
      return GroupedLogEntry(
        example: sorted[0],
        count: entries.count,
        firstSeen: sorted[0].timestamp,
        lastSeen: sorted[sorted.count - 1].timestamp
      )
    }.sorted { $0.count > $1.count }
  }

  /// Formats a date as a compact timestamp string.
  ///
  /// Produces a short date/time string without year or seconds (MM/dd HH:mm)
  /// to save horizontal space in terminal output.
  ///
  /// - Parameter date: The date to format.
  /// - Returns: Compact timestamp string (e.g., "01/29 14:30").
  func formatCompactDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM/dd HH:mm"
    return formatter.string(from: date)
  }

  /// Returns the ANSI color code for a log level.
  ///
  /// Maps log severity levels to terminal colors: red for errors/faults,
  /// yellow for warnings, no color for info/debug.
  ///
  /// - Parameter level: The log severity level.
  /// - Returns: ANSI color escape sequence, or empty string for info/debug.
  func colorForLevel(_ level: LogLevel) -> String {
    switch level {
      case .error, .fault:
        return TerminalColor.red
      case .warning:
        return TerminalColor.yellow
      case .info, .debug:
        return ""
    }
  }

  /// Formats a subsystem identifier by removing the "com.apple." prefix.
  ///
  /// Shortens subsystem names for more compact output. For example,
  /// "com.apple.HomeKit" becomes "HomeKit".
  ///
  /// - Parameter subsystem: The full subsystem identifier.
  /// - Returns: Shortened subsystem name.
  func formatSubsystem(_ subsystem: String) -> String {
    if subsystem.hasPrefix("com.apple.") {
      return String(subsystem.dropFirst("com.apple.".count))
    }
    return subsystem
  }

  /// Formats the metadata line for a grouped log entry.
  ///
  /// Creates a gray-colored metadata line showing occurrence count, time range,
  /// log level (if not Info), and subsystem. Used when deduplication is enabled.
  ///
  /// - Parameter group: The grouped log entry.
  /// - Returns: Formatted metadata line with ANSI color codes.
  func formatMetadataLineGrouped(_ group: GroupedLogEntry) -> String {
    var line = "\(TerminalColor.gray)[\(group.count)x] "
    line += "[\(formatCompactDate(group.firstSeen))"
    if group.count > 1 {
      line += " - \(formatCompactDate(group.lastSeen))"
    }
    line += "]"

    // Only show level if not Info
    if group.example.level != .info {
      line += " [\(group.example.level.rawValue)]"
    }

    line += " [\(formatSubsystem(group.example.subsystem))]"
    line += "\(TerminalColor.reset)"
    return line
  }

  /// Formats the metadata line for a single log entry.
  ///
  /// Creates a gray-colored metadata line showing timestamp, log level
  /// (if not Info), and subsystem. Used when deduplication is disabled.
  ///
  /// - Parameter entry: The log entry.
  /// - Returns: Formatted metadata line with ANSI color codes.
  func formatMetadataLineEntry(_ entry: LogEntry) -> String {
    var line = "\(TerminalColor.gray)[\(formatCompactDate(entry.timestamp))]"

    // Only show level if not Info
    if entry.level != .info {
      line += " [\(entry.level.rawValue)]"
    }

    line += " [\(formatSubsystem(entry.subsystem))]"
    line += "\(TerminalColor.reset)"
    return line
  }

  /// Formats the problematic entries section.
  ///
  /// Generates output showing all entries identified as problematic (errors,
  /// faults, or messages with failure keywords). Groups entries if deduplication
  /// is enabled. Uses colored, bold text for messages. Substitutes UUIDs with
  /// human-readable names when available.
  ///
  /// - Returns: Formatted problematic entries section.
  func formatProblematicEntries() -> String {
    var output = "PROBLEMATIC ENTRIES\n"
    output += "===================\n\n"

    if deduplicate {
      let grouped = groupEntries(analysis.problematicEntries)
      output +=
        "Showing \(grouped.count) unique problematic entry types (out of \(analysis.problematicCount) total)\n\n"

      for group in grouped {
        let color = colorForLevel(group.example.level)

        // Metadata line
        output += formatMetadataLineGrouped(group)
        output += "\n"

        // Message in bold color with UUID substitution
        let message = substituteNames
          ? analysis.uuidNamer.substitute(in: group.example.message)
          : group.example.message
        output += "\(color)\(TerminalColor.bold)\(message)\(TerminalColor.reset)\n\n"
      }
    } else {
      for entry in analysis.problematicEntries {
        let color = colorForLevel(entry.level)

        // Metadata line
        output += formatMetadataLineEntry(entry)
        output += "\n"

        // Message in bold color with UUID substitution
        let message = substituteNames
          ? analysis.uuidNamer.substitute(in: entry.message)
          : entry.message
        output += "\(color)\(TerminalColor.bold)\(message)\(TerminalColor.reset)\n\n"
      }
    }

    return output
  }

  /// Formats the complete log entries section.
  ///
  /// Generates output showing all log entries (or all entries of a filtered
  /// subset). Groups entries if deduplication is enabled. Uses colored, bold
  /// text for error/warning messages. Substitutes UUIDs with human-readable
  /// names when available.
  ///
  /// - Returns: Formatted complete entries section.
  func formatAllEntries() -> String {
    var output = "ALL ENTRIES\n"
    output += "===========\n\n"

    if deduplicate {
      let grouped = groupEntries(analysis.allEntries)
      output +=
        "Showing \(grouped.count) unique entry types (out of \(analysis.totalEntries) total)\n\n"

      for group in grouped {
        let color = colorForLevel(group.example.level)

        // Metadata line
        output += formatMetadataLineGrouped(group)
        output += "\n"

        // Message with color if error/warning, with UUID substitution
        let message = substituteNames
          ? analysis.uuidNamer.substitute(in: group.example.message)
          : group.example.message
        if !color.isEmpty {
          output +=
            "\(color)\(TerminalColor.bold)\(message)\(TerminalColor.reset)\n\n"
        } else {
          output += "\(message)\n\n"
        }
      }
    } else {
      for entry in analysis.allEntries {
        let color = colorForLevel(entry.level)

        // Metadata line
        output += formatMetadataLineEntry(entry)
        output += "\n"

        // Message with color if error/warning, with UUID substitution
        let message = substituteNames
          ? analysis.uuidNamer.substitute(in: entry.message)
          : entry.message
        if !color.isEmpty {
          output += "\(color)\(TerminalColor.bold)\(message)\(TerminalColor.reset)\n\n"
        } else {
          output += "\(message)\n\n"
        }
      }
    }

    return output
  }

  /// Formats the UUID naming summary section.
  ///
  /// Shows all UUIDs that were assigned names during log analysis, grouped
  /// by type (Home, Device, Action Set, Unknown). Displays each UUID's first
  /// 8 characters followed by names discovered for it.
  ///
  /// - Parameter namedUUIDs: Array of UUID-to-entities mappings with type information.
  /// - Returns: Formatted UUID summary section.
  func formatUUIDSummary(
    namedUUIDs: [(uuid: String, entities: Set<NamedEntity>, primaryType: NameType)]
  ) -> String {
    var output = "UUID NAMING SUMMARY\n"
    output += "===================\n\n"
    output += "Discovered \(namedUUIDs.count) named UUID(s):\n\n"

    // Group by type
    var currentType: NameType? = nil

    for (uuid, entities, primaryType) in namedUUIDs {
      // Print type header when type changes
      if currentType != primaryType {
        if currentType != nil {
          output += "\n"
        }
        output += "\(TerminalColor.bold)\(primaryType.rawValue)s:\(TerminalColor.reset)\n"
        currentType = primaryType
      }

      let sortedNames = entities.map { $0.name }.sorted()
      let prefix = String(uuid.prefix(8))
      output += "  \(TerminalColor.gray)\(prefix)...\(TerminalColor.reset) → "
      output += sortedNames.joined(separator: " / ")
      output += "\n"
    }

    return output
  }
}
