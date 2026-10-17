import AppKit
import SwiftUI

/// Window-scoped modifier feedback; no polling or global keyboard interception.
struct CanvasModifierMonitor: NSViewRepresentable {
    @Binding var optionDown: Bool
    var onEscape: () -> Bool
    final class Monitor: NSView {
        var changed: (Bool) -> Void = { _ in }
        var escape: () -> Bool = { false }
        private var token: Any?
        private var resign: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .flagsChanged {
                    let pressed = event.modifierFlags.contains(.option)
                    // A release in another panel must also clear stale feedback.
                    if !pressed || event.window === self.window { self.changed(pressed) }
                }
                guard event.window === self.window else { return event }
                if event.type == .keyDown && event.keyCode == 53 && self.escape() { return nil }
                return event
            }
            resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object:nil, queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed(false) }
            }
        }
        func stop() {
            if let token { NSEvent.removeMonitor(token); self.token = nil }
            if let resign { NotificationCenter.default.removeObserver(resign); self.resign = nil }
        }
        deinit { if let token { NSEvent.removeMonitor(token) }; if let resign { NotificationCenter.default.removeObserver(resign) } }
    }
    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) { view.changed = { optionDown = $0 }; view.escape = onEscape }
    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.stop() }
}

/// An extra source display exists only while framing. It shares the live source,
/// never clones a camera/decoder, and is outside every engine scene/output.
struct CanvasCropGhost: View {
    @ObservedObject var model: StudioModel
    let item: [String: Any]
    let box: CanvasGeometry
    let factor: Double
    let canvasSize: CGSize
    let cropPath: Path
    var body: some View {
        let sourceSize = CGSize(width:item.number("width"),height:item.number("height"))
        let crop = CanvasGeometry.Crop(left:item.number("cropLeft"),top:item.number("cropTop"),right:item.number("cropRight"),bottom:item.number("cropBottom"))
        if crop.left+crop.right+crop.top+crop.bottom > 0,
           let transform = box.sourceTransform(sourceSize:sourceSize,crop:crop) {
            // Bound the extra display resolution even when the source is zoomed.
            let resolution = min(1, 1024/max(sourceSize.width,sourceSize.height))
            let projection = CGAffineTransform(a:transform.a*factor/resolution,b:transform.b*factor/resolution,
                c:transform.c*factor/resolution,d:transform.d*factor/resolution,tx:transform.tx*factor,ty:transform.ty*factor)
            let fullPath = Path { path in
                let corners = [CGPoint.zero,CGPoint(x:sourceSize.width,y:0),CGPoint(x:sourceSize.width,y:sourceSize.height),CGPoint(x:0,y:sourceSize.height)]
                for (index,point) in corners.enumerated() {
                    let p=point.applying(transform),scaled=CGPoint(x:p.x*factor,y:p.y*factor)
                    if index == 0 { path.move(to:scaled) } else { path.addLine(to:scaled) }
                }
                path.closeSubpath()
            }
            CameraSourcePreview(model:model,sourceName:item.string("name"))
                .frame(width:sourceSize.width*resolution,height:sourceSize.height*resolution)
                .projectionEffect(ProjectionTransform(projection))
                .frame(width:canvasSize.width,height:canvasSize.height,alignment:.topLeading)
                .opacity(0.3)
                .mask {
                    Path { p in p.addRect(CGRect(origin:.zero,size:canvasSize)); p.addPath(cropPath) }
                        .fill(style:FillStyle(eoFill:true))
                }
            fullPath.stroke(.orange.opacity(0.65),style:StrokeStyle(lineWidth:1,dash:[5,4]))
        }
    }
}

struct CanvasFramingControls: View {
    @ObservedObject var model: StudioModel
    let item: [String: Any]
    private var active: Bool { model.framingItem == item.sceneItemID }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Button {
                model.framingItem = active ? nil : item.sceneItemID
            } label: {
                Label(active ? "Concluir enquadramento" : "Ajustar enquadramento",systemImage:active ? "checkmark" : "crop")
            }.tint(active ? .orange : .accentColor)
                .disabled(item.flag("locked") || item.number("boundsType") != 0 || item.number("width") <= 0 || item.number("height") <= 0)
            if active {
                Text("Arraste as alças laranja para recortar. Arraste por dentro para mover o conteúdo. A parte translúcida fica fora do recorte.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Centralizar conteúdo no recorte") {
                    let h=item.number("cropLeft")+item.number("cropRight"),v=item.number("cropTop")+item.number("cropBottom")
                    _ = model.command("item.transform",["scene":model.sceneName,"id":item.sceneItemID,
                        "cropLeft":floor(h/2),"cropRight":h-floor(h/2),"cropTop":floor(v/2),"cropBottom":v-floor(v/2)])
                }.disabled(item.flag("locked"))
                Text("Esc conclui. A guia translúcida aparece somente no editor.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
