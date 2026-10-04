// Public documentation fixture, rendered from the actual SquirrelPanel.
// Original Telepathy demo harness. GPL-3.0-only.
import AppKit
import InputMethodKit

// The production support code needs these paths but no input-method server is
// started. All Rime state and preferences are scoped to this fixture.
struct SquirrelApp {
  static let appDir = Bundle.main.bundleURL
  static let userDir = FileManager.default.temporaryDirectory
  static let logDir = FileManager.default.temporaryDirectory
}

private let prefix = "作为消费者，我们有依法要求商家提供合格产品的"
private let pinyin = "quanli"

private func fail(_ message: String) -> Never {
  fputs("Native demo: \(message)\n", stderr)
  exit(1)
}

private func cachedImage(_ view: NSView) -> NSImage {
  view.layoutSubtreeIfNeeded()
  view.displayIfNeeded()
  guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    fail("Unable to allocate an AppKit view snapshot")
  }
  view.cacheDisplay(in: view.bounds, to: rep)
  let image = NSImage(size: view.bounds.size)
  image.addRepresentation(rep)
  return image
}

private final class DemoDocument: NSView {
  override var isFlipped: Bool { true }
  let panelImage: NSImage
  let panelOrigin: NSPoint
  init(panel: NSImage) {
    panelImage = panel
    panelOrigin = NSPoint(x: min(490, 1064 - panel.size.width), y: 291)
    super.init(frame: NSRect(x: 0, y: 0, width: 1120, height: 574))
    let title = NSTextField(labelWithString: "Consumer rights")
    title.font = .systemFont(ofSize: 14, weight: .medium)
    title.textColor = .secondaryLabelColor
    title.frame = NSRect(x: 56, y: 51, width: 500, height: 24)
    addSubview(title)
    let heading = NSTextField(labelWithString: "A little context. The right word.")
    heading.font = .systemFont(ofSize: 29, weight: .semibold)
    heading.textColor = NSColor(srgbRed: 0.10, green: 0.20, blue: 0.16, alpha: 1)
    heading.frame = NSRect(x: 56, y: 85, width: 1000, height: 42)
    addSubview(heading)
    let explanation = NSTextField(labelWithString: "Typing quanli after a sentence about consumer rights")
    explanation.font = .systemFont(ofSize: 17)
    explanation.textColor = .secondaryLabelColor
    explanation.frame = NSRect(x: 56, y: 139, width: 1000, height: 28)
    addSubview(explanation)
    let document = NSTextView(frame: NSRect(x: 56, y: 216, width: 1008, height: 71))
    document.drawsBackground = false
    document.isEditable = false
    document.isSelectable = false
    document.textContainerInset = .zero
    document.textContainer?.lineFragmentPadding = 0
    let text = NSMutableAttributedString(string: prefix, attributes: [
      .font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.labelColor])
    text.append(NSAttributedString(string: pinyin, attributes: [
      .font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.labelColor,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .underlineColor: NSColor.secondaryLabelColor]))
    document.textStorage?.setAttributedString(text)
    addSubview(document)
    let footer = NSTextField(labelWithString: "Native macOS candidate panel · Synthetic example")
    footer.font = .systemFont(ofSize: 13)
    footer.textColor = .tertiaryLabelColor
    footer.frame = NSRect(x: 56, y: 514, width: 1000, height: 24)
    addSubview(footer)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func draw(_ dirtyRect: NSRect) {
    NSColor(srgbRed: 0.965, green: 0.973, blue: 0.963, alpha: 1).setFill()
    bounds.fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 28, y: 190, width: 1064, height: 295), xRadius: 12, yRadius: 12).fill()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
    shadow.shadowOffset = NSSize(width: 0, height: 4)
    shadow.shadowBlurRadius = 11
    shadow.set()
    panelImage.draw(in: NSRect(origin: panelOrigin, size: panelImage.size), from: .zero,
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
  }
}

