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
        DayruleSheet(
            title: "Repeat",
            confirm: SheetAction(title: "Save", identifier: "repeat.save") { save() },
            size: .standard
        ) {
            Form {
                Section {
                    Picker("Frequency", selection: $freq) {
                        Text("Daily").tag(RepeatRule.Freq.day)
                        Text("Weekly").tag(RepeatRule.Freq.week)
                        Text("Monthly").tag(RepeatRule.Freq.month)
                        Text("Yearly").tag(RepeatRule.Freq.year)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("repeat.freq")
                    Stepper(value: $every, in: 1...99) {
                        Text("Every \(every) \(unitLabel)")
                            .foregroundStyle(colors.text)
                    }
                    .accessibilityIdentifier("repeat.every")
                } header: {
                    DayruleSectionHeader(title: "How often")
                }
                .dayruleSheetRow(colors: colors)
                if freq == .week && mode == .fixed {
                    Section {
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                weekdayChip(i, colors: colors)
                            }
                        }
                    } header: {
                        DayruleSectionHeader(title: "On these days")
                    }
                    .dayruleSheetRow(colors: colors)
                }
                Section {
                    Picker(selection: $mode) {
                        Text("On a schedule").tag(RepeatRule.Mode.fixed)
                        Text("After I complete the last one").tag(RepeatRule.Mode.afterCompletion)
                    } label: {
                        Text("Mode").foregroundStyle(colors.text)
                    }
                    .accessibilityIdentifier("repeat.mode")
                    DatePicker(selection: $anchor, displayedComponents: .date) {
                        Text("Starting").foregroundStyle(colors.text)
                    }
                    .accessibilityIdentifier("repeat.anchor")
                } header: {
                    DayruleSectionHeader(title: "Repeat")
                }
                .dayruleSheetRow(colors: colors)
                SheetClearSection(
                    title: "Stop repeating",
                    isVisible: currentRule != nil,
                    identifier: "repeat.stop"
                ) {
                    stop()
                }
            }
            .dayruleAnimation(Motion.standard, value: freq)
            .dayruleAnimation(Motion.standard, value: mode)
            .onAppear(perform: load)
        }
    }

    private func weekdayChip(_ i: Int, colors: DayruleColors) -> some View {
        let on = weekdays.contains(i)
        return Button {
            if on { weekdays.remove(i) } else { weekdays.insert(i) }
        } label: {
            Text(Self.dayLabels[i])
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Tokens.minHit)
                .foregroundStyle(on ? colors.bg : colors.text)
                .background(on ? colors.text : colors.sidebar, in: Capsule())
                .overlay(Capsule().strokeBorder(colors.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // dayLabels start on Monday; weekdaySymbols start on Sunday.
        .accessibilityLabel(Calendar.current.weekdaySymbols[(i + 1) % 7])
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("repeat.weekday.\(i)")
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
