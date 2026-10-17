import Foundation

@main struct ScreenCaptureThrottleTests {
  static func main() {
    var now: TimeInterval = 100
    let throttle = ScreenCaptureThrottle(clock: { now })
    precondition(throttle.claim() == 0, "The first eligible capture must start immediately")
    precondition(throttle.claim() == 5, "A second controller must share the five-second cooldown")
    now += 2
    precondition(throttle.claim() == 3, "Deferred attempts must not extend the cooldown")
    now += 3
    precondition(throttle.claim() == 0, "The next eligible field may capture when the cooldown expires")
    precondition(throttle.claim() == 5, "A successful claim must restart the cooldown")
    now += 60
    precondition(throttle.claim() == 0 && throttle.claim() == 5, "Idle time must not accumulate a burst allowance")
    print("PASS: shared monotonic screenshot cooldown, delayed claims and no burst allowance")
  }
}
