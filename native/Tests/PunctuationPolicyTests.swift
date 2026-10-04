import Foundation

@main struct PunctuationPolicyTests {
  static func check(_ ok: Bool, _ message: String) {
    if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  static func main() {
    func ascii(_ key: Character, _ text: String, fallback: Bool = true) -> Bool? {
      PunctuationPolicy.decide(key: key, context: text, defaultChinese: fallback)?.ascii
    }
    check(ascii(".", "I think he can help ") == true, "English punctuation must stay ASCII after Space")
    check(ascii(",", "这是一个中文句子") == false, "Chinese prose must use Chinese comma")
    check(ascii(".", "这个项目叫 ProjectTelepathy") == false, "An English term must not change a Chinese sentence's punctuation")
    check(ascii("?", "I like 中文") == true, "A Chinese term must not change an English sentence's punctuation")
    check(ascii(".", "Python 的速度不错") == false, "A Chinese sentence may start with an English product name")
    check(ascii(".", "这句话结束了。This is English now") == true, "A new sentence must recompute its language")
    check(ascii(".", "This is English.\n我们换成中文") == false, "A new paragraph must recompute its language")
    check(ascii(".", "版本号是 3") == true, "Decimal punctuation must stay ASCII")
    check(ascii(":", "现在是 12") == true, "Time separators must stay ASCII")
    check(ascii(".", "访问 https://example") == true, "URL punctuation must stay ASCII inside Chinese prose")
    check(ascii(".", "访问 www") == true, "The first www dot must start an ASCII URL")
    check(ascii(".", "邮件发到 name@example") == true, "Email punctuation must stay ASCII")
    check(ascii(";", "代码是 `x = 1") == true, "Inline code must preserve ASCII punctuation")
    check(ascii(".", "中文说明\n```swift\nlet x = 1") == true, "Fenced code must preserve ASCII punctuation")
    check(ascii(")", "说明（English text") == false, "Closing brackets must match their Chinese opener")
    check(ascii(")", "Example (中文") == true, "Closing brackets must match their ASCII opener")
    check(ascii("\"", "他说：“hello") == false, "Closing quotes must match their Chinese opener")
    check(ascii("'", "他说：‘hello") == false, "Closing single quotes must match their Chinese opener")
    check(ascii(")", "访问（https://example.com") == false, "A URL must not change its surrounding bracket style")
    check(ascii("'", "我说 don't") == true, "Contractions must preserve their apostrophe")
    check(ascii(".", "", fallback: false) == true, "Empty context must respect the configured fallback")
    check(ascii(".", "", fallback: true) == false, "Empty context must retain configured Chinese punctuation")
    check(ascii("a", "中文") == nil, "Letters must remain on the normal composition path")
    print("PASS: contextual punctuation, mixed prose, technical text, pairs and configured fallback")
  }
}
