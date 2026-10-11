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
        let selected = currentSelection
        NavigationStack {
            List {
                Section {
                    whenRow("Today", selected: selected == .today, colors: colors) { apply(.today) }
                    Button {
                        showDatePicker.toggle()
                    } label: {
                        HStack {
                            Text("Pick a date")
                                .foregroundStyle(colors.text)
                            Spacer()
                            if selected == .pickDate {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .listRowBackground(colors.bg)
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
                        .listRowBackground(colors.bg)
                    }
                    whenRow("Backlog", selected: selected == .backlog, colors: colors) { apply(.ready) }
                    whenRow("Not now", selected: selected == .notNow, colors: colors) { apply(.later) }
                    whenRow("Inbox", selected: selected == .inbox, colors: colors) { apply(.inbox) }
                    whenRow("Clear", selected: false, colors: colors) { apply(.clear) }
                }
                Section("Type a date") {
                    TextField("tomorrow, next monday, 15 oct…", text: $freeText)
                        .onSubmit(parseAndApply)
                        .listRowBackground(colors.bg)
                    Button("Apply") { parseAndApply() }
                        .foregroundStyle(colors.accent)
                        .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .listRowBackground(colors.bg)
                    if let parseError {
                        Text(parseError)
                            .font(.footnote)
                            .foregroundStyle(Tokens.Light.deadline)
                            .listRowBackground(colors.bg)
                    }
                }
            }
            .listStyle(.plain)
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

    private enum Selection: Equatable {
        case today, pickDate, backlog, notNow, inbox
    }

    /// Match vocabulary for the first id (single-item When from row menus).
    private var currentSelection: Selection? {
        guard let id = ids.first else { return nil }
        let today = When.toLocalDate(Date())
        if let t = model.entities.todos[id] {
            return selection(start: t.start, startDate: t.startDate, today: today)
        }
        if let p = model.entities.projects[id] {
            return selection(start: p.start, startDate: p.startDate, today: today)
        }
        return nil
    }

    private func selection(start: StartBucket, startDate: LocalDate?, today: LocalDate) -> Selection? {
        if start == .later { return .notNow }
        if start == .inbox { return .inbox }
        if let startDate {
            if startDate == today { return .today }
            if startDate > today { return .pickDate }
            return .today
        }
        if start == .ready { return .backlog }
        return nil
    }

    private func whenRow(
        _ title: String,
        selected: Bool,
        colors: DayruleColors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(colors.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(colors.accent)
                }
            }
        }
        .listRowBackground(colors.bg)
        .listRowSeparatorTint(colors.hairline)
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
