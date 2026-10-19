import Foundation
import Darwin

@MainActor
final class AgentSocket {
    static let enabledKey = "DanteLive.localMCPEnabled"
    static let settingChanged = Notification.Name("DanteLiveLocalMCPSettingChanged")

    private weak var model: StudioModel?
    private var listener: Int32 = -1
    private var socketPath: String?
    private var generation = 0
    private(set) var problem: String?

    init(model: StudioModel) { self.model = model }

    var running: Bool { listener >= 0 }

    func applyPreference() {
        if UserDefaults.standard.bool(forKey: Self.enabledKey) { start() }
        else { stop(); problem = nil }
    }

    func start() {
        guard listener < 0 else { return }
        do {
            let directory = AgentWire.directory(model?.projectDirectory)
            let path = try AgentWire.path(model?.projectDirectory)
            var info = stat()
            if Darwin.lstat(directory.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK {
                throw AgentWireError.message("A pasta privada MCP não pode ser um link simbólico.")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            guard Darwin.lstat(directory.path, &info) == 0, info.st_uid == getuid(),
                  (info.st_mode & S_IFMT) == S_IFDIR else {
                throw AgentWireError.message("A pasta MCP não pertence ao usuário atual.")
            }
            if Darwin.lstat(path, &info) == 0 {
                let probe = try AgentWire.socket()
                var address = AgentWire.address(path)
                let active = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
                }
                Darwin.close(probe)
                guard !active, (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else {
                    throw AgentWireError.message("Já existe um servidor MCP neste endereço.")
                }
                guard Darwin.unlink(path) == 0 else { throw AgentWireError.message("Não foi possível limpar o socket MCP antigo.") }
            }
            let fd = try AgentWire.socket(timeout: false)
            var address = AgentWire.address(path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
            }
            guard bound, Darwin.chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
                Darwin.close(fd); _ = Darwin.unlink(path)
                throw AgentWireError.message("Não foi possível abrir o socket MCP privado.")
            }
            listener = fd; socketPath = path; generation += 1; problem = nil
            let currentGeneration = generation
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let client = Darwin.accept(fd, nil, nil)
                    if client < 0 { break }
                    AgentWire.setTimeout(client)
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        self?.serve(client, generation: currentGeneration)
                    }
                }
            }
        } catch { problem = error.localizedDescription }
    }

    func stop() {
        guard listener >= 0 else { return }
        generation += 1
        _ = Darwin.shutdown(listener, SHUT_RDWR)
        Darwin.close(listener); listener = -1
        if let socketPath { _ = Darwin.unlink(socketPath) }
        socketPath = nil
    }

    nonisolated private func serve(_ fd: Int32, generation: Int) {
        defer { Darwin.close(fd) }
        do {
            let input = try AgentWire.readLine(fd)
            guard let request = try JSONSerialization.jsonObject(with: input) as? [String: Any],
                  let tool = request["tool"] as? String,
                  let args = request["arguments"] as? [String: Any] else {
                throw AgentWireError.message("Pedido MCP local inválido.")
            }
            let result: [String: Any] = DispatchQueue.main.sync {
                guard self.generation == generation, self.running,
                      UserDefaults.standard.bool(forKey: Self.enabledKey), let model = self.model else {
                    return ["ok": false, "error": "MCP local desativado ou estúdio fechado."]
                }
                do { return ["ok": true, "data": try AgentTools.execute(tool, arguments: args, model: model)] }
                catch { return ["ok": false, "error": error.localizedDescription] }
            }
            try AgentWire.writeLine(JSONSerialization.data(withJSONObject: result), to: fd)
        } catch {
            let failure: [String: Any] = ["ok": false, "error": error.localizedDescription]
            if let data = try? JSONSerialization.data(withJSONObject: failure) { try? AgentWire.writeLine(data, to: fd) }
        }
    }
}
