import Foundation

struct ActivationTraceState {
  private var activatedAt: Double?
  private var activation = 0
  private var keyRecorded = false

  mutating func activate(at uptime: Double) -> [String: Any] {
    activation += 1
    activatedAt = uptime
    keyRecorded = false
    return ["event": "activate", "uptime": uptime, "activation": activation]
  }

  mutating func deactivate(at uptime: Double) -> [String: Any] {
    activatedAt = nil
    keyRecorded = false
    return ["event": "deactivate", "uptime": uptime, "activation": activation]
  }

  mutating func firstKey(eventTime: Double, receivedAt: Double) -> [String: Any]? {
    guard !keyRecorded else { return nil }
    keyRecorded = true
    var row: [String: Any] = ["event": activatedAt == nil ? "key_without_activation" : "first_key",
      "uptime": receivedAt, "event_uptime": eventTime, "activation": activation]
    if let activatedAt {
      row["lead_ms"] = (eventTime - activatedAt) * 1000
      row["received_lead_ms"] = (receivedAt - activatedAt) * 1000
    }
    return row
  }
}
