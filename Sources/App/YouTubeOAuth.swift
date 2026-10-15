import AppKit
import Network
import CryptoKit
import Security

@MainActor final class YouTubeOAuth {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var continuation: CheckedContinuation<(String, String), Error>?
    private var timeout: Task<Void, Never>?
    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw StudioError.message("Não foi possível iniciar uma conexão segura com o Google.") }
        return base64URL(Data(bytes))
    }
    static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func callbackCode(target: String, state: String) throws -> String? {
        guard let url = URLComponents(string: "http://127.0.0.1" + target), url.path == "/" else { return nil }
        let query = url.queryItems ?? []
        guard query.filter({ $0.name == "state" }).count == 1, query.first(where: { $0.name == "state" })?.value == state else { return nil }
        if query.contains(where: { $0.name == "error" }) { throw StudioError.message("A conexão com o Google foi cancelada ou não autorizada.") }
        guard query.filter({ $0.name == "code" }).count == 1, let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code
    }
    func authorize(client: YouTubeOAuthClient, api: YouTubeAPI) async throws -> YouTubeTokens {
        cancel()
        let state = try Self.randomToken(); let verifier = try Self.randomToken()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let (code, redirect) = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] status in
                    Task { @MainActor in
                        guard let self, self.continuation != nil else { return }
                        switch status {
                        case .ready:
                            guard let port = listener?.port else { self.finish(.failure(StudioError.message("Porta local indisponível."))); return }
                            let redirect = "http://127.0.0.1:\(port.rawValue)/"
                            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                            url.queryItems = ["client_id":client.clientID,"redirect_uri":redirect,"response_type":"code","scope":"https://www.googleapis.com/auth/youtube","access_type":"offline","prompt":"consent select_account","state":state,"code_challenge":challenge,"code_challenge_method":"S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
                            if !NSWorkspace.shared.open(url.url!) { self.finish(.failure(StudioError.message("Não foi possível abrir o navegador."))) }
                        case .failed: self.finish(.failure(StudioError.message("Não foi possível abrir o retorno local do Google.")))
                        default: break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        guard let self, self.connections.count < 8, let port = self.listener?.port else { connection.cancel(); return }
                        self.connections.append(connection); connection.start(queue: .main)
                        self.receive(connection, data: Data(), state: state, redirect: "http://127.0.0.1:\(port.rawValue)/")
                    }
                }
                listener.start(queue: .main)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(180)) } catch { return }
                    self?.finish(.failure(StudioError.message("O login expirou. Clique em Conectar YouTube para tentar novamente.")))
                }
            } catch { finish(.failure(StudioError.message("Não foi possível iniciar o retorno local do Google."))) }
        }
        try Task.checkCancellation()
        return try await api.tokens(client: client, fields: ["grant_type":"authorization_code","code":code,"redirect_uri":redirect,"code_verifier":verifier])
    }
    private func receive(_ connection: NWConnection, data: Data, state: String, redirect: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var data = data; if let chunk { data.append(chunk) }
                guard data.count <= 8192, error == nil else { self.close(connection); return }
                guard let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if complete { self.close(connection) } else { self.receive(connection, data: data, state: state, redirect: redirect) }; return
                }
                let request = text.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
                var result: Result<(String, String), Error>?
                if request.count == 3, request[0] == "GET" {
                    do { if let code = try Self.callbackCode(target: String(request[1]), state: state) { result = .success((code, redirect)) } }
                    catch { result = .failure(error) }
                }
                let body = result == nil ? "Solicitacao ignorada." : "Resposta recebida. Volte ao Dante Live para concluir a conexao."
                let response = "HTTP/1.1 \(result == nil ? "400 Bad Request" : "200 OK")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                let outcome = result
                connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
                    Task { @MainActor in
                        self?.close(connection)
                        if let outcome { self?.finish(outcome) }
                    }
                })
            }
        }
    }
    private func close(_ connection: NWConnection) { connection.cancel(); connections.removeAll { $0 === connection } }
    private func finish(_ result: Result<(String,String),Error>) {
        let pending = continuation; continuation = nil
        listener?.cancel(); listener = nil; connections.forEach { $0.cancel() }; connections.removeAll()
        timeout?.cancel(); timeout = nil
        pending?.resume(with: result)
    }
    func cancel() { finish(.failure(CancellationError())) }
}
