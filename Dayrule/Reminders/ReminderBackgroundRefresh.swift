import Foundation

#if os(iOS)
import BackgroundTasks

/// iOS BGAppRefresh to reschedule the nearest 64 reminders while stay-unlocked
/// (PLAN §11). No-op on macOS.
enum ReminderBackgroundRefresh {
    static let taskIdentifier = "uk.co.lessknown.dayrule.reminders.refresh"

    @MainActor
    private static weak var model: AppModel?

    /// Call once at process launch (before the run loop settles).
    static func registerLauncher() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            let finish = TaskCompletion(task)
            let work = Task { @MainActor in
                await model?.handleBackgroundReminderRefresh()
                scheduleIfNeeded()
            }
            task.expirationHandler = { work.cancel() }
            Task {
                _ = await work.result
                finish.complete(success: !work.isCancelled)
            }
        }
    }

    @MainActor
    static func bind(_ model: AppModel) {
        self.model = model
        scheduleIfNeeded()
    }

    @MainActor
    static func scheduleIfNeeded() {
        guard DeviceUnlockPrefs.stayUnlocked, DeviceReminderPrefs.enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // System may deny duplicates or rate-limit; ignore.
        }
    }
}

/// BGTask is not Sendable; box completion for the short-lived refresh Task.
private final class TaskCompletion: @unchecked Sendable {
    private let task: BGTask
    init(_ task: BGTask) { self.task = task }
    func complete(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
#endif
