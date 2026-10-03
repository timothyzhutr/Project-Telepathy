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

@main struct CreditsOpenerTests {
  static func main() {
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
    guard let window = app.windows.first(where: { $0.title == "Telepathy — Credits and licenses" }),
          window.isVisible, let content = window.contentView,
          let tabs = descendants(content, of: NSTabView.self).first,
          tabs.tabViewItems.map({ $0.label }) == ["Credits", "Licenses"],
          let creditsView = tabs.tabViewItems[0].view,
          let credits = descendants(creditsView, of: NSTextView.self).first,
          credits.string.contains("librime 1.17.0"),
          !credits.string.contains("| Component |"),
          let licenseView = tabs.tabViewItems[1].view,
          let table = descendants(licenseView, of: NSTableView.self).first,
          table.numberOfRows > 40,
          let license = descendants(licenseView, of: NSTextView.self).first,
          license.string.contains("GNU GENERAL PUBLIC LICENSE") else {
      fatalError("The native window must display readable credits and bundled license texts")
    }
    guard tabs.selectedTabViewItem === tabs.tabViewItems[0] else {
      fatalError("The window must open on Credits")
    }
    let names = (0..<table.numberOfRows).compactMap {
      table.dataSource?.tableView?(table, objectValueFor: table.tableColumns[0], row: $0) as? String
    }
    guard !names.contains(where: { $0.contains("__pycache__") || $0.hasSuffix(".pyc") }) else {
      fatalError("License rows must exclude Python bytecode and caches")
    }
    tabs.selectTabViewItem(at: 1)
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
    tabs.selectTabViewItem(at: 0)
    print("PASS: native credits/licenses, filtering, read failures, copy/select/close shortcuts, reopening")
    if CommandLine.arguments.contains("--preview") { app.run() }
    window.close()
  }
}
