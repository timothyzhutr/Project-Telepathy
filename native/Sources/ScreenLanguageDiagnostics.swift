import AppKit

extension Notification.Name {
  static let telepathyScreenHintChanged = Notification.Name("TelepathyScreenHintChanged")
}

// Deliberately stores only coarse state, the chosen language and elapsed time.
// No screenshot, application title or client text is retained in diagnostics.
final class ScreenLanguageDiagnostics {
  static let shared = ScreenLanguageDiagnostics()
  private(set) var summary = "No screen hint yet."
  private(set) var history = [String]()
  private let started = Date()
  private var observer: NSObjectProtocol?
  func record(status: String, language: String? = nil, requestMS: Double? = nil, reason: String? = nil,
              revision: Int? = nil, bundleIdentifier: String? = nil, flags: [String: Bool] = [:], updateSummary: Bool = true) {
    let safeStatus = ["scheduled", "capturing", "judging", "ok", "busy", "unavailable", "capture_unavailable", "model_missing", "loading", "error", "discarded", "cancelled", "capture_timeout", "waiting_for_caret", "skipped", "capture_event"].contains(status) ? status : "unavailable"
    let safeLanguage = language.flatMap { ["chinese", "english", "uncertain"].contains($0) ? $0 : nil }
    let duration = requestMS.flatMap { $0.isFinite && $0 >= 0 ? String(format: " · %.0f ms", $0) : nil } ?? ""
    let safeReasons = ["activation", "duplicate_activation", "disabled", "context_unavailable", "context_restricted", "context_text_present", "revision_changed", "process_changed", "focus_identity_changed", "anchor_changed", "screen_changed", "caret_changed", "capture_started", "capture_callback", "capture_superseded", "capture_deadline", "png_unavailable", "request_started", "response_received", "response_revision_changed", "invalid_language", "manual_choice", "manual_chinese", "preferences_changed", "first_word_finished", "deactivated", "first_character_retry", "front_app_changed", "secure_input", "permission_denied", "restricted_client", "secure_field", "caret_missing", "metadata_started", "metadata_ready", "metadata_failed", "window_not_at_caret", "screenshot_started", "screenshot_failed", "image_encoded", "before_capture", "before_upload", "response", "controller_not_eligible", "controller_hint_applied", "controller_context_present", "controller_no_raw", "controller_intent_rejected", "controller_caret_moved"]
    let safeReason = reason.flatMap { safeReasons.contains($0) || $0 == "capture_rate_limited" ? $0 : "unknown" }
    let reasonText = safeReason.map { " · " + $0 } ?? ""
    if updateSummary { summary = "Latest screen hint: \(safeLanguage ?? safeStatus)\(reasonText)\(duration)" }
    var event = String(format: "+%.0fms %@", Date().timeIntervalSince(started) * 1000, safeLanguage ?? safeStatus) + reasonText + duration
    if let revision { event += " · rev=\(revision)" }
    if let bundleIdentifier, !bundleIdentifier.isEmpty,
       bundleIdentifier.count <= 200, bundleIdentifier.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil { event += " · app=" + bundleIdentifier }
    let allowedFlags: Set<String> = ["assistance", "auto", "screen_hint", "allowed", "same_process", "same_identity", "same_anchor", "same_screen", "same_caret", "prefix_empty", "marked", "composition", "permission", "secure", "same_front_app", "caret_valid", "host_window_found"]
    for key in flags.keys.sorted() where allowedFlags.contains(key) { event += " · \(key)=\(flags[key] == true ? "1" : "0")" }
    history.append(event)
    if history.count > 32 { history.removeFirst(history.count - 32) }
    NotificationCenter.default.post(name: .telepathyScreenHintChanged, object: self)
  }
  func startReporting() {
    guard observer == nil else { return }
    observer = DistributedNotificationCenter.default().addObserver(forName: .init("TelepathyScreenHintStatusRequest"), object: nil, queue: .main) { [weak self] note in
      guard let self, let ticket = note.object as? String else { return }
      DistributedNotificationCenter.default().postNotificationName(.init("TelepathyScreenHintStatusResponse"), object: ticket,
        userInfo: ["summary": self.summary, "permission": ScreenLanguageCapture.permissionGranted, "history": self.history], deliverImmediately: true)
    }
  }
  static func printRunningStatus() {
    let ticket = UUID().uuidString
    var result: [AnyHashable: Any]?
    let center = DistributedNotificationCenter.default()
    let observer = center.addObserver(forName: .init("TelepathyScreenHintStatusResponse"), object: ticket, queue: .main) { note in result = note.userInfo }
    defer { center.removeObserver(observer) }
    center.postNotificationName(.init("TelepathyScreenHintStatusRequest"), object: ticket, userInfo: nil, deliverImmediately: true)
    let deadline = Date().addingTimeInterval(2)
    while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    if let result {
      print("Screen permission: \(result["permission"] as? Bool == true ? "granted" : "not granted"). \(result["summary"] as? String ?? "")")
      for event in result["history"] as? [String] ?? [] { print(event) }
    }
    else { print("Telepathy is not responding to screen-hint status requests.") }
  }
}
