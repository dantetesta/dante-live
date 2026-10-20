import AppKit
import SwiftUI

@main enum PartnerBannerVisual {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3,
              let icon = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
            fatalError("Usage: PartnerBannerVisual /path/to/DanteLive.png /path/to/output.png")
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 55),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: DanteLivePartnerBanner(icon: icon))
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                   CGWindowID(window.windowNumber),
                                                   [.boundsIgnoreFraming, .bestResolution]) else {
            fatalError("Cannot capture the banner's own test window")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        precondition(bitmap.pixelsWide >= 400 && bitmap.pixelsHigh >= 55)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
        print("Partner banner rendered at \(bitmap.pixelsWide)×\(bitmap.pixelsHigh): \(output.path)")
        window.close()
        fflush(stdout)
        exit(0)
    }
}
