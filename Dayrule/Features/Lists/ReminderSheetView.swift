import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Reminder picker: date+time on a plain to-do, or time-of-day on a repeat
/// template (web `ReminderPicker`, M5). Local notifications land in M6.
struct ReminderSheetView: View {
    @Bindable var model: AppModel
    let todoId: ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var date = Date()
    @State private var time = Date()
    @State private var remindersOn = true
    @State private var turningOn = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayruleSheet(
            title: "Reminder",
            confirm: SheetAction(title: "Remind me", identifier: "reminder.apply") { apply() },
            size: .standard
        ) {
            Form {
                if !remindersOn {
                    Section {
                        HStack(spacing: Tokens.Space.s) {
                            Text("Reminders are off on this device")
                                .font(DayruleType.helper)
                                .foregroundStyle(colors.textSecondary)
                            Spacer(minLength: Tokens.Space.s)
                            Button("Turn On") {
                                Task { await turnOnReminders() }
                            }
                            .buttonStyle(.dayruleLink)
                            .disabled(turningOn)
                        }
                    }
                    .dayruleSheetRow(colors: colors)
                    .transition(.opacity)
                }
                if let todo, todo.repeat != nil {
                    Section {
                        Text("Each repeat is reminded at:")
                            .foregroundStyle(colors.textSecondary)
                    }
                    .dayruleSheetRow(colors: colors)
                } else {
                    Section {
                        DatePicker(
                            "Date",
                            selection: $date,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .accessibilityIdentifier("reminder.date")
                    } header: {
                        DayruleSectionHeader(title: "Day")
                    }
                    .dayruleSheetRow(colors: colors)
                }
                DayruleFormSection {
                    DatePicker(selection: $time, displayedComponents: .hourAndMinute) {
                        Text("Time").foregroundStyle(colors.text)
                    }
                    .accessibilityIdentifier("reminder.time")
                } header: {
                    DayruleSectionHeader(title: "Time")
                } footer: {
                    Text("Reminders go off on the quarter hour. The server never sees what a reminder is for.")
                        .font(DayruleType.helper)
                        .foregroundStyle(colors.textSecondary)
                }
                .dayruleSheetRow(colors: colors)
                SheetClearSection(
                    title: "Clear",
                    isVisible: hasReminder,
                    identifier: "reminder.clear"
                ) {
                    clear()
                }
            }
            .dayruleAnimation(Motion.standard, value: remindersOn)
            .onAppear(perform: load)
        }
    }

    private var todo: Todo? { model.entities.todos[todoId] }

    private var hasReminder: Bool {
        guard let todo else { return false }
        if todo.repeat != nil { return todo.repeat?.reminderTime != nil }
        return todo.reminderAt != nil
    }

    private func load() {
        remindersOn = DeviceReminderPrefs.enabled
        guard let todo else { return }
        let today = When.toLocalDate(Date())
        let dateStr: String
        let timeStr: String
        if todo.repeat != nil {
            dateStr = today
            timeStr = todo.repeat?.reminderTime ?? "09:00"
        } else {
            dateStr = todo.reminderAt.map { String($0.prefix(10)) }
                ?? todo.startDate
                ?? today
            timeStr = todo.reminderAt.flatMap { at -> String? in
                guard at.count >= 16 else { return nil }
                return String(at.dropFirst(11).prefix(5))
            } ?? "09:00"
        }
        date = When.fromLocalDate(dateStr) ?? Date()
        time = Self.date(fromTime: timeStr) ?? Date()
    }

    /// Same path as Settings → Reminders; if the OS has said no, send the user to its settings.
    private func turnOnReminders() async {
        turningOn = true
        defer { turningOn = false }
        let ok = await ReminderScheduler.requestAuthorization()
        if ok {
            DeviceReminderPrefs.enabled = true
            remindersOn = true
            model.scheduleRemindersIfUnlocked()
        } else {
            openNotificationSettings()
        }
    }

    private func openNotificationSettings() {
        #if os(iOS)
        let link = UIApplication.openNotificationSettingsURLString
        #else
        let link = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        #endif
        if let url = URL(string: link) {
            openURL(url)
        }
    }

    private func apply() {
        let hhmm = When.roundToQuarter(Self.timeString(from: time))
        let day: LocalDate = {
            if todo?.repeat != nil { return When.toLocalDate(Date()) }
            return When.toLocalDate(date)
        }()
        let at = "\(day)T\(hhmm)"
        model.store.run("Reminder") { d, env in
            Commands.setReminder(d, env, ids: [todoId], at: at)
        }
        model.noteEntitiesChanged()
        dismiss()
    }

    private func clear() {
        model.store.run("Clear Reminder") { d, env in
            Commands.setReminder(d, env, ids: [todoId], at: nil)
        }
        model.noteEntitiesChanged()
        dismiss()
    }

    private static func timeString(from date: Date) -> String {
        let c = When.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func date(fromTime hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var comp = DateComponents()
        comp.hour = parts[0]
        comp.minute = parts[1]
        return When.calendar.date(from: comp)
    }
}
