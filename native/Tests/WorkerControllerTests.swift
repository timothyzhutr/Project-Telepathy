import Foundation

@main struct WorkerControllerTests {
  static func main() {
    let args = CommandLine.arguments
    let name = "local.telepathy.tests.worker." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = TelepathyPreferences(defaults: defaults)
    preferences.set(false, for: .kev)
    let url = URL(string: "http://127.0.0.1:" + args[4])!
    let bundled = args[2] == "--bundled"
    let workerArguments = bundled
      ? ["--serve", "--wait-lock", "--port", args[4], "--model-dir", args[5]]
      : [args[2], "--serve", "--wait-lock", "--port", args[4], "--model-dir", args[3] + "/missing"]
    let controller = TelepathyWorkerController(preferences: preferences,
      executable: URL(fileURLWithPath: args[1]),
      arguments: workerArguments,
      environment: ProcessInfo.processInfo.environment.merging(["TELEPATHY_DATA_DIR": args[3]]) { _, new in new },
      baseURL: url)
    defer { controller.shutdown() }
    func available(_ requireReady: Bool = false) -> Bool {
      var finished = false, result = false
      var request = URLRequest(url: url.appendingPathComponent("api/health"))
      request.timeoutInterval = 0.3
      URLSession.shared.dataTask(with: request) { data, response, _ in
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        result = (response as? HTTPURLResponse)?.statusCode == 200 && json?["app"] as? String == "Telepathy" &&
          (!requireReady || json?["status"] as? String == "ready")
        finished = true
      }.resume()
      let deadline = Date().addingTimeInterval(1)
      while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
      return result
    }
    func wait(_ message: String, _ condition: () -> Bool) {
      let deadline = Date().addingTimeInterval(bundled ? 45 : 6)
      while !condition() {
        guard Date() < deadline else { fatalError(message) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      }
    }
    controller.start()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    precondition(!available(), "Assistance off at startup must not launch the helper")
    preferences.set(true, for: .kev)
    wait("Enabling assistance must start the real helper") { available(bundled) }
    preferences.set(false, for: .kev)
    wait("Disabling assistance must stop the real helper") { !available() }
    // Rapid toggling while shutdown is pending must not stop the replacement
    // helper or leave a second helper waiting behind the singleton lock.
    for _ in 0..<5 {
      preferences.set(true, for: .kev)
      RunLoop.current.run(until: Date().addingTimeInterval(0.03))
      preferences.set(false, for: .kev)
    }
    preferences.set(true, for: .kev)
    wait("Rapid toggles must settle on one available helper") { available(bundled) }
    controller.shutdown()
    wait("App shutdown must release the helper even when the saved preference is on") { !available() }
    precondition(preferences.enabled(.kev), "Stopping the app must preserve the saved preference")
    print("PASS: real helper disabled startup, off/on, rapid restart and app exit")
  }
}
