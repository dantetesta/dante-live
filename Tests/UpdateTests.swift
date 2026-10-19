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
    // A fixed number of yields does not guarantee the deferred callback ran.
    // Wait for its observable completion, retaining a bounded failure deadline.
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while installs == 0 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    precondition(installs == 1 && saves == 1 && installing && !pending && !gate.pending,
                 "The deferred update callback must run exactly once after preparation")
    gate.finish(); precondition(!gate.installing && !installing)
    let comparator = SUStandardVersionComparator.default
    precondition(comparator.compareVersion("9", toVersion: "10") == .orderedAscending)
    precondition(comparator.compareVersion("8", toVersion: "8") == .orderedSame)
    model.state["streaming"] = true
    precondition(model.liveOperationInProgress && model.updateCheckBlocked)
    // Refresh reads the real idle engine; use start/countdown flags for the actual guard.
    model.preparingLive = true
    precondition(model.liveOperationInProgress)
    do { try model.prepareForApplicationUpdate(); preconditionFailure("Should block preparing live") } catch { }
    model.preparingLive = false
    model.countdown.start(interval: .seconds(60)) { }
    precondition(model.liveOperationInProgress && model.updateCheckBlocked); model.countdown.cancel()
    model.state["streaming"] = false
    let openInvite = try model.guests.makeInvite()
    precondition(model.guests.invites.contains(where: { $0.id == openInvite.id }))
    precondition(model.liveOperationInProgress && !model.updateCheckBlocked,
                 "An open guest invite must not block checking after the stream ends")
    var guestLifecycle = GuestRoomStreamLifecycle()
    precondition(!guestLifecycle.ended(["started": true, "busy": true]))
    precondition(!guestLifecycle.ended(["started": false, "busy": true, "reconnecting": true]))
    precondition(guestLifecycle.ended(["started": false, "busy": false]))
    precondition(!guestLifecycle.ended(["started": false, "busy": false]))
    model.endLive()
    precondition(model.guests.invites.isEmpty, "Ending the stream must revoke invitations and close the guest room")
    precondition(!model.liveOperationInProgress && !model.updateCheckBlocked)
    // The profile fixture has a real project store; update preparation must
    // flush the currently selected profile before installation.
    try model.prepareForApplicationUpdate()
    precondition(FileManager.default.fileExists(atPath: model.projectDirectory!.appendingPathComponent("studio.json").path))
    model.updateInstalling = true; model.beginLive()
    precondition(model.pendingLive == nil && !model.preparingLive)
    model.updateInstalling = false
    print("PASS: update waits for live, explicit resume, persistence failure, duplicate install prevention, version comparison, live preparation/countdown guards and no start during install")
}
