import AppKit
import SwiftUI

@main
enum DanteLiveApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: StudioModel
    var window: NSWindow?
    lazy var updates = AppUpdateCoordinator(model: model, enabled: model.projectDirectory == nil)
    private var projectorWindows: [NSWindow] = []
    private var preferencesWindow: NSWindow?
    override init() {
        let arguments = CommandLine.arguments
        let index = arguments.firstIndex(of: "--validation-directory")
        let path = index.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        model = StudioModel(projectDirectory: path.flatMap { ($0 as NSString).isAbsolutePath ? URL(fileURLWithPath: $0, isDirectory: true) : nil })
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.restore()
        setupMenus()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1350, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = model.projectDirectory == nil ? "Dante Live \(appVersion)" : "Dante Live \(appVersion) • Validação isolada"
        window.subtitle = "Estúdio nativo para Mac"
        window.minSize = NSSize(width: 1050, height: 700)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("DanteStudioWindow")
        window.contentView = NSHostingView(rootView: StudioView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
        model.start()
        updates.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.refresh()
        if model.liveOperationInProgress {
            let alert = NSAlert(); alert.messageText = "O estúdio ainda está em uso"
            alert.informativeText = "Pare a transmissão, encerre a sala de convidados e aguarde a finalização antes de sair."
            alert.addButton(withTitle: "Voltar ao estúdio"); alert.runModal(); return .terminateCancel
        }
        // Destroy native displays while the engine remains alive.
        for sheet in window?.sheets ?? [] { detachPreviews(sheet.contentView) }
        for projector in projectorWindows {
            detachPreviews(projector.contentView)
            projector.contentView = nil
            projector.close()
        }
        projectorWindows.removeAll()
        detachPreviews(window?.contentView)
        window?.contentView = nil
        model.shutdown()
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender !== window { return true }
        model.refresh()
        if model.liveOperationInProgress {
            let alert = NSAlert(); alert.messageText = "Pare a transmissão e encerre a sala de convidados antes de fechar o estúdio."
            alert.runModal(); return false
        }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        guard let projector = notification.object as? NSWindow else { return }
        if projector === window {
            for secondary in projectorWindows { secondary.close() }
            preferencesWindow?.close()
            return
        }
        detachPreviews(projector.contentView)
        projector.contentView = nil
        projectorWindows.removeAll { $0 === projector }
    }
    func detachPreviews(_ view: NSView?) {
        guard let view else { return }
        (view as? EngineDisplayOwner)?.detach()
        view.subviews.forEach { detachPreviews($0) }
    }
    func setupMenus() {
        let menu = NSMenu()
        let application = NSMenuItem(); menu.addItem(application)
        let appMenu = NSMenu(); application.submenu = appMenu
        appMenu.addItem(withTitle: "Sobre o Dante Live", action: #selector(about), keyEquivalent: "").target = self
        add(appMenu, "Preferências…", #selector(openPreferences), ",")
        let updateItem = appMenu.addItem(withTitle: "Verificar atualizações…", action: #selector(AppUpdateCoordinator.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updates
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar Dante Live", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Sair do Dante Live", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); menu.addItem(fileItem); let file = NSMenu(title: "Arquivo"); fileItem.submenu = file
        add(file, "Abrir coleção…", #selector(openProject), "o")
        add(file, "Salvar", #selector(saveProject), "s")
        add(file, "Exportar coleção…", #selector(exportProject), "")
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title: "Editar"); editItem.submenu = edit
        add(edit, "Desfazer", #selector(undoProject), "z")
        let redo = add(edit, "Refazer", #selector(redoProject), "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        add(edit, "Ajustar fonte ao canvas", #selector(fitSource), "f")
        edit.addItem(.separator())
        for (title, action, key) in [("Recortar", "cut:", "x"), ("Copiar", "copy:", "c"), ("Colar", "paste:", "v"), ("Selecionar tudo", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        let viewItem = NSMenuItem(); menu.addItem(viewItem); let view = NSMenu(title: "Visualizar"); viewItem.submenu = view
        add(view, "Aparência do sistema", #selector(systemAppearance), "")
        add(view, "Modo claro", #selector(lightAppearance), "")
        add(view, "Modo escuro", #selector(darkAppearance), "")
        view.addItem(.separator())
        add(view, "Abrir projeção do programa", #selector(openProjector), "")
        NSApp.mainMenu = menu
    }
    @discardableResult func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem { let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self; return item }
    @objc func openProject() { model.importProject() }
    @objc func saveProject() { model.save() }
    @objc func exportProject() { model.exportProject() }
    @objc func undoProject() { model.undo() }
    @objc func redoProject() { model.redo() }
    @objc func systemAppearance() { AppAppearance.select(.system) }
    @objc func lightAppearance() { AppAppearance.select(.light) }
    @objc func darkAppearance() { AppAppearance.select(.dark) }
    @objc func fitSource() {
        guard NSApp.keyWindow === window, window?.sheets.isEmpty == true, !(window?.firstResponder is NSTextView) else { return }
        model.fitSelectedSource()
    }
    @objc func openPreferences() {
        if let preferencesWindow { preferencesWindow.makeKeyAndOrderFront(nil); return }
        let preferences = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 566, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        preferences.title = "Preferências do Dante Live"; preferences.isReleasedWhenClosed = false
        preferences.contentView = NSHostingView(rootView: PreferencesView())
        preferences.center(); preferences.makeKeyAndOrderFront(nil); preferencesWindow = preferences
    }
    @objc func openProjector() {
        guard model.engine != nil else { return }
        let projector = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        projector.title = "Dante Live • Programa"
        projector.isReleasedWhenClosed = false
        projector.delegate = self
        projector.collectionBehavior = [.fullScreenPrimary]
        projector.minSize = NSSize(width: 320, height: 180)
        projector.contentView = NSHostingView(rootView: CanvasView(model: model, program: true))
        projector.center()
        projector.makeKeyAndOrderFront(nil)
        projectorWindows.append(projector)
    }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Dante Live", .applicationVersion: "\(appVersion) — desenvolvimento", .credits: NSAttributedString(string: "Interface nativa SwiftUI e AppKit. Motor OBS Studio 32.2.2, GPL v2 ou posterior. Consulte os avisos em Contents/Resources/Licenses. Recursos e validação em evolução.")])
    }
}

var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "desenvolvimento" }
