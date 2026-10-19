import Foundation
import Darwin

private func object(_ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
    ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
}
private func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
private func number(_ description: String) -> [String: Any] { ["type": "number", "description": description] }
private func integer(_ description: String) -> [String: Any] { ["type": "integer", "description": description] }

private let tools: [[String: Any]] = [
    ["name": "studio_overview", "description": "Lista cenas, cena selecionada e dimensões do canvas. Não revela configurações de transmissão.", "inputSchema": object()],
    ["name": "scene_items", "description": "Mostra os elementos e suas coordenadas em uma cena, sem credenciais nem configurações privadas.",
     "inputSchema": object(["scene": string("Nome exato da cena")], required: ["scene"])],
    ["name": "source_types", "description": "Lista os tipos de elementos visuais que a IA pode adicionar à cena.", "inputSchema": object()],
    ["name": "source_options", "description": "Mostra valores padrão e propriedades configuráveis de um tipo de fonte visual.",
     "inputSchema": object(["type": string("ID retornado por source_types")], required: ["type"])],
    ["name": "scene_create", "description": "Cria uma cena vazia no projeto local. Disponível somente fora de uma transmissão.",
     "inputSchema": object(["name": string("Nome exclusivo da nova cena")], required: ["name"])],
    ["name": "scene_rename", "description": "Renomeia uma cena do projeto local.",
     "inputSchema": object(["scene": string("Nome atual"), "newName": string("Novo nome")], required: ["scene", "newName"])],
    ["name": "scene_select", "description": "Seleciona uma cena no editor. Disponível somente fora de uma transmissão.",
     "inputSchema": object(["scene": string("Nome exato da cena")], required: ["scene"])],
    ["name": "source_add", "description": "Adiciona uma fonte visual permitida; consulte source_types e source_options. Arquivos locais exigem um caminho existente.",
     "inputSchema": object(["scene": string("Cena de destino"), "type": string("ID da fonte"), "name": string("Nome exclusivo"),
                            "settings": ["type": "object", "description": "Configurações OBS da fonte", "additionalProperties": true]],
                           required: ["scene", "type", "name", "settings"])],
    ["name": "source_update", "description": "Atualiza propriedades de uma fonte visual já criada; não altera câmera, microfone nem transmissão.",
     "inputSchema": object(["name": string("Nome exato da fonte"), "settings": ["type": "object", "additionalProperties": true]], required: ["name", "settings"])],
    ["name": "source_reuse", "description": "Reutiliza numa cena uma fonte visual já existente no projeto, inclusive câmera previamente configurada. Não abre uma nova captura.",
     "inputSchema": object(["scene": string("Cena de destino"), "name": string("Nome da fonte existente")], required: ["scene", "name"])],
    ["name": "item_transform", "description": "Posiciona, dimensiona proporcionalmente, gira ou recorta um elemento por ID. Campos omitidos mantêm o valor anterior.",
     "inputSchema": object(["scene": string("Cena"), "id": integer("ID retornado por scene_items"),
                            "x": number("Posição horizontal em pixels"), "y": number("Posição vertical em pixels"),
                            "scaleX": number("Escala horizontal"), "scaleY": number("Escala vertical"),
                            "rotation": number("Graus"), "cropLeft": integer("Recorte esquerdo"),
                            "cropRight": integer("Recorte direito"), "cropTop": integer("Recorte superior"),
                            "cropBottom": integer("Recorte inferior")], required: ["scene", "id"])],
    ["name": "item_visibility", "description": "Mostra ou oculta um elemento da cena por ID.",
     "inputSchema": object(["scene": string("Cena"), "id": integer("ID do elemento"), "visible": ["type": "boolean"]], required: ["scene", "id", "visible"])],
    ["name": "item_order", "description": "Altera a posição de uma fonte na pilha da cena, de 0 até a última posição.",
     "inputSchema": object(["scene": string("Cena"), "id": integer("ID do elemento"), "index": integer("Nova posição na lista")], required: ["scene", "id", "index"])],
    ["name": "studio_undo", "description": "Desfaz a última edição do projeto local, se possível.", "inputSchema": object()]
]

private func json(_ value: Any) -> Data? {
    guard JSONSerialization.isValidJSONObject(value) else { return nil }
    return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private func respond(_ value: [String: Any]) {
    guard let data = json(value), data.count < AgentWire.maxMessage else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

private func error(_ id: Any, _ code: Int, _ message: String) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
}

private func appCall(_ name: String, _ arguments: [String: Any]) throws -> [String: Any] {
    let path = try AgentWire.path()
    let fd = try AgentWire.socket()
    defer { Darwin.close(fd) }
    var address = AgentWire.address(path)
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
    }
    guard connected else { throw AgentWireError.message("Abra o Dante Live e ative MCP local em Preferências.") }
    guard let request = json(["tool": name, "arguments": arguments]) else { throw AgentWireError.message("Argumentos inválidos.") }
    try AgentWire.writeLine(request, to: fd)
    let response = try AgentWire.readLine(fd)
    guard let parsed = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
        throw AgentWireError.message("Resposta inválida do Dante Live.")
    }
    guard parsed["ok"] as? Bool == true else { throw AgentWireError.message(parsed["error"] as? String ?? "Edição recusada pelo Dante Live.") }
    return parsed["data"] as? [String: Any] ?? [:]
}

private func inputLine() -> Data? {
    var data = Data()
    while data.count < AgentWire.maxMessage {
        let byte = fgetc(stdin)
        if byte == EOF { return nil }
        if byte == 10 { return data }
        data.append(UInt8(byte))
    }
    // Discard the rest of an oversized message before reading another one.
    while true { let byte = fgetc(stdin); if byte == EOF || byte == 10 { break } }
    return Data()
}

var initialized = false
while let line = inputLine() {
    guard !line.isEmpty, let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        respond(error(NSNull(), -32700, "JSON inválido.")); continue
    }
    guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
        respond(error(request["id"] ?? NSNull(), -32600, "Pedido JSON-RPC inválido.")); continue
    }
    if method == "notifications/initialized" { continue }
    guard let id = request["id"] else { continue }
    switch method {
    case "initialize":
        initialized = true
        respond(["jsonrpc": "2.0", "id": id, "result": [
            "protocolVersion": "2025-11-25", "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "dante-live", "title": "Dante Live", "version": "1.0.0"],
            "instructions": "Controle local de cenas. Leia studio_overview, scene_items e source_options antes de editar. As edições são bloqueadas durante a live."
        ]])
    case "ping":
        respond(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
    case "tools/list" where initialized:
        respond(["jsonrpc": "2.0", "id": id, "result": ["tools": tools]])
    case "tools/call" where initialized:
        let params = request["params"] as? [String: Any] ?? [:]
        guard let name = params["name"] as? String, tools.contains(where: { $0["name"] as? String == name }),
              let arguments = params["arguments"] as? [String: Any] else {
            respond(error(id, -32602, "Ferramenta ou argumentos inválidos.")); continue
        }
        do {
            let result = try appCall(name, arguments)
            let content = String(data: json(result) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
            respond(["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": content]], "structuredContent": result, "isError": false]])
        } catch {
            respond(["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]])
        }
    default:
        respond(error(id, -32601, "Método MCP não disponível."))
    }
}
