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
    let limited = state.reset(key: "limited", count: 12, rankedCount: 3, shownCount: 5)
    check(!state.apply(Array((0..<12).reversed()), revision: limited), "A reply must match the requested ranking pool")
    check(state.apply([2, 1, 0], revision: limited), "A smaller ranking reply must map into the full native page")
    check(state.visibleOrder == [2, 1, 0, 3, 4] && state.nativeIndex(5) == nil, "Only the visible prefix can be selected")
    check(state.page(up: false) && state.visibleOrder == [5, 6, 7, 8, 9], "Paging must reach the hidden middle choices")
    check(state.page(up: false) && state.visibleOrder == [10, 11], "The final displayed page may contain fewer choices")
    check(!state.page(up: false) && state.nativeIndex(2) == nil, "No forward page or hidden choice exists after the final page")
    check(!state.apply([0, 1, 2], revision: limited), "Paging must freeze late model replies")
    check(state.page(up: true) && state.page(up: true) && !state.page(up: true), "Backward paging must stop at the first displayed page")
    state.lastDisplayPage()
    check(state.displayIndex(10) == 0 && state.visibleOrder == [10, 11], "Returning from the next Rime page must select the previous last display page")
    _ = state.reset(key: "single", count: 3, rankedCount: 0, shownCount: 1)
    check(state.visibleOrder == [0] && state.page(up: false) && state.visibleOrder == [1], "One visible choice must still support paging without inference")
    print("PASS: current/stale replies, candidate mapping, malformed order, selection freeze, deactivation")
  }
}
