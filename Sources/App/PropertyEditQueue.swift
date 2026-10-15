import Foundation
import Combine

/// Coalesces typed edits; picker/toggle changes are committed in the same event.
/// Actions capture their source identity rather than reading the current selection.
@MainActor
final class PropertyEditQueue: ObservableObject {
    private var task: Task<Void, Never>?
    private var pending: (() -> Void)?
    private var revision = 0

    func submit(immediate: Bool, action: @escaping () -> Void) {
        task?.cancel()
        revision += 1
        pending = action
        if immediate { flush(); return }
        let submitted = revision
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.revision == submitted else { return }
            self.flush()
        }
    }
    func flush() {
        task?.cancel(); task = nil; revision += 1
        let action = pending; pending = nil
        action?()
    }
    func cancel() {
        task?.cancel(); task = nil; pending = nil; revision += 1
    }
    deinit { task?.cancel() }
}

enum SourceOrder {
    /// Both arguments and result use display order (front to back).
    static func moving(_ ids: [Int64], from offsets: IndexSet, to destination: Int) -> [Int64]? {
        guard (0...ids.count).contains(destination), !offsets.isEmpty,
              offsets.allSatisfy({ ids.indices.contains($0) }), Set(ids).count == ids.count else { return nil }
        let moving = offsets.map { ids[$0] }
        var result = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        result.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        return result
    }
}
