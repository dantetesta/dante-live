import Foundation
import Network

/// Loopback-only HTTP endpoint. It exposes exactly three bundled web assets and
/// authenticated guest signaling, never the engine, filesystem or OBS API.
@MainActor
final class GuestHTTPServer {
    typealias Reply = (Int, Data, String) -> Void
    var api: ((String, String, [String: Any], @escaping Reply) -> Void)?
    var publicHost: String?
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var requests: [Date] = []
    private let resources: URL
    private(set) var port: UInt16 = 0
    init(resources: URL) { self.resources = resources }
    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard !finished else { return }
                    switch state {
                    case .ready:
                        finished = true; self?.port = listener.port?.rawValue ?? 0; continuation.resume()
                    case .failed, .cancelled:
                        finished = true; continuation.resume(throwing: StudioError.message("Não foi possível abrir a sala local."))
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
        }
    }
    func stop() { listener?.cancel(); listener = nil; for connection in connections.values { connection.cancel() }; connections.removeAll(); port = 0; publicHost = nil }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection; connection.start(queue: .main)
        receive(connection, id: id, bytes: Data())
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(25))
            if let connection = self?.connections.removeValue(forKey: id) { connection.cancel() }
        }
    }
    private func receive(_ connection: NWConnection, id: UUID, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var all = bytes; if let data { all.append(data) }
                guard all.count <= 98_304, error == nil else { self.send(connection, id, 413, Data(), "text/plain"); return }
                guard let separator = all.range(of: Data("\r\n\r\n".utf8)) else {
                    if complete || all.count > 8_192 { self.send(connection, id, 400, Data(), "text/plain") }
                    else { self.receive(connection, id: id, bytes: all) }; return
                }
                guard separator.lowerBound <= 8_192, let header = String(data: all[..<separator.lowerBound], encoding: .utf8) else { self.send(connection,id,400,Data(),"text/plain");return }
                let lines = header.components(separatedBy: "\r\n"), first = lines[0].split(separator: " ")
                guard first.count == 3 else { self.send(connection,id,400,Data(),"text/plain");return }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { self.send(connection,id,400,Data(),"text/plain");return }
                    let key = String(line[..<colon]).lowercased()
                    guard headers[key] == nil else { self.send(connection,id,400,Data(),"text/plain");return }
                    headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                guard headers["transfer-encoding"] == nil, let count = Int(headers["content-length"] ?? "0"), (0...90_000).contains(count) else { self.send(connection,id,400,Data(),"text/plain");return }
                let body = Data(all[separator.upperBound...])
                if body.count < count && !complete { self.receive(connection,id:id,bytes:all);return }
                guard body.count == count else { self.send(connection,id,400,Data(),"text/plain");return }
                self.route(connection,id,String(first[0]),String(first[1]),headers,body)
            }
        }
    }
    private func route(_ connection: NWConnection,_ id: UUID,_ method: String,_ path: String,_ headers: [String:String],_ body: Data) {
        let host = headers["host"] ?? ""
        let local = "127.0.0.1:\(port)"
        guard host == local || host == publicHost else { send(connection,id,403,Data(),"text/plain");return }
        let now = Date(); requests.removeAll { now.timeIntervalSince($0) > 10 }
        guard requests.count < 160 else { send(connection,id,429,Data(),"text/plain");return }; requests.append(now)
        let files = ["/": ("index.html","text/html; charset=utf-8"),"/guest.js":("guest.js","text/javascript; charset=utf-8"),"/guest.css":("guest.css","text/css; charset=utf-8")]
        if method == "GET", let (file,type) = files[path], let content = try? Data(contentsOf: resources.appendingPathComponent(file)) { send(connection,id,200,content,type);return }
        let expectedOrigin = host == local ? "http://\(local)" : "https://\(host)"
        guard method == "POST", ["/join","/offer","/ice","/status","/leave"].contains(path),
              headers["origin"] == expectedOrigin,
              headers["content-type"]?.hasPrefix("application/json") == true,
              let auth = headers["authorization"], auth.hasPrefix("Bearer "), auth.count == 71,
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let api else { send(connection,id,403,Data(),"text/plain");return }
        api(path,String(auth.dropFirst(7)),payload) { [weak self, weak connection] status,data,type in
            guard let self, let connection, self.connections[id] != nil else { return };self.send(connection,id,status,data,type)
        }
    }
    private func send(_ connection: NWConnection,_ id: UUID,_ status: Int,_ data: Data,_ type: String) {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Length: \(data.count)\r\nContent-Type: \(type)\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nPermissions-Policy: camera=(self), microphone=(self), display-capture=(self)\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; media-src 'self' blob:; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n"
        var response = Data(header.utf8);response.append(data)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in connection.cancel();self?.connections.removeValue(forKey:id) }
        })
    }
}
