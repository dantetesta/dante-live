import AppKit
import SwiftUI

// Explicit generic type preserves the macOS 14 property wrapper on SDKs that also export a State macro.
typealias LegacyState<Value> = SwiftUI.State<Value>

@MainActor protocol EngineDisplayOwner: AnyObject { func detach() }

final class EnginePreviewNSView: NSView, EngineDisplayOwner {
    var preview: UnsafeMutableRawPointer?
    var owner: OpaquePointer?
    var program = false
    override var isFlipped: Bool { true }
    func attach(engine: OpaquePointer?, program: Bool) {
        guard owner != engine || self.program != program else { return }
        detach(); owner = engine; self.program = program
        if let engine { preview = dante_engine_preview_create(engine, Unmanaged.passUnretained(self).toOpaque(), program); resizePreview() }
    }
    func detach() { if let preview { dante_engine_preview_destroy(preview); self.preview = nil }; owner = nil }
    func resizePreview() {
        guard let preview else { return }
        let pixels = convertToBacking(bounds)
        dante_engine_preview_resize(preview, UInt32(max(1, pixels.width)), UInt32(max(1, pixels.height)))
    }
    override func layout() { super.layout(); resizePreview() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); resizePreview() }
}

struct EnginePreview: NSViewRepresentable {
    @ObservedObject var model: StudioModel
    let program: Bool
    func makeNSView(context: Context) -> EnginePreviewNSView { EnginePreviewNSView() }
    func updateNSView(_ view: EnginePreviewNSView, context: Context) { view.attach(engine: model.engine, program: program) }
    static func dismantleNSView(_ view: EnginePreviewNSView, coordinator: ()) { view.detach() }
}

