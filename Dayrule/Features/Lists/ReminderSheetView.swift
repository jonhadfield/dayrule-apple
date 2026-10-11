import SwiftUI

/// Reminder picker: date+time on a plain to-do, or time-of-day on a repeat
/// template (web `ReminderPicker`, M5). Local notifications land in M6.
struct ReminderSheetView: View {
    @Bindable var model: AppModel
    let todoId: ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var date = Date()
    @State private var time = Date()

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            Form {
                if let todo, todo.repeat != nil {
                    Section {
                        Text("Each repeat is reminded at:")
                            .foregroundStyle(colors.textSecondary)
                    }
                } else {
                    Section("Day") {
                        DatePicker(
                            "Date",
                            selection: $date,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .accessibilityIdentifier("reminder.date")
                    }
                }
                Section("Time") {
                    DatePicker(
                        "Time",
                        selection: $time,
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("reminder.time")
                }
                Section {
                    Button("Remind me") { apply() }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("reminder.apply")
                    if hasReminder {
                        Button("Clear", role: .destructive) { clear() }
                            .accessibilityIdentifier("reminder.clear")
                    }
                }
                Section {
                    Text("Reminders go off on the quarter hour. Turn them on in Settings → Reminders. The server never sees what a reminder is for.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Reminder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
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