@main struct TelepathyNativeDemo {
  static func main() throws {
    guard CommandLine.arguments.count >= 5 else { fail("Run scripts/render_demo.py") }
    let shared = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let user = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let output = URL(fileURLWithPath: CommandLine.arguments[3])
    let snapshotURL = URL(fileURLWithPath: CommandLine.arguments[4])
    let replay = CommandLine.arguments.contains("--replay")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .aqua)
    app.finishLaunching()
    let defaults = UserDefaults.standard
    let domain = Bundle.main.bundleIdentifier!
    defaults.removePersistentDomain(forName: domain)
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(4, forKey: TelepathyPreferences.Key.rows.rawValue)
    defaults.set(22, forKey: TelepathyPreferences.Key.font.rawValue)
    defaults.set(false, forKey: TelepathyPreferences.Key.annotations.rawValue)
    defaults.set(false, forKey: TelepathyPreferences.Key.inferenceAccent.rawValue)
    let previous = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(shared.path)
    defer { FileManager.default.changeCurrentDirectoryPath(previous) }
    let api = rime_get_api_stdbool().pointee
    var traits = RimeTraits.rimeStructInit()
    traits.setCString(shared.path, to: \.shared_data_dir)
    traits.setCString(user.path, to: \.user_data_dir)
    traits.setCString(user.path, to: \.log_dir)
    traits.setCString("telepathy.documentation", to: \.app_name)
    traits.min_log_level = 3
    api.setup(&traits)
    api.initialize(&traits)
    defer { api.finalize() }
    let session = api.create_session()
    guard session != 0, api.select_schema(session, "wanxiang") else { fail("Unable to open the bundled schema") }
    defer { _ = api.destroy_session(session) }
    for option in ["ascii_mode", "context_reorder", "s2t", "s2hk", "s2tw"] {
      api.set_option(session, option, false)
    }
    for character in pinyin.utf8 { _ = api.process_key(session, Int32(character), 0) }
    var context = RimeContext_stdbool.rimeStructInit()
    guard api.get_context(session, &context) else { fail("The schema returned no candidates") }
    defer { _ = api.free_context(&context) }
    let count = Int(context.menu.num_candidates)
    guard count == 12 else { fail("Expected the app's twelve-candidate page; got \(count)") }
    let candidates = (0..<count).map { String(cString: context.menu.candidates[$0].text) }
    var ends = [Int32](repeating: -1, count: count)
    ends.withUnsafeMutableBufferPointer { tp_candidate_ends(session, Int32(count), $0.baseAddress) }
    let request: [String: Any] = ["revision": 1, "prefix": prefix, "pinyin": pinyin, "pending": pinyin,
                                  "candidates": candidates, "candidate_ends": ends.map(Int.init)]
    var decision: [String: Any]?
    if replay {
      let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as! [String: Any]
      guard let original = saved["request"] as? [String: Any],
            original["candidates"] as? [String] == candidates,
            original["prefix"] as? String == prefix,
            original["pinyin"] as? String == pinyin else { fail("Replay fixture differs from the native snapshot") }
      decision = saved["decision"] as? [String: Any]
    } else {
      var http = URLRequest(url: URL(string: "http://127.0.0.1:18765/api/decision")!)
      http.httpMethod = "POST"
      http.setValue("application/json", forHTTPHeaderField: "Content-Type")
      http.httpBody = try JSONSerialization.data(withJSONObject: request)
      http.timeoutInterval = 15
      let semaphore = DispatchSemaphore(value: 0)
      let task = URLSession.shared.dataTask(with: http) { data, response, error in
        defer { semaphore.signal() }
        if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data {
          decision = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
      }
      task.resume()
      guard semaphore.wait(timeout: .now() + 20) == .success else {
        task.cancel(); fail("The local worker timed out")
      }
    }
    guard let decision, decision["status"] as? String == "ok", decision["ranked"] as? Bool == true,
          let order = decision["order"] as? [Int], order.sorted() == Array(0..<count),
          candidates[order[0]] == "权利" else { fail("The local worker did not choose 权利 for the consumer-rights context") }
    if !replay {
      let fixture: [String: Any] = ["request": request, "decision": decision,
        "source": "Bundled wanxiang schema and one local Kev decision; entirely synthetic text."]
      try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: snapshotURL)
    }
    let config = SquirrelConfig()
    guard config.openBaseConfig() else { fail("Unable to open the app's panel configuration") }
    let panel = SquirrelPanel(position: NSRect(x: 400, y: 500, width: 1, height: 26))
    panel.load(config: config, forDarkMode: false)
    panel.load(config: config, forDarkMode: true)
    panel.update(preedit: "", selRange: NSRange(location: 0, length: 0), caretPos: 0,
                 candidates: order.map { candidates[$0] }, comments: Array(repeating: "", count: count),
                 labels: (1...count).map(String.init), highlighted: 0, page: 0,
                 lastPage: context.menu.is_last_page, update: true)
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    guard let content = panel.contentView else { fail("The candidate panel has no content view") }
    let panelImage = cachedImage(content)
    panel.hide()
    guard panelImage.size.width > 200, panelImage.size.height > 60 else { fail("Candidate panel did not lay out") }
    let document = DemoDocument(panel: panelImage)
    let window = NSWindow(contentRect: document.frame, styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
    window.title = "Telepathy · Native typing demo"
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = document
    let scene = cachedImage(document)
    let pixelWidth = 2240, pixelHeight = 1148
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = document.frame.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    scene.draw(in: document.bounds)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output)
    window.close()
    print("Rendered the actual SquirrelPanel: \(order.map { candidates[$0] }.joined(separator: ", "))")
  }
}
