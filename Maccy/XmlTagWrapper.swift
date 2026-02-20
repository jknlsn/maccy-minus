import AppKit
import Defaults
import Logging

struct XmlTagWrapper {
  private static let logger = Logger(label: "org.p0deje.Maccy.XmlTagWrapper")

  /// Reads clipboard, classifies, wraps in XML tags, and pastes into
  /// the frontmost application.
  @MainActor
  static func wrapAndPaste() {
    logger.info("wrapAndPaste triggered")

    let pasteboard = NSPasteboard.general
    guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
      logger.info("No string content on pasteboard, aborting")
      return
    }

    // Don't double-wrap if already tagged.
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if ContentTag.allCases.contains(where: {
      trimmed.hasPrefix("<\($0.rawValue)>") && trimmed.hasSuffix("</\($0.rawValue)>")
    }) {
      logger.info("Already wrapped, pasting as-is")
      Clipboard.shared.paste()
      return
    }

    let tag = ContentTagger.classify(text)
    let wrapped = ContentTagger.wrap(text)
    logger.info("Classified as '\(tag.rawValue)'")

    // Suppress Maccy from recording the wrapped version as a new history item.
    let wasIgnoring = Defaults[.ignoreEvents]
    Defaults[.ignoreEvents] = true

    pasteboard.clearContents()
    pasteboard.setString(wrapped, forType: .string)
    Clipboard.shared.changeCount = pasteboard.changeCount

    Clipboard.shared.paste()

    if !wasIgnoring {
      Defaults[.ignoreEvents] = false
    }
  }
}
