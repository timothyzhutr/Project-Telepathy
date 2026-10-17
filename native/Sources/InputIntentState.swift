import Foundation

struct InputIntentState {
  enum Action { case none, space, commitAndPass, chinese }
  private(set) var english = false
  private(set) var defaultLanguage: String?
  private var raw = ""
  private var revision = 0
  private var manualChinese = false
  private var contextualDecision = false
  private(set) var literalRun = false
  mutating func startLiteralRun() {
    literalRun = true
    // Capitalizing an embedded name/URL is a word override, not a request to
    // replace an established Chinese default for everything that follows.
    if defaultLanguage == nil { defaultLanguage = "english" }
  }
  mutating func passLiteralKey(_ key: UInt32) -> Bool {
    guard literalRun else { return false }
    // A capital, URL or identifier stays literal until a word boundary or edit.
    if key == 32 || key >= 0xff00 && key != 0xff08 { literalRun = false }
    return true
  }

  mutating func update(raw: String, revision: Int) {
    if raw.isEmpty || self.raw.isEmpty || !(raw.hasPrefix(self.raw) || self.raw.hasPrefix(raw)) {
      english = !raw.isEmpty && defaultLanguage == "english"
      manualChinese = false; contextualDecision = false
    }
    self.raw = raw; self.revision = revision
  }
  mutating func apply(_ language: String, revision: Int, hasContext: Bool = true) -> Bool {
    guard revision == self.revision, !raw.isEmpty, !manualChinese else { return false }
    switch language {
    case "english": english = true; defaultLanguage = language
    case "chinese": english = false; defaultLanguage = language
    case "uncertain": return true
    default: return false
    }
    contextualDecision = contextualDecision || hasContext
    return true
  }
  mutating func applyInitialHint(_ language: String, revision: Int) -> Bool {
    guard !contextualDecision else { return false }
    return apply(language, revision: revision, hasContext: false)
  }
  // Prewarming may finish before a composition exists. Remember that decision
  // without making Space or punctuation act as if there were a pending word.
  mutating func rememberScreenHint(_ language: String) -> Bool {
    guard !contextualDecision, !manualChinese, ["english", "chinese"].contains(language) else { return false }
    defaultLanguage = language
    if !raw.isEmpty { english = language == "english" }
    return true
  }
  mutating func forceChinese(remember: Bool = false) {
    english = false; manualChinese = true
    if remember { defaultLanguage = "chinese" }
  }
  mutating func invalidate(revision: Int, resetDefault: Bool = false) {
    raw = ""; english = false; manualChinese = false; contextualDecision = false; self.revision = revision
    literalRun = false
    if resetDefault { defaultLanguage = nil }
  }
  func action(for key: UInt32) -> Action {
    guard english else { return .none }
    if key == 32 { return .space }
    if [UInt32(0xff09), 0xff52, 0xff54].contains(key) { return .chinese }
    // Keep letters, Backspace and apostrophes inside Rime's raw buffer.
    // Commit before punctuation, digits, Return or host cursor movement.
    if (33...126).contains(key), key != 39, !(65...90).contains(key), !(97...122).contains(key) { return .commitAndPass }
    if [UInt32(0xff0d), 0xff51, 0xff53, 0xff50, 0xff57, 0xffff].contains(key) { return .commitAndPass }
    return .none
  }
}
