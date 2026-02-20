import NaturalLanguage

enum ContentTag: String, CaseIterable {
  case logs
  case code
  case article
  case email
  case data
  case docs
  case command
  case url
  case unknown

  var xmlTag: String { rawValue }
}

struct ContentTagger {
  static func classify(_ text: String) -> ContentTag {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return .unknown
    }

    let lines = trimmed.components(separatedBy: .newlines)

    // URL - single line that's just a URL
    if lines.count <= 2,
       trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
      return .url
    }

    // Email
    if trimmed.contains("Subject:") || trimmed.contains("From:"),
       trimmed.contains("@") {
      return .email
    }

    // Logs
    let logPatterns = [
      "error:", "warning:", "Error -", "fatal:",
      "\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}",
      "^\\s*[>❯\\$#]\\s",
      "\\[(INFO|ERROR|WARN|DEBUG)\\]",
      "stack trace", "Traceback", "at \\S+\\(\\S+:\\d+\\)"
    ]
    if matchesAny(text, patterns: logPatterns, threshold: 2) {
      return .logs
    }

    // Code
    let codePatterns = [
      "^(import |from .+ import |#include |using |require\\()",
      "func\\s+\\w+", "def\\s+\\w+", "class\\s+\\w+",
      "\\{[^}]*\\}", "=>", "->",
      "if\\s*\\(", "for\\s*\\(", "while\\s*\\(",
      "return\\s+", "var\\s+", "let\\s+", "const\\s+"
    ]
    if matchesAny(text, patterns: codePatterns, threshold: 3) {
      return .code
    }

    // Data - JSON, CSV, XML-ish
    if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
       (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
      return .data
    }
    if lines.count > 2, let firstLine = lines.first {
      let commaCount = firstLine.filter { $0 == "," }.count
      if commaCount >= 2 { return .data }
    }

    // Command - short shell-ish
    if lines.count <= 3 {
      let commandPrefixes = [
        "git ", "npm ", "brew ", "docker ", "curl ",
        "cd ", "ls ", "mkdir ", "rm ", "cp ", "mv ",
        "sudo ", "chmod ", "chown ", "ssh ", "scp "
      ]
      if commandPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
        return .command
      }
    }

    // Article - long text with paragraphs
    if trimmed.count > 500, lines.count > 5 {
      let avgLineLength = trimmed.count / max(lines.count, 1)
      if avgLineLength > 60 { return .article }
    }

    // NLP embedding fallback
    return classifyWithEmbedding(trimmed) ?? .unknown
  }

  static func wrap(_ text: String) -> String {
    let tag = classify(text)
    return "<\(tag.xmlTag)>\n\(text)\n</\(tag.xmlTag)>"
  }

  // MARK: - NLP Embedding

  private static func classifyWithEmbedding(_ text: String) -> ContentTag? {
    guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
      return nil
    }

    let snippet = String(text.prefix(200))

    let labels: [(ContentTag, String)] = [
      (.logs, "error log output debug warning stack trace terminal"),
      (.code, "function variable class import return code programming"),
      (.article, "article paragraph essay writing prose text content"),
      (.email, "email message subject dear regards sincerely"),
      (.data, "json data csv table rows columns structured"),
      (.docs, "documentation api reference guide manual instructions"),
      (.command, "terminal command shell bash run execute")
    ]

    var bestTag: ContentTag = .unknown
    var bestDistance: Double = .greatestFiniteMagnitude

    for (tag, label) in labels {
      let distance = embedding.distance(between: snippet, and: label)
      if distance < bestDistance {
        bestDistance = distance
        bestTag = tag
      }
    }

    return bestDistance < 1.0 ? bestTag : nil
  }

  // MARK: - Helpers

  private static func matchesAny(_ text: String,
                                  patterns: [String],
                                  threshold: Int) -> Bool {
    var matches = 0
    for pattern in patterns {
      if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
        let range = NSRange(text.startIndex..., in: text)
        if regex.numberOfMatches(in: text, range: range) > 0 {
          matches += 1
          if matches >= threshold { return true }
        }
      }
    }
    return false
  }
}
