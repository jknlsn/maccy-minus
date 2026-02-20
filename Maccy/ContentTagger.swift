import Defaults
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

enum ContentTag: String, CaseIterable {
  // Original tags
  case logs
  case code
  case article
  case email
  case data
  case docs
  case command
  case url

  // LLM-focused
  case prompt
  case response
  case conversation
  case instructions

  // Code-focused
  case config
  case snippet
  case diff
  case error

  // Doc / notes
  case notes
  case markdown

  // Input-focused
  case query
  case template

  case unknown

  var xmlTag: String { rawValue }
}

// MARK: - Foundation Models Structured Output

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
enum ContentClassificationResult {
  // Original tags
  case logs
  case code
  case article
  case email
  case data
  case docs
  case command
  case url

  // LLM-focused
  case prompt
  case response
  case conversation
  case instructions

  // Code-focused
  case config
  case snippet
  case diff
  case error

  // Doc / notes
  case notes
  case markdown

  // Input-focused
  case query
  case template

  case unknown
}
#endif

struct ContentTagger {

  // MARK: - Public Sync API (backward compatible)

  static func classify(_ text: String) -> ContentTag {
    if let tag = classifyWithHeuristics(text) {
      return tag
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return classifyWithEmbedding(trimmed) ?? .unknown
  }

  static func wrap(_ text: String) -> String {
    let tag = classify(text)
    return "<\(tag.xmlTag)>\n\(text)\n</\(tag.xmlTag)>"
  }

  // MARK: - Public Async API (tiered pipeline)

  static func classify(_ text: String) async -> ContentTag {
    let bypassHeuristics = Defaults[.alwaysUseFoundationModels]

    // 1. Heuristics fast path (skipped when bypass is enabled)
    if !bypassHeuristics, let tag = classifyWithHeuristics(text) {
      return tag
    }

    // 2. Foundation Models (macOS 26+ only)
    #if canImport(FoundationModels)
    if #available(macOS 26, *) {
      if let tag = await classifyWithFoundationModels(text) {
        return tag
      }
    }
    #endif

    // 3. Heuristics fallback when bypass was on but FM failed
    if bypassHeuristics, let tag = classifyWithHeuristics(text) {
      return tag
    }

    // 4. NaturalLanguage embedding fallback
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return classifyWithEmbedding(trimmed) ?? .unknown
  }

  static func wrap(_ text: String) async -> String {
    let tag = await classify(text)
    return "<\(tag.xmlTag)>\n\(text)\n</\(tag.xmlTag)>"
  }

  // MARK: - Heuristics

