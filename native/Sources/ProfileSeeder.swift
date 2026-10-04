import Foundation

enum ProfileSeeder {
  static func seed(source: URL, target: URL) throws {
    let fm = FileManager.default
    let files = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    guard files.contains(where: { $0.lastPathComponent == "wanxiang.schema.yaml" }) else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    if files.allSatisfy({ fm.fileExists(atPath: target.appendingPathComponent($0.lastPathComponent).path) }) { return }
    let parent = target.deletingLastPathComponent()
    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    let stage = parent.appendingPathComponent(".build-staging-" + UUID().uuidString)
    let previous = parent.appendingPathComponent(".build-incomplete-" + UUID().uuidString)
    defer { try? fm.removeItem(at: stage) }
    // Copying completes before the visible build directory changes. A killed
    // first launch leaves only a staging folder and the next launch can retry.
    try fm.copyItem(at: source, to: stage)
    let existed = fm.fileExists(atPath: target.path)
    if existed { try fm.moveItem(at: target, to: previous) }
    do { try fm.moveItem(at: stage, to: target) }
    catch {
      if existed { try? fm.moveItem(at: previous, to: target) }
      throw error
    }
    // Keep displaced custom/configuration files available for manual recovery.
  }
}
