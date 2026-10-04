import Foundation

@main struct InputIntentStateTests {
  static func check(_ ok: Bool, _ message: String) {
    if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  static func main() {
    var state = InputIntentState()
    state.update(raw: "he", revision: 1)
    check(state.apply("english", revision: 1), "A current English judgment must be accepted")
    check(state.english, "English must preserve keyboard text")
    check(state.action(for: 32) == .space, "English Space must insert a literal space")
    check(state.action(for: 0xff0d) == .commitAndPass, "English Return must reach the host after committing text")
    check(state.action(for: 46) == .commitAndPass, "English punctuation must reach the host literally")
    check(state.action(for: 39) == .none, "A contraction apostrophe must stay in the word")
    check(state.action(for: 0xff54) == .chinese, "Down must restore Chinese choices")
    state.update(raw: "help", revision: 2)
    check(state.english, "An English word must stay visible while more letters arrive")
    check(!state.apply("chinese", revision: 1), "A late decision for shorter input must be ignored")
    check(state.apply("chinese", revision: 2) && !state.english, "Fresh context can restore Chinese")
    state.forceChinese()
    check(!state.apply("english", revision: 2), "Manual Chinese selection must override the model")
    state.update(raw: "helper", revision: 3)
    check(!state.apply("english", revision: 3), "Manual intent must persist through this composition")
    state.invalidate(revision: 4)
    check(!state.apply("english", revision: 3), "Commit/deactivation must discard pending intent")
    state.update(raw: "can", revision: 5)
    check(state.apply("english", revision: 5), "A new word must clear the manual override")
    state.update(raw: "nihao", revision: 6)
    check(!state.english, "Replacing a word must discard the old English intent")
    check(state.apply("uncertain", revision: 6) && !state.english, "Uncertain input must keep Chinese candidates")
    check(state.action(for: 32) == .none, "Chinese Space must retain Rime selection behavior")
    state.startLiteralRun()
    check(state.passLiteralKey(65), "An explicit capital must preserve its case")
    check(state.passLiteralKey(47), "URL punctuation must stay ASCII")
    check(state.passLiteralKey(0xff08), "Backspace must reach the host within a literal run")
    check(state.passLiteralKey(32), "The terminating space must reach the host")
    check(!state.passLiteralKey(97), "The next word must resume automatic language decisions")
    state.startLiteralRun()
    state.invalidate(revision: 7)
    check(!state.passLiteralKey(97), "Deactivation must clear literal passthrough")
    print("PASS: English boundaries, fresh/stale language decisions, manual override, commit reset")
  }
}
