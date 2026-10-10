import SwiftUI

/// Minimal When picker (Today / Later / Ready / Clear + free-text parse).
struct WhenSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var freeText = ""
    @State private var parseError: String?

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            List {
                Section {
                    button("Today", colors: colors) { apply(.today) }
                    button("Later", colors: colors) { apply(.later) }
                    button("Anytime", colors: colors) { apply(.ready) }
                    button("Clear date", colors: colors) { apply(.clear) }
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
