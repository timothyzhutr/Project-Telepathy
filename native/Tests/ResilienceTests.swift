import Foundation

private final class ResponseProtocol: URLProtocol {
  static var status = 400
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    if Self.status == 0 { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("{}".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main struct ResilienceTests {
  static func main() throws {
    let prefix = String(repeating: "中", count: 510) + "\r\n你好"
    let capped = DecisionSnapshot.cappedPrefix(prefix)
    precondition(capped.unicodeScalars.count == 512 && capped.hasSuffix("你好"), "Context must respect the worker's code-point budget")
    for raw in ["/fh", "`ni", String(repeating: "a", count: 65), "NI", "", "ni\0"] {
      precondition(!DecisionSnapshot.validPinyin(raw), "Unsupported input must bypass inference")
    }
    precondition(DecisionSnapshot.validPinyin("xi'an") && DecisionSnapshot.validPinyin("nihao"))
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("telepathy-profile-test-" + UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("build")
    try fm.createDirectory(at: source, withIntermediateDirectories: true)
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    for file in ["wanxiang.schema.yaml", "wanxiang.table.bin"] { try Data("packaged".utf8).write(to: source.appendingPathComponent(file)) }
    try Data("partial".utf8).write(to: target.appendingPathComponent("wanxiang.schema.yaml"))
    try ProfileSeeder.seed(source: source, target: target)
    precondition(fm.fileExists(atPath: target.appendingPathComponent("wanxiang.table.bin").path), "An interrupted copy must recover even when its schema exists")
    try Data("custom".utf8).write(to: target.appendingPathComponent("wanxiang.schema.yaml"))
    try ProfileSeeder.seed(source: source, target: target)
    let retained = try String(contentsOf: target.appendingPathComponent("wanxiang.schema.yaml"), encoding: .utf8)
    precondition(retained == "custom", "Complete profiles must retain local configuration")
    try fm.removeItem(at: target.appendingPathComponent("wanxiang.table.bin"))
    try Data("personal".utf8).write(to: target.appendingPathComponent("custom.txt"))
    try ProfileSeeder.seed(source: source, target: target)
    let recoveries = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".build-incomplete-") }
    precondition(recoveries.count == 2, "Each repair must retain its displaced incomplete profile")
    let customRecovery = recoveries.first { (try? String(contentsOf: $0.appendingPathComponent("wanxiang.schema.yaml"), encoding: .utf8)) == "custom" }
    precondition(customRecovery != nil && fm.fileExists(atPath: customRecovery!.appendingPathComponent("custom.txt").path), "Repair must preserve custom data in its recovery copy")
    let suite = "local.telepathy.transport-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = TelepathyPreferences(defaults: defaults)
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ResponseProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    var launches = 0
    let transport = DecisionTransport(preferences: preferences, session: session, launchWorker: { launches += 1 })
    for status in [400, 500, 0] {
      ResponseProtocol.status = status; var finished = false
      transport.submit(Data("{}".utf8)) { _ in finished = true }
      let deadline = Date().addingTimeInterval(2)
      while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
      precondition(finished)
      precondition(launches == (status == 0 ? 1 : 0), "An HTTP error must not restart a responsive worker")
    }
    print("PASS: Unicode context, request eligibility, profile recovery and HTTP recovery")
  }
}
