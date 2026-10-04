import Foundation

enum PunctuationPolicy {
  struct Decision {
    let ascii: Bool
    let continueLiteral: Bool
    let text: String
  }
  private static let chinese: [Character: String] = [
    ",": "，", ".": "。", "!": "！", "?": "？", ":": "：", ";": "；",
    "(": "（", ")": "）", "[": "【", "]": "】", "{": "「", "}": "」",
    "<": "《", ">": "》", "\"": "“", "'": "‘"
  ]
  private static let pairs: [Character: [Character: Character]] = [
    ")": ["(": ")", "（": "）"],
    "]": ["[": "]", "【": "】", "［": "］", "〔": "〕"],
    "}": ["{": "}", "「": "」", "『": "』", "｛": "｝", "〖": "〗"],
    ">": ["<": ">", "《": "》", "〈": "〉"]
  ]
  static func supports(_ key: Character) -> Bool { chinese[key] != nil }

  // Bounded native work only: punctuation never creates or waits for a model request.
  static func decide(key: Character, context: String, defaultChinese: Bool) -> Decision? {
    guard let fullWidth = chinese[key] else { return nil }
    let text = String(context.suffix(512))
    func decision(_ ascii: Bool, continueLiteral: Bool = false, output: String? = nil) -> Decision {
      Decision(ascii: ascii, continueLiteral: continueLiteral, text: output ?? (ascii ? String(key) : fullWidth))
    }
    let token = text.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
    let last = text.last
    let numeric = ".,:".contains(key) && (last?.isASCII == true && last?.isNumber == true)
    let address = token.contains("://") || token.contains("@") || token.hasPrefix("www.") ||
      beginsAddress(key: key, context: text)
    let code = text.filter { $0 == "`" }.count % 2 == 1
    let contraction = key == "'" && last.map(isLatin) == true
    if code { return decision(true, continueLiteral: true) }

    // A pasted opener is authoritative too; do not rely on Rime's quote toggle.
    if let openings = pairs[key] {
      var depth = 0
      for char in text.reversed() {
        if openings.values.contains(char) { depth += 1 }
        else if let closing = openings[char] {
          if depth == 0 { return decision(char.isASCII, output: String(closing)) }
          depth -= 1
        }
      }
    }
    if key == "\"" || key == "'" {
      let opening: Character = key == "\"" ? "“" : "‘"
      let closing: Character = key == "\"" ? "”" : "’"
      if text.lastIndex(of: opening).map({ index in
        text.lastIndex(of: closing).map { $0 < index } ?? true
      }) == true { return decision(false, output: String(closing)) }
      if text.filter({ $0 == key }).count % 2 == 1 { return decision(true) }
    }
    if address || contraction { return decision(true, continueLiteral: true) }
    // Digits already pass through native Rime. Do not make the next alphabetic
    // word literal merely because it follows a decimal/time separator.
    if numeric { return decision(true) }

    let sentence = text.split(whereSeparator: { "。？！.!?\n\r".contains($0) }).last.map(String.init) ?? ""
    let hanCount = sentence.filter(isHan).count
    let words = sentence.split(whereSeparator: { !isLatin($0) }).count
    let firstScript = sentence.first(where: { isHan($0) || isLatin($0) })
    // Sentence language survives embedded terms. A leading product name followed
    // by Chinese grammar ("Python 的速度不错") is still a Chinese sentence.
    let useChinese = firstScript.map { isHan($0) || (hanCount >= 3 && words <= 1) } ?? defaultChinese
    return decision(!useChinese)
  }

  static func beginsAddress(key: Character, context: String) -> Bool {
    let token = context.split(whereSeparator: { !$0.isASCII || $0.isWhitespace }).last.map { $0.lowercased() } ?? ""
    return key == "." && token == "www" || key == ":" && ["http", "https", "ftp"].contains(token)
  }

  private static func isLatin(_ char: Character) -> Bool {
    char.isASCII && char.isLetter
  }
  private static func isHan(_ char: Character) -> Bool {
    char.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) || (0x20000...0x323af).contains($0.value) }
  }
}
