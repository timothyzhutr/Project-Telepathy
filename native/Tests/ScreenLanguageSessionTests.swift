import AppKit
import ScreenCaptureKit

private final class ScreenProtocol: URLProtocol {
  static var requests = 0
  static var lastBody: [String: Any] = [:]
  static var delay = 0.01
  static var status = "ok"
  private var work: DispatchWorkItem?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    precondition(request.url?.absoluteString == "http://127.0.0.1:18765/api/screen-language")
    Self.requests += 1
    var bytes = request.httpBody ?? Data()
    if bytes.isEmpty, let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 1024)
      while stream.hasBytesAvailable {
        let n = stream.read(&buffer, maxLength: buffer.count)
        if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n))
      }
    }
    precondition(bytes.count <= ScreenLanguageImage.maximumRequestBytes)
    Self.lastBody = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    precondition(Set(Self.lastBody.keys) == ["revision", "image"], "Only the image and focus revision may leave native memory")
    let result: [String: Any] = ["status": Self.status, "revision": Self.lastBody["revision"]!, "language": "english", "request_ms": 23]
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
      self.client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: result))
      self.client?.urlProtocolDidFinishLoading(self)
    }
    self.work = work
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: work)
  }
  override func stopLoading() { work?.cancel() }
}

@main struct ScreenLanguageSessionTests {
  static func main() {
    let suite = "local.telepathy.screen-tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = TelepathyPreferences(defaults: defaults)
    preferences.set(true, for: .autoLanguage)
    defaults.set("kev", forKey: "TelepathyRankingStrategy")
    precondition(preferences.rankingStrategy == "continuation", "Legacy Kev settings must migrate to the supported vision ranking method")
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ScreenProtocol.self]
    let http = URLSession(configuration: config)
    defer { http.invalidateAndCancel() }
    var captures = 0, results = [String]()
    let session = ScreenLanguageSession(preferences: preferences, session: http, throttle: .init(minimumInterval: 0), capture: { _, callback in
      captures += 1; callback(Data([137, 80, 78, 71]))
    })
    let context = ScreenLanguageCaptureContext(processID: getpid(), caret: .zero, primaryScreenHeight: 900, allowed: true)
    func activate(_ identity: String, prefix: @escaping () -> String = { "" }) {
      session.activate(identity: identity, context: { context }, precedingText: prefix) { results.append($0) }
    }
    func wait(_ seconds: Double = 0.15) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    let started = Date()
    activate("first"); activate("first")
    precondition(Date().timeIntervalSince(started) < 0.05 && captures == 0, "Activation must not block typing")
    wait()
    precondition(captures == 1 && results == ["english"] && ScreenProtocol.requests == 1, "Activation must coalesce into one request")
    precondition(session.language(precedingText: "") == "english")
    session.finishFirstWord()
    precondition(session.language(precedingText: "") == nil)
    activate("first"); wait()
    precondition(captures == 2 && results.count == 2, "A new blank session may reuse the same browser client")
    activate("first"); wait()
    precondition(captures == 3 && results.count == 3, "A later focus activation can reuse a client even before any word is committed")
    let beforeStale = results.count
    ScreenProtocol.delay = 0.3
    session.deactivate(); activate("stale"); wait(0.12); session.deactivate(); activate("fresh"); wait(0.5)
    precondition(results.count == beforeStale + 1, "A deactivated screen response must be discarded")
    let beforeCancel = results.count
    session.deactivate(); activate("manual"); wait(0.12); session.cancel(); wait(0.4)
    precondition(results.count == beforeCancel, "Manual selection must cancel an in-flight request")
    session.deactivate(); activate("toggle"); wait(0.12)
    preferences.set(false, for: .kev); preferences.set(true, for: .kev); wait(0.4)
    precondition(results.count == beforeCancel, "Disabling and quickly re-enabling assistance must not revive an old screenshot")
    let beforeContext = captures
    session.deactivate(); activate("context", prefix: { "Hello " }); wait()
    precondition(captures == beforeContext, "Nonempty text must bypass screen capture")
    ScreenProtocol.delay = 0.01; ScreenProtocol.status = "busy"
    session.deactivate(); activate("busy"); wait()
    precondition(results.count == beforeCancel && session.language(precedingText: "") == nil, "A busy model must leave typing available")
    preferences.set(false, for: .kev)
    session.deactivate(); let beforeOff = captures; activate("off"); wait()
    precondition(captures == beforeOff, "Assistance off must never capture")
    preferences.set(true, for: .kev); ScreenProtocol.status = "ok"
    let anchor = ScreenLanguageCaptureContext(processID: getpid(), caret: .init(x: 100, y: 100, width: 1, height: 20), primaryScreenHeight: 900, allowed: true)
    for replacement in [nil,
      ScreenLanguageCaptureContext(processID: getpid(), caret: anchor.caret, primaryScreenHeight: 900, allowed: false),
      ScreenLanguageCaptureContext(processID: getpid(), caret: .init(x: 600, y: 500, width: 1, height: 20), primaryScreenHeight: 900, allowed: true)] as [ScreenLanguageCaptureContext?] {
      var current: ScreenLanguageCaptureContext? = anchor
      var captured: ((Data?) -> Void)?
      var applied = false
      let guarded = ScreenLanguageSession(preferences: preferences, session: http, throttle: .init(minimumInterval: 0), capture: { _, complete in captured = complete })
      let before = ScreenProtocol.requests
      guarded.activate(identity: UUID().uuidString, context: { current }, precedingText: { "" }) { _ in applied = true }
      wait(0.12); precondition(captured != nil)
      current = replacement; captured?(Data([137, 80, 78, 71])); wait(0.05)
      precondition(ScreenProtocol.requests == before && !applied, "A focus change or restricted field during capture must prevent the image POST")
      precondition(!ScreenLanguageDiagnostics.shared.summary.contains("capturing"), "A dropped PNG must leave a terminal status instead of capturing forever")
    }
    var current: ScreenLanguageCaptureContext? = anchor
    var applied = false
    ScreenProtocol.delay = 0.2
    let guarded = ScreenLanguageSession(preferences: preferences, session: http, throttle: .init(minimumInterval: 0), capture: { _, complete in complete(Data([137, 80, 78, 71])) })
    guarded.activate(identity: "response-focus", context: { current }, precedingText: { "" }) { _ in applied = true }
    wait(0.13); current = nil; wait(0.25)
    precondition(!applied && guarded.language(precedingText: "") == nil, "Focus must be revalidated when the model response arrives")
    precondition(!ScreenLanguageDiagnostics.shared.summary.contains("judging"), "A dropped model response must leave a terminal status")
    var retryContext: ScreenLanguageCaptureContext?
    var retryCaptures = 0
    let retrying = ScreenLanguageSession(preferences: preferences, session: http, throttle: .init(minimumInterval: 0), capture: { _, complete in retryCaptures += 1; complete(nil) })
    retrying.activate(identity: "missing-caret", context: { retryContext }, precedingText: { "" }) { _ in }
    wait(0.12); precondition(retryCaptures == 0)
    retryContext = anchor
    retrying.firstCharacterDidArrive(); wait(0.08)
    precondition(retryCaptures == 1, "A missing activation caret may retry once after marked text exists")
    retrying.firstCharacterDidArrive(); retrying.firstCharacterDidArrive(); wait(0.1)
    precondition(retryCaptures == 1, "A failed first-character retry must never become per-keystroke capture")
    let diagnostics = ScreenLanguageDiagnostics()
    var lateCapture: ((Data?) -> Void)?
    let timed = ScreenLanguageSession(preferences: preferences, session: http, diagnostics: diagnostics, captureTimeout: 0.04,
      throttle: .init(minimumInterval: 0),
      capture: { _, complete in lateCapture = complete })
    let beforeTimeout = ScreenProtocol.requests
    timed.activate(identity: "timeout", context: { anchor }, precedingText: { "" }) { _ in fatalError("A timed-out capture must not apply") }
    wait(0.2)
    precondition(diagnostics.summary.contains("capture_timeout"), "ScreenCaptureKit must have a bounded deadline")
    lateCapture?(Data([137, 80, 78, 71])); wait(0.05)
    precondition(ScreenProtocol.requests == beforeTimeout, "A callback after the capture deadline must never upload")
    for index in 0..<40 { diagnostics.record(status: "scheduled", reason: "activation", revision: index) }
    precondition(diagnostics.history.count == 32, "Diagnostic event history must be bounded")
    diagnostics.record(status: "secret screenshot text", language: "secret document", reason: "secret window title",
      bundleIdentifier: "invalid bundle with spaces", flags: ["secret text": true])
    precondition(!diagnostics.summary.contains("secret") && !diagnostics.history.joined().contains("secret") && !diagnostics.history.joined().contains("invalid bundle"),
      "Diagnostics must retain only allowed status metadata, never arbitrary input strings")
    precondition(ScreenLanguageImage.requestData(png: Data(repeating: 0, count: 3 * 1024 * 1024), revision: 1) == nil)
    ScreenProtocol.delay = 0.01; ScreenProtocol.status = "ok"
    let sharedLimit = ScreenCaptureThrottle(minimumInterval: 0.4)
    var limitedCaptures = 0
    let capture: ScreenLanguageSession.Capture = { _, complete in limitedCaptures += 1; complete(Data([137, 80, 78, 71])) }
    let firstField = ScreenLanguageSession(preferences: preferences, session: http, throttle: sharedLimit, capture: capture)
    let secondField = ScreenLanguageSession(preferences: preferences, session: http, throttle: sharedLimit, capture: capture)
    firstField.activate(identity: "first-limited", context: { anchor }, precedingText: { "" }) { _ in }
    wait(0.15)
    secondField.activate(identity: "second-limited", context: { anchor }, precedingText: { "" }) { _ in }
    wait(0.15)
    precondition(limitedCaptures == 1, "A new controller must not bypass another controller's capture cooldown")
    secondField.finishFirstWord(); wait(0.3)
    precondition(limitedCaptures == 1, "Finishing a word must cancel its deferred screenshot")
    secondField.deactivate()
    secondField.activate(identity: "latest-limited", context: { anchor }, precedingText: { "" }) { _ in }
    wait(0.15)
    precondition(limitedCaptures == 2, "An eligible fresh field may capture after the cooldown")
    var movedPrefix = ""
    firstField.deactivate()
    firstField.activate(identity: "context-before-deferred", context: { anchor }, precedingText: { movedPrefix }) { _ in }
    wait(0.15); movedPrefix = "Hello "; wait(0.3)
    precondition(limitedCaptures == 2, "A deferred screenshot must recheck text context before capturing")
    firstField.deactivate(); secondField.deactivate()
    // Hold the real capture pipeline at its asynchronous window-metadata
    // boundary. Cancellation must prevent pixels, not merely prevent a POST.
    for invalidation in ["none", "disable", "deactivate", "commit", "timeout", "focus", "text", "restricted"] {
      var current: ScreenLanguageCaptureContext? = anchor
      var prefix = ""
      var metadata: ((ScreenLanguageCaptureWindow?) -> Void)?
      var screenshots = 0
      let beforeRequests = ScreenProtocol.requests
      let pending = ScreenLanguageSession(preferences: preferences, session: http,
        captureTimeout: invalidation == "timeout" ? 0.04 : 1,
        throttle: .init(minimumInterval: 0), capture: { context, complete in
          ScreenLanguageCapture.capture(context, accessFailure: { nil },
            resolveWindow: { _, callback in metadata = callback }, completion: complete)
        })
      pending.activate(identity: "metadata-" + invalidation, context: { current }, precedingText: { prefix }) { _ in
        fatalError("This fixture never supplies image pixels")
      }
      wait(0.12)
      precondition(metadata != nil, "The fixture must reach the pending metadata boundary")
      switch invalidation {
      case "disable": preferences.set(false, for: .screenLanguage); preferences.set(true, for: .screenLanguage)
      case "deactivate": pending.deactivate()
      case "commit": pending.finishFirstWord()
      case "timeout": wait(0.08)
      case "focus": current = ScreenLanguageCaptureContext(processID: getpid(), caret: anchor.caret,
        primaryScreenHeight: 900, allowed: true, insertionAnchor: 20)
      case "text": prefix = "Hello "
      case "restricted": current = ScreenLanguageCaptureContext(processID: getpid(), caret: anchor.caret,
        primaryScreenHeight: 900, allowed: false)
      default: break
      }
      metadata?(ScreenLanguageCaptureWindow(frame: .init(x: 0, y: 0, width: 800, height: 600),
        captureImage: { _, complete in screenshots += 1; complete(nil) }))
      wait(0.03)
      precondition(screenshots == (invalidation == "none" ? 1 : 0),
        "Pending metadata must not start a screenshot after \(invalidation)")
      precondition(ScreenProtocol.requests == beforeRequests, "The fixture must never upload an image")
      pending.deactivate()
    }
    print("PASS: nonblocking screen transport, shared capture cooldown, deferred cancellation, context revalidation and fallback")
  }
}
