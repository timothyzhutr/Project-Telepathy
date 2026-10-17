import AppKit
import InputMethodKit

// Included only in the temporary experiment build, never the release app.
final class ActivationTimingProbe {
  private var state = ActivationTraceState()
  private let controller = UUID().uuidString

  func activate(_ client: Any?) {
    emit(state.activate(at: ProcessInfo.processInfo.systemUptime), client)
  }

  func deactivate(_ client: Any?) {
    emit(state.deactivate(at: ProcessInfo.processInfo.systemUptime), client)
  }

  func key(_ event: NSEvent, client: Any?) {
    guard event.type == .keyDown,
      let row = state.firstKey(eventTime: event.timestamp, receivedAt: ProcessInfo.processInfo.systemUptime) else { return }
    emit(row, client)
  }

  private func emit(_ row: [String: Any], _ client: Any?) {
    guard FileManager.default.fileExists(atPath: ActivationTimingPaths.enabled.path) else { return }
    var row = row
    row["controller"] = controller
    row["process"] = ProcessInfo.processInfo.processIdentifier
    row["client_app"] = (client as? IMKTextInput)?.bundleIdentifier() ?? "unknown"
    guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
          let output = try? FileHandle(forWritingTo: ActivationTimingPaths.log) else { return }
    defer { try? output.close() }
    data.append(10)
    do { try output.seekToEnd(); try output.write(contentsOf: data) } catch {}
  }
}
