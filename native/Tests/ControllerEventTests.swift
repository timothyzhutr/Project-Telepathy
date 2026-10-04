import AppKit
@_silgen_name("tp_test_probe_count") private func coverageProbeCount() -> Int32
import InputMethodKit
import ObjectiveC

// Stub only the asynchronous model boundary; the controller, key conversion,
// Rime schema, marked-text updates and commits are the production implementations.
private final class IntentProtocol: URLProtocol {
  static var rankCalls = 0
  static var languageCalls = 0
  static var delay = 0.01
  static var failLanguage = false
  static var lastRankingStrategy: String?
  static var lastRankCandidates = [String]()
  static var lastLanguageCandidates = [String]()
  static var reverseRanking = false
  static var inferenceRan = true
  private var work: DispatchWorkItem?
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.path == "/api/language" || request.url?.path == "/api/decision"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let stream = request.httpBodyStream
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream {
      stream.open(); defer { stream.close() }
      var bytes = [UInt8](repeating: 0, count: 1024)
      while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
      }
    }
    let body = (try! JSONSerialization.jsonObject(with: data)) as! [String: Any]
    let isRank = request.url!.path == "/api/decision"
    if isRank {
      Self.rankCalls += 1; Self.lastRankingStrategy = body["strategy"] as? String
      Self.lastRankCandidates = body["candidates"] as! [String]
    }
    else { Self.languageCalls += 1; Self.lastLanguageCandidates = body["candidates"] as! [String] }
    let result: [String: Any] = isRank
      ? ["status": "ok", "revision": body["revision"]!, "order": Self.reverseRanking ? Array((0..<(body["candidates"] as! [String]).count).reversed()) : Array(0..<(body["candidates"] as! [String]).count), "ranked": true, "inferred": Self.inferenceRan, "inferred_indices": Self.inferenceRan ? Array(0..<(body["candidates"] as! [String]).count) : [], "strategy": "continuation", "request_ms": 8]
      : ["status": "ok", "revision": body["revision"]!, "language": (body["prefix"] as! String).hasPrefix("中文") ? "chinese" : "english"]
    let status = !isRank && Self.failLanguage ? 500 : 200
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      self.client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: result))
      self.client?.urlProtocolDidFinishLoading(self)
    }
    self.work = work
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: work)
  }
  override func stopLoading() { work?.cancel() }
}

private final class TextClient: NSObject, IMKTextInput {
  var text = "I think "
  var marked = ""
  func insertText(_ string: Any!, replacementRange: NSRange) {
    text += (string as? NSAttributedString)?.string ?? (string as? String ?? "")
    marked = ""
  }
  func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
    marked = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
  }
  func selectedRange() -> NSRange { .init(location: text.utf16.count, length: 0) }
  func markedRange() -> NSRange { .init(location: marked.isEmpty ? NSNotFound : text.utf16.count, length: marked.utf16.count) }
  func attributedSubstring(from range: NSRange) -> NSAttributedString! { NSAttributedString(string: (text as NSString).substring(with: range)) }
  func length() -> Int { text.utf16.count }
  func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
  func attributes(forCharacterIndex index: Int, lineHeightRectangle: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
    lineHeightRectangle.pointee = .init(x: 300, y: 300, width: 1, height: 20); return [:]
  }
  func validAttributesForMarkedText() -> [Any]! { [] }
  func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
  func selectMode(_ modeIdentifier: String!) {}
  func supportsUnicode() -> Bool { true }
  func bundleIdentifier() -> String! { "local.telepathy.tests.client" }
  func windowLevel() -> CGWindowLevel { 0 }
  func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
  func uniqueClientIdentifierString() -> String! { "telepathy-controller-test" }
  func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { (text as NSString).substring(with: range) }
  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}

