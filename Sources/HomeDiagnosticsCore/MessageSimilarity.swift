import Foundation

/// Provides token-based similarity detection for log messages.
///
/// Uses Jaccard similarity coefficient to determine if two messages are similar
/// enough to be grouped together. Extracts significant tokens from messages by
/// filtering out common stop words and focuses on meaningful content words.
public struct MessageSimilarity: Sendable {

  /// Common stop words to ignore when calculating similarity.
  ///
  /// These are frequently occurring words that don't contribute to the semantic
  /// meaning of error messages (articles, prepositions, common verbs, etc.).
  private static let stopWords: Set<String> = [
    // Articles
    "a", "an", "the",
    // Prepositions
    "in", "on", "at", "to", "for", "of", "with", "from", "by", "as",
    // Common verbs
    "is", "are", "was", "were", "be", "been", "being",
    "has", "have", "had",
    "do", "does", "did",
    // Pronouns
    "i", "you", "he", "she", "it", "we", "they",
    "this", "that", "these", "those",
    // Conjunctions
    "and", "or", "but", "if",
    // Common adverbs
    "not", "no", "yes",
    // Other common words
    "can", "will", "would", "could", "should",
  ]

  /// Extracts significant tokens from a message for similarity comparison.
  ///
  /// Tokenizes the message into words, converts to lowercase, removes stop words,
  /// and filters out tokens that are too short or consist only of placeholders.
  /// For testing purposes only.
  ///
  /// - Parameter message: The message to tokenize.
  /// - Returns: A set of significant tokens.
  public static func significantTokens(from message: String) -> Set<String> {
    // Split on whitespace and punctuation
    let words = message.components(separatedBy: CharacterSet.alphanumerics.inverted)

    // Filter and normalize
    let tokens = words
      .map { $0.lowercased() }
      .filter { word in
        // Must be at least 2 characters
        guard word.count >= 2 else { return false }

        // Skip pure numbers
        if word.allSatisfy({ $0.isNumber }) {
          return false
        }

        // Skip stop words
        guard !stopWords.contains(word) else { return false }

        // Skip pure placeholder tokens (like "n", "id", "mac", etc.)
        guard !["n", "id", "mac", "addr", "obj", "bool", "domain", "prefix", "private"].contains(
          word) else { return false }

        return true
      }

    return Set(tokens)
  }

  /// Calculates the Jaccard similarity coefficient between two messages.
  ///
  /// The Jaccard similarity is defined as the size of the intersection divided by
  /// the size of the union of two sets. Returns a value between 0.0 (no similarity)
  /// and 1.0 (identical sets).
  ///
  /// - Parameters:
  ///   - msg1: The first message to compare.
  ///   - msg2: The second message to compare.
  /// - Returns: A similarity score between 0.0 and 1.0.
  public static func similarity(between msg1: String, and msg2: String) -> Double {
    let tokens1 = significantTokens(from: msg1)
    let tokens2 = significantTokens(from: msg2)

    // Handle edge case: both messages have no significant tokens
    if tokens1.isEmpty && tokens2.isEmpty {
      return 1.0
    }

    // Handle edge case: one message has no significant tokens
    if tokens1.isEmpty || tokens2.isEmpty {
      return 0.0
    }

    // Calculate Jaccard similarity: |A ∩ B| / |A ∪ B|
    let intersection = tokens1.intersection(tokens2)
    let union = tokens1.union(tokens2)

    return Double(intersection.count) / Double(union.count)
  }

  /// Determines if two messages are similar enough to be grouped together.
  ///
  /// Uses the Jaccard similarity coefficient with a configurable threshold.
  /// The default threshold of 0.75 means that 75% of the tokens must be
  /// shared between the two messages for them to be considered similar.
  ///
  /// - Parameters:
  ///   - msg1: The first message to compare.
  ///   - msg2: The second message to compare.
  ///   - threshold: The minimum similarity score required (default: 0.75).
  /// - Returns: `true` if the messages are similar enough to group together.
  public static func areSimilar(
    _ msg1: String,
    _ msg2: String,
    threshold: Double = 0.75
  ) -> Bool {
    similarity(between: msg1, and: msg2) >= threshold
  }

  /// Groups log entries by similarity using normalized messages.
  ///
  /// Performs a second-pass grouping on already-deduplicated entries by finding
  /// entries whose normalized messages are similar according to token-based
  /// similarity. This helps identify messages that differ in structure but
  /// represent the same type of error.
  ///
  /// - Parameters:
  ///   - entries: The log entries to group by similarity.
  ///   - threshold: The minimum similarity score required (default: 0.75).
  /// - Returns: An array of entry groups, where each group contains similar entries.
  public static func groupBySimilarity(
    _ entries: [LogEntry],
    threshold: Double = 0.75
  ) -> [[LogEntry]] {
    // Build a list of unique normalized messages with their entries
    var messageGroups: [String: [LogEntry]] = [:]
    for entry in entries {
      let normalized = entry.normalizedMessage
      messageGroups[normalized, default: []].append(entry)
    }

    // Get all unique normalized messages
    let uniqueMessages = Array(messageGroups.keys)

    // Track which messages have been grouped
    var grouped: Set<String> = []
    var result: [[LogEntry]] = []

    // For each message, find similar messages and group them
    for i in uniqueMessages.indices {
      let msg1 = uniqueMessages[i]

      // Skip if already grouped
      if grouped.contains(msg1) {
        continue
      }

      // Start a new group with this message
      var group = messageGroups[msg1]!
      grouped.insert(msg1)

      // Find similar messages
      for j in (i + 1)..<uniqueMessages.count {
        let msg2 = uniqueMessages[j]

        // Skip if already grouped
        if grouped.contains(msg2) {
          continue
        }

        // Check similarity
        if areSimilar(msg1, msg2, threshold: threshold) {
          group.append(contentsOf: messageGroups[msg2]!)
          grouped.insert(msg2)
        }
      }

      result.append(group)
    }

    return result
  }
}
