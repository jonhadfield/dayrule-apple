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
        NavigationStack {
            List {
                if let current = currentDeadline {
                    Section {
                        Text("Current: \(current)")
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("deadline.current")
                    }
                }
                Section("Type a date") {
                    TextField("fri, tomorrow, 15 oct…", text: $freeText)
                        .accessibilityIdentifier("deadline.field")
                        .onSubmit(parseAndApply)
                    Button("Apply") { parseAndApply() }
                        .foregroundStyle(colors.accent)
                        .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let parseError {
                        Text(parseError)
                            .font(.footnote)
                            .foregroundStyle(Tokens.Light.deadline)
                    }
                }
                Section("Calendar") {
                    DatePicker(
                        "Deadline",
                        selection: $pickedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    Button("Use selected day") {
                        apply(When.toLocalDate(pickedDate))
                    }
                    .foregroundStyle(colors.accent)
                    .accessibilityIdentifier("deadline.useCalendar")
                }
                Section {
                    Button("Remove deadline", role: .destructive) {
                        apply(nil)
                    }
                    .accessibilityIdentifier("deadline.clear")
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Deadline")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
            .onAppear {
                if let current = currentDeadline, let d = When.fromLocalDate(current) {
                    pickedDate = d
                }
            }
        }
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
        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
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
