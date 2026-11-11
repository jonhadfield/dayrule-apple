import SwiftUI

/// Deadline picker: free-text parse (same as When) + calendar + clear (M5).
struct DeadlineSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var freeText = ""
    @State private var parseError: String?
    @State private var pickedDate = Date()

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayruleSheet(
            title: "Deadline",
            confirm: SheetAction(title: "Save", identifier: "deadline.useCalendar") {
                apply(When.toLocalDate(pickedDate))
            },
            size: .tall
        ) {
            List {
                if let current = currentDeadline {
                    Section {
                        Text(DayruleDateFormat.due(current, today: When.toLocalDate(Date())))
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("deadline.current")
                            .dayruleSheetRow(colors: colors)
                    }
                }
                Section {
                    HStack(spacing: Tokens.Space.s) {
                        TextField(
                            "Type a date",
                            text: $freeText,
                            prompt: Text("Fri, tomorrow, 15 Oct…")
                                .foregroundStyle(colors.textSecondary)
                        )
                        .dayruleBareField(colors: colors)
                        .submitLabel(.done)
                        .accessibilityIdentifier("deadline.field")
                        .onSubmit(parseAndApply)
                        Button("Apply", action: parseAndApply)
                            .buttonStyle(.borderless)
                            .disabled(trimmedText.isEmpty)
                    }
                    .dayruleSheetRow(colors: colors)
                    if let parseError {
                        Text(parseError)
                            .font(DayruleType.error)
                            .foregroundStyle(colors.deadline)
                            .transition(.dayruleInlineError)
                            .dayruleSheetRow(colors: colors)
                    }
                } header: {
                    DayruleSectionHeader(title: "Type a date", surface: .sheet)
                }
                Section {
                    DatePicker(
                        "Deadline",
                        selection: $pickedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .dayruleSheetRow(colors: colors)
                } header: {
                    DayruleSectionHeader(title: "Calendar", surface: .sheet)
                }
                SheetClearSection(
                    title: "Remove deadline",
                    isVisible: currentDeadline != nil,
                    identifier: "deadline.clear"
                ) {
                    apply(nil)
                }
            }
            .listStyle(.plain)
            .dayruleAnimation(Motion.quick, value: parseError)
            .onChange(of: freeText) { parseError = nil }
            .onAppear {
                if let current = currentDeadline, let d = When.fromLocalDate(current) {
                    pickedDate = d
                }
            }
        }
    }

    private var trimmedText: String {
        freeText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentDeadline: LocalDate? {
        guard let id = ids.first else { return nil }
        return model.entities.todos[id]?.deadline ?? model.entities.projects[id]?.deadline
    }

    private func apply(_ deadline: LocalDate?) {
        model.store.run("Deadline") { d, env in
            Commands.setDeadline(d, env, ids: ids, deadline: deadline)
        }
        model.noteEntitiesChanged()
        dismiss()
    }

    private func parseAndApply() {
        let text = trimmedText
        guard !text.isEmpty else { return }
        guard let result = When.parseWhen(text, today: Date()) else {
            parseError = "Couldn’t understand that date."
            return
        }
        switch result {
        case .today:
            apply(When.toLocalDate(Date()))
        case .date(let d):
            apply(d)
        case .later:
            parseError = "Use a calendar date for a deadline."
        }
    }
}
