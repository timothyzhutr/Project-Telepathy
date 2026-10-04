import Foundation

enum DecisionSnapshot {
  static func cappedPrefix(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.suffix(512)))
  }
  static func validPinyin(_ text: String) -> Bool {
    !text.isEmpty && text.utf8.count <= 64 && text.utf8.allSatisfy { (97...122).contains($0) || $0 == 39 }
  }
}
