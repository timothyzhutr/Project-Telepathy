import Foundation

final class ScreenLanguageSession {
  typealias Capture = (ScreenLanguageCaptureContext, @escaping (Data?) -> Void) -> Void
  private var state = ScreenLanguageHintState()
  private let preferences: TelepathyPreferences
  private let session: URLSession
  private let capture: Capture
  private let diagnostics: ScreenLanguageDiagnostics
  private let captureTimeout: TimeInterval
  private let throttle: ScreenCaptureThrottle
  private var delay: DispatchWorkItem?
  private var request: URLSessionDataTask?
  private var preferenceObserver: NSObjectProtocol?
  private var activationTime = Date.distantPast
  private var activationIdentity = ""
  private var requestAttempt: (() -> Void)?
  private var firstCharacterArrived = false
  private var needsFirstCharacterRetry = false
  private var retriedAfterFirstCharacter = false
  private var captureDeadline: DispatchWorkItem?
  private var captureSequence = 0
  private var phase = "idle"
  var active: Bool { state.active }
  init(preferences: TelepathyPreferences = .shared, session: URLSession? = nil,
       diagnostics: ScreenLanguageDiagnostics = .shared, captureTimeout: TimeInterval = 3,
       throttle: ScreenCaptureThrottle = .shared,
       capture: @escaping Capture = ScreenLanguageCapture.capture) {
    self.preferences = preferences; self.capture = capture
    self.diagnostics = diagnostics; self.captureTimeout = captureTimeout
    self.throttle = throttle
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 4
    configuration.timeoutIntervalForResource = 5
    self.session = session ?? URLSession(configuration: configuration)
    preferenceObserver = NotificationCenter.default.addObserver(forName: .telepathyPreferencesChanged, object: preferences, queue: .main) { [weak self] _ in self?.cancel(reason: "preferences_changed") }
  }
  deinit {
    delay?.cancel(); request?.cancel(); captureDeadline?.cancel()
    if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
  }
  func language(precedingText: String) -> String? { state.language(precedingText: precedingText) }
  private var enabled: Bool { preferences.enabled(.kev) && preferences.enabled(.autoLanguage) && preferences.enabled(.screenLanguage) }
  func activate(identity: String, context: @escaping () -> ScreenLanguageCaptureContext?,
                precedingText: @escaping () -> String, completion: @escaping (String) -> Void) {
    let now = Date()
    if state.active && activationIdentity == identity {
      if now.timeIntervalSince(activationTime) < 0.1 {
        diagnostics.record(status: "skipped", reason: "duplicate_activation", revision: state.revision, updateSummary: false); return
      }
      // Browser clients may be reused across fields without a deactivation.
      // Only rapid duplicate notifications represent the same activation.
      state.deactivate()
    }
    guard state.activate(identity: identity) else { return }
    activationTime = now; activationIdentity = identity
    stopRequests()
    guard enabled, let revision = state.beginRequest() else {
      diagnostics.record(status: "skipped", reason: "disabled", revision: state.revision,
        flags: ["assistance": preferences.enabled(.kev), "auto": preferences.enabled(.autoLanguage), "screen_hint": preferences.enabled(.screenLanguage)])
      return
    }
    phase = "scheduled"
    diagnostics.record(status: "scheduled", reason: "activation", revision: revision)
    let attempt = { [weak self] in
      guard let self else { return }
      guard self.enabled, self.state.revision == revision else {
        let current = self.state.revision == revision
        if current { self.phase = "idle" }
        self.diagnostics.record(status: "discarded", reason: current ? "disabled" : "revision_changed", revision: revision, updateSummary: current)
        return
      }
      guard let capturedContext = context(), capturedContext.allowed else {
        self.phase = "waiting_for_caret"
        self.diagnostics.record(status: "waiting_for_caret", reason: "context_unavailable", revision: revision)
        self.needsFirstCharacterRetry = true; self.scheduleFirstCharacterRetry(); return
      }
      guard ScreenLanguageHintState.empty(precedingText()) else {
        self.discard(reason: "context_text_present", revision: revision, context: capturedContext); return
      }
      let cooldown = self.throttle.claim()
      if cooldown > 0 {
        // Keep only this session's latest pending focus. The retry runs the
        // complete context/permission/revision checks again before capturing.
        self.phase = "scheduled"
        self.diagnostics.record(status: "scheduled", reason: "capture_rate_limited", revision: revision,
          bundleIdentifier: capturedContext.bundleIdentifier)
        guard let attempt = self.requestAttempt else { return }
        let deferred = DispatchWorkItem(block: attempt)
        self.delay?.cancel(); self.delay = deferred
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldown, execute: deferred)
        return
      }
      self.phase = "capturing"
      self.diagnostics.record(status: "capturing", reason: "capture_started", revision: revision, bundleIdentifier: capturedContext.bundleIdentifier,
        flags: ["marked": capturedContext.hasMarkedText, "composition": capturedContext.compositionActive, "prefix_empty": true])
      self.captureSequence += 1
      let sequence = self.captureSequence
      let deadline = DispatchWorkItem { [weak self] in
        guard let self, self.state.revision == revision, self.captureSequence == sequence else { return }
        self.captureSequence += 1; self.captureDeadline = nil; self.phase = "idle"
        self.diagnostics.record(status: "capture_timeout", reason: "capture_deadline", revision: revision, bundleIdentifier: capturedContext.bundleIdentifier)
        self.needsFirstCharacterRetry = true; self.scheduleFirstCharacterRetry()
      }
      self.captureDeadline = deadline
      DispatchQueue.main.asyncAfter(deadline: .now() + self.captureTimeout, execute: deadline)
      self.capture(capturedContext) { [weak self] png in
        guard let self else { return }
        guard self.enabled, self.state.revision == revision, self.captureSequence == sequence else {
          let current = self.state.revision == revision && self.captureSequence == sequence
          if current { self.captureDeadline?.cancel(); self.captureDeadline = nil; self.phase = "idle" }
          self.diagnostics.record(status: "discarded", reason: current ? "disabled" : (self.state.revision != revision ? "revision_changed" : "capture_superseded"), revision: revision, updateSummary: current); return
        }
        self.captureDeadline?.cancel(); self.captureDeadline = nil
        guard let current = context() else {
          self.discard(reason: "context_unavailable", revision: revision, context: capturedContext); return
        }
        if let reason = capturedContext.mismatchReason(current) {
          self.discard(reason: reason, revision: revision, context: capturedContext, flags: capturedContext.comparisonFlags(current)); return
        }
        guard ScreenLanguageHintState.empty(precedingText()) else {
          self.discard(reason: "context_text_present", revision: revision, context: capturedContext); return
        }
        guard let png, let data = ScreenLanguageImage.requestData(png: png, revision: revision) else {
          self.needsFirstCharacterRetry = true; self.scheduleFirstCharacterRetry()
          self.phase = "idle"
          self.diagnostics.record(status: "capture_unavailable", reason: "png_unavailable", revision: revision, bundleIdentifier: capturedContext.bundleIdentifier); return
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18765/api/screen-language")!)
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        self.phase = "judging"
        self.diagnostics.record(status: "judging", reason: "request_started", revision: revision, bundleIdentifier: capturedContext.bundleIdentifier)
        self.request = self.session.dataTask(with: request) { [weak self] data, response, error in
          let result = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
          DispatchQueue.main.async {
            guard let self else { return }
            guard self.enabled, self.state.revision == revision else {
              let current = self.state.revision == revision
              if current { self.phase = "idle"; self.request = nil }
              self.diagnostics.record(status: "discarded", reason: current ? "disabled" : "revision_changed", revision: revision, updateSummary: current); return
            }
            self.request = nil
            guard let current = context() else {
              self.discard(reason: "context_unavailable", revision: revision, context: capturedContext); return
            }
            if let reason = capturedContext.mismatchReason(current) {
              self.discard(reason: reason, revision: revision, context: capturedContext, flags: capturedContext.comparisonFlags(current)); return
            }
            guard ScreenLanguageHintState.empty(precedingText()) else {
              self.discard(reason: "context_text_present", revision: revision, context: capturedContext); return
            }
            self.phase = "idle"
            let status = result?["status"] as? String ?? "unavailable"
            let language = result?["language"] as? String
            self.diagnostics.record(status: status, language: language, requestMS: result?["request_ms"] as? Double,
              reason: "response_received", revision: revision, bundleIdentifier: capturedContext.bundleIdentifier)
            guard status == "ok" else { return }
            guard result?["revision"] as? Int == revision else {
              self.discard(reason: "response_revision_changed", revision: revision, context: capturedContext); return
            }
            guard let language, self.state.accept(language, revision: revision, precedingText: precedingText()) else {
              self.discard(reason: "invalid_language", revision: revision, context: capturedContext); return
            }
            completion(language)
          }
        }
        self.request?.resume()
      }
    }
    requestAttempt = attempt
    let work = DispatchWorkItem(block: attempt)
    delay = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
  }
  func firstCharacterDidArrive() {
    firstCharacterArrived = true
    scheduleFirstCharacterRetry()
  }
  private func scheduleFirstCharacterRetry() {
    guard firstCharacterArrived, needsFirstCharacterRetry, !retriedAfterFirstCharacter, let requestAttempt else { return }
    retriedAfterFirstCharacter = true; needsFirstCharacterRetry = false
    diagnostics.record(status: "scheduled", reason: "first_character_retry", revision: state.revision, updateSummary: false)
    let work = DispatchWorkItem(block: requestAttempt)
    delay = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
  }
  private func stopRequests() {
    captureDeadline?.cancel(); captureDeadline = nil; captureSequence += 1
    delay?.cancel(); delay = nil; request?.cancel(); request = nil; requestAttempt = nil
    firstCharacterArrived = false; needsFirstCharacterRetry = false; retriedAfterFirstCharacter = false
    phase = "idle"
  }
  private func discard(reason: String, revision: Int, context: ScreenLanguageCaptureContext, flags: [String: Bool] = [:]) {
    phase = "idle"
    diagnostics.record(status: "discarded", reason: reason, revision: revision, bundleIdentifier: context.bundleIdentifier, flags: flags)
  }
  func cancel(reason: String = "manual_choice") {
    let wasWorking = phase != "idle"
    if state.active { diagnostics.record(status: "cancelled", reason: reason, revision: state.revision, updateSummary: wasWorking) }
    state.cancel(); stopRequests()
  }
  func finishFirstWord() {
    let wasWorking = phase != "idle"
    if state.active { diagnostics.record(status: "cancelled", reason: "first_word_finished", revision: state.revision, updateSummary: wasWorking) }
    state.finishFirstWord(); stopRequests()
  }
  func deactivate() {
    let wasWorking = phase != "idle"
    if state.active { diagnostics.record(status: "cancelled", reason: "deactivated", revision: state.revision, updateSummary: wasWorking) }
    state.deactivate(); stopRequests()
  }
}
