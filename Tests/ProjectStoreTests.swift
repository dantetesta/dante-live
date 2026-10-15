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
        print("PASS: atomic persistence, previous-version recovery, invalid save rejection, corrupt-file preservation")
        print("PASS: inline credential rejection, rejected-current quarantine without data loss")
    }
}
