import AppKit

@main enum PreviewLifecycleTests {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the isolated app bundle path") }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dante-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let engine = dante_engine_create_with_config(CommandLine.arguments[1], 640, 360, 10, directory.path) else {
            fatalError(String(cString: dante_engine_last_error(nil)))
        }
        precondition(dante_engine_command(engine, "scene.create", "{\"name\":\"Preview lifecycle\"}"))
        for iteration in 0..<3 {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
            window.contentView = view
            guard let preview = dante_engine_preview_create(engine, Unmanaged.passUnretained(view).toOpaque(), iteration % 2 == 0) else {
                fatalError("Could not create native preview")
            }
            dante_engine_preview_resize(preview, 960, 540)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            dante_engine_preview_destroy(preview)
            window.contentView = nil
            window.close()
        }
        dante_engine_destroy(engine)
        print("PASS: three offscreen AppKit preview/program display lifecycles, resize and engine teardown; no window presented or device opened")
    }
}
