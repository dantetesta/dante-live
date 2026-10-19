import Foundation
import Darwin

enum AgentWireError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

/// Small, local-only wire protocol shared by the app and the stdio MCP helper.
enum AgentWire {
    static let maxMessage = 64 * 1024
    static let socketName = "agent.sock"

    static func directory(_ projectDirectory: URL? = nil) -> URL {
        (projectDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dante Live", isDirectory: true))
            .appendingPathComponent("agent-private", isDirectory: true)
    }

    static func path(_ projectDirectory: URL? = nil) throws -> String {
        let value = directory(projectDirectory).appendingPathComponent(socketName).path
        guard value.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw AgentWireError.message("O caminho local do MCP é longo demais para o macOS.")
        }
        return value
    }

    static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in path.utf8.enumerated() { bytes[index] = byte }
        }
        return address
    }

    static func socket(timeout: Bool = true) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentWireError.message("Não foi possível criar o canal MCP local.") }
        if timeout { setTimeout(fd) }
        return fd
    }

    static func setTimeout(_ fd: Int32) {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) { setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size)) }
        _ = withUnsafePointer(to: &timeout) { setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size)) }
    }

    static func readLine(_ fd: Int32) throws -> Data {
        var result = Data()
        var byte: UInt8 = 0
        while result.count < maxMessage {
            let count = Darwin.recv(fd, &byte, 1, 0)
            if count == 0 { throw AgentWireError.message("A conexão local com o Dante Live foi encerrada.") }
            if count < 0 { throw AgentWireError.message("Tempo esgotado na conexão local com o Dante Live.") }
            if byte == 10 { return result }
            result.append(byte)
        }
        throw AgentWireError.message("Mensagem MCP grande demais.")
    }

    static func writeLine(_ data: Data, to fd: Int32) throws {
        guard data.count < maxMessage else { throw AgentWireError.message("Resposta MCP grande demais.") }
        var output = data
        output.append(10)
        try output.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.send(fd, base.advanced(by: offset), raw.count - offset, 0)
                guard written > 0 else { throw AgentWireError.message("Falha ao enviar resposta MCP.") }
                offset += written
            }
        }
    }
}
