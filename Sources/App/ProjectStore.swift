import Foundation
import Security

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct ProjectStore {
    let directory: URL
    var current: URL { directory.appendingPathComponent("studio.json") }
    var backup: URL { directory.appendingPathComponent("studio.previous.json") }
    init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dante Live", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    func save(_ json: String) throws {
        guard let data = json.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else { throw StudioError.message("O projeto não contém JSON válido.") }
        if FileManager.default.fileExists(atPath: current.path) {
            let previous = try Data(contentsOf: current)
            // Never replace a valid recovery copy with malformed current data.
            if (try? JSONSerialization.jsonObject(with: previous)) != nil { try previous.write(to: backup, options: .atomic) }
        }
        try data.write(to: current, options: .atomic)
    }
    func load() throws -> (json: String, recovered: Bool)? {
        for (url, recovered) in [(current, false), (backup, true)] where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url), (try? JSONSerialization.jsonObject(with: data)) != nil,
               let json = String(data: data, encoding: .utf8) { return (json, recovered) }
        }
        if FileManager.default.fileExists(atPath: current.path) { throw StudioError.message("Não foi possível abrir o projeto nem a cópia de recuperação. Os arquivos foram preservados.") }
        return nil
    }
    func previous() throws -> String? {
        guard FileManager.default.fileExists(atPath: backup.path) else { return nil }
        let data = try Data(contentsOf: backup)
        _ = try JSONSerialization.jsonObject(with: data)
        return String(data: data, encoding: .utf8)
    }
    func preserveRejectedCurrent() throws {
        guard FileManager.default.fileExists(atPath: current.path) else { return }
        try FileManager.default.moveItem(at: current, to: directory.appendingPathComponent("studio.rejected-\(UUID().uuidString).json"))
    }
}

// Authenticated source URLs need a dedicated Keychain reference contract before support.
// Reject instead of silently persisting embedded secrets in project JSON/exports.
func validateNoInlineSecrets(_ value: Any) throws {
    let secretKeys: Set<String> = ["password", "passwd", "token", "api_key", "apikey", "access_token", "secret", "stream_key", "authorization"]
    if let dictionary = value as? [String: Any] {
        for (key, child) in dictionary {
            if secretKeys.contains(key.lowercased()), let string = child as? String, !string.isEmpty { throw StudioError.message("Credenciais em propriedades de fontes ainda não são suportadas. A chave de transmissão deve ser configurada em Saídas e armazenada no Acesso às Chaves.") }
            try validateNoInlineSecrets(child)
        }
    } else if let array = value as? [Any] { for child in array { try validateNoInlineSecrets(child) } }
    else if let string = value as? String, string.contains("://"), let url = URLComponents(string: string) {
        if url.user != nil || url.password != nil || url.queryItems?.contains(where: { secretKeys.contains($0.name.lowercased()) || $0.name.lowercased() == "key" }) == true {
            throw StudioError.message("URLs com credenciais embutidas não podem ser salvas no projeto. Use uma fonte sem autenticação; a transmissão possui configuração protegida no Acesso às Chaves.")
        }
    }
}

enum SecretStore {
    static let service = "com.dantetesta.DanteLive.streaming"
    static func save(_ secret: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(secret.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var new = query
            new[kSecValueData as String] = data
            new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(new as CFDictionary, nil)
            guard added == errSecSuccess else { throw StudioError.message("Não foi possível guardar a chave no Acesso às Chaves (\(added)).") }
        } else if result != errSecSuccess { throw StudioError.message("Acesso às Chaves indisponível (\(result)).") }
    }
    static func read(account: String) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        if result == errSecItemNotFound { return "" }
        guard result == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else { throw StudioError.message("Não foi possível ler a chave de transmissão.") }
        return text
    }
}

func jsonString(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "{}" }
    return text
}
func jsonObject(_ text: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
func copied(_ pointer: UnsafePointer<CChar>?) -> String { pointer.map(String.init(cString:)) ?? "" }
extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, _ fallback: String = "") -> String { self[key] as? String ?? fallback }
    func number(_ key: String, _ fallback: Double = 0) -> Double { (self[key] as? NSNumber)?.doubleValue ?? fallback }
    func flag(_ key: String, _ fallback: Bool = false) -> Bool { (self[key] as? NSNumber)?.boolValue ?? fallback }
    func array(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func object(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
}

extension Dictionary where Key == String, Value == Any {
    var entryName: String { string("name") }
    var entryID: String { string("id") }
    var sceneItemID: Int64 { (self["id"] as? NSNumber)?.int64Value ?? 0 }
}
