import Foundation

// Shared across input controllers. Call only from the main/event queue.
final class ScreenCaptureThrottle {
  static let shared = ScreenCaptureThrottle()
  private let minimumInterval: TimeInterval
  private let clock: () -> TimeInterval
  private var lastCapture: TimeInterval?

  init(minimumInterval: TimeInterval = 5, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.minimumInterval = max(0, minimumInterval); self.clock = clock
  }
  // Zero reserves this capture; a positive value tells the caller to recheck
  // eligibility and claim again later, rather than reserving a stale field.
  func claim() -> TimeInterval {
    let now = clock()
    if let lastCapture {
      let remaining = minimumInterval - (now - lastCapture)
      if remaining > 0 { return remaining }
    }
    lastCapture = now
    return 0
  }
}
