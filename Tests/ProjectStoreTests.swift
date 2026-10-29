import Foundation

@main
enum ProjectStoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dante-project-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProjectStore(directory: directory)
        let empty = try store.load(); precondition(empty == nil)
        try store.save("{\"version\":1}")
        try store.save("{\"version\":2}")
        let current = try store.load()
        precondition(current?.json == "{\"version\":2}" && current?.recovered == false)
        try Data("corrupt".utf8).write(to: store.current)
        let restored = try store.load()
        precondition(restored?.json == "{\"version\":1}" && restored?.recovered == true)
        try store.save("{\"version\":3}")
        let backup = try Data(contentsOf: store.backup)
        precondition(String(data: backup, encoding: .utf8) == "{\"version\":1}")
        var rejected = false
        do { try store.save("invalid") } catch { rejected = true }
        precondition(rejected)
        let final = try store.load()
        precondition(final?.json == "{\"version\":3}")
        try validateNoInlineSecrets(["local_file": "/tmp/media.mov", "text": "Dante Live"])
        for unsafe in [["password": "test-only"], ["url": "rtsp://test:example@localhost/test"], ["url": "https://localhost/test?token=example"]] {
            var refused = false
            do { try validateNoInlineSecrets(unsafe) } catch { refused = true }
            precondition(refused, "Inline credential accepted")
        }
        try store.preserveRejectedCurrent()
        precondition(!FileManager.default.fileExists(atPath: store.current.path))
        let quarantined = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("studio.rejected-") }
        precondition(quarantined.count == 1)
        let preserved = try Data(contentsOf: quarantined[0])
        precondition(String(data: preserved, encoding: .utf8) == "{\"version\":3}")
        var profiles = try ProductionProfiles(directory: directory)
        precondition(profiles.selectedID == "default" && profiles.directory(for: "default") == directory)
        let legacy = try Data(contentsOf: store.backup)
        let added = try profiles.create(name: "Tema A", project: String(decoding: legacy, as: UTF8.self))
        precondition(profiles.selectedID == added.id && profiles.profiles.count == 2)
        let profileProject = try ProjectStore(directory: profiles.directory(for: added.id)).load()
        precondition(profileProject?.json == String(decoding: legacy, as: UTF8.self))
        try profiles.select("default")
        try profiles.rename(added.id, to: "Tema B")
        let reopened = try ProductionProfiles(directory: directory)
        precondition(reopened.selectedID == "default" && reopened.profiles.first(where: { $0.id == added.id })?.name == "Tema B")
        precondition(FileManager.default.fileExists(atPath: store.backup.path), "legacy project was moved")
        let removedDirectory = profiles.directory(for: added.id)!
        let testTrash = directory.appendingPathComponent("test-trash")
        let moveToTrash: (URL) throws -> URL = { source in
            try FileManager.default.moveItem(at: source, to: testTrash)
            return testTrash
        }
        // Refuse the initial profile, the active profile and stale IDs before IO.
        for id in ["default", "missing"] {
            var refused = false
            do { try profiles.remove(id, moveToTrash: { _ in preconditionFailure("Protected profile reached trash") }) }
            catch { refused = true }
            precondition(refused)
        }
        try profiles.select(added.id)
        var activeRefused = false
        do { try profiles.remove(added.id, moveToTrash: moveToTrash) } catch { activeRefused = true }
        precondition(activeRefused && FileManager.default.fileExists(atPath: removedDirectory.path))
        try profiles.select("default")
        var trashRefused = false
        do { try profiles.remove(added.id, moveToTrash: { _ in throw StudioError.message("Trash unavailable fixture") }) }
        catch { trashRefused = true }
        precondition(trashRefused && profiles.profiles.count == 2)
        let afterTrashFailure = try ProductionProfiles(directory: directory)
        precondition(afterTrashFailure.profiles.count == 2)

        // Force catalog persistence to fail after staging the folder; restore it.
        let catalogURL = directory.appendingPathComponent("production-profiles.json")
        let catalogData = try Data(contentsOf: catalogURL)
        try FileManager.default.removeItem(at: catalogURL)
        try FileManager.default.createDirectory(at: catalogURL, withIntermediateDirectories: false)
        var saveRefused = false
        do { try profiles.remove(added.id, moveToTrash: moveToTrash) } catch { saveRefused = true }
        precondition(saveRefused && profiles.profiles.count == 2)
        precondition(FileManager.default.fileExists(atPath: removedDirectory.path))
        precondition(!FileManager.default.fileExists(atPath: testTrash.path))
        try FileManager.default.removeItem(at: catalogURL)
        try catalogData.write(to: catalogURL)

        try profiles.remove(added.id, moveToTrash: moveToTrash)
        precondition(profiles.profiles.count == 1 && profiles.selectedID == "default")
        precondition(!FileManager.default.fileExists(atPath: removedDirectory.path))
        precondition(FileManager.default.fileExists(atPath: testTrash.appendingPathComponent("studio.json").path))
        let afterRemoval = try ProductionProfiles(directory: directory)
        let preservedLegacy = try Data(contentsOf: store.backup)
        precondition(afterRemoval.profiles == profiles.profiles)
        precondition(preservedLegacy == legacy, "initial project changed during removal")

        // A missing private folder must not leave an unremovable stale entry.
        let missing = try profiles.create(name: "Pasta ausente", project: "{}")
        let missingDirectory = profiles.directory(for: missing.id)!
        try profiles.select("default")
        try FileManager.default.removeItem(at: missingDirectory)
        try profiles.remove(missing.id, moveToTrash: { _ in preconditionFailure("Missing folder reached trash") })
        let afterMissingRemoval = try ProductionProfiles(directory: directory)
        precondition(afterMissingRemoval.profiles.count == 1)
        print("PASS: atomic persistence, previous-version recovery, invalid save rejection, corrupt-file preservation")
        print("PASS: inline credential rejection, rejected-current quarantine without data loss")
        print("PASS: profile catalog preserves legacy project, isolates files and reopens last selection")
        print("PASS: profile removal persists, protects initial/active profiles, preserves projects on trash/catalog failure, handles missing folders")
    }
}
