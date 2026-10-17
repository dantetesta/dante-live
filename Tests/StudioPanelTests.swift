import AppKit
import SwiftUI

@MainActor private final class PanelFixture: ObservableObject {
    @Published var first = false
    @Published var second = false
    var firstClosed = 0
    var secondClosed = 0
}
private struct PanelFixtureView: View {
    @ObservedObject var fixture: PanelFixture
    var body: some View {
        Text("Estúdio operável").frame(width: 400, height: 200)
            .studioPanel(isPresented: $fixture.first, title: "QA Chat", onDismiss: { fixture.firstClosed += 1 }) {
                PanelFixtureContent().frame(width: 320, height: 180)
            }
            .studioPanel(isPresented: $fixture.second, title: "QA Configurações", onDismiss: { fixture.secondClosed += 1 }) {
                Text("Segundo painel").frame(width: 320, height: 180)
            }
    }
}
private struct PanelFixtureContent: View {
    @StudioDismiss private var dismiss
    var body: some View { Button("Fechar painel") { dismiss() }.keyboardShortcut(.cancelAction) }
}
@MainActor func runStudioPanelTests() async throws {
    let fixture = PanelFixture()
    let owner = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 400, height: 200), styleMask: [.titled,.closable], backing: .buffered, defer: false)
    owner.isReleasedWhenClosed = false
    owner.contentView = NSHostingView(rootView: PanelFixtureView(fixture: fixture))
    owner.makeKeyAndOrderFront(nil)
    fixture.first = true; fixture.second = true
    try await Task.sleep(for: .milliseconds(180))
    let first = NSApp.windows.first { $0.title == "QA Chat" && $0.isVisible }!
    let second = NSApp.windows.first { $0.title == "QA Configurações" && $0.isVisible }!
    precondition(first !== second && first.isMovable && second.isMovable)
    precondition(NSApp.modalWindow == nil && owner.sheets.isEmpty && first.sheetParent == nil)
    first.setFrameOrigin(NSPoint(x:200,y:200)); second.setFrameOrigin(NSPoint(x:550,y:240))
    precondition(first.frame.origin != second.frame.origin)
    owner.makeKeyAndOrderFront(nil)
    precondition(owner.canBecomeKey && first.isVisible && second.isVisible)
    first.performClose(nil)
    try await Task.sleep(for: .milliseconds(120))
    precondition(!fixture.first && fixture.second && fixture.firstClosed == 1 && fixture.secondClosed == 0)
    fixture.first = true
    try await Task.sleep(for: .milliseconds(120))
    let reopened = NSApp.windows.first { $0.title == "QA Chat" && $0.isVisible }!
    precondition(reopened !== first)
    fixture.first = false; fixture.second = false
    try await Task.sleep(for: .milliseconds(120))
    precondition(!reopened.isVisible && !second.isVisible && fixture.firstClosed == 2 && fixture.secondClosed == 1)
    owner.contentView = nil; owner.close()
    print("PASS: simultaneous nonmodal movable panels, studio remains operable, independent close/bindings/callbacks and reopen")
}
