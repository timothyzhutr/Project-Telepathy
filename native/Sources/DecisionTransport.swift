import Foundation

// One running decision and one replaceable pending snapshot across the IME.
// Completion handlers execute on the main queue; no native Rime pointers cross it.
final class DecisionTransport {
  static let shared = DecisionTransport()
  static let language = DecisionTransport(endpoint: "language")
  private let endpoint: String
  init(endpoint: String = "decision") { self.endpoint = endpoint }
  private var pending: (Data, ([String: Any]?) -> Void)?
  private var running = false
  private var lastLaunch = Date.distantPast
  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 2.5
    config.timeoutIntervalForResource = 3
    return URLSession(configuration: config)
  }()

  func submit(_ data: Data, completion: @escaping ([String: Any]?) -> Void) {
    pending = (data, completion)
    startNext()
  }

  private func startNext() {
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
        if !valid { self.launchWorker() }
        self.startNext()
      }
    }.resume()
  }

  func launchWorker() {
    guard Date().timeIntervalSince(lastLaunch) > 15 else { return }
    lastLaunch = Date()
    let process = Process()
    process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker")
    process.arguments = ["--serve"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
  }
}
