import SwiftUI

/// When picker — vocabulary matches lists: Today, date, Backlog, Not now, Inbox, Clear.
struct WhenSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var freeText = ""
    @State private var pickDate = Date()
    @State private var showDatePicker = false
    @State private var parseError: String?

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            List {
                Section {
                    button("Today", colors: colors) { apply(.today) }
                    Button {
                        showDatePicker.toggle()
                    } label: {
                        Text("Pick a date")
                            .foregroundStyle(colors.text)
                    }
                    if showDatePicker {
                        DatePicker(
                            "Date",
                            selection: $pickDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .listRowBackground(colors.bg)
                        Button("Use this date") {
                            apply(.date(When.toLocalDate(pickDate)))
                        }
                        .foregroundStyle(colors.accent)
                    }
                    button("Backlog", colors: colors) { apply(.ready) }
                    button("Not now", colors: colors) { apply(.later) }
                    button("Inbox", colors: colors) { apply(.inbox) }
                    button("Clear", colors: colors) { apply(.clear) }
                }
                Section("Type a date") {
                    TextField("tomorrow, next monday, 15 oct…", text: $freeText)
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
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("When")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
        }
    }

    private func button(_ title: String, colors: DayruleColors, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .foregroundStyle(colors.text)
    }

    private func apply(_ when: Commands.When) {
        do {
            try model.store.run("When") { d, env in
                try Commands.setWhen(d, env, ids: ids, when: when)
            }
            model.noteEntitiesChanged()
            dismiss()
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func parseAndApply() {
        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let result = When.parseWhen(text, today: Date()) else {
            parseError = "Couldn’t understand that date."
            return
        }
        apply(Commands.When(result))
    }
}
