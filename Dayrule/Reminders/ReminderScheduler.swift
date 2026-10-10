import Foundation
import UserNotifications

/// Schedules local notifications for upcoming to-do reminders (PLAN §11).
/// Never calls `PUT /reminders`. Caps at 64 pending OS requests.
@MainActor
enum ReminderScheduler {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func reschedule(entities: Entities) async {
        let center = UNUserNotificationCenter.current()
        let ours = await pendingDayruleIdentifiers(center: center)
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard DeviceReminderPrefs.enabled else { return }

        let entries = ReminderPlan.upcoming(entities)
        let requests = ReminderPlan.requests(from: entries, showTitles: DeviceReminderPrefs.showTitles)
        for req in requests {
            guard let comps = ReminderPlan.dateComponents(from: req.fireAt) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Dayrule"
            content.body = req.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: req.identifier,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func clearAll() async {
        let center = UNUserNotificationCenter.current()
        let ours = await pendingDayruleIdentifiers(center: center)
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Pull identifiers via the completion API so non-Sendable
    /// `UNNotificationRequest` never crosses an async boundary (Xcode 16.4 / Swift 6).
    private static func pendingDayruleIdentifiers(
        center: UNUserNotificationCenter
    ) async -> [String] {
        await withCheckedContinuation { cont in
            center.getPendingNotificationRequests { requests in
                let ids = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix(ReminderPlan.idPrefix) }
                cont.resume(returning: ids)
            }
        }
    }
}
