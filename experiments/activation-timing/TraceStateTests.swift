import Foundation

@main struct TraceStateTests {
  static func main() {
    var state = ActivationTraceState()
    let activation = state.activate(at: 100)
    precondition(activation["event"] as? String == "activate", "Activation must be logged before typing")
    let first = state.firstKey(eventTime: 100.5, receivedAt: 100.51)!
    precondition(abs((first["lead_ms"] as! Double)-500) < 0.0001)
    precondition(abs((first["received_lead_ms"] as! Double)-510) < 0.0001)
    precondition(state.firstKey(eventTime: 101, receivedAt: 101) == nil,
                 "Only the first key in an activation belongs in this trace")
    _ = state.deactivate(at: 102)
    let orphan = state.firstKey(eventTime: 103, receivedAt: 103)!
    precondition(orphan["event"] as? String == "key_without_activation")
    precondition(orphan["lead_ms"] == nil, "A previous destination's activation must not be reused")
    _ = state.activate(at: 104)
    let late = state.firstKey(eventTime: 103.999, receivedAt: 104.001)!
    precondition((late["lead_ms"] as! Double) < 0, "Do not hide an activation caused by the key itself")
    precondition(Set(first.keys) == Set(["event","uptime","event_uptime","activation","lead_ms","received_lead_ms"]),
                 "Trace payload must not contain typed text or key codes")
    print("Activation trace state checks passed")
  }
}
