import AppKit
import Foundation

let appVersion = "Browser tab QA"

@main
struct BrowserTabAudioHarness {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw StudioError.message("Informe app e pasta temporária.") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let app = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = StudioModel(projectDirectory: output.appendingPathComponent("project-\(UUID().uuidString)", isDirectory: true), engineBundlePath: app.path)
        model.start()
        guard model.engine != nil else { throw StudioError.message("Motor não iniciou.") }
        guard model.command("source.add", ["scene": model.sceneName, "type": "dante_browser_tab_audio", "name": "Aba QA"], undo: false) else {
            throw StudioError.message(model.error ?? "Fonte não criada.")
        }
        let url = try await model.browserTabAudio.prepare("Aba QA")
        let connection = output.appendingPathComponent("connection.json")
        let data = try JSONSerialization.data(withJSONObject: ["url": url.absoluteString])
        try data.write(to: connection, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: connection.path)
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(250))
            if let engine = model.engine {
                let levels = copied(dante_engine_audio_levels(engine))
                try levels.write(to: output.appendingPathComponent("levels.json"), atomically: true, encoding: .utf8)
            }
        }
        model.shutdown()
    }
}
