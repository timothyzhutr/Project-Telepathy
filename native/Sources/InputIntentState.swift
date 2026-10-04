import Foundation

struct InputIntentState {
  enum Action { case none, space, commitAndPass, chinese }
  private(set) var english = false
  private var raw = ""
  private var revision = 0
  private var manualChinese = false
  private(set) var literalRun = false
  mutating func startLiteralRun() { literalRun = true }
  mutating func passLiteralKey(_ key: UInt32) -> Bool {
    guard literalRun else { return false }
    // A capital, URL or identifier stays literal until a word boundary or edit.
    if key == 32 || key >= 0xff00 && key != 0xff08 { literalRun = false }
    return true
  }

  mutating func update(raw: String, revision: Int) {
    if raw.isEmpty || self.raw.isEmpty || !(raw.hasPrefix(self.raw) || self.raw.hasPrefix(raw)) {
      english = false; manualChinese = false
    }
    self.raw = raw; self.revision = revision
  }
  mutating func apply(_ language: String, revision: Int) -> Bool {
    guard revision == self.revision, !raw.isEmpty, !manualChinese else { return false }
    switch language {
    case "english": english = true
    case "chinese": english = false
    case "uncertain": break
    default: return false
    }
    return true
  }
  mutating func forceChinese() { english = false; manualChinese = true }
  mutating func invalidate(revision: Int) {
    raw = ""; english = false; manualChinese = false; self.revision = revision
    literalRun = false
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