enum ControllerEventTests {
  static func run(delegate: SquirrelApplicationDelegate) {
    let root = Bundle.main.bundleURL.deletingLastPathComponent()
    let shared = root.appendingPathComponent("package-data/SharedSupport")
    let user = FileManager.default.temporaryDirectory.appendingPathComponent("telepathy-controller-" + UUID().uuidString)
    try! FileManager.default.copyItem(at: root.appendingPathComponent("package-data/Resources/Profile"), to: user)
    let previous = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(shared.path)
    defer { FileManager.default.changeCurrentDirectoryPath(previous); try? FileManager.default.removeItem(at: user) }
    let api = rime_get_api_stdbool().pointee
    var traits = RimeTraits.rimeStructInit()
    traits.setCString(shared.path, to: \.shared_data_dir); traits.setCString(user.path, to: \.user_data_dir)
    traits.setCString(user.path, to: \.log_dir); traits.setCString("telepathy.test", to: \.app_name)
    traits.min_log_level = 3
    api.setup(&traits); api.initialize(&traits)
    defer { api.finalize() }
    NSApp.delegate = delegate
    delegate.panel = SquirrelPanel(position: .zero); delegate.loadSettings()
    TelepathyPreferences.shared.set(true, for: .kev)
    TelepathyPreferences.shared.set(true, for: .autoLanguage)
    URLProtocol.registerClass(IntentProtocol.self)
    defer { URLProtocol.unregisterClass(IntentProtocol.self); delegate.panel?.hide() }
    // Custom ephemeral sessions do not inherit URLProtocol's global registry.
    let configuration = class_getClassMethod(URLSessionConfiguration.self, NSSelectorFromString("ephemeralSessionConfiguration"))!
    let localHTTP: @convention(c) (AnyObject, Selector) -> AnyObject = { _, _ in
      let config = URLSessionConfiguration.default
      config.protocolClasses = [IntentProtocol.self]
      return config
    }
    let previousConfiguration = method_setImplementation(configuration, unsafeBitCast(localHTTP, to: IMP.self))
    defer { method_setImplementation(configuration, previousConfiguration) }
    let server = IMKServer(name: "TelepathyTest_" + UUID().uuidString, bundleIdentifier: Bundle.main.bundleIdentifier!)!
    let client = TextClient()
    // InputMethodKit requires its private cross-process client proxy. Replace
    // only that initializer boundary with the in-process test client.
    let initialize = class_getInstanceMethod(IMKInputController.self, NSSelectorFromString("initWithServer:delegate:client:"))!
    let localClient: @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> AnyObject = { object, _, _, _, _ in object }
    let previousInitialize = method_setImplementation(initialize, unsafeBitCast(localClient, to: IMP.self))
    let controller = SquirrelInputController(server: server, delegate: nil, client: client)!
    method_setImplementation(initialize, previousInitialize)
    func wait(_ seconds: Double = 0.15) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    @discardableResult func key(_ chars: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) -> Bool {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                  windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                  isARepeat: false, keyCode: code)!
      let consumed = controller.handle(event, client: client)
      if !consumed, flags.intersection([.command, .control, .option]).isEmpty,
         chars.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) { client.text += chars }
      return consumed
    }
    func shift(_ down: Bool) {
      _ = controller.handle(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: down ? .shift : [],
        timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: 56)!, client: client)
    }
    func check(_ ok: Bool, _ message: String) { if !ok { fatalError(message) } }
    key("h"); key("e"); wait()
    check(client.marked == "he", "English must display the original raw text")
    check(IntentProtocol.rankCalls == 0, "Early English must skip pointer reranking")
    key(" ", code: 49)
    check(client.text == "I think he ", "English Space must commit raw text plus one space; got \(client.text), language calls \(IntentProtocol.languageCalls)")
    key(".", code: 47)
    check(client.text == "I think he .", "English period after committing a word must stay ASCII")
    shift(true); key("H", flags: .shift); shift(false)
    check(!key("e"), "Shift-release must preserve the literal run after H")
    key("l"); key("l"); key("o"); key(" ", code: 49)
    check(client.text.hasSuffix("Hello "), "Capitals and subsequent letters must reach the host unchanged")
    key("h"); key("e"); wait()
    controller.deactivateServer(client)
    check(client.text.hasSuffix("Hello he"), "Deactivation must commit English raw, not a Chinese candidate")
    controller.activateServer(client)
    IntentProtocol.delay = 0.15; IntentProtocol.rankCalls = 0
    key("h"); key("e"); wait(0.4)
    check(IntentProtocol.rankCalls == 0, "Delayed English must skip full reranking after the debounce deadline")
    key(" ", code: 49)
    IntentProtocol.delay = 0.01
    key("h"); key("e"); wait()
    let beforeChinese = client.text
    key("\u{f701}", code: 125)
    key("n"); wait()
    check(IntentProtocol.rankCalls > 0, "Editing after manual Chinese override must resume candidate ranking")
    key(" ", code: 49)
    check(!client.text.dropFirst(beforeChinese.count).allSatisfy({ $0.isASCII }), "Down must restore Chinese Space selection")
    for navigate in [0, 1] {
      let before = client.text
      key("h"); key("e"); wait(); key("\u{f701}", code: 125)
      if navigate == 0 {
        check(controller.page(up: false) && controller.page(up: true), "Fixture must have another candidate page")
      } else {
        check(controller.moveCaret(forward: true) && controller.moveCaret(forward: false), "Fixture must permit caret navigation")
      }
      wait(); key(" ", code: 49)
      check(!client.text.dropFirst(before.count).allSatisfy({ $0.isASCII }), "Paging or caret navigation must preserve manual Chinese intent")
    }
    client.text = "中文："
    key("n"); key("i"); key("h"); key("a"); key("o"); wait()
    let beforeEdit = client.marked
    check(key("w", flags: .control) && client.marked != beforeEdit, "Chinese Control+w must retain Rime word deletion")
    controller.commitComposition(client)
    client.text = "I think "
    TelepathyPreferences.shared.set("continuation", for: .rankingStrategy)
    controller.preferencesDidChange()
    IntentProtocol.failLanguage = true; IntentProtocol.rankCalls = 0
    key("h"); key("e"); wait(0.2)
    check(IntentProtocol.rankCalls > 0, "A failed language decision must retain Chinese reranking")
    check(IntentProtocol.lastRankingStrategy == "continuation", "The native controller must send the selected experimental strategy to the worker")
    controller.commitComposition(client)
    TelepathyPreferences.shared.set("kev", for: .rankingStrategy)
    controller.preferencesDidChange()
    IntentProtocol.failLanguage = false
    IntentProtocol.delay = 0.25
    key("h"); key("e")
    controller.commitComposition(client)
    let committed = client.text
    wait(0.35)
    check(client.text == committed && client.marked.isEmpty, "Late judgments must never rewrite committed text")
    IntentProtocol.delay = 0.01
    for (prefix, mark, expected) in [
      ("中文句子", ",", "，"), ("I think so ", ".", "."),
      ("这个项目叫 ProjectTelepathy", ",", "，"), ("Python 的速度不错", ".", "。"),
      ("I like 中文", "?", "?"), ("版本号是 3", ".", "."),
      ("访问 https://example", ".", "."), ("邮件发到 name@example", ".", "."),
      ("中文代码 `x = 1", ";", ";"), ("说明（English text", ")", "）"),
      ("Example (中文", ")", ")"), ("他说：“hello", "\"", "”"),
      ("他说：‘hello", "'", "’"), ("访问（https://example.com", ")", "）")
    ] {
      client.text = prefix
      let calls = IntentProtocol.languageCalls + IntentProtocol.rankCalls
      check(key(mark), "Automatic punctuation should commit synchronously")
      check(client.text == prefix + expected, "Wrong punctuation for \(prefix): \(client.text)")
      wait(0.02)
      check(IntentProtocol.languageCalls + IntentProtocol.rankCalls == calls, "Punctuation must not request model inference")
    }
    // Punctuation commits the displayed language/candidate and ends composition.
    client.text = "中文："
    key("n"); key("i"); key("h"); key("a"); key("o"); wait()
    key(",")
    check(client.text == "中文：你好，" && client.marked.isEmpty, "Chinese composition must commit before punctuation")
    client.text = "I think "
    key("h"); key("e"); wait(); key(",")
    check(client.text == "I think he," && client.marked.isEmpty, "English composition must stay literal before punctuation")
    client.text = "中文价格是 3"
    key("."); key("1"); key("4"); key(",")
    key("k"); key("e"); key("y"); key("i"); wait(); key(" ", code: 49)
    check(client.text.hasSuffix("可以"), "A decimal must not make following Chinese pinyin literal: \(client.text)")
    client.text = "中文访问 "
    key("w"); key("w"); key("w"); key(".")
    check(client.text == "中文访问 www.", "An explicit URL start must preserve raw letters before its first dot")
    key("e"); key("x"); key("a"); key("m"); key("p"); key("l"); key("e"); key("."); key("c"); key("o"); key("m"); key(" ", code: 49)
    check(client.text == "中文访问 www.example.com ", "An address must stay literal through its punctuation")
    client.text = "中文："
    key("x"); key("i"); key("'")
    check(!client.marked.isEmpty && client.text == "中文：", "Pinyin apostrophe must remain a syllable separator")
    controller.commitComposition(client)
    TelepathyPreferences.shared.set(false, for: .autoPunctuation)
    controller.preferencesDidChange()
    client.text = "English text "
    key(".")
    check(client.text == "English text 。", "Disabling Auto punctuation must restore configured Chinese forms")
    TelepathyPreferences.shared.set(true, for: .autoPunctuation)
    TelepathyPreferences.shared.set(false, for: .punctuation)
    controller.preferencesDidChange()
    client.text = "中文句子"
    key(",")
    check(client.text == "中文句子,", "The ASCII punctuation override must take precedence")
    TelepathyPreferences.shared.set(true, for: .punctuation)
    controller.preferencesDidChange()
    key("#", code: 20, flags: [.control, .shift])
    client.text = "中文句子"
    key(",")
    check(client.text == "中文句子,", "Rime's manual ASCII punctuation shortcut must take precedence")
    key("#", code: 20, flags: [.control, .shift])
    controller.deactivateServer(client)
    controller.activateServer(client)
    let defaults = UserDefaults.standard
    defaults.set(12, forKey: "TelepathyCandidatesToRank")
    defaults.set(6, forKey: "TelepathyCandidatesToShow")
    TelepathyPreferences.shared.set(false, for: .autoLanguage)
    controller.preferencesDidChange()
    IntentProtocol.reverseRanking = true
    func renderedCandidates() -> String {
      func findText(_ view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.compactMap(findText).first
      }
      return findText(delegate.panel!.contentView!)!.textContentStorage?.attributedString?.string ?? ""
    }
    func highlightedColor() -> NSColor {
      let view = delegate.panel!.contentView!.subviews.compactMap { $0 as? SquirrelView }.first!
      return view.textContentStorage.attributedString!.attribute(.foregroundColor, at: view.candidateRanges[view.hilightedIndex].location, effectiveRange: nil) as! NSColor
    }
    func typeLe() {
      client.text = "中文："; key("l"); key("e"); wait(0.25)
    }
    typeLe()
    let all = IntentProtocol.lastRankCandidates
    check(all.count == 12, "The ranking pool must remain twelve while only six are shown")
    let reversed = Array(all.reversed())
    let inferredColor = highlightedColor()
    controller.commitComposition(client)
    let beforeFastTyping = coverageProbeCount()
    client.text = "中文："; key("l"); key("e")
    check(coverageProbeCount() == beforeFastTyping, "Fast typing must defer native coverage probes until the snapshot debounce")
    wait(0.25)
    check(coverageProbeCount() == beforeFastTyping + 1, "Only the settled composition needs a coverage probe")
    controller.commitComposition(client)
    typeLe(); key("\u{f703}", code: 124); key(" ", code: 49)
    check(client.text == "中文：" + reversed[1], "Right must select the next displayed ranked candidate")
    typeLe(); key("\u{f703}", code: 124); key("\u{f702}", code: 123); key(" ", code: 49)
    check(client.text == "中文：" + reversed[0], "Left must return through the displayed ranked order")
    typeLe(); for _ in 0..<10 { key("\u{f703}", code: 124) }; key(" ", code: 49)
    check(client.text == "中文：" + reversed[5], "Right must stop at the last visible candidate")
    IntentProtocol.delay = 0.25
    client.text = "中文："; key("l"); key("e"); wait(0.12)
    key("\u{f703}", code: 124); wait(0.35); key(" ", code: 49)
    check(client.text == "中文：" + all[1], "A late model reply must not override Right navigation")
    IntentProtocol.delay = 0.01
    IntentProtocol.inferenceRan = false
    typeLe()
    let ordinaryColor = highlightedColor()
    check(inferredColor != ordinaryColor, "A model-evaluated candidate must have an accent; fallbacks must retain the normal highlight")
    controller.commitComposition(client)
    IntentProtocol.inferenceRan = true
    defaults.set(false, forKey: "TelepathyInferenceAccent")
    controller.preferencesDidChange()
    typeLe()
    check(highlightedColor() == ordinaryColor, "The accent preference must disable the inference highlight")
    controller.commitComposition(client)
    defaults.removeObject(forKey: "TelepathyInferenceAccent")
    controller.preferencesDidChange()
    typeLe()
    check(!renderedCandidates().contains("Full phrase") && !renderedCandidates().contains("Context") && !renderedCandidates().contains(" ms"),
          "Inference must be indicated visually without adding status text to candidates")
    check(reversed.prefix(6).allSatisfy { renderedCandidates().contains($0) } &&
          reversed.suffix(6).allSatisfy { !renderedCandidates().contains($0) },
          "The panel must show only the six best candidates after ranking")
    let savedAppearance = defaults.object(forKey: "TelepathyAppearance")
    let images = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("inference-accent")
    try! FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    for name in ["light", "dark"] {
      controller.commitComposition(client)
      defaults.set(name, forKey: "TelepathyAppearance")
      delegate.loadSettings(); controller.preferencesDidChange()
      var normal: NSColor?
      for assisted in [false, true] {
        IntentProtocol.inferenceRan = assisted
        typeLe()
        let view = delegate.panel!.contentView!.subviews.compactMap { $0 as? SquirrelView }.first!
        check(view.currentTheme === (name == "dark" ? view.darkTheme : view.lightTheme), "Visual checks must use the packaged light/dark theme")
        let color = highlightedColor()
        if assisted {
          print("Accent QA", name, "rendered", color, "theme", view.currentTheme.inferredLabelAttrs[.foregroundColor]!)
          check(color == view.currentTheme.inferredLabelAttrs[.foregroundColor] as? NSColor, "Text colors must match the current model accent appearance")
          check(color != normal, "The model accent must be distinct in both appearances")
          check(view.inferredCandidates == Set(0..<6), "Every scored visible candidate must retain its status")
        } else { normal = color }
        wait(0.05)
        let content = delegate.panel!.contentView!
        content.displayIfNeeded()
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: images.appendingPathComponent(name + (assisted ? "-inferred.png" : "-ordinary.png")))
        controller.commitComposition(client)
      }
    }
    if let savedAppearance { defaults.set(savedAppearance, forKey: "TelepathyAppearance") }
    else { defaults.removeObject(forKey: "TelepathyAppearance") }
    IntentProtocol.inferenceRan = true
    delegate.loadSettings(); controller.preferencesDidChange()
    typeLe()
    let beforeHiddenKey = client.text
    let beforeHiddenMarked = client.marked
    key("7", code: 26)
    check(client.text == beforeHiddenKey && !client.marked.isEmpty,
          "A number key must never select a hidden candidate")
    key("7", code: 89, flags: .numericPad)
    check(client.text == beforeHiddenKey && client.marked == beforeHiddenMarked,
          "A numeric keypad key must never select a hidden candidate")
    check(!controller.selectCandidate(6), "Clicks outside the displayed page must be rejected")
    for _ in 0..<10 { key("\u{f701}", code: 125) }
    key(" ", code: 49)
    check(client.text == "中文：" + reversed[5], "Arrow navigation must stop at the last visible candidate")
    typeLe(); key("c", code: 8, flags: .command)
    key("7", code: 26)
    check(client.text == "中文：" && !client.marked.isEmpty, "A Command shortcut must not allow hidden candidate selection afterward")
    key("1", code: 18)
    check(client.text == "中文：" + reversed[0], "A Command shortcut must preserve the displayed selection mapping")
    typeLe()
    check(key("=", code: 24), "The paging shortcut must reveal the rest of the ranking pool")
    check(reversed.suffix(6).allSatisfy { renderedCandidates().contains($0) } &&
          reversed.prefix(6).allSatisfy { !renderedCandidates().contains($0) },
          "Paging must reveal candidates seven to twelve without skipping them")
    key("1", code: 18)
    check(client.text == "中文：" + reversed[6], "Number selection on the second displayed page must use its own mapping")
    typeLe(); key("=", code: 24); key("-", code: 78, flags: .numericPad)
    check(reversed.prefix(6).allSatisfy { renderedCandidates().contains($0) }, "Keypad minus must page back within the ranked pool")
    key("=", code: 24); key("1", code: 83, flags: .numericPad)
    check(client.text == "中文：" + reversed[6], "Keypad selection must use the currently displayed candidate mapping")
    defaults.set(3, forKey: "TelepathyCandidatesToRank")
    controller.preferencesDidChange()
    typeLe()
    check(IntentProtocol.lastRankCandidates == Array(all.prefix(3)), "The worker must receive only the configured ranking pool")
    let limited = Array(all.prefix(3).reversed()) + Array(all[3..<6])
    check(limited.allSatisfy { renderedCandidates().contains($0) } &&
          all.suffix(6).allSatisfy { !renderedCandidates().contains($0) },
          "Showing more than are ranked must keep remaining candidates in native order")
    check(highlightedColor() == inferredColor, "The ranked prefix must retain its inference accent")
    for _ in 0..<3 { key("\u{f701}", code: 125) }
    check(highlightedColor() == ordinaryColor, "Unranked candidates must never inherit the inference accent")
    controller.commitComposition(client)
    TelepathyPreferences.shared.set(true, for: .autoLanguage)
    controller.preferencesDidChange()
    typeLe()
    check(IntentProtocol.lastLanguageCandidates == all && IntentProtocol.lastRankCandidates.count == 3,
          "A small ranking budget must not reduce the Chinese/English routing evidence")
    controller.commitComposition(client)
    client.text = "I think "; key("h"); key("e"); wait()
    key("1", code: 83, flags: .numericPad)
    check(client.text == "I think he1", "An English word followed by a keypad digit must commit raw English and pass the digit to the host")
    key(" ", code: 49)
    TelepathyPreferences.shared.set(false, for: .autoLanguage)
    defaults.set(12, forKey: "TelepathyCandidatesToRank")
    defaults.set(1, forKey: "TelepathyCandidatesToShow")
    controller.preferencesDidChange()
    typeLe()
    check(renderedCandidates().contains(reversed[0]) && !renderedCandidates().contains(reversed[1]), "A display count of one must show only the highest-ranked word")
    key("2", code: 19)
    check(client.text == "中文：", "Hidden number keys must be ignored even with one visible candidate")
    check(controller.page(up: false), "A single visible choice must still allow paging")
    key(" ", code: 49)
    check(client.text == "中文：" + reversed[1], "Space must commit the candidate on the current displayed page")
    defaults.set(5, forKey: "TelepathyCandidatesToShow")
    controller.preferencesDidChange()
    typeLe()
    key("\u{f72d}", code: 121); key("\u{f72d}", code: 121)
    check(reversed.suffix(2).allSatisfy { renderedCandidates().contains($0) } &&
          reversed.prefix(10).allSatisfy { !renderedCandidates().contains($0) },
          "Page Down must reach the short final display page")
    let beforeNativePage = coverageProbeCount()
    check(controller.page(up: false), "After exhausting the pool, paging must reach the next Rime page")
    check(coverageProbeCount() == beforeNativePage, "Unranked native pages must bypass coverage probing")
    check(controller.page(up: true), "Paging back from another Rime page must succeed")
    check(all.suffix(2).allSatisfy { renderedCandidates().contains($0) } &&
          all.prefix(10).allSatisfy { !renderedCandidates().contains($0) },
          "Returning from another Rime page must restore its previous last display page")
    key("1", code: 18)
    check(client.text == "中文：" + all[10], "Selection after crossing a Rime page boundary must use the displayed word")
    defaults.set(6, forKey: "TelepathyCandidatesToShow")
    TelepathyPreferences.shared.set(false, for: .kev)
    controller.preferencesDidChange()
    let callsBeforeOff = IntentProtocol.rankCalls
    let probesBeforeOff = coverageProbeCount()
    typeLe()
    check(all.prefix(6).allSatisfy { renderedCandidates().contains($0) } &&
          all.suffix(6).allSatisfy { !renderedCandidates().contains($0) } && IntentProtocol.rankCalls == callsBeforeOff,
          "The display limit must also apply when model assistance is off")
    check(coverageProbeCount() == probesBeforeOff, "Assistance off must bypass coverage probing")
    check(controller.page(up: false) && controller.page(up: true), "Display paging must work without model assistance")
    key("1", code: 18)
    check(client.text == "中文：" + all[0], "Paging back must restore the visible native selection mapping")
    TelepathyPreferences.shared.set(true, for: .kev)
    controller.preferencesDidChange()
    let beforeSymbols = coverageProbeCount(), requestsBeforeSymbols = IntentProtocol.rankCalls
    client.text = "中文："; key("/"); key("f"); key("h"); wait(0.25)
    check(coverageProbeCount() == beforeSymbols && IntentProtocol.rankCalls == requestsBeforeSymbols,
          "Rime symbol input must bypass model requests and probing")
    controller.commitComposition(client)
    controller.deactivateServer(client)
    IntentProtocol.reverseRanking = false
    defaults.removeObject(forKey: "TelepathyCandidatesToRank")
    defaults.removeObject(forKey: "TelepathyCandidatesToShow")
    print("PASS: actual controller language commits, contextual punctuation, technical text, settings and skipped inference")
  }
}
