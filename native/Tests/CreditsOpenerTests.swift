import AppKit
import InputMethodKit
import ObjectiveC

// Supply the app paths without starting an input-method server in this test.
struct SquirrelApp {
  static let appDir = Bundle.main.bundleURL
  static let userDir = FileManager.default.temporaryDirectory
  static let logDir = FileManager.default.temporaryDirectory
}

private var openedDocuments = [URL]()
private var openedApplication: URL?
private var defaultHandlerUsed = false
private var copiedFrom: NSTextView?

private final class TestHealthProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.absoluteString == "http://127.0.0.1:18765/api/health"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"app":"Telepathy","status":"ready"}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main struct CreditsOpenerTests {
  static func main() {
    URLProtocol.registerClass(TestHealthProtocol.self)
    defer { URLProtocol.unregisterClass(TestHealthProtocol.self) }
    // Intercept only the OS launch boundary so the real menu action can be
    // tested without launching whichever app owns the user's Markdown files.
    let defaultMethod = class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString("openURL:"))!
    let explicitMethod = class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString("openURLs:withApplicationAtURL:configuration:completionHandler:"))!
    let captureDefault: @convention(c) (AnyObject, Selector, NSURL) -> Bool = { _, _, url in
      openedDocuments = [url as URL]
      defaultHandlerUsed = true
      return true
    }
    let captureExplicit: @convention(c) (AnyObject, Selector, NSArray, NSURL, AnyObject, AnyObject?) -> Void = { _, _, urls, app, _, _ in
      openedDocuments = urls as! [URL]
      openedApplication = app as URL
    }
    let previousDefault = method_setImplementation(defaultMethod, unsafeBitCast(captureDefault, to: IMP.self))
    let previousExplicit = method_setImplementation(explicitMethod, unsafeBitCast(captureExplicit, to: IMP.self))
    defer {
      method_setImplementation(defaultMethod, previousDefault)
      method_setImplementation(explicitMethod, previousExplicit)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let cache = Bundle.main.resourceURL!.appendingPathComponent("licenses/__pycache__/test.pyc")
    try! FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data([0xff]).write(to: cache)
    defer { try? FileManager.default.removeItem(at: cache) }
    let delegate = SquirrelApplicationDelegate()
    delegate.openWiki()
    guard openedDocuments.isEmpty, !defaultHandlerUsed, openedApplication == nil else {
      fputs("FAIL: Credits must open inside Telepathy without launching an external application.\n", stderr)
      exit(1)
    }
    func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
      let matches = (view as? T).map { [$0] } ?? []
      return matches + view.subviews.flatMap { descendants($0, of: type) }
    }
    guard let window = app.windows.first(where: { $0.title == "Telepathy" }),
          window.isVisible, let content = window.contentView,
          let tabs = descendants(content, of: NSTabView.self).first,
          tabs.tabViewItems.map({ $0.label }) == ["Settings", "Credits", "Licenses"],
          let creditsView = tabs.tabViewItems[1].view,
          let credits = descendants(creditsView, of: NSTextView.self).first,
          credits.string.contains("librime 1.17.0"),
          !credits.string.contains("| Component |"),
          let licenseView = tabs.tabViewItems[2].view,
          let table = descendants(licenseView, of: NSTableView.self).first,
          table.numberOfRows > 40,
          let license = descendants(licenseView, of: NSTextView.self).first,
          license.string.contains("GNU GENERAL PUBLIC LICENSE") else {
      fatalError("The native window must display readable credits and bundled license texts")
    }
    guard tabs.selectedTabViewItem === tabs.tabViewItems[1] else {
      fatalError("The window must open on Credits")
    }
    // Clicking the tab itself must refresh health, even when Settings was not
    // opened through the input-source menu. Stub only the HTTP boundary.
    tabs.selectTabViewItem(at: 0)
    let status = descendants(tabs.tabViewItems[0].view!, of: NSTextField.self).first(where: { $0.stringValue == "Checking model status…" })!
    let deadline = Date().addingTimeInterval(0.5)
    while status.stringValue == "Checking model status…", Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    guard status.stringValue == "Kev is ready · Runs on this Mac" else {
      fatalError("Clicking the Settings tab must fetch and display worker health")
    }
    let defaults = UserDefaults.standard
    defer {
      for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("Telepathy") || key == "KevEnabled" {
        defaults.removeObject(forKey: key)
      }
    }
    func control<T: NSControl>(_ name: String, _ type: T.Type) -> T {
      guard let view = descendants(tabs.tabViewItems[0].view!, of: type).first(where: { $0.identifier?.rawValue == name }) else {
        fatalError("Missing settings control: \(name)")
      }
      return view
    }
    func change(_ control: NSControl) {
      guard let action = control.action else { fatalError("Settings controls must be functional") }
      app.sendAction(action, to: control.target, from: control)
    }
    let rows = control("settings.rows", NSPopUpButton.self)
    rows.selectItem(withTag: 3); change(rows)
    guard defaults.integer(forKey: "TelepathyCandidatesPerRow") == 3 else { fatalError("Row layout must persist") }
    let font = control("settings.font", NSSlider.self)
    font.doubleValue = 22; change(font)
    guard defaults.integer(forKey: "TelepathyFontSize") == 22 else { fatalError("Text size must persist") }
    let panel = SquirrelPanel(position: NSRect(x: 400, y: 400, width: 0, height: 0))
    panel.load(config: SquirrelConfig(), forDarkMode: false)
    panel.load(config: SquirrelConfig(), forDarkMode: true)
    let samples = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸", "子", "丑"]
    panel.update(preedit: "", selRange: .init(location: 0, length: 0), caretPos: 0,
                 candidates: samples, comments: Array(repeating: "", count: 12),
                 labels: (1...12).map(String.init), highlighted: 0, page: 0, lastPage: true, update: true)
    let candidateText = descendants(panel.contentView!, of: NSTextView.self).first!
    let rendered = candidateText.textContentStorage?.attributedString?.string ?? ""
    guard rendered.components(separatedBy: "\n").count == 4,
          samples.allSatisfy({ rendered.contains($0) }) else {
      fatalError("The actual typing panel must show three candidates per row without losing any of the twelve")
    }
    let wordOffset = (rendered as NSString).range(of: "甲").location
    let wordFont = candidateText.textContentStorage?.attributedString?.attribute(.font, at: wordOffset, effectiveRange: nil) as? NSFont
    guard wordFont?.pointSize == 22 else { fatalError("The actual typing panel must apply the saved text size") }
    panel.hide()
    let kev = control("settings.kev", NSButton.self)
    kev.state = .off; change(kev)
    guard defaults.object(forKey: "KevEnabled") as? Bool == false else { fatalError("Settings must share the existing Kev menu preference") }
    delegate.openSettings()
    guard tabs.selectedTabViewItem?.label == "Settings", app.windows.filter({ $0.title == window.title }).count == 1 else {
      fatalError("Settings must open in the retained credits window")
    }
    defaults.set("preserve", forKey: "UnrelatedPreference")
    let reset = descendants(tabs.tabViewItems[0].view!, of: NSButton.self).first(where: { $0.title == "Restore default settings" })!
    change(reset)
    guard defaults.object(forKey: "KevEnabled") == nil, rows.selectedTag() == 0,
          font.intValue == 16, defaults.string(forKey: "UnrelatedPreference") == "preserve" else {
      fatalError("Restoring defaults must refresh controls and preserve unrelated preferences")
    }
    defaults.removeObject(forKey: "UnrelatedPreference")
    let names = (0..<table.numberOfRows).compactMap {
      table.dataSource?.tableView?(table, objectValueFor: table.tableColumns[0], row: $0) as? String
    }
    guard !names.contains(where: { $0.contains("__pycache__") || $0.hasSuffix(".pyc") }) else {
      fatalError("License rows must exclude Python bytecode and caches")
    }
    tabs.selectTabViewItem(at: 2)
    let kevRow = names.firstIndex(of: "Kev-Apache-2.0.txt")!
    let kevURL = Bundle.main.resourceURL!.appendingPathComponent("licenses/Kev-Apache-2.0.txt")
    let original = try! Data(contentsOf: kevURL)
    try! Data([0xff]).write(to: kevURL)
    table.selectRowIndexes(IndexSet(integer: kevRow), byExtendingSelection: false)
    let readFailedSafely = license.string.contains("Unable to read") && !license.string.contains("GNU GENERAL PUBLIC LICENSE")
    try! original.write(to: kevURL)
    guard readFailedSafely else { fatalError("An unreadable file must not display a different license") }
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    table.selectRowIndexes(IndexSet(integer: kevRow), byExtendingSelection: false)
    guard license.string.contains("Apache License") else { fatalError("Selecting a dependency must display its license") }

    // Route key equivalents through AppKit, observing only the final Copy
    // action so the user's clipboard is left intact.
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(license)
    license.setSelectedRange(NSRange(location: 0, length: 6))
    let copy = class_getInstanceMethod(NSTextView.self, #selector(NSText.copy(_:)))!
    let captureCopy: @convention(c) (AnyObject, Selector, AnyObject?) -> Void = { text, _, _ in copiedFrom = text as? NSTextView }
    let previousCopy = method_setImplementation(copy, unsafeBitCast(captureCopy, to: IMP.self))
    func command(_ character: String) {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                  characters: character, charactersIgnoringModifiers: character,
                                  isARepeat: false, keyCode: 0)!
      guard window.performKeyEquivalent(with: event) == true else {
        fatalError("AppKit must route Command-\(character) through the window's responder chain")
      }
    }
    command("c")
    method_setImplementation(copy, previousCopy)
    guard copiedFrom === license, copiedFrom?.selectedRange().length == 6 else {
      fatalError("Command-C must invoke Copy on the selected license text")
    }
    command("a")
    guard license.selectedRange().length == (license.string as NSString).length else {
      fatalError("Command-A must select the license text")
    }
    command("w")
    guard !window.isVisible else { fatalError("Command-W must close the information window") }
    delegate.openWiki()
    guard window.isVisible, app.windows.filter({ $0.title == window.title }).count == 1 else {
      fatalError("Closing and reopening must reuse the same window")
    }
    tabs.selectTabViewItem(at: 1)
    print("PASS: native settings, persistence, panel rows/font, health, scoped reset, credits/licenses, keyboard shortcuts, reopening")
    if CommandLine.arguments.contains("--preview") { delegate.openSettings(); app.run() }
    window.close()
  }
}
