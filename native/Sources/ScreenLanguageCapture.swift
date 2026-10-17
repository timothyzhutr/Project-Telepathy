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

enum ScreenLanguageCapture {
  // The permission prompt is deliberately confined to the explicit Settings
  // action/CLI. Every automatic path checks permission without requesting it.
  static var permissionGranted: Bool { CGPreflightScreenCaptureAccess() }
  static func capture(_ context: ScreenLanguageCaptureContext, completion: @escaping (Data?) -> Void) {
    func trace(_ reason: String, flags: [String: Bool] = [:]) {
      ScreenLanguageDiagnostics.shared.record(status: "capture_event", reason: reason,
        bundleIdentifier: context.bundleIdentifier, flags: flags, updateSummary: false)
    }
    guard context.allowed else { trace("context_restricted"); completion(nil); return }
    guard context.caret.height > 0 else { trace("caret_missing"); completion(nil); return }
    guard permissionGranted else { trace("permission_denied"); completion(nil); return }
    guard !IsSecureEventInputEnabled() else { trace("secure_input"); completion(nil); return }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID else { trace("front_app_changed"); completion(nil); return }
    trace("metadata_started")
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, _ in
      DispatchQueue.main.async {
        guard permissionGranted else { trace("permission_denied"); completion(nil); return }
        guard !IsSecureEventInputEnabled() else { trace("secure_input"); completion(nil); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID else { trace("front_app_changed"); completion(nil); return }
        guard let content else { trace("metadata_failed"); completion(nil); return }
        trace("metadata_ready")
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
          trace("window_not_at_caret", flags: ["host_window_found": !sorted.isEmpty]); completion(nil); return
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let size = ScreenLanguageImage.scaledSize(window.frame.size)
        config.width = Int(size.width); config.height = Int(size.height)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .nominal
        trace("screenshot_started")
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
          guard let image else { DispatchQueue.main.async { trace("screenshot_failed"); completion(nil) }; return }
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
            guard permissionGranted else { trace("permission_denied"); completion(nil); return }
            guard !IsSecureEventInputEnabled() else { trace("secure_input"); completion(nil); return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID else { trace("front_app_changed"); completion(nil); return }
            trace("image_encoded")
            completion(png)
          }
        }
      }
    }
  }
}
