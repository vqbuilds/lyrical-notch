import Foundation

// Opt-in local diagnostics only: no files or network uploads in normal operation.
let playbackTracingEnabled = CommandLine.arguments.contains("--trace-playback")
func tracePlayback(_ event: String, _ fields: [String: Any] = [:]) {
    guard playbackTracingEnabled else { return }
    var row = fields
    row["event"] = event
    row["uptime"] = ProcessInfo.processInfo.systemUptime
    guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return }
    print(text)
    fflush(stdout)
}
