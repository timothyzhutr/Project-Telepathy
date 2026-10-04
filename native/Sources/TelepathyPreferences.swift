import Foundation

extension Notification.Name {
  static let telepathyPreferencesChanged = Notification.Name("TelepathyPreferencesChanged")
}

final class TelepathyPreferences {
  static let shared = TelepathyPreferences()
  enum Key: String, CaseIterable {
    case rows = "TelepathyCandidatesPerRow", font = "TelepathyFontSize", appearance = "TelepathyAppearance"
    case inlinePinyin = "TelepathyInlinePinyin", annotations = "TelepathyAnnotations"
    case timing = "TelepathyRankingTiming", punctuation = "TelepathyChinesePunctuation"
    case statusIcon = "TelepathyStatusIcon", kev = "KevEnabled", autoLanguage = "TelepathyAutoLanguage"
    case autoPunctuation = "TelepathyAutoPunctuation"
    case rankingStrategy = "TelepathyRankingStrategy"
  }
  static let rowOptions = [0, 1, 2, 3, 4, 6, 12]
  let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  var candidatesPerRow: Int {
    let value = defaults.integer(forKey: Key.rows.rawValue)
    return Self.rowOptions.contains(value) ? value : 0
  }
  var fontSize: Int {
    guard let value = defaults.object(forKey: Key.font.rawValue) as? NSNumber,
          value.doubleValue.isFinite else { return 16 }
    return Int(min(28, max(12, value.doubleValue)))
  }
  var appearance: String {
    let value = defaults.string(forKey: Key.appearance.rawValue) ?? "system"
    return ["system", "light", "dark"].contains(value) ? value : "system"
  }
  var rankingStrategy: String {
    defaults.string(forKey: Key.rankingStrategy.rawValue) == "kev" ? "kev" : "continuation"
  }
  func enabled(_ key: Key) -> Bool {
    defaults.object(forKey: key.rawValue) as? Bool ?? (key != .statusIcon && key != .autoLanguage)
  }
  func set(_ value: Any, for key: Key) {
    defaults.set(value, forKey: key.rawValue)
    NotificationCenter.default.post(name: .telepathyPreferencesChanged, object: self)
  }
  func reset() {
    Key.allCases.forEach { defaults.removeObject(forKey: $0.rawValue) }
    NotificationCenter.default.post(name: .telepathyPreferencesChanged, object: self)
  }
  func separator(before index: Int, linear: Bool) -> String {
    if index == 0 { return "" }
    if !linear || (candidatesPerRow > 0 && index % candidatesPerRow == 0) { return "\n" }
    return "  "
  }
}
