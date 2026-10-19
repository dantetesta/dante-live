import Foundation

/// The MCP surface is intentionally narrower than the engine's command API.
/// In particular, no output, guest, credential, or arbitrary command is exposed.
@MainActor
enum AgentTools {
    static let editableTypes: Set<String> = [
        "text_ft2_source_v2", "color_source_v3", "image_source", "dante_marquee",
        "dante_qrcode", "dante_audio_visualizer", "dante_youtube_chat", "dante_superchat"
    ]

    static func execute(_ name: String, arguments: [String: Any], model: StudioModel) throws -> [String: Any] {
        guard model.engine != nil else { throw StudioError.message("O estúdio ainda não está pronto.") }
        if name == "studio_overview" {
            return ["canvas": ["width": model.canvasWidth, "height": model.canvasHeight],
                    "selectedScene": model.sceneName, "live": model.active,
                    "scenes": model.scenes.map { ["name": $0.string("name"), "itemCount": $0.array("items").count] }]
        }
        if name == "scene_items" {
            let scene = try sceneName(arguments, model: model)
            let items = model.scenes.first { $0.string("name") == scene }?.array("items") ?? []
            let safeKeys = ["id", "name", "type", "sourceUUID", "audio", "x", "y", "scaleX", "scaleY", "width", "height", "rotation", "visible", "locked", "cropLeft", "cropRight", "cropTop", "cropBottom"]
            return ["scene": scene, "items": items.map { item in item.filter { safeKeys.contains($0.key) } }]
        }
        if name == "source_types" {
            return ["sources": model.catalog.array("sources")
                .filter { editableTypes.contains($0.string("id")) }
                .map { ["id": $0.string("id"), "name": $0.string("name")] }]
        }
        if name == "source_options" {
            let type = try text(arguments, "type")
            guard editableTypes.contains(type), model.catalog.array("sources").contains(where: { $0.string("id") == type }) else {
                throw StudioError.message("Tipo de fonte indisponível para o MCP.")
            }
            let details = model.properties(type: type)
            return ["type": type, "settings": details.object("settings"), "properties": details.array("properties")]
        }

        guard !model.active, !model.updateInstalling, !model.preparingLive else {
            throw StudioError.message("A edição por IA fica pausada durante transmissão ou preparação. Use o editor após encerrar a live.")
        }
        switch name {
        case "scene_create":
            let value = try text(arguments, "name")
            try run(model, "scene.create", ["name": value])
            return ["created": value]
        case "scene_rename":
            let scene = try sceneName(arguments, model: model)
            let value = try text(arguments, "newName")
            try run(model, "scene.rename", ["scene": scene, "name": value])
            return ["scene": value]
        case "scene_select":
            let scene = try sceneName(arguments, model: model)
            try run(model, "scene.select", ["scene": scene])
            return ["selectedScene": scene]
        case "source_add":
            let scene = try sceneName(arguments, model: model)
            let type = try text(arguments, "type")
            guard editableTypes.contains(type), model.catalog.array("sources").contains(where: { $0.string("id") == type }) else {
                throw StudioError.message("Tipo de fonte indisponível para o MCP. Consulte source_types.")
            }
            let source = try text(arguments, "name")
            let settings = try settings(arguments)
            try run(model, "source.add", ["scene": scene, "type": type, "name": source, "settings": settings])
            let item = model.scenes.first { $0.string("name") == scene }?.array("items").first { $0.string("name") == source }
            return ["scene": scene, "name": source, "id": item?.sceneItemID ?? 0]
        case "source_update":
            let source = try text(arguments, "name")
            guard model.scenes.flatMap({ $0.array("items") }).contains(where: { $0.string("name") == source && editableTypes.contains($0.string("type")) }) else {
                throw StudioError.message("Fonte visual não encontrada.")
            }
            try run(model, "source.update", ["name": source, "settings": try settings(arguments)])
            return ["updated": source]
        case "source_reuse":
            let scene = try sceneName(arguments, model: model)
            let source = try text(arguments, "name")
            guard !model.guests.managedSourceNames.contains(source),
                  model.scenes.flatMap({ $0.array("items") }).contains(where: {
                      $0.string("name") == source && ($0.number("width") > 0 || $0.flag("awaitingVideo"))
                  }) else { throw StudioError.message("Fonte visual existente não encontrada.") }
            try run(model, "source.reuse", ["scene": scene, "name": source])
            let item = model.scenes.first { $0.string("name") == scene }?.array("items").first { $0.string("name") == source }
            return ["scene": scene, "name": source, "id": item?.sceneItemID ?? 0]
        case "item_transform":
            let scene = try sceneName(arguments, model: model)
            let id = try itemID(arguments, scene: scene, model: model)
            var payload: [String: Any] = ["scene": scene, "id": id]
            for key in ["x", "y", "scaleX", "scaleY", "rotation", "cropLeft", "cropRight", "cropTop", "cropBottom"] {
                guard let raw = arguments[key] else { continue }
                guard let number = raw as? NSNumber, number.doubleValue.isFinite else { throw StudioError.message("Valor inválido para \(key).") }
                let value = number.doubleValue
                let limit: ClosedRange<Double> = key.hasPrefix("crop") ? 0...8192 : key.hasPrefix("scale") ? 0.01...64 : key == "rotation" ? -3600...3600 : -32768...32768
                guard limit.contains(value) else { throw StudioError.message("Valor fora do limite para \(key).") }
                payload[key] = number
            }
            guard payload.count > 2 else { throw StudioError.message("Informe ao menos uma coordenada, escala, rotação ou recorte.") }
            try run(model, "item.transform", payload)
            return ["scene": scene, "id": id]
        case "item_visibility":
            let scene = try sceneName(arguments, model: model)
            let id = try itemID(arguments, scene: scene, model: model)
            guard let visible = arguments["visible"] as? Bool else { throw StudioError.message("Informe visible como verdadeiro ou falso.") }
            try run(model, "item.visible", ["scene": scene, "id": id, "value": visible])
            return ["scene": scene, "id": id, "visible": visible]
        case "item_order":
            let scene = try sceneName(arguments, model: model)
            let id = try itemID(arguments, scene: scene, model: model)
            guard let raw = arguments["index"] as? NSNumber else { throw StudioError.message("Informe index.") }
            let count = model.scenes.first { $0.string("name") == scene }?.array("items").count ?? 0
            let index = raw.intValue
            guard (0..<count).contains(index) else { throw StudioError.message("Posição fora da lista de fontes.") }
            try run(model, "item.order", ["scene": scene, "id": id, "index": index])
            return ["scene": scene, "id": id, "index": index]
        case "studio_undo":
            let before = model.undoCount
            guard before > 0 else { throw StudioError.message("Não há alteração para desfazer.") }
            model.undo()
            guard model.undoCount < before else { throw StudioError.message(model.error ?? "Não foi possível desfazer.") }
            return ["undone": true]
        default:
            throw StudioError.message("Ferramenta MCP desconhecida.")
        }
    }

