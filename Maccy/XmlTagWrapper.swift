import AppKit
import Defaults
import Logging

struct XmlTagWrapper {
  private static let logger = Logger(label: "org.p0deje.Maccy.XmlTagWrapper")

  /// Wraps clipboard text in XML tags. Called on key-down.
  @MainActor
  static func wrapClipboard() {
    logger.info("wrapClipboard triggered")

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
      logger.info("Already wrapped, skipping")
      return
    }

    let tag = ContentTagger.classify(text)
    let wrapped = ContentTagger.wrap(text)
    logger.info("Classified as '\(tag.rawValue)'")

    // Suppress Maccy from recording the wrapped version as a new history item.
    Defaults[.ignoreEvents] = true

    pasteboard.clearContents()
    pasteboard.setString(wrapped, forType: .string)
    Clipboard.shared.changeCount = pasteboard.changeCount

    Defaults[.ignoreEvents] = false
  }

  /// Pastes the current clipboard contents. Called on key-up,
  /// when the user's shortcut modifier keys are physically released.
  @MainActor
  static func pasteClipboard() {
    logger.info("pasteClipboard triggered (key-up)")
    Clipboard.shared.paste()
  }
}