  private static func classifyWithHeuristics(_ text: String) -> ContentTag? {
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

    // Diff / patch
    let diffPatterns = [
      "^diff --git", "^@@\\s", "^\\+\\+\\+\\s", "^---\\s"
    ]
    if matchesAny(text, patterns: diffPatterns, threshold: 2) {
      return .diff
    }

    // Error / stack trace
    let errorPatterns = [
      "stack trace", "Traceback", "at \\S+\\(\\S+:\\d+\\)",
      "^\\s*Exception", "^\\s*panic:", "SIGABRT", "SIGSEGV",
      "^\\s*fatal error:"
    ]
    if matchesAny(text, patterns: errorPatterns, threshold: 1) {
      return .error
    }

    // Logs
    let logPatterns = [
      "error:", "warning:", "Error -", "fatal:",
      "\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}",
      "^\\s*[>❯\\$#]\\s",
      "\\[(INFO|ERROR|WARN|DEBUG)\\]"
    ]
    if matchesAny(text, patterns: logPatterns, threshold: 1) {
      return .logs
    }

    // Config files
    let configPatterns = [
      "^\\s*\\[\\w+\\]\\s*$",                     // INI sections
      "^\\w+\\s*[:=]\\s*",                         // key: value / key=value
      "^\\s*\\w+\\.\\w+\\s*=",                     // dotted.key = value
      "^---\\s*$"                                   // YAML document start
    ]
    if matchesAny(text, patterns: configPatterns, threshold: 2) {
      return .config
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

    // Short code snippet (fewer pattern matches needed for short text)
    if lines.count <= 5, matchesAny(text, patterns: codePatterns, threshold: 1) {
      return .snippet
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

    // Markdown
    let markdownPatterns = [
      "^#{1,6}\\s", "^\\s*[-*]\\s", "^\\s*\\d+\\.\\s",
      "\\[.+\\]\\(.+\\)", "```"
    ]
    if matchesAny(text, patterns: markdownPatterns, threshold: 2) {
      return .markdown
    }

    // Query (SQL, search)
    let queryPatterns = [
      "^\\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\\s",
      "\\sWHERE\\s", "\\sFROM\\s.*\\sWHERE", "\\sJOIN\\s"
    ]
    if matchesAny(text, patterns: queryPatterns, threshold: 1) {
      return .query
    }

    // Template (placeholders)
    let templatePatterns = [
      "\\{\\{\\s*\\w+\\s*\\}\\}", "\\$\\{\\w+\\}",
      "<%.*%>", "\\{\\w+\\}"
    ]
    if matchesAny(text, patterns: templatePatterns, threshold: 2) {
      return .template
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

    return nil // No heuristic match
  }

  // MARK: - Foundation Models Classification

  #if canImport(FoundationModels)
  @available(macOS 26, *)
  private static func classifyWithFoundationModels(_ text: String) async -> ContentTag? {
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
      return nil
    }

    do {
      let session = LanguageModelSession(
        model: SystemLanguageModel(useCase: .contentTagging),
        instructions: """
          Classify clipboard text into exactly one content category. \
          Choose the most specific applicable tag. \
          Use 'prompt' for LLM user prompts, 'response' for LLM assistant replies, \
          'conversation' for multi-turn chat transcripts, \
          'instructions' for system prompts or directives, \
          'snippet' for short code examples, 'diff' for patches, \
          'config' for configuration files, 'query' for SQL or search queries, \
          'template' for text with placeholders, 'markdown' for markdown-formatted text, \
          'notes' for bullet points or outlines, 'error' for error messages or stack traces.
          """
      )
      let snippet = String(text.prefix(500))
      let response = try await session.respond(
        to: snippet,
        generating: ContentClassificationResult.self
      )
      return mapClassificationResult(response.content)
    } catch {
      return nil
    }
  }

  @available(macOS 26, *)
  private static func mapClassificationResult(_ result: ContentClassificationResult) -> ContentTag {
    switch result {
    case .logs: return .logs
    case .code: return .code
    case .article: return .article
    case .email: return .email
    case .data: return .data
    case .docs: return .docs
    case .command: return .command
    case .url: return .url
    case .prompt: return .prompt
    case .response: return .response
    case .conversation: return .conversation
    case .instructions: return .instructions
    case .config: return .config
    case .snippet: return .snippet
    case .diff: return .diff
    case .error: return .error
    case .notes: return .notes
    case .markdown: return .markdown
    case .query: return .query
    case .template: return .template
    case .unknown: return .unknown
    }
  }
  #endif

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
      (.command, "terminal command shell bash run execute"),
      (.prompt, "prompt request question ask user input llm chat"),
      (.response, "response answer reply assistant output generated"),
      (.conversation, "conversation chat dialog message exchange multi-turn"),
      (.instructions, "system prompt instruction directive role rules"),
      (.config, "configuration settings yaml toml ini env variables"),
      (.snippet, "code snippet example short sample demonstration"),
      (.diff, "diff patch git changes added removed lines"),
      (.error, "error exception crash stack trace fatal panic"),
      (.notes, "notes bullet points outline list items todo"),
      (.markdown, "markdown heading links formatted document readme"),
      (.query, "query sql select database search filter"),
      (.template, "template placeholder variable substitution mustache")
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
