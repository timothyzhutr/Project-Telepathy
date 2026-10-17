import Foundation
import Carbon
import AppKit

func identifier(_ source: TISInputSource) -> String {
  guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "unknown" }
  return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
if CommandLine.arguments.count == 1 {
  print(identifier(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
} else {
  let args = Array(CommandLine.arguments.dropFirst())
  if args.first == "--when-front" {
    precondition(args.count == 3)
    let deadline = Date().addingTimeInterval(20)
    while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != args[1] {
      if Date() > deadline { fputs("Target app did not become frontmost\n", stderr); exit(2) }
      Thread.sleep(forTimeInterval: 0.01)
    }
  }
  let id = args.last!
  let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
  guard let source = sources.first(where: { identifier($0) == id }) else { exit(1) }
  let status = TISSelectInputSource(source)
  print("TISSelectInputSource: \(status); current: \(identifier(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))")
  if status != noErr { exit(1) }
}
