import Foundation

// One running decision and one replaceable pending snapshot across the IME.
// Completion handlers execute on the main queue; no native Rime pointers cross it.
final class DecisionTransport {
  static let shared = DecisionTransport()
  static let language = DecisionTransport(endpoint: "language")
  private let endpoint: String
  private let preferences: TelepathyPreferences
  private let recoverWorker: () -> Void
  private let session: URLSession
  init(endpoint: String = "decision", preferences: TelepathyPreferences = .shared,
       session: URLSession? = nil,
       launchWorker: @escaping () -> Void = { TelepathyWorkerController.shared.ensureRunning() }) {
    self.endpoint = endpoint; self.preferences = preferences; self.recoverWorker = launchWorker
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 2.5
    config.timeoutIntervalForResource = 3
    self.session = session ?? URLSession(configuration: config)
  }
  private var pending: (Data, ([String: Any]?) -> Void)?
  private var running = false

  func submit(_ data: Data, completion: @escaping ([String: Any]?) -> Void) {
    guard preferences.enabled(.kev) else { completion(nil); return }
    pending = (data, completion)
    startNext()
  }

  private func startNext() {
    guard preferences.enabled(.kev) else { pending = nil; return }
    guard !running, let (data, completion) = pending else { return }
    pending = nil
    running = true
    var request = URLRequest(url: URL(string: "http://127.0.0.1:18765/api/\(endpoint)")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    session.dataTask(with: request) { [weak self] data, response, error in
      let valid = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
      let result = valid ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.running = false
        completion(result)
        if error != nil || !(response is HTTPURLResponse) { self.launchWorker() }
        self.startNext()
      }
    }.resume()
  }

  func launchWorker() {
    recoverWorker()
  }
}
