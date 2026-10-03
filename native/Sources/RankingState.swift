import Foundation

struct RankingState {
  private(set) var revision = 0
  private(set) var key = ""
  private(set) var order = [Int]()
  private(set) var frozen = false
  mutating func reset(key: String, count: Int) -> Int {
    revision += 1
    self.key = key
    order = Array(0..<count)
    frozen = false
    return revision
  }
  mutating func apply(_ order: [Int], revision: Int) -> Bool {
    guard revision == self.revision, !frozen, order.sorted() == self.order.sorted(), !order.isEmpty else { return false }
    self.order = order
    return true
  }
  mutating func freeze() { frozen = true }
  mutating func invalidate() { _ = reset(key: "", count: 0) }
  func nativeIndex(_ displayed: Int) -> Int? {
    order.indices.contains(displayed) ? order[displayed] : nil
  }
  func displayIndex(_ native: Int) -> Int? { order.firstIndex(of: native) }
}
