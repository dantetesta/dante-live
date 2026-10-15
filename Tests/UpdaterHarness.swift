import AppKit
import Sparkle

@main enum UpdaterHarness {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = HarnessDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class HarnessDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var controller: SPUStandardUpdaterController!
    var window: NSWindow!
    var label: NSTextField!
    var live = false
    var gate: UpdateInstallationGate!
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String }
    var directory: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "FixtureDirectory") as! String) }
    func event(_ kind: String) {
        let path = directory.appendingPathComponent("events.txt")
        let text = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        try! (text + "\(kind) version=\(version) pid=\(ProcessInfo.processInfo.processIdentifier)\n").write(to: path, atomically: true, encoding: .utf8)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        event("launch")
        gate = UpdateInstallationGate(isBusy: { [weak self] in self?.live != false }, prepare: { [weak self] in self?.event("save-before-update") }, changed: { [weak self] pending, installing, message in
            self?.label.stringValue = message ?? (installing ? "Instalando…" : "Pronto")
            self?.event(pending ? "deferred-live" : installing ? "installing" : "idle")
        })
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item);let appMenu = NSMenu();item.submenu=appMenu
        let check=appMenu.addItem(withTitle:"Verificar atualizações…",action:#selector(checkUpdate),keyEquivalent:"u");check.target=self
        let toggle=appMenu.addItem(withTitle:"Simular live",action:#selector(toggleLive),keyEquivalent:"l");toggle.target=self
        appMenu.addItem(withTitle:"Sair",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        NSApp.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:220),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="Dante Update Test • versão \(version)"
        let stack=NSStackView();stack.orientation = .vertical;stack.spacing=15;stack.edgeInsets=NSEdgeInsets(top:20,left:20,bottom:20,right:20)
        label=NSTextField(wrappingLabelWithString:"Teste isolado • versão \(version)")
        stack.addArrangedSubview(label)
        for (title,selector) in [("Verificar atualizações",#selector(checkUpdate)),("Simular live ativa / encerrada",#selector(toggleLive)),("Instalar atualização adiada",#selector(resumeUpdate))] { stack.addArrangedSubview(NSButton(title:title,target:self,action:selector)) }
        window.contentView=stack;window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        controller.startUpdater()
        if version == "1" { controller.updater.checkForUpdatesInBackground() }
    }
    @objc func checkUpdate() { controller.checkForUpdates(nil) }
    @objc func toggleLive() { live.toggle();label.stringValue=live ? "Live sintética ativa" : "Live sintética encerrada";event(live ? "live-start" : "live-stop") }
    @objc func resumeUpdate() { gate.resume() }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool { gate.request(installHandler);return true }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply { event(live ? "termination-blocked" : "termination-approved");return live ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}
