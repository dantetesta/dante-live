import Foundation
import Sparkle

@MainActor func runUpdateTests(model: StudioModel) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dante-update-store-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let youtube = YouTubeModel(directory: directory)
    try youtube.prepareForApplicationUpdate()
    precondition(FileManager.default.fileExists(atPath: directory.appendingPathComponent("youtube.json").path))
    try Data("invalid".utf8).write(to: directory.appendingPathComponent("youtube.json"))
    let corrupt = YouTubeModel(directory: directory)
    do { try corrupt.prepareForApplicationUpdate(); preconditionFailure("Corrupt draft must block update") } catch { }
    let preservedDraft = try String(contentsOf: directory.appendingPathComponent("youtube.json"), encoding: .utf8)
    precondition(preservedDraft == "invalid")
    var busy = true; var preparationFails = false; var saves = 0; var installs = 0
    var pending = false; var installing = false; var problem: String?
    let gate = UpdateInstallationGate(isBusy: { busy }, prepare: {
        if preparationFails { throw StudioError.message("Falha sintética ao salvar") }; saves += 1
    }, changed: { pending = $0; installing = $1; problem = $2 })
    gate.request { installs += 1 }
    precondition(gate.pending && pending && !installing && installs == 0 && saves == 0)
    gate.request { installs += 100 } // Duplicate callback must not replace the original.
    busy = false; await Task.yield()
    precondition(installs == 0) // End of live alone must not restart the app.
    preparationFails = true; gate.resume()
    precondition(installs == 0 && gate.pending && problem != nil)
    preparationFails = false; gate.resume(); gate.resume()
    for _ in 0..<10 { await Task.yield() }
    precondition(installs == 1 && saves == 1 && installing && !pending && !gate.pending)
    gate.finish(); precondition(!gate.installing && !installing)
    let comparator = SUStandardVersionComparator.default
    precondition(comparator.compareVersion("9", toVersion: "10") == .orderedAscending)
    precondition(comparator.compareVersion("8", toVersion: "8") == .orderedSame)
    model.state["streaming"] = true
    precondition(model.liveOperationInProgress)
    // Refresh reads the real idle engine; use start/countdown flags for the actual guard.
    model.preparingLive = true
    precondition(model.liveOperationInProgress)
    do { try model.prepareForApplicationUpdate(); preconditionFailure("Should block preparing live") } catch { }
    model.preparingLive = false
    model.countdown.start(interval: .seconds(60)) { }
    precondition(model.liveOperationInProgress); model.countdown.cancel()
    // This engine-only fixture has no ProjectStore; fail closed instead of installing.
    do { try model.prepareForApplicationUpdate(); preconditionFailure("Expected unavailable store rejection") } catch { }
    model.updateInstalling = true; model.beginLive()
    precondition(model.pendingLive == nil && !model.preparingLive)
    model.updateInstalling = false
    print("PASS: update waits for live, explicit resume, persistence failure, duplicate install prevention, version comparison, live preparation/countdown guards and no start during install")
}
