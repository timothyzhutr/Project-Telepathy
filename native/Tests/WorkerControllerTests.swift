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
    let environment = ProcessInfo.processInfo.environment.merging(["TELEPATHY_DATA_DIR": args[3], "TP_TEST_EXEC": args[1]]) { _, new in new }
    let marker = URL(fileURLWithPath: args[3]).appendingPathComponent("launches")
    let wrapper = URL(fileURLWithPath: args[3]).appendingPathComponent("launch-worker")
    try! "#!/bin/sh\nprintf 'launch\\n' >> \"$TELEPATHY_DATA_DIR/launches\"\nexec \"$TP_TEST_EXEC\" \"$@\"\n".write(to: wrapper, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    if args.contains("--crash-retry") {
      try! "#!/bin/sh\nprintf 'launch\\n' >> \"$TELEPATHY_DATA_DIR/launches\"\nexit 1\n".write(to: wrapper, atomically: true, encoding: .utf8)
    }
    let controller = TelepathyWorkerController(preferences: preferences,
      executable: wrapper,
      arguments: workerArguments,
      environment: environment,
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
    if args.contains("--crash-retry") {
      preferences.set(true, for: .kev)
      RunLoop.current.run(until: Date().addingTimeInterval(16))
      let launches = try! String(contentsOf: marker, encoding: .utf8).split(separator: "\n").count
      precondition(launches == 2, "Unexpected helper failure must retry after the cooldown")
      preferences.set(false, for: .kev)
      RunLoop.current.run(until: Date().addingTimeInterval(16))
      let stoppedLaunches = try! String(contentsOf: marker, encoding: .utf8).split(separator: "\n").count
      precondition(stoppedLaunches == 2, "Assistance off must cancel a scheduled crash retry")
      print("PASS: delayed abnormal-exit recovery and retry cancellation")
      return
    }
    if args.contains("--lock-contention") {
      preferences.set(true, for: .kev)
      let deadline = Date().addingTimeInterval(22)
      while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
      let launches = try! String(contentsOf: marker, encoding: .utf8).split(separator: "\n").count
      precondition(launches == 1, "A clean lock-contention exit must not trigger a restart loop")
      controller.shutdown()
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
      print("PASS: clean lock-contention exit does not respawn")
      return
    }
    let orphan = Process()
    orphan.executableURL = URL(fileURLWithPath: args[1]); orphan.arguments = workerArguments
    orphan.environment = environment; orphan.standardOutput = FileHandle.nullDevice; orphan.standardError = FileHandle.nullDevice
    try! orphan.run()
    defer { if orphan.isRunning { orphan.terminate(); orphan.waitUntilExit() } }
    wait("The orphan fixture must serve health") { available(bundled) }
    preferences.set(true, for: .kev)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    precondition(!FileManager.default.fileExists(atPath: marker.path), "A responsive orphan helper must be reused without launching a lock-waiting child")
    preferences.set(false, for: .kev)
    wait("Assistance off must also stop the orphan helper") { !available() }
    orphan.waitUntilExit()
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
