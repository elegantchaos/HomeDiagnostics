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

  /// Optional filter for message content (plain text or regex)
  public let filter: String?


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
    filter: String? = nil,
    substituteNames: Bool = true
  ) {
    self.analysis = analysis
    self.showSummary = showSummary
    self.deduplicate = deduplicate
    self.errorsOnly = errorsOnly
    self.filter = filter
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
    if substituteNames && !analysis.uuidNameResolver.namedUUIDs.isEmpty {
      output += formatUUIDSummary(resolver: analysis.uuidNameResolver)
    }

    return output
  }
}

// MARK: - Private Formatting Helpers

private extension OutputFormatter {
  /// Checks if text matches a filter pattern (plain text or regex).
  /// Attempts as regex first; falls back to localized string search if invalid.
  func matchesFilter(_ text: String, pattern: String) -> Bool {
    do {
      let regex = try Regex(pattern).ignoresCase()
      return text.contains(regex)
    } catch {
      return text.localizedStandardContains(pattern)
    }
  }

  /// Formats the summary statistics section.
  ///
  /// Generates a text summary showing total counts, severity breakdowns,
  /// and counts by subsystem. Includes unique entry count when deduplication
  /// is enabled.
  ///
  /// - Returns: Formatted summary section.
  func formatSummary() -> String {
    // Apply filtering for display summaries as well
    let filteredEntries = analysis.allEntries.filter { entry in
      let passesError = !errorsOnly || entry.isProblematic
      let passesFilter = filter == nil || matchesFilter(entry.message, pattern: filter!)
      return passesError && passesFilter
    }
    let filteredProblematic = filteredEntries.filter { $0.isProblematic }

    var summary = "SUMMARY\n"
    summary += "=======\n\n"
    summary += "Total log entries: \(filteredEntries.count)\n"
    summary += "Errors: \(filteredEntries.filter { $0.level == .error }.count)\n"
    summary += "Faults: \(filteredEntries.filter { $0.level == .fault }.count)\n"
    summary += "Warnings: \(filteredEntries.filter { $0.level == .warning }.count)\n"
    summary += "Potentially problematic: \(filteredProblematic.count)\n"

    if deduplicate {
      let uniqueCount = groupEntries(filteredEntries).count
      summary += "Unique entry types: \(uniqueCount)\n"
    }

    summary += "\nEntries by subsystem:\n"
    let subsystemCounts = Dictionary(grouping: filteredEntries, by: { $0.subsystem }).mapValues { $0.count }
    for (subsystem, count) in subsystemCounts.sorted(by: { $0.value > $1.value }) {
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
      case .info, .debug, .default:
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

    // Filter problematic entries further by output-stage filter
    let filteredProblematic = analysis.problematicEntries.filter { entry in
      filter == nil || matchesFilter(entry.message, pattern: filter!)
    }

    if deduplicate {
      let grouped = groupEntries(filteredProblematic)
      output +=
        "Showing \(grouped.count) unique problematic entry types (out of \(filteredProblematic.count) total)\n\n"

      for group in grouped {
        let color = colorForLevel(group.example.level)

        // Metadata line
        output += formatMetadataLineGrouped(group)
        output += "\n"

        // Message in bold color with UUID substitution
        let message =
          substituteNames
          ? analysis.uuidNameResolver.substitute(in: group.example.message)
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
        let message =
          substituteNames
          ? analysis.uuidNameResolver.substitute(in: entry.message)
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

    // Filter entries based on filter and errorsOnly flags
    let filteredEntries = analysis.allEntries.filter { entry in
      let passesError = !errorsOnly || entry.isProblematic
      let passesFilter = filter == nil || matchesFilter(entry.message, pattern: filter!)
      return passesError && passesFilter
    }

    if deduplicate {
      let grouped = groupEntries(filteredEntries)
      output +=
        "Showing \(grouped.count) unique entry types (out of \(filteredEntries.count) total)\n\n"

      for group in grouped {
        let color = colorForLevel(group.example.level)

        // Metadata line
        output += formatMetadataLineGrouped(group)
        output += "\n"

        // Message with color if error/warning, with UUID substitution
        let message =
          substituteNames
          ? analysis.uuidNameResolver.substitute(in: group.example.message)
          : group.example.message
        if !color.isEmpty {
          output +=
            "\(color)\(TerminalColor.bold)\(message)\(TerminalColor.reset)\n\n"
        } else {
          output += "\(message)\n\n"
        }
      }
    } else {
      for entry in filteredEntries {
        let color = colorForLevel(entry.level)

        // Metadata line
        output += formatMetadataLineEntry(entry)
        output += "\n"

        // Message with color if error/warning, with UUID substitution
        let message =
          substituteNames
          ? analysis.uuidNameResolver.substitute(in: entry.message)
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
  /// Shows all UUIDs that were assigned names during log analysis, organized
  /// by home. For each home, displays the home name followed by devices and
  /// action sets that belong to it. Entities not associated with any home are
  /// Formats the UUID naming summary section.
  ///
  /// Shows all UUIDs that were assigned names during log analysis, organized
  /// by home. For each home, displays the home name followed by devices and
  /// action sets that belong to it. Entities not associated with any home are
  /// shown in a separate "Unknown Home" section.
  ///
  /// - Parameter resolver: The entity resolver with all extracted names and associations.
  /// - Returns: Formatted UUID summary section.
  func formatUUIDSummary(resolver: EntityResolver) -> String {
    var output = "UUID NAMING SUMMARY\n"
    output += "===================\n\n"
    output += "Discovered \(resolver.allEntities.count) entities.\n"
    output += "Discovered \(resolver.namedUUIDs.count) named UUID(s):\n\n"

    let (homeToEntities, _, unknownHomeEntities) = resolver.entitiesByHome()

    let homes = resolver.allEntities.filter { $0.type == .home }
    let sortedHomes = homes.sorted { lhs, rhs in
      let lhsName = lhs.name.lowercased()
      let rhsName = rhs.name.lowercased()
      if lhsName != rhsName {
        return lhsName < rhsName
      }
      let lhsID = lhs.uuids.sorted().first ?? ""
      let rhsID = rhs.uuids.sorted().first ?? ""
      return lhsID < rhsID
    }

    for homeEntity in sortedHomes {
      let homeUUIDs = homeEntity.uuids.sorted()
      let primaryUUID = homeUUIDs.first ?? ""
      let homePrefix = String(primaryUUID.prefix(8))
      let aliasPrefixes = homeUUIDs.dropFirst().map { String($0.prefix(8)) }

      if !homeEntity.name.isEmpty {
        output += "\(TerminalColor.bold)\(homeEntity.name)\(TerminalColor.reset) "
        output += "\(TerminalColor.gray)(ID: \(homePrefix)...)\(TerminalColor.reset)"
        if !aliasPrefixes.isEmpty {
          output += " \(TerminalColor.gray)[Aliases: \(aliasPrefixes.joined(separator: ", "))]\(TerminalColor.reset)"
        }
        if let matterID = resolver.matterID(for: primaryUUID) {
          output += " \(TerminalColor.gray)[Matter: \(matterID)]\(TerminalColor.reset)"
        }
        output += "\n"
      } else {
        output += "\(TerminalColor.bold)Home\(TerminalColor.reset) "
        output += "\(TerminalColor.gray)(ID: \(homePrefix)...)\(TerminalColor.reset)\n"
      }

      var entityUUIDs: Set<String> = []
      for homeUUID in homeUUIDs {
        if let childUUIDs = homeToEntities[homeUUID] {
          entityUUIDs.formUnion(childUUIDs)
        }
      }

      if !entityUUIDs.isEmpty {
        for entityUUID in entityUUIDs {
          guard let entity = resolver.entity(for: entityUUID) else { continue }
          let typeLabel = entity.type == .actionSet ? "Scene" : "Device"
          let prefix = String(entityUUID.prefix(8))

          output += "  \(TerminalColor.gray)[\(typeLabel)]\(TerminalColor.reset) "
          output += "\(TerminalColor.gray)\(prefix)...\(TerminalColor.reset) → "
          output += entity.name

          if let matterID = resolver.matterID(for: entityUUID) {
            output += " \(TerminalColor.gray)[Matter: \(matterID)]\(TerminalColor.reset)"
          }
          output += "\n"
        }
      }

      output += "\n"
    }

    // Display entities with unknown homes
    if !unknownHomeEntities.isEmpty {
      output += "\(TerminalColor.bold)Unknown Home\(TerminalColor.reset)\n"

      for entityUUID in unknownHomeEntities {
        guard let entity = resolver.entity(for: entityUUID) else { continue }
        let typeLabel: String
        switch entity.type {
          case .actionSet:
            typeLabel = "Scene"
          case .device:
            typeLabel = "Device"
          default:
            typeLabel = "Unknown"
        }
        let prefix = String(entityUUID.prefix(8))

        output += "  \(TerminalColor.gray)[\(typeLabel)]\(TerminalColor.reset) "
        output += "\(TerminalColor.gray)\(prefix)...\(TerminalColor.reset) → "
        output += entity.name
        output += "\n"
      }
    }

    return output
  }
}
