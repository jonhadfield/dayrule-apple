import SwiftUI

/// Keeps just-completed rows on screen for `linger` (`Motion.linger`), then folds them away,
/// so the checkbox pop and tick are seen and Undo has a target.
@Observable
@MainActor
final class LingerStore {
    private(set) var ids: Set<ID> = []
    /// Rows fading out under Reduce Motion; views draw them transparent.
    private(set) var fading: Set<ID> = []
    @ObservationIgnored private var tasks: [ID: Task<Void, Never>] = [:]
    @ObservationIgnored private let linger: Duration
    @ObservationIgnored private let reduceMotion: @MainActor () -> Bool

    /// Tests inject a short `linger` and the Reduce Motion setting; the app uses the defaults.
    init(linger: Duration = Motion.linger, reduceMotion: @escaping @MainActor () -> Bool = { Motion.reduceMotion }) {
        self.linger = linger
        self.reduceMotion = reduceMotion
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
            if self.reduceMotion() {
                // A List slides a removed row whatever animation it is given, so fade
                // the row out first, then close the gap without animating (PLAN §6.4).
                withAnimation(Motion.fade) {
                    _ = self.fading.insert(id)
                }
                try? await Task.sleep(for: Motion.fadeDuration)
                guard !Task.isCancelled else { return }
                self.tasks[id] = nil
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.ids.remove(id)
                    self.fading.remove(id)
                }
            } else {
                self.tasks[id] = nil
                withAnimation(Motion.fold) {
                    _ = self.ids.remove(id)
                }
            }
        }
    }

    /// Reopened before the fold: drop it straight away, no animation.
    func release(_ id: ID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        ids.remove(id)
        fading.remove(id)
    }

    /// Lock and hydrate: forget everything.
    func clear() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        ids = []
        fading = []
    }
}
