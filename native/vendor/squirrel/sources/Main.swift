import Foundation
import InputMethodKit

@main struct SquirrelApp {
  static let userDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Telepathy/Rime", isDirectory: true)
  static let appDir = Bundle.main.bundleURL
  static let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Telepathy", isDirectory: true)
  static func main() {
    let installer = SquirrelInstaller()
    if let action = CommandLine.arguments.dropFirst().first {
      switch action {
      case "--download-model", "--check-model", "--self-test":
        let worker = Process()
        worker.executableURL = appDir.appendingPathComponent("Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker")
        worker.arguments = Array(CommandLine.arguments.dropFirst())
        do { try worker.run(); worker.waitUntilExit(); exit(worker.terminationStatus) }
        catch { fputs("Unable to start the bundled worker.\n", stderr); exit(1) }
      case "--register-input-source": installer.register(); return
      case "--enable-input-source": installer.enable(); return
      case "--select-input-source": installer.select(); return
      case "--disable-input-source": installer.disable(); return
      case "--current-input-source": print(SquirrelInstaller.currentInputSourceID() ?? "unknown"); return
      case "--verify-input-source":
        guard !installer.enabledModes().isEmpty else {
          fputs("Telepathy is not registered and enabled in macOS.\n", stderr)
          exit(1)
        }
        print("Telepathy is registered and enabled."); return
      case "--verify-runtime":
        let name = Bundle.main.object(forInfoDictionaryKey: "InputMethodServerControllerClass") as? String ?? ""
        guard NSClassFromString(name) != nil else {
          fputs("InputMethodKit controller class is unavailable: \(name)\n", stderr)
          exit(1)
        }
        print("InputMethodKit controller is available: \(name)"); return
      case "--quit":
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).forEach { $0.terminate() }; return
      default: break
      }
    }
    // Register with InputMethodKit before AppKit initializes the application,
    // matching Squirrel's native startup sequence.
    guard let server = IMKServer(name: Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
                                 bundleIdentifier: Bundle.main.bundleIdentifier!) else {
      fputs("Telepathy could not create its InputMethodKit server.\n", stderr)
      exit(1)
    }
    let app = NSApplication.shared
    let delegate = SquirrelApplicationDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    FileManager.default.changeCurrentDirectoryPath(Bundle.main.sharedSupportPath!)
    // Start from the packaged compiled profile, without a source checkout or deployment.
    do {
      try ProfileSeeder.seed(source: appDir.appendingPathComponent("Contents/Resources/Profile/build"), target: userDir.appendingPathComponent("build"))
    } catch { fputs("Unable to initialize the packaged Rime profile.\n", stderr); exit(1) }
    delegate.setupRime()
    delegate.startRime(fullCheck: false)
    delegate.loadSettings()
    TelepathyWorkerController.shared.start()
    withExtendedLifetime(server) { app.run() }
    rime_get_api_stdbool().pointee.finalize()
  }
}
