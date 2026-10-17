import AppKit
import SwiftUI

private struct PanelDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var studioPanelDismiss: (() -> Void)? {
        get { self[PanelDismissKey.self] }
        set { self[PanelDismissKey.self] = newValue }
    }
}
@propertyWrapper struct StudioDismiss: DynamicProperty {
    @Environment(\.dismiss) private var native
    @Environment(\.studioPanelDismiss) private var panel
    var wrappedValue: () -> Void { { if let panel { panel() } else { native() } } }
}

/// One coordinator per presenter; no application modal session or attached sheet.
@MainActor final class StudioPanelController: NSObject, NSWindowDelegate {
    private static let controllers = NSHashTable<StudioPanelController>.weakObjects()
    private(set) var window: NSPanel?
    private var identity: AnyHashable?
    private var closed: (() -> Void)?
    override init() { super.init(); Self.controllers.add(self) }
    func present(identity: AnyHashable, title: String, content: AnyView, closed: @escaping () -> Void) {
        self.closed = closed
        if let window {
            if self.identity != identity {
                self.identity = identity
                window.contentView = NSHostingView(rootView: content)
            } else if let host = window.contentView as? NSHostingView<AnyView> {
                host.rootView = content
            }
            return
        }
        self.identity = identity
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = true
        panel.isMovable = true; panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = host; panel.delegate = self
        panel.center(); window = panel; panel.makeKeyAndOrderFront(nil)
    }
    func close(notify: Bool = true) {
        guard let window else { return }
        let callback = notify ? closed : nil
        self.window = nil; identity = nil; closed = nil
        window.delegate = nil
        window.contentView = nil
        window.close()
        callback?()
    }
    func windowWillClose(_ notification: Notification) { close() }
    static func closeAll() { for controller in controllers.allObjects { controller.close(notify: false) } }
}

private struct StudioPanelPresenter<PanelContent: View>: NSViewRepresentable {
    var identity: AnyHashable?
    var title: String
    var closed: () -> Void
    @ViewBuilder var content: () -> PanelContent
    func makeCoordinator() -> StudioPanelController { StudioPanelController() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        let controller = context.coordinator
        if let identity {
            let root = AnyView(content().environment(\.studioPanelDismiss, { [weak controller] in controller?.close() }))
            controller.present(identity: identity, title: title, content: root) {
                // Do not mutate SwiftUI state from updateNSView/window teardown.
                DispatchQueue.main.async { closed() }
            }
        } else { controller.close() }
    }
    static func dismantleNSView(_ view: NSView, coordinator: StudioPanelController) { coordinator.close(notify: false) }
}

extension View {
    func studioPanel<Content: View>(isPresented: Binding<Bool>, title: String, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        background(StudioPanelPresenter(identity: isPresented.wrappedValue ? AnyHashable(true) : nil, title: title, closed: {
            isPresented.wrappedValue = false; onDismiss?()
        }, content: content).frame(width: 0, height: 0))
    }
    func studioPanel<Item: Identifiable, Content: View>(item: Binding<Item?>, title: String, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        background(StudioPanelPresenter(identity: item.wrappedValue.map { AnyHashable($0.id) }, title: title, closed: {
            item.wrappedValue = nil; onDismiss?()
        }) { if let value = item.wrappedValue { content(value) } }.frame(width: 0, height: 0))
    }
}
