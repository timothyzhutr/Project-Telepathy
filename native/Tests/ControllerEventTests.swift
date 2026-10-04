import AppKit
import InputMethodKit
import ObjectiveC

// Stub only the asynchronous model boundary; the controller, key conversion,
// Rime schema, marked-text updates and commits are the production implementations.
private final class IntentProtocol: URLProtocol {
  static var rankCalls = 0
  static var languageCalls = 0
  static var delay = 0.01
  static var failLanguage = false
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
    if isRank { Self.rankCalls += 1 }
    else { Self.languageCalls += 1 }
    let result: [String: Any] = isRank
      ? ["status": "ok", "revision": body["revision"]!, "order": Array(0..<(body["candidates"] as! [String]).count), "ranked": false]
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
    IntentProtocol.failLanguage = true; IntentProtocol.rankCalls = 0
    key("h"); key("e"); wait(0.2)
    check(IntentProtocol.rankCalls > 0, "A failed language decision must retain Chinese reranking")
    controller.commitComposition(client)
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
    print("PASS: actual controller language commits, contextual punctuation, technical text, settings and skipped inference")
  }
}
