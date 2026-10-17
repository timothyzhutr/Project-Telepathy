import AppKit
import Carbon
import ScreenCaptureKit

struct ScreenLanguageCaptureContext {
  let processID: pid_t
  let caret: CGRect
  let primaryScreenHeight: CGFloat
  let allowed: Bool
  var focusIdentity: String = ""
  var insertionAnchor: Int?
  var bundleIdentifier: String = ""
  var hasMarkedText = false
  var compositionActive = false
  // Evaluated on the main queue at each asynchronous capture boundary.
  var captureIsCurrent: () -> Bool = { true }
  func mismatchReason(_ other: ScreenLanguageCaptureContext) -> String? {
    if !allowed || !other.allowed { return "context_restricted" }
    if processID != other.processID { return "process_changed" }
    if insertionAnchor != other.insertionAnchor { return "anchor_changed" }
    if focusIdentity != other.focusIdentity { return "focus_identity_changed" }
    if primaryScreenHeight != other.primaryScreenHeight { return "screen_changed" }
    if !sameCaret(other) { return "caret_changed" }
    return nil
  }
  func comparisonFlags(_ other: ScreenLanguageCaptureContext) -> [String: Bool] {
    ["allowed": other.allowed, "same_process": processID == other.processID,
     "same_identity": focusIdentity == other.focusIdentity, "same_anchor": insertionAnchor == other.insertionAnchor,
     "same_screen": primaryScreenHeight == other.primaryScreenHeight, "same_caret": sameCaret(other),
     "marked": other.hasMarkedText, "composition": other.compositionActive]
  }
  private func sameCaret(_ other: ScreenLanguageCaptureContext) -> Bool {
    if caret.height <= 0 || other.caret.height <= 0 { return caret == other.caret }
    return abs(caret.minY - other.caret.minY) <= max(6, min(caret.height, other.caret.height) / 2) &&
      abs(caret.minX - other.caret.minX) <= max(24, min(caret.height, other.caret.height) * 2)
  }
  func matches(_ other: ScreenLanguageCaptureContext) -> Bool {
    mismatchReason(other) == nil
  }
}

// A selected host window and its pixel operation. Keeping metadata and pixels
// separate lets regressions delay metadata without recording the desktop.
struct ScreenLanguageCaptureWindow {
  let frame: CGRect
  let captureImage: (SCStreamConfiguration, @escaping (CGImage?) -> Void) -> Void
}

enum ScreenLanguageCapture {
  typealias ResolveWindow = (ScreenLanguageCaptureContext, @escaping (ScreenLanguageCaptureWindow?) -> Void) -> Void
  // The permission prompt is deliberately confined to the explicit Settings
  // action/CLI. Every automatic path checks permission without requesting it.
  static var permissionGranted: Bool { CGPreflightScreenCaptureAccess() }
  static func capture(_ context: ScreenLanguageCaptureContext, completion: @escaping (Data?) -> Void) {
    capture(context, accessFailure: { accessFailure(context) }, resolveWindow: resolveWindow, completion: completion)
  }
  private static func trace(_ context: ScreenLanguageCaptureContext, _ reason: String, flags: [String: Bool] = [:]) {
    ScreenLanguageDiagnostics.shared.record(status: "capture_event", reason: reason,
      bundleIdentifier: context.bundleIdentifier, flags: flags, updateSummary: false)
  }
  private static func accessFailure(_ context: ScreenLanguageCaptureContext) -> String? {
    if !context.allowed { return "context_restricted" }
    if context.caret.height <= 0 { return "caret_missing" }
    if !permissionGranted { return "permission_denied" }
    if IsSecureEventInputEnabled() { return "secure_input" }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != context.processID { return "front_app_changed" }
    return nil
  }
  static func capture(_ context: ScreenLanguageCaptureContext, accessFailure: @escaping () -> String?,
                      resolveWindow: @escaping ResolveWindow, completion: @escaping (Data?) -> Void) {
    func permitted() -> Bool {
      guard context.captureIsCurrent() else { trace(context, "capture_superseded"); return false }
      if let reason = accessFailure() { trace(context, reason); return false }
      return true
    }
    guard permitted() else { completion(nil); return }
    trace(context, "metadata_started")
    resolveWindow(context) { window in
      DispatchQueue.main.async {
        guard permitted() else { completion(nil); return }
        guard let window else { completion(nil); return }
        let config = SCStreamConfiguration()
        let size = ScreenLanguageImage.scaledSize(window.frame.size)
        config.width = Int(size.width); config.height = Int(size.height)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .nominal
        trace(context, "screenshot_started")
        window.captureImage(config) { image in
          guard let image else { DispatchQueue.main.async { trace(context, "screenshot_failed"); completion(nil) }; return }
          // Encoding stays in memory. Reduce further if detailed content would
          // exceed the worker's 3 MiB JSON budget after base64 expansion.
          var png: Data?
          for edge: CGFloat in [960, 720, 540, 405] {
            if let candidate = ScreenLanguageImage.png(image, caret: context.caret, window: window.frame,
              primaryScreenHeight: context.primaryScreenHeight, longestEdge: edge),
              ScreenLanguageImage.requestData(png: candidate, revision: Int.max) != nil {
              png = candidate; break
            }
          }
          DispatchQueue.main.async {
            guard permitted() else { completion(nil); return }
            trace(context, "image_encoded")
            completion(png)
          }
        }
      }
    }
  }
  private static func resolveWindow(_ context: ScreenLanguageCaptureContext, completion: @escaping (ScreenLanguageCaptureWindow?) -> Void) {
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, _ in
      DispatchQueue.main.async {
        guard let content else { trace(context, "metadata_failed"); completion(nil); return }
        trace(context, "metadata_ready")
        let windows = content.windows.filter {
          $0.owningApplication?.processID == context.processID && $0.windowLayer == 0 && $0.isOnScreen &&
          $0.frame.width > 40 && $0.frame.height > 40
        }
        // The metadata list provides front-to-back order without capturing
        // any pixels outside the host app's selected window.
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
          .compactMap { $0[kCGWindowNumber as String] as? UInt32 }
        let sorted = windows.sorted { (order.firstIndex(of: $0.windowID) ?? .max) < (order.firstIndex(of: $1.windowID) ?? .max) }
        let caretPoint = CGPoint(x: context.caret.midX, y: context.primaryScreenHeight - context.caret.midY)
        guard let window = sorted.first(where: { $0.frame.contains(caretPoint) }) else {
          trace(context, "window_not_at_caret", flags: ["host_window_found": !sorted.isEmpty]); completion(nil); return
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        completion(ScreenLanguageCaptureWindow(frame: window.frame, captureImage: { config, callback in
          SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in callback(image) }
        }))
      }
    }
  }
}