struct CanvasView: View {
    @ObservedObject var model: StudioModel
    var program = false
    @LegacyState private var dragStart: [String: Any]?
    @LegacyState private var dragUndo: String?
    @LegacyState private var cropping = false
    var body: some View {
        GeometryReader { geometry in
            let factor = min(geometry.size.width / model.canvasWidth, geometry.size.height / model.canvasHeight)
            let size = CGSize(width: model.canvasWidth * factor, height: model.canvasHeight * factor)
            ZStack(alignment: .topLeading) {
                EnginePreview(model: model, program: program)
                if !program {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { point in select(at: point, factor: factor) }
                    if let item = model.selected, item.number("width") > 0, item.number("height") > 0, let box = geometryFor(item) {
                        let path = Path { path in
                            path.move(to: scaled(box.corners[0], factor))
                            for corner in box.corners.dropFirst() { path.addLine(to: scaled(corner, factor)) }
                            path.closeSubpath()
                        }
                        path.fill(Color.white.opacity(0.001))
                            .contentShape(path)
                            .gesture(moveGesture(item: item, factor: factor))
                        path.stroke(item.flag("locked") ? Color.orange : Color.cyan, lineWidth: 1.5)
                            .allowsHitTesting(false)
                        if !item.flag("locked"), item.number("boundsType") == 0 {
                            ForEach(0..<8, id: \.self) { handle in
                                Rectangle().fill(.white).frame(width: 10, height: 10)
                                    .overlay(Rectangle().stroke(cropping ? .green : .cyan, lineWidth: 2))
                                    .frame(width: 28, height: 28).contentShape(Rectangle())
                                    .position(handlePosition(pointForHandle(handle, box: box), factor: factor, size: size))
                                    .highPriorityGesture(resizeGesture(item: item, factor: factor, handle: handle))
                                    .help("Arraste para redimensionar. Option (⌥) + arrasto para recortar.")
                                    .accessibilityLabel("Redimensionar ou recortar fonte, controle \(handle + 1)")
                            }
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height).clipped().background(.black)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .background(Color.black.opacity(0.85))
        .accessibilityLabel(program ? "Programa ao vivo" : "Editor da cena")
    }
    func scaled(_ point: CGPoint, _ factor: Double) -> CGPoint {
        CGPoint(x: point.x * factor, y: point.y * factor)
    }
    func handlePosition(_ point: CGPoint, factor: Double, size: CGSize) -> CGPoint {
        // Keep controls reachable when a fitted source meets the canvas edge.
        CGPoint(x: min(max(8, point.x * factor), max(8, size.width - 8)),
                y: min(max(8, point.y * factor), max(8, size.height - 8)))
    }
    func geometryFor(_ item: [String: Any]) -> CanvasGeometry? {
        guard let corners = item["boxCorners"] as? [[Double]] else { return nil }
        return CanvasGeometry(corners: corners)
    }
    func select(at point: CGPoint, factor: Double) {
        let canvasPoint = CGPoint(x: point.x / factor, y: point.y / factor)
        model.selectedItem = model.items.reversed().first(where: { item in
            item.flag("visible", true) && (geometryFor(item)?.contains(canvasPoint) ?? false)
        }).map { $0.sceneItemID }
    }
    func pointForHandle(_ handle: Int, box: CanvasGeometry) -> CGPoint {
        let a = box.corners[handle/2], b = box.corners[(handle/2+1)%4]
        return handle%2 == 0 ? a : CGPoint(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
    }
    func cropFor(_ item: [String: Any]) -> CanvasGeometry.Crop { .init(left: item.number("cropLeft"), top: item.number("cropTop"), right: item.number("cropRight"), bottom: item.number("cropBottom")) }
    func applyCrop(_ crop: CanvasGeometry.Crop, item: [String: Any], position: CGPoint) {
        _ = model.command("item.transform", ["scene": model.sceneName, "id": item.sceneItemID, "x": position.x, "y": position.y,
            "cropLeft": crop.left, "cropTop": crop.top, "cropRight": crop.right, "cropBottom": crop.bottom], undo: false)
    }
    func begin(_ item: [String: Any]) { if dragStart == nil { dragStart = item; dragUndo = model.captureUndo(); cropping = NSEvent.modifierFlags.contains(.option) } }
    func end() { if let dragUndo { model.pushUndo(dragUndo) }; dragStart = nil; dragUndo = nil; cropping = false }
    func moveGesture(item: [String: Any], factor: Double) -> some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in
            guard !item.flag("locked") else { return }; begin(item)
            let origin = dragStart ?? item
            if cropping, origin.number("boundsType") == 0, let box = geometryFor(origin),
               let crop = box.panCrop(translation: CGSize(width: value.translation.width/factor, height: value.translation.height/factor), sourceSize: CGSize(width: origin.number("width"), height: origin.number("height")), initial: cropFor(origin)) {
                applyCrop(crop, item: origin, position: CGPoint(x: origin.number("x"), y: origin.number("y"))); return
            }
            var x = origin.number("x") + value.translation.width / factor
            var y = origin.number("y") + value.translation.height / factor
            if abs(x) < 8 { x = 0 }; if abs(y) < 8 { y = 0 }
            _ = model.command("item.transform", ["scene": model.sceneName, "id": item.sceneItemID, "x": x, "y": y], undo: false)
        }.onEnded { _ in end() }
    }
    func resizeGesture(item: [String: Any], factor: Double, handle: Int) -> some Gesture {
        DragGesture(minimumDistance: 1).onChanged { value in
            begin(item); let origin = dragStart ?? item
            guard let box = geometryFor(origin) else { return }
            let translation = CGSize(width: value.translation.width/factor, height: value.translation.height/factor)
            if cropping {
                if let edit = box.crop(handle: handle, translation: translation, sourceSize: CGSize(width: origin.number("width"), height: origin.number("height")), initial: cropFor(origin), position: CGPoint(x: origin.number("x"), y: origin.number("y")), alignment: Int(origin.number("alignment", 5))) {
                    applyCrop(edit.crop, item: origin, position: edit.position)
                }
                return
            }
            guard let resize = box.resize(handle: handle,
                translation: translation,
                position: CGPoint(x: origin.number("x"), y: origin.number("y"))) else { return }
            _ = model.command("item.transform", ["scene": model.sceneName, "id": item.sceneItemID,
                "x": resize.position.x, "y": resize.position.y,
                "scaleX": origin.number("scaleX", 1) * resize.multiplier,
                "scaleY": origin.number("scaleY", 1) * resize.multiplier], undo: false)
        }.onEnded { _ in end() }
    }
}
