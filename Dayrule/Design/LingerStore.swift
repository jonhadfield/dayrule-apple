import SwiftUI

/// Keeps just-completed rows on screen for `linger` (`Motion.linger`), then folds them away,
/// so the checkbox pop and tick are seen and Undo has a target.
@Observable
@MainActor
final class LingerStore {
    private(set) var ids: Set<ID> = []
    @ObservationIgnored private var tasks: [ID: Task<Void, Never>] = [:]
    @ObservationIgnored private let linger: Duration

    /// Tests inject a short `linger`; the app uses the default.
    init(linger: Duration = Motion.linger) {
        self.linger = linger
    }

    /// Pass to `Lists.Context(keepVisible:)`.
    var keepVisible: Set<ID>? { ids.isEmpty ? nil : ids }

    func hold(_ id: ID) {
        tasks[id]?.cancel()
        ids.insert(id)
        let linger = linger
        tasks[id] = Task { [weak self] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, let self else { return }
            self.tasks[id] = nil
            withAnimation(Motion.system(Motion.fold)) {
                _ = self.ids.remove(id)
            }
        }
    }

    /// Reopened before the fold: drop it straight away, no animation.
    func release(_ id: ID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        ids.remove(id)
    }

    /// Lock and hydrate: forget everything.
    func clear() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        ids = []
    }
}
