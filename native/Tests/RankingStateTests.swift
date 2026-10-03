import Foundation

@main struct RankingStateTests {
  static func check(_ ok: Bool, _ message: String) {
    if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  static func main() {
    var state = RankingState()
    let first = state.reset(key: "one", count: 3)
    check(state.apply([2, 0, 1], revision: first), "current result must be admitted")
    check(state.nativeIndex(0) == 2 && state.displayIndex(2) == 0, "click/number keys must select the displayed native word")
    let next = state.reset(key: "two", count: 2)
    check(!state.apply([2, 0, 1], revision: first), "old results must be rejected")
    check(state.order == [0, 1], "new input must start with native order")
    check(!state.apply([1, 1], revision: next), "invalid permutations must be rejected")
    state.freeze()
    check(!state.apply([1, 0], revision: next), "browsing freezes the list")
    let third = state.reset(key: "three", count: 2)
    check(state.apply([1, 0], revision: third), "new composition clears the freeze")
    state.invalidate()
    check(!state.apply([0, 1], revision: third), "deactivation invalidates a pending reply")
    check(state.nativeIndex(0) == nil, "cleared composition has no selectable word")
    print("PASS: current/stale replies, candidate mapping, malformed order, selection freeze, deactivation")
  }
}
