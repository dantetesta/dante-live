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
        print("PASS: atomic persistence, previous-version recovery, invalid save rejection, corrupt-file preservation")
        print("PASS: inline credential rejection, rejected-current quarantine without data loss")
        print("PASS: profile catalog preserves legacy project, isolates files and reopens last selection")
    }
}
