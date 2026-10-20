import Foundation
import Combine

struct MicrophoneSample {
    let id: String
    let name: String
    let enabled: Bool
    /// Monotonic age from the last non-silent audio callback; nil means no signal yet.
    let signalAge: Double?
}
func microphoneOnAir(_ source: [String: Any], programAudioIDs: Set<String>) -> Bool {
    source.flag("sourceActive") || programAudioIDs.contains(source.string("sourceUUID", source.string("name")))
}
struct MicrophoneSilenceWatch {
    private var watchingSince: [String: TimeInterval] = [:]
    private var acknowledged = Set<String>()
    private var currentWarningIDs = Set<String>()
    mutating func acknowledgeCurrent() { acknowledged.formUnion(currentWarningIDs); currentWarningIDs.removeAll() }
    mutating func update(_ samples: [MicrophoneSample], live: Bool, now: TimeInterval) -> [String] {
        guard live else { watchingSince.removeAll(); acknowledged.removeAll(); currentWarningIDs.removeAll(); return [] }
        let enabled = samples.filter(\.enabled)
        let ids = Set(enabled.map(\.id))
        watchingSince = watchingSince.filter { ids.contains($0.key) }
        acknowledged.formIntersection(ids)
        currentWarningIDs.removeAll()
        var warnings: [String] = []
        for sample in enabled {
            let start = watchingSince[sample.id] ?? now
            watchingSince[sample.id] = start
            // Both a full 30 s of monitoring and 30 s without signal are required.
            let age = sample.signalAge.map { max(0, $0) } ?? .infinity
            if age < 30 { acknowledged.remove(sample.id) }
            if now - start >= 30 && age >= 30 && !acknowledged.contains(sample.id) {
                warnings.append(sample.name); currentWarningIDs.insert(sample.id)
            }
        }
        return warnings.sorted()
    }
}

@MainActor final class LiveCountdown: ObservableObject {
    @Published private(set) var remaining: Int?
    private var task: Task<Void, Never>?
    func start(interval: Duration = .seconds(1), action: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        remaining = 3
        task = Task { [weak self] in
            for next in [2,1,0] {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                if next == 0 { self.remaining = nil; self.task = nil; action() }
                else { self.remaining = next }
            }
        }
    }
    func cancel() { task?.cancel(); task = nil; remaining = nil }
    deinit { task?.cancel() }
}
