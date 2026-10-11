import SwiftUI

/// Repeat rule picker for a to-do / template (web `RepeatPicker`, M5).
struct RepeatSheetView: View {
    @Bindable var model: AppModel
    let todoId: ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var freq: RepeatRule.Freq = .week
    @State private var every = 1
    @State private var weekdays: Set<Int> = []
    @State private var mode: RepeatRule.Mode = .fixed
    @State private var anchor = Date()

    private static let dayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            Form {
                Section("How often") {
                    Picker("Frequency", selection: $freq) {
                        Text("Daily").tag(RepeatRule.Freq.day)
                        Text("Weekly").tag(RepeatRule.Freq.week)
                        Text("Monthly").tag(RepeatRule.Freq.month)
                        Text("Yearly").tag(RepeatRule.Freq.year)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("repeat.freq")
                    Stepper("Every \(every) \(unitLabel)", value: $every, in: 1...99)
                        .accessibilityIdentifier("repeat.every")
                }
                if freq == .week && mode == .fixed {
                    Section("On these days") {
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                Button {
                                    if weekdays.contains(i) { weekdays.remove(i) }
                                    else { weekdays.insert(i) }
                                } label: {
                                    Text(Self.dayLabels[i])
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            weekdays.contains(i) ? colors.text : colors.bg
                                        )
                                        .foregroundStyle(
                                            weekdays.contains(i) ? colors.bg : colors.text
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(colors.hairline, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("repeat.weekday.\(i)")
                            }
                        }
                    }
                }
                Section("Repeat") {
                    Picker("Mode", selection: $mode) {
                        Text("On a schedule").tag(RepeatRule.Mode.fixed)
                        Text("After I complete the last one").tag(RepeatRule.Mode.afterCompletion)
                    }
                    .accessibilityIdentifier("repeat.mode")
                    DatePicker(
                        "Starting",
                        selection: $anchor,
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("repeat.anchor")
                }
                Section {
                    Button(currentRule != nil ? "Save" : "Repeat") { save() }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("repeat.save")
                    if currentRule != nil {
                        Button("Stop repeating", role: .destructive) { stop() }
                            .accessibilityIdentifier("repeat.stop")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Repeat")
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

    private var templateId: ID {
        guard let todo = model.entities.todos[todoId] else { return todoId }
        if todo.repeat != nil { return todo.id }
        return todo.repeatTemplateId ?? todo.id
    }

    private var currentRule: RepeatRule? {
        model.entities.todos[templateId]?.repeat
    }

    private var unitLabel: String {
        let plural: String
        switch freq {
        case .day: plural = "days"
        case .week: plural = "weeks"
        case .month: plural = "months"
        case .year: plural = "years"
        }
        return every == 1 ? String(plural.dropLast()) : plural
    }

    private func load() {
        let todo = model.entities.todos[todoId]
        let rule = currentRule
        freq = rule?.freq ?? .week
        every = rule?.every ?? 1
        weekdays = Set(rule?.weekdays ?? [])
        mode = rule?.mode ?? .fixed
        let anchorDate = rule?.anchor ?? todo?.startDate ?? When.toLocalDate(Date())
        anchor = When.fromLocalDate(anchorDate) ?? Date()
    }

    private func save() {
        let clamped = max(1, min(99, every))
        var rule = RepeatRule(
            freq: freq,
            every: clamped,
            weekdays: nil,
            mode: mode,
            anchor: When.toLocalDate(anchor),
            next: nil,
            reminderTime: currentRule?.reminderTime
        )
        if freq == .week, mode == .fixed, !weekdays.isEmpty {
            rule.weekdays = weekdays.sorted()
        }
        model.store.run("Repeat") { d, env in
            Repeats.setRepeat(d, env, id: templateId, rule: rule)
        }
        model.noteEntitiesChanged()
        dismiss()
    }

    private func stop() {
        model.store.run("Stop Repeating") { d, env in
            Repeats.setRepeat(d, env, id: templateId, rule: nil)
        }
        model.noteEntitiesChanged()
        dismiss()
    }
}
