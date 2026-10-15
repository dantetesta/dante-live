import Foundation
import Combine

struct MicrophoneSample {
    let id: String
    let name: String
    let enabled: Bool
    /// Monotonic age from the last non-silent audio callback; nil means no signal yet.
    let signalAge: Double?
}
struct MicrophoneSilenceWatch {
    private var watchingSince: [String: TimeInterval] = [:]
    mutating func update(_ samples: [MicrophoneSample], live: Bool, now: TimeInterval) -> [String] {
        guard live else { watchingSince.removeAll(); return [] }
        let enabled = samples.filter(\.enabled)
        let ids = Set(enabled.map(\.id))
        watchingSince = watchingSince.filter { ids.contains($0.key) }
        var warnings: [String] = []
        for sample in enabled {
            let start = watchingSince[sample.id] ?? now
            watchingSince[sample.id] = start
            // Both a full 30 s of monitoring and 30 s without signal are required.
            let age = sample.signalAge.map { max(0, $0) } ?? .infinity
            if now - start >= 30 && age >= 30 { warnings.append(sample.name) }
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
