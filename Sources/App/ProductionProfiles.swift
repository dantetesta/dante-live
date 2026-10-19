import Foundation

struct ProductionProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var lastOpened: Date
}

/// The original studio.json stays in place as the default profile. Only newly
/// created profiles live below profiles/, so upgrading never moves user media.
struct ProductionProfiles {
    private struct Index: Codable {
        var version: Int
        var selectedID: String
        var profiles: [ProductionProfile]
    }

    let baseDirectory: URL
    private(set) var profiles: [ProductionProfile]
    private(set) var selectedID: String
    private var indexURL: URL { baseDirectory.appendingPathComponent("production-profiles.json") }

    init(directory: URL) throws {
        baseDirectory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalogURL = directory.appendingPathComponent("production-profiles.json")
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: catalogURL))
            guard index.version == 1,
                  !index.profiles.isEmpty,
                  Set(index.profiles.map(\.id)).count == index.profiles.count,
                  index.profiles.contains(where: { $0.id == "default" }),
                  index.profiles.contains(where: { $0.id == index.selectedID }),
                  index.profiles.allSatisfy({ $0.id == "default" || UUID(uuidString: $0.id) != nil }) else {
                throw StudioError.message("O catálogo de perfis está inválido. Os projetos originais foram preservados.")
            }
            profiles = index.profiles
            selectedID = index.selectedID
        } else {
            profiles = [ProductionProfile(id: "default", name: "Meu estúdio", lastOpened: Date())]
            selectedID = "default"
        }
    }

    var selected: ProductionProfile { profiles.first { $0.id == selectedID }! }

    func directory(for id: String) -> URL? {
        guard profiles.contains(where: { $0.id == id }) else { return nil }
        return id == "default" ? baseDirectory : baseDirectory.appendingPathComponent("profiles", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    mutating func create(name: String, project: String) throws -> ProductionProfile {
        let title = try validatedName(name)
        guard !profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(title) == .orderedSame }) else {
            throw StudioError.message("Já existe um perfil com esse nome.")
        }
        let profile = ProductionProfile(id: UUID().uuidString, name: title, lastOpened: Date())
        let directory = baseDirectory.appendingPathComponent("profiles", isDirectory: true).appendingPathComponent(profile.id, isDirectory: true)
        let store = try ProjectStore(directory: directory)
        do {
            try store.save(project)
            var next = self
            next.profiles.append(profile)
            next.selectedID = profile.id
            try next.persist()
            self = next
            return profile
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    mutating func select(_ id: String) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw StudioError.message("Perfil não encontrado.") }
        var next = self
        next.selectedID = id
        next.profiles[next.profiles.firstIndex(where: { $0.id == id })!].lastOpened = Date()
        try next.persist()
        self = next
    }

    mutating func rename(_ id: String, to name: String) throws {
        let title = try validatedName(name)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw StudioError.message("Perfil não encontrado.") }
        guard !profiles.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(title) == .orderedSame }) else {
            throw StudioError.message("Já existe um perfil com esse nome.")
        }
        var next = self
        next.profiles[index].name = title
        try next.persist()
        self = next
    }

    private func validatedName(_ name: String) throws -> String {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80, !title.contains("\n"), !title.contains("\r") else {
            throw StudioError.message("Use um nome de perfil com até 80 caracteres e sem quebra de linha.")
        }
        return title
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(Index(version: 1, selectedID: selectedID, profiles: profiles))
        try data.write(to: indexURL, options: .atomic)
    }
}
