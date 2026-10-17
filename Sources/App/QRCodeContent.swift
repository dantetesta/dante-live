import Foundation

struct QRContentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum QRContent {
    static func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    static func fail(_ message: String) -> QRContentError { QRContentError(message: message) }
    static func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func payload(_ s: [String: Any]) throws -> String {
        switch s.string("qrType", "url") {
        case "url":
            let value = clean(s.string("qrValue"))
            guard value.utf8.count <= 1000, let url = URLComponents(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, !value.contains(where: { $0.isWhitespace }) else { throw fail("Informe um link completo, como https://seusite.com.br.") }
            return value
        case "text":
            let value = s.string("qrValue")
            guard !clean(value).isEmpty, value.utf8.count <= 1000 else { throw fail("Digite um texto de até 1.000 bytes.") }
            return value
        case "pix": return try pix(s)
        default: throw fail("Escolha Link, Texto ou Pix.")
        }
    }
    static func pixKey(_ input: String, kind: String) throws -> String {
        let raw = clean(input)
        switch kind {
        case "email":
            let key = raw.lowercased()
            guard key.utf8.count <= 77, matches(key, "^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,}$") else { throw fail("Confira o e-mail cadastrado como chave Pix.") }
            return key
        case "phone":
            let key = raw.replacingOccurrences(of: "[ ()-]", with: "", options: .regularExpression)
            guard matches(key, "^\\+[1-9][0-9]{7,14}$") else { throw fail("Use o telefone com código do país, por exemplo +5511999999999.") }
            return key
        case "random":
            guard matches(raw, "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") else { throw fail("Cole a chave aleatória completa, incluindo os hífens.") }
            return raw.lowercased()
        case "cpf", "cnpj":
            let key = raw.replacingOccurrences(of: "[ ./-]", with: "", options: .regularExpression).uppercased()
            let cpf = kind == "cpf"
            guard matches(key, cpf ? "^[0-9]{11}$" : "^[A-Z0-9]{12}[0-9]{2}$"), Set(key).count > 1 else { throw fail("Confira o formato do \(cpf ? "CPF" : "CNPJ").") }
            let values = key.utf8.map { Int($0) - 48 }
            func digit(_ count: Int, _ weights: [Int]) -> Int {
                let rest = zip(values.prefix(count), weights).reduce(0) { $0 + $1.0 * $1.1 } % 11
                return rest < 2 ? 0 : 11 - rest
            }
            let n = cpf ? 9 : 12
            let first = cpf ? Array(stride(from: 10, through: 2, by: -1)) : [5,4,3,2,9,8,7,6,5,4,3,2]
            let second = cpf ? Array(stride(from: 11, through: 2, by: -1)) : [6,5,4,3,2,9,8,7,6,5,4,3,2]
            guard digit(n, first) == values[n], digit(n + 1, second) == values[n + 1] else { throw fail("Os dígitos verificadores do \(cpf ? "CPF" : "CNPJ") não conferem.") }
            return key
        default: throw fail("Selecione o tipo de chave Pix.")
        }
    }
    static func field(_ id: String, _ value: String) throws -> String {
        guard value.utf8.count <= 99 else { throw fail("Os dados do Pix ultrapassam o limite do padrão BR Code.") }
        return id + String(format: "%02d", value.utf8.count) + value
    }
    static func crc(_ text: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in text.utf8 {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc &<< 1) ^ 0x1021 : crc &<< 1 }
        }
        return String(format: "%04X", crc)
    }
    static func pix(_ s: [String: Any]) throws -> String {
        let key = try pixKey(s.string("pixKey"), kind: s.string("pixKeyType", "email"))
        func merchant(_ key: String, _ label: String, _ limit: Int) throws -> String {
            let value = clean(s.string(key)).folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            guard !value.isEmpty, value.utf8.count <= limit, matches(value, "^[A-Za-z0-9 .'-]+$") else { throw fail("Informe \(label), com até \(limit) caracteres, sem emojis ou símbolos especiais.") }
            return value
        }
        let name = try merchant("pixName", "o nome do recebedor", 25)
        let city = try merchant("pixCity", "a cidade", 15)
        var result = try field("00", "01") + field("26", field("00", "br.gov.bcb.pix") + field("01", key)) + field("52", "0000") + field("53", "986")
        let amount = clean(s.string("pixAmount")).replacingOccurrences(of: ",", with: ".")
        if !amount.isEmpty {
            guard matches(amount, "^[0-9]{1,10}(\\.[0-9]{1,2})?$"), let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { throw fail("Use um valor positivo, como 25,00, ou deixe vazio para valor livre.") }
            let parts = amount.split(separator: ".", omittingEmptySubsequences: false)
            let integer = String(Int(parts[0]) ?? 0), cents = parts.count == 2 ? String(parts[1]).padding(toLength: 2, withPad: "0", startingAt: 0) : "00"
            result += try field("54", integer + "." + cents)
        }
        result += try field("58", "BR") + field("59", name) + field("60", city) + field("62", field("05", "***"))
        result += "6304"
        return result + crc(result)
    }
}
