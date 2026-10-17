import AppKit

@main struct ScreenLanguageHintTests {
  static func main() {
    var state = ScreenLanguageHintState()
    precondition(state.activate(identity: "first"))
    let revision = state.revision
    precondition(!state.activate(identity: "first"), "Duplicate activation must not reset the first word")
    precondition(state.beginRequest() == revision)
    precondition(state.beginRequest() == nil, "Only one capture is allowed in a focused session")
    precondition(state.accept("english", revision: revision, precedingText: " \n"))
    precondition(state.language(precedingText: "") == "english")
    precondition(state.language(precedingText: "中文：") == nil, "Text context always wins")
    state.finishFirstWord()
    precondition(state.language(precedingText: "") == nil, "No hint is allowed after committing the first word")
    precondition(!state.accept("chinese", revision: revision, precedingText: ""))
    precondition(state.activate(identity: "first"), "A later explicit activation must rearm a completed field even when the browser reuses its client")
    state.deactivate()
    precondition(state.activate(identity: "second"))
    precondition(!state.accept("english", revision: revision, precedingText: ""), "Stale activation must be rejected")
    let second = state.beginRequest()!
    state.cancel()
    precondition(!state.accept("english", revision: second, precedingText: ""), "Manual choices or assistance changes cancel pending hints")
    precondition(state.beginRequest() == nil, "Cancelled focus must not retry on every character")
    state.deactivate()
    precondition(state.activate(identity: "third"))
    precondition(state.language(precedingText: "") == nil, "Typing does not wait for capture")
    let third = state.beginRequest()!
    precondition(!state.accept("english", revision: third, precedingText: "Hello "), "Nonempty context discards a pending screen hint")
    precondition(!ScreenLanguageCapturePolicy.allowed(permission: false, secureInput: false, restrictedClient: false))
    precondition(!ScreenLanguageCapturePolicy.allowed(permission: true, secureInput: true, restrictedClient: false))
    precondition(!ScreenLanguageCapturePolicy.allowed(permission: true, secureInput: false, restrictedClient: true))
    precondition(ScreenLanguageCapturePolicy.allowed(permission: true, secureInput: false, restrictedClient: false))
    let size = ScreenLanguageImage.scaledSize(CGSize(width: 3000, height: 2000))
    precondition(size == CGSize(width: 960, height: 640) && size.width * size.height < 1_000_000)
    let marker = ScreenLanguageImage.markerRect(caret: CGRect(x: 130, y: 700, width: 1, height: 20),
      window: CGRect(x: 100, y: 100, width: 800, height: 600), primaryScreenHeight: 900,
      output: CGSize(width: 800, height: 600))!
    precondition(marker.minX == 30 && marker.minY == 80, "AppKit bottom-left caret must map into top-left window image coordinates")
    precondition(ScreenLanguageImage.markerRect(caret: .zero, window: .init(x: 0, y: 0, width: 800, height: 600),
      primaryScreenHeight: 900, output: .init(width: 800, height: 600)) == nil)
    let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(.init(x: 0, y: 0, width: 800, height: 600))
    let png = ScreenLanguageImage.png(context.makeImage()!, caret: .init(x: 130, y: 700, width: 1, height: 20),
      window: .init(x: 100, y: 100, width: 800, height: 600), primaryScreenHeight: 900)!
    let bitmap = NSBitmapImageRep(data: png)!
    let blue = bitmap.colorAt(x: 22, y: 80)!.usingColorSpace(.deviceRGB)!
    let opposite = bitmap.colorAt(x: 22, y: 520)!.usingColorSpace(.deviceRGB)!
    precondition(blue.blueComponent > 0.9 && blue.redComponent < 0.1 && opposite.redComponent > 0.9,
      "The PNG must mark the actual input location rather than its vertical mirror")
    print("PASS: focused-session screen hints, cancellation, text/manual precedence, privacy, sizing and caret coordinates")
  }
}
