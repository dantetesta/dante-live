import AppKit
import Foundation
import Network
import Security

/// Chrome's chooser owns tab selection and permission. Only audio PCM crosses
/// this loopback endpoint; the selected tab's video never enters Dante Live.
@MainActor
final class BrowserTabAudioModel: ObservableObject {
    @Published private(set) var status: [String: String] = [:]
    private weak var studio: StudioModel?
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var connections: [UUID: NWConnection] = [:]
    private var sourceByToken: [String: String] = [:]
    private var tokenBySource: [String: String] = [:]
    private var lastFrame: [String: Date] = [:]

    init(studio: StudioModel) { self.studio = studio }

    func message(for source: String) -> String {
        guard let token = tokenBySource[source] else { return "Nenhuma aba selecionada. A escolha é renovada ao reabrir o app." }
        if let received = lastFrame[source], Date().timeIntervalSince(received) < 3 {
            return "Áudio da aba conectado ao mixer. As outras abas ficam de fora."
        }
        return sourceByToken[token] == nil ? "A conexão da aba foi encerrada." : "Aguardando áudio da aba. Mantenha a página de captura aberta no Chrome."
    }

    func select(_ source: String) async {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            studio?.error = "Instale ou abra o Google Chrome para escolher uma aba com áudio."; return
        }
        do {
            let url = try await prepare(source)
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error { Task { @MainActor in self?.studio?.error = "Não foi possível abrir o Chrome: \(error.localizedDescription)" } }
            }
        } catch { studio?.error = error.localizedDescription }
    }

    func prepare(_ source: String) async throws -> URL {
        guard studio?.engine != nil,
              studio?.scenes.contains(where: { $0.array("items").contains(where: { $0.string("name") == source && $0.string("type") == "dante_browser_tab_audio" }) }) == true else {
            throw StudioError.message("Selecione uma fonte de áudio de aba existente.")
        }
        try await start()
        let token = try Self.randomToken()
        if let old = tokenBySource[source] { sourceByToken.removeValue(forKey: old) }
        sourceByToken[token] = source; tokenBySource[source] = token
        lastFrame.removeValue(forKey: source)
        status[source] = "Escolha uma aba e marque Compartilhar áudio no Chrome."
        return URL(string: "http://127.0.0.1:\(port)/capture?session=\(token)")!
    }

    func prune(validSources: Set<String>) {
        for (source, token) in tokenBySource where !validSources.contains(source) {
            tokenBySource.removeValue(forKey: source)
            sourceByToken.removeValue(forKey: token)
            status.removeValue(forKey: source)
            lastFrame.removeValue(forKey: source)
        }
    }

    func stop() {
        listener?.cancel(); listener = nil; port = 0
        for connection in connections.values { connection.cancel() }
        connections.removeAll(); sourceByToken.removeAll(); tokenBySource.removeAll(); lastFrame.removeAll(); status.removeAll()
    }

    private func start() async throws {
        if listener != nil { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var done = false
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard !done else { return }
                        switch state {
                        case .ready:
                            done = true; self?.port = listener.port?.rawValue ?? 0; continuation.resume()
                        case .failed(let error):
                            done = true; continuation.resume(throwing: error)
                        case .cancelled:
                            done = true; continuation.resume(throwing: StudioError.message("A captura local foi encerrada."))
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
            }
        } catch { listener.cancel(); self.listener = nil; throw error }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 20 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection; connection.start(queue: .main)
        receive(connection, id: id, accumulated: Data())
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if let connection = self?.connections.removeValue(forKey: id) { connection.cancel() }
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                guard error == nil, bytes.count <= 65_536 else { self.respond(connection, id: id, code: 413); return }
                guard let separator = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                    if complete || bytes.count > 4096 { self.respond(connection, id: id, code: 400) }
                    else { self.receive(connection, id: id, accumulated: bytes) }
                    return
                }
                guard separator.lowerBound <= 4096,
                      let header = String(data: bytes[..<separator.lowerBound], encoding: .utf8) else { self.respond(connection, id: id, code: 400); return }
                let lines = header.components(separatedBy: "\r\n")
                let first = lines[0].split(separator: " ")
                guard first.count == 3, first[2] == "HTTP/1.1" else { self.respond(connection, id: id, code: 400); return }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { self.respond(connection, id: id, code: 400); return }
                    let key = String(line[..<colon]).lowercased()
                    guard headers[key] == nil else { self.respond(connection, id: id, code: 400); return }
                    headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                guard headers["host"] == "127.0.0.1:\(self.port)", headers["transfer-encoding"] == nil,
                      let length = Int(headers["content-length"] ?? "0"), (0...60_000).contains(length) else {
                    self.respond(connection, id: id, code: 400); return
                }
                let body = Data(bytes[separator.upperBound...])
                if body.count < length && !complete { self.receive(connection, id: id, accumulated: bytes); return }
                guard body.count == length else { self.respond(connection, id: id, code: 400); return }
                self.route(connection, id: id, method: String(first[0]), path: String(first[1]), headers: headers, body: body)
            }
        }
    }

    private func route(_ connection: NWConnection, id: UUID, method: String, path: String, headers: [String: String], body: Data) {
        let resource = studio.map { URL(fileURLWithPath: $0.engineBundlePath, isDirectory: true)
            .appendingPathComponent("Contents/Resources/TabAudioWeb", isDirectory: true) }
        if method == "GET", path.hasPrefix("/capture?session="),
           let token = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems?.first(where: { $0.name == "session" })?.value,
           sourceByToken[token] != nil, let data = resource.flatMap({ try? Data(contentsOf: $0.appendingPathComponent("capture.html")) }) {
            respond(connection, id: id, code: 200, body: data, type: "text/html; charset=utf-8"); return
        }
        if method == "GET", ["/capture.js", "/processor.js"].contains(path),
           let data = resource.flatMap({ try? Data(contentsOf: $0.appendingPathComponent(String(path.dropFirst()))) }) {
            respond(connection, id: id, code: 200, body: data, type: "text/javascript; charset=utf-8"); return
        }
        if method == "POST", path == "/pcm", headers["origin"] == "http://127.0.0.1:\(port)",
           headers["content-type"] == "application/octet-stream",
           let authorization = headers["authorization"], authorization.hasPrefix("Bearer "),
           let source = sourceByToken[String(authorization.dropFirst(7))],
           let rate = UInt32(headers["x-sample-rate"] ?? ""), (16000...96000).contains(rate),
           body.count >= 4, body.count <= 32_768, body.count.isMultiple(of: 4), let engine = studio?.engine {
            let frames = body.count / MemoryLayout<Float>.size
            var samples = [Float](repeating: 0, count: frames)
            _ = samples.withUnsafeMutableBytes { body.copyBytes(to: $0) }
            let accepted = samples.withUnsafeBufferPointer { dante_browser_tab_audio_frame(source, $0.baseAddress, UInt32(frames), rate) }
            if accepted {
                lastFrame[source] = Date()
                if status[source] != "Áudio da aba conectado." { status[source] = "Áudio da aba conectado." }
            }
            respond(connection, id: id, code: accepted ? 204 : 410)
            _ = engine // Keep engine lifetime explicit through the serialized bridge call.
            return
        }
        respond(connection, id: id, code: 403)
    }

    private func respond(_ connection: NWConnection, id: UUID, code: Int, body: Data = Data(), type: String = "text/plain") {
        let header = "HTTP/1.1 \(code) \(code == 200 ? "OK" : code == 204 ? "No Content" : "Error")\r\nContent-Length: \(body.count)\r\nContent-Type: \(type)\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nPermissions-Policy: display-capture=(self), camera=(), microphone=()\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n"
        var packet = Data(header.utf8); packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in connection.cancel(); self?.connections.removeValue(forKey: id) }
        })
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw StudioError.message("Não foi possível abrir uma captura segura.")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
