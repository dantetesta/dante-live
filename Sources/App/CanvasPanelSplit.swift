import SwiftUI
import AppKit

/// Keeps the preview and production panels alive while changing only their layout.
struct CanvasPanelSplit<Preview: View, Controls: View>: View {
    @AppStorage("DanteLive.canvasHeightFraction") private var fraction = 0.60
    @GestureState private var translation: CGFloat = 0
    @LegacyState private var hovering = false
    private let preview: Preview
    private let controls: Controls
    private let handleHeight: CGFloat = 12

    init(@ViewBuilder preview: () -> Preview, @ViewBuilder controls: () -> Controls) {
        self.preview = preview()
        self.controls = controls()
    }

    var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.height - handleHeight)
            let limits = CanvasPanelLayout.limits(available: available)
            let base = CanvasPanelLayout.height(fraction: fraction, available: available)
            let height = min(limits.upperBound, max(limits.lowerBound, base + translation))
            VStack(spacing: 0) {
                preview.frame(height: height).clipped()
                resizeHandle(base: base, height: height, available: available)
                controls.frame(height: max(0, available - height)).clipped()
            }
            .coordinateSpace(name: "canvasPanelSplit")
        }
    }

    private func resizeHandle(base: CGFloat, height: CGFloat, available: CGFloat) -> some View {
        let percent = available > 0 ? Int(height / available * 100) : 0
        return ZStack {
            Color(nsColor: .windowBackgroundColor)
            Capsule().fill(hovering ? Color.teal : Color.secondary.opacity(0.45))
                .frame(width: 42, height: 4)
        }
        .frame(height: handleHeight)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .background(VerticalResizeCursor())
        .onHover { hovering = $0 }
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("canvasPanelSplit"))
            .updating($translation) { value, offset, _ in offset = value.translation.height }
            .onEnded { value in
                guard available > 0 else { return }
                adjust(by: value.translation.height, base: base, available: available)
            })
        .onTapGesture(count: 2) { fraction = 0.60 }
        .focusable()
        .onMoveCommand { direction in
            if direction == .up { adjust(by: -32, base: base, available: available) }
            if direction == .down { adjust(by: 32, base: base, available: available) }
        }
        .accessibilityElement()
        .accessibilityLabel("Divisão entre canvas e fontes")
        .accessibilityValue("Canvas: \(percent) por cento")
        .accessibilityHint("Arraste para ajustar. Use as setas para cima ou para baixo. Dois cliques restauram a divisão inicial.")
        .accessibilityAdjustableAction { direction in
            adjust(by: direction == .increment ? 32 : -32, base: base, available: available)
        }
        .help("Arraste para redimensionar o canvas e os painéis. Dois cliques para restaurar.")
    }

    private func adjust(by delta: CGFloat, base: CGFloat, available: CGFloat) {
        guard available > 0 else { return }
        let limits = CanvasPanelLayout.limits(available: available)
        fraction = Double(min(limits.upperBound, max(limits.lowerBound, base + delta)) / available)
    }
}

enum CanvasPanelLayout {
    static func limits(available: CGFloat) -> ClosedRange<CGFloat> {
        let space = max(0, available)
        // Keep mixer faders and mute buttons visible at the minimum window size.
        let minimumPreview = min(200, space * 0.4)
        let minimumControls = min(300, space * 0.6)
        return minimumPreview...max(minimumPreview, space - minimumControls)
    }

    static func height(fraction: Double, available: CGFloat) -> CGFloat {
        let limits = limits(available: available)
        let safeFraction = fraction.isFinite ? min(1, max(0, fraction)) : 0.60
        return min(limits.upperBound, max(limits.lowerBound, available * safeFraction))
    }
}

private struct VerticalResizeCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CursorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class CursorView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
