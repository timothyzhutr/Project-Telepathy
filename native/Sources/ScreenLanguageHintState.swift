import Foundation

// A focus revision is independent of per-keystroke ranking revisions. A capture
// can finish while the first word grows, but cannot survive a commit or choice.
struct ScreenLanguageHintState {
  private(set) var revision = 0
  private(set) var active = false
  private var identity = ""
  private var requested = false
  private var firstWord = true
  private var hint: String?

  mutating func activate(identity: String) -> Bool {
    guard !active || self.identity != identity || !firstWord else { return false }
    revision += 1; active = true; self.identity = identity
    requested = false; firstWord = true; hint = nil
    return true
  }
  mutating func beginRequest() -> Int? {
    guard active, !requested, firstWord else { return nil }
    requested = true
    return revision
  }
  mutating func accept(_ language: String, revision: Int, precedingText: String) -> Bool {
    guard revision == self.revision, active, firstWord, Self.empty(precedingText),
          ["chinese", "english", "uncertain"].contains(language) else { return false }
    hint = language
    return true
  }
  func language(precedingText: String) -> String? {
    active && firstWord && Self.empty(precedingText) ? hint : nil
  }
  mutating func finishFirstWord() { cancel() }
  mutating func cancel() {
    revision += 1; requested = true; firstWord = false; hint = nil
  }
  mutating func deactivate() { cancel(); active = false }
  static func empty(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum ScreenLanguageCapturePolicy {
  static func allowed(permission: Bool, secureInput: Bool, restrictedClient: Bool) -> Bool {
    permission && !secureInput && !restrictedClient
  }
}
