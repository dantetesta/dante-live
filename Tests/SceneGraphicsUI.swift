import AppKit
import SwiftUI
let appVersion = "Scene graphics QA"
struct GraphicsFixture: View {
    @LegacyState var marquee: [String: Any] = ["text": "DANTE LIVE • CUPOM LIVE10 • example.org", "height": 80, "speed": 90, "fontSize": 36, "bold": true]
    @LegacyState var qr: [String: Any] = ["qrType": "pix", "pixKeyType": "random", "pixName": "Nome de exemplo", "pixCity": "BRASILIA"]
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            MarqueeSettingsView(settings: $marquee, onEdit: { _ in }).frame(width: 330)
            Divider()
            QRCodeSettingsView(settings: $qr, onApply: {}).frame(width: 330)
        }.padding(24).frame(width: 740, height: 960, alignment: .top).background(Color(nsColor: .windowBackgroundColor))
    }
}
@main struct SceneGraphicsUI {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 960), styleMask: [.titled], backing: .buffered, defer: false);window.isReleasedWhenClosed = false
        for dark in [false,true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let view = NSHostingView(rootView: GraphicsFixture().environment(\.colorScheme, dark ? .dark : .light))
            window.contentView = view;window.setContentSize(NSSize(width: 740,height: 960));try await Task.sleep(for: .milliseconds(150));view.layoutSubtreeIfNeeded()
            let b = view.bitmapImageRepForCachingDisplay(in: view.bounds)!;view.cacheDisplay(in: view.bounds,to:b)
            try b.representation(using:.png,properties:[:])!.write(to: URL(fileURLWithPath:"build/scene-graphics-qa/controls-\(dark ? "dark" : "light").png"))
        }
        window.close(); print("PASS: native controls rendered at 330pt in both appearances")
    }
}