    private static func run(_ model: StudioModel, _ operation: String, _ payload: [String: Any]) throws {
        guard model.command(operation, payload) else { throw StudioError.message(model.error ?? "O motor recusou a edição.") }
        model.notice = "IA local • \(operation)"
    }

    private static func text(_ args: [String: Any], _ key: String) throws -> String {
        guard let raw = args[key] as? String else { throw StudioError.message("Informe \(key).") }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80, !value.contains("\n") else { throw StudioError.message("\(key) deve ter de 1 a 80 caracteres em uma linha.") }
        return value
    }

    private static func sceneName(_ args: [String: Any], model: StudioModel) throws -> String {
        let value = try text(args, "scene")
        guard model.scenes.contains(where: { $0.string("name") == value }) else { throw StudioError.message("Cena não encontrada.") }
        return value
    }

    private static func itemID(_ args: [String: Any], scene: String, model: StudioModel) throws -> Int64 {
        guard let number = args["id"] as? NSNumber else { throw StudioError.message("Informe o id do elemento.") }
        let id = number.int64Value
        guard model.scenes.first(where: { $0.string("name") == scene })?.array("items").contains(where: { $0.sceneItemID == id }) == true else {
            throw StudioError.message("Elemento não encontrado nesta cena.")
        }
        return id
    }

    private static func settings(_ args: [String: Any]) throws -> [String: Any] {
        guard let value = args["settings"] as? [String: Any] else { throw StudioError.message("Informe settings como objeto JSON.") }
        guard JSONSerialization.isValidJSONObject(value), jsonString(value).utf8.count < 16 * 1024 else { throw StudioError.message("Configuração inválida ou grande demais.") }
        try validateNoInlineSecrets(value)
        return value
    }
}
