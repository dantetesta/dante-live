import Foundation

/// A downloaded update may never interrupt capture/output or a pending live start.
/// Waiting for the operator to resume also prevents an unexpected restart at the end of a live.
@MainActor final class UpdateInstallationGate {
    private let isBusy: () -> Bool
    private let prepare: () throws -> Void
    private let changed: (Bool, Bool, String?) -> Void
    private var handler: (() -> Void)?
    private(set) var installing = false
    var pending: Bool { handler != nil }
    init(isBusy: @escaping () -> Bool, prepare: @escaping () throws -> Void,
         changed: @escaping (Bool, Bool, String?) -> Void) {
        self.isBusy = isBusy; self.prepare = prepare; self.changed = changed
    }
    func request(_ callback: @escaping () -> Void) {
        guard !installing, handler == nil else { return }
        handler = callback; resume()
    }
    func resume() {
        guard !installing, let callback = handler else { return }
        guard !isBusy() else {
            changed(true, false, "Atualização pronta. Finalize a live e use Dante Live → Verificar atualizações para instalar e reiniciar.")
            return
        }
        do { try prepare() }
        catch { changed(true, false, "A atualização foi adiada: \(error.localizedDescription)"); return }
        installing = true; handler = nil; changed(false, true, nil)
        // The delegate must return before invoking Sparkle's continuation.
        Task { @MainActor in await Task.yield(); callback() }
    }
    func finish() { handler = nil; installing = false; changed(false, false, nil) }
}

