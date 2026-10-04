import Foundation

struct RankingState {
  private(set) var revision = 0
  private(set) var key = ""
  private(set) var order = [Int]()
  private(set) var frozen = false
  private(set) var rankedCount = 0
  private(set) var displayPage = 0
  private(set) var displayLimit = 12
  var visibleOrder: [Int] { Array(order.dropFirst(displayPage * displayLimit).prefix(displayLimit)) }
  var hasNextDisplayPage: Bool { (displayPage + 1) * displayLimit < order.count }
  mutating func reset(key: String, count: Int, rankedCount: Int? = nil, shownCount: Int = 12) -> Int {
    revision += 1
    self.key = key
    order = Array(0..<count)
    frozen = false
    self.rankedCount = min(count, max(0, rankedCount ?? count))
    displayLimit = max(1, shownCount)
    displayPage = 0
    return revision
  }
  mutating func apply(_ order: [Int], revision: Int) -> Bool {
    guard revision == self.revision, !frozen, order.sorted() == Array(0..<rankedCount), !order.isEmpty else { return false }
    self.order = order + Array(rankedCount..<self.order.count)
    displayPage = 0
    return true
  }
  mutating func page(up: Bool) -> Bool {
    let next = displayPage + (up ? -1 : 1)
    guard next >= 0, next * displayLimit < order.count else { return false }
    displayPage = next; freeze()
    return true
  }
  mutating func lastDisplayPage() {
    displayPage = max(0, (order.count - 1) / displayLimit); freeze()
  }
  mutating func freeze() { frozen = true }
  mutating func invalidate() { _ = reset(key: "", count: 0) }
  func nativeIndex(_ displayed: Int) -> Int? {
    visibleOrder.indices.contains(displayed) ? visibleOrder[displayed] : nil
  }
  func displayIndex(_ native: Int) -> Int? { visibleOrder.firstIndex(of: native) }
}
