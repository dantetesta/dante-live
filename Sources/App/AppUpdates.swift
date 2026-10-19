import AppKit
import Sparkle

@MainActor final class AppUpdateCoordinator: NSObject, SPUUpdaterDelegate, NSMenuItemValidation {
    private weak var model: StudioModel?
    private let enabled: Bool
    private var controller: SPUStandardUpdaterController?
    private lazy var gate = UpdateInstallationGate(isBusy: { [weak self] in self?.model?.liveOperationInProgress != false }, prepare: { [weak self] in
        guard let model = self?.model else { throw StudioError.message("O estúdio não está disponível.") }
        try model.prepareForApplicationUpdate()
    }, changed: { [weak self] pending, installing, message in
        self?.model?.updateInstalling = installing
        self?.model?.pendingUpdateMessage = message
    })
    init(model: StudioModel, enabled: Bool) { self.model = model; self.enabled = enabled; super.init() }
    func start() {
        guard enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.startUpdater()
        // Sparkle documents this call immediately after start, before the next run loop.
        // Respect the user's automatic-check preference; never auto-download/install.
        if controller.updater.automaticallyChecksForUpdates { controller.updater.checkForUpdatesInBackground() }
    }
    @objc func checkForUpdates(_ sender: Any?) {
        guard enabled else { show("Atualizações desativadas nesta cópia de validação."); return }
        model?.refresh()
        guard model?.updateCheckBlocked == false else { show("Finalize a transmissão ou a preparação da live antes de verificar atualizações. Sua live continuará funcionando."); return }
        if gate.pending {
            let alert = NSAlert(); alert.messageText = "Instalar a atualização baixada?"
            alert.informativeText = "O Dante salvará o projeto, encerrará e abrirá novamente na versão atualizada."
            alert.addButton(withTitle: "Instalar e reiniciar"); alert.addButton(withTitle: "Agora não")
            if alert.runModal() == .alertFirstButtonReturn { gate.resume() }
        } else { controller?.checkForUpdates(sender) }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        enabled && !gate.installing && (gate.pending || controller?.updater.canCheckForUpdates == true)
    }
    private func show(_ text: String) { let alert = NSAlert(); alert.messageText = "Atualizações do Dante Live"; alert.informativeText = text; alert.runModal() }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        model?.refresh()
        guard enabled, model?.updateCheckBlocked == false else {
            throw NSError(domain: "DanteLive.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "Verificação adiada enquanto há uma live ativa ou sendo preparada."])
        }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        gate.request(installHandler)
        return true
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if error != nil { gate.finish() }
    }
}
