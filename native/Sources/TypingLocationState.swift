import Foundation
import CoreGraphics

// Track the host insertion point, distinguishing our own text edits from a
// cursor move. No global event monitor or continuously running timer is used.
struct TypingLocationState {
  struct Snapshot {
    let client: ObjectIdentifier
    var selection: NSRange
    var caret: CGRect?
    var marked = false
  }
  private var expected: Snapshot?
  mutating func record(_ snapshot: Snapshot) { expected = snapshot }
  mutating func observe(_ snapshot: Snapshot) -> Bool {
    guard let old = expected else { expected = snapshot; return true }
    if old.client != snapshot.client { expected = snapshot; return true }
    let known = snapshot.selection.location != NSNotFound
    if known, old.selection.location != NSNotFound {
      let sameSelection = snapshot.selection == old.selection ||
        (snapshot.marked && snapshot.selection.location == old.selection.location)
      if !sameSelection { expected = snapshot; return true }
    }
    if !snapshot.marked, let caret = snapshot.caret, let previous = old.caret,
       abs(caret.minX - previous.minX) > 2 || abs(caret.minY - previous.minY) > 2 {
      expected = snapshot; return true
    }
    // Missing host data cannot prove a move. Keep the last known point.
    if known {
      var next = snapshot
      if next.caret == nil { next.caret = old.caret }
      expected = next
    }
    return false
  }
  mutating func expectHostEdit(insertedUTF16: Int = 0, backwardDelete: Bool = false) {
    guard var next = expected, next.selection.location != NSNotFound else { return }
    let start = next.selection.location
    let offset = backwardDelete && next.selection.length == 0 ? max(0, start - 1) : start + insertedUTF16
    next.selection = NSRange(location: offset, length: 0)
    next.caret = nil; next.marked = false
    expected = next
  }
}
