import Foundation
import CoreGraphics

@main struct TypingLocationStateTests {
  static func main() {
    let first = NSObject(), second = NSObject()
    func point(_ offset: Int, length: Int = 0, x: CGFloat = 100, y: CGFloat = 100,
               marked: Bool = false, client: NSObject? = nil) -> TypingLocationState.Snapshot {
      .init(client: ObjectIdentifier(client ?? first), selection: NSRange(location: offset, length: length),
            caret: CGRect(x: x, y: y, width: 1, height: 20), marked: marked)
    }
    var state = TypingLocationState()
    state.record(point(5))
    precondition(state.observe(point(2)), "Clicking elsewhere in the same client must reset the language default")
    precondition(!state.observe(point(2)), "Observing the same cursor must retain its default")
    precondition(state.observe(point(2, length: 3)), "Selecting text must count as a new cursor location")
    state.record(point(2, length: 3))
    precondition(!state.observe(point(2, marked: true)), "Replacing a selection with marked text is our own composition")
    precondition(!state.observe(point(2, x: 150, marked: true)), "Marked text moving its displayed caret must not look like a new field")
    state.record(point(7, x: 150))
    precondition(!state.observe(point(7, x: 150)), "A recorded own commit must retain the default")
    state.expectHostEdit(insertedUTF16: 1)
    precondition(!state.observe(point(8, x: 170)), "Literal keys passed to the host must advance the expected cursor")
    state.expectHostEdit(backwardDelete: true)
    precondition(!state.observe(point(7, x: 150)), "Host Backspace must not reset the default")
    precondition(state.observe(point(7, x: 600, y: 400)), "A reused browser client at the same offset in another field must reset")
    precondition(state.observe(point(7, x: 600, y: 400, client: second)), "A new client must reset")
    var unavailable = point(NSNotFound, client: second); unavailable.caret = nil
    precondition(!state.observe(unavailable), "Missing selection geometry is not evidence of a cursor move")
    precondition(!state.observe(point(7, x: 600, y: 400, client: second)), "Missing observations must not erase the last known point")
    print("PASS: cursor selections, reused browser fields, own commits, marked text and unavailable geometry")
  }
}
