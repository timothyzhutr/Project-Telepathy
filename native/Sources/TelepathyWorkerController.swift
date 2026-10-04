import Foundation

// Assistance owns the entire helper process, including its Python and Metal
// runtime. Stopping only the model would leave that runtime resident.
final class TelepathyWorkerController {
  static let shared = TelepathyWorkerController()
  private let preferences: TelepathyPreferences
  private let executable: URL
  private let arguments: [String]
  private let environment: [String: String]?
  private let baseURL: URL
  private var process: Process?
  private var observer: NSObjectProtocol?
  private var shutdownInFlight = false
  private var stopped = false
  private var lastEnabled: Bool?
  private var lastAttempt = Date.distantPast
  private var healthTask: URLSessionDataTask?
  private var restart: DispatchWorkItem?
  private var generation = 0
  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 1
    config.timeoutIntervalForResource = 2
    return URLSession(configuration: config)
  }()

  init(preferences: TelepathyPreferences = .shared,
       executable: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker"),
       arguments: [String] = ["--serve", "--wait-lock"],
       environment: [String: String]? = nil,
       baseURL: URL = URL(string: "http://127.0.0.1:18765")!) {
    self.preferences = preferences; self.executable = executable
    self.arguments = arguments; self.environment = environment; self.baseURL = baseURL
  }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

  func start() {
    guard observer == nil, !stopped else { return }
    observer = NotificationCenter.default.addObserver(forName: .telepathyPreferencesChanged, object: preferences, queue: .main) { [weak self] _ in
      self?.synchronize()
    }
    synchronize()
  }

  private func synchronize() {
    let enabled = preferences.enabled(.kev)
    guard lastEnabled != enabled else { return }
    lastEnabled = enabled
    lastAttempt = .distantPast
    if enabled { ensureRunning() } else { stopRunning() }
  }

  func ensureRunning() {
    guard !stopped, preferences.enabled(.kev), !shutdownInFlight,
          process?.isRunning != true, healthTask == nil,
          Date().timeIntervalSince(lastAttempt) > 15 else { return }
    let ticket = generation
    healthTask = session.dataTask(with: baseURL.appendingPathComponent("api/health")) { [weak self] data, response, error in
      let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let serving = error == nil && (response as? HTTPURLResponse)?.statusCode == 200 &&
        body?["app"] as? String == "Telepathy" && body?["ime_api"] as? Int == 1
      DispatchQueue.main.async {
        guard let self, self.generation == ticket else { return }
        self.healthTask = nil
        guard !serving, !self.stopped, self.preferences.enabled(.kev),
              !self.shutdownInFlight, self.process?.isRunning != true else { return }
        self.launch()
      }
    }
    healthTask?.resume()
  }

  private func launch() {
    lastAttempt = Date()
    let child = Process()
    child.executableURL = executable; child.arguments = arguments; child.environment = environment
    child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
    child.terminationHandler = { [weak self] child in
      DispatchQueue.main.async {
        guard let self, self.process === child else { return }
        self.process = nil
        // A clean lock-contention exit means another helper owns service.
        // Only an unexpected failure schedules an automatic retry.
        if child.terminationStatus != 0 && !self.stopped && self.preferences.enabled(.kev) {
          let work = DispatchWorkItem { [weak self] in self?.ensureRunning() }
          self.restart = work
          DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, 15.01 - Date().timeIntervalSince(self.lastAttempt)), execute: work)
        }
      }
    }
    do { try child.run(); process = child } catch { process = nil }
  }

  private func stopRunning() {
    generation += 1
    healthTask?.cancel(); healthTask = nil
    restart?.cancel(); restart = nil
    if let process, process.isRunning { process.terminate() }
    guard !shutdownInFlight else { return }
    shutdownInFlight = true
    // This also stops a helper left by a previous native process. Gate restart
    // until this request finishes so it cannot arrive at the replacement.
    var request = URLRequest(url: baseURL.appendingPathComponent("api/shutdown"))
    request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    session.dataTask(with: request) { [weak self] _, _, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        self.shutdownInFlight = false
        self.ensureRunning()
      }
    }.resume()
  }

  func shutdown() {
    guard !stopped else { return }
    stopped = true
    if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    stopRunning()
  }
}
