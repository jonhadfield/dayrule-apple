import SwiftUI

/// When picker — vocabulary matches lists: Today, date, Backlog, Not now, Inbox, Clear.
struct WhenSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dayruleDenseLayout) private var denseLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var freeText = ""
    @State private var pickDate = Date()
    @State private var showDatePicker = false
    @State private var parseError: String?
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        let selected = currentSelection
        DayruleSheet(
            title: "When",
            confirm: showDatePicker
                ? SheetAction(title: "Use this date") { apply(.date(When.toLocalDate(pickDate))) }
                : nil,
            size: .tall,
            detents: [.medium, .large],
            detentSelection: $detent
        ) {
            List {
                Section {
                    whenRow("Today", selected: selected == .today) { apply(.today) }
                    whenRow("Tomorrow", selected: selected == .tomorrow) {
                        let tomorrow = When.addLocalDays(When.toLocalDate(Date()), 1)
                        apply(.date(tomorrow))
                    }
                    pickDateRow(selected: selected == .pickDate, colors: colors)
                    if showDatePicker {
                        DatePicker(
                            "Date",
                            selection: $pickDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .dayruleSheetRow(colors: colors)
                    }
                    whenRow("Backlog", selected: selected == .backlog) { apply(.ready) }
                    whenRow("Not now", selected: selected == .notNow) { apply(.later) }
                    whenRow("Inbox", selected: selected == .inbox) { apply(.inbox) }
                }
                Section {
                    HStack(spacing: Tokens.Space.s) {
                        TextField(
                            "Type a date",
                            text: $freeText,
                            prompt: Text("Tomorrow, next Monday, 15 Oct…")
                                .foregroundStyle(colors.textSecondary)
                        )
                        .dayruleBareField(colors: colors)
                        .submitLabel(.done)
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
                    DayruleSectionHeader(title: "Type a date")
                }
                SheetClearSection(title: "Clear", isVisible: !ids.isEmpty) { apply(.clear) }
            }
            .listStyle(.plain)
            .dayruleAnimation(Motion.quick, value: parseError)
            .onChange(of: freeText) { parseError = nil }
        }
        .onChange(of: showDatePicker) { _, open in
            // The calendar opens at full height.
            if open { detent = .large }
        }
    }

    private enum Selection: Equatable {
        case today, tomorrow, pickDate, backlog, notNow, inbox
    }

    private var trimmedText: String {
        freeText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if startDate == When.addLocalDays(today, 1) { return .tomorrow }
            if startDate > today { return .pickDate }
            return .today
        }
        if start == .ready { return .backlog }
        return nil
    }

    private func pickDateRow(selected: Bool, colors: DayruleColors) -> some View {
        Button {
            withAnimation(Motion.resolve(Motion.standard, reduceMotion: reduceMotion)) {
                showDatePicker.toggle()
            }
        } label: {
            HStack {
                Text("Pick a date")
                Spacer()
                if selected {
                    SelectionCheckmark()
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.textSecondary)
                    .rotationEffect(.degrees(showDatePicker ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tokens.rowMinHeight(dense: denseLayout))
        }
        .buttonStyle(.dayruleRow)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(showDatePicker ? "Calendar shown" : "")
        .dayruleSheetRow(colors: colors)
    }

    private func whenRow(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        return Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected {
                    SelectionCheckmark()
                }
            }
            .frame(minHeight: Tokens.rowMinHeight(dense: denseLayout))
        }
        .buttonStyle(.dayruleRow)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .dayruleSheetRow(colors: colors)
    }

    private func apply(_ when: Commands.When) {
        do {
            try model.store.run("When") { d, env in
                try Commands.setWhen(d, env, ids: ids, when: when)
            }
            model.noteEntitiesChanged()
            model.bumpHaptic(\.chip)
            model.undoNotice(undoMessage(for: when))
            dismiss()
        } catch {
            parseError = error.localizedDescription
            model.bumpHaptic(\.error)
        }
    }

    /// Undo bar copy for a When move (PLAN §6.7), in list vocabulary.
    private func undoMessage(for when: Commands.When) -> String {
        switch when {
        case .today: return "Moved to Today"
        case .date(let d):
            let today = When.toLocalDate(Date())
            if d == today { return "Moved to Today" }
            return "Scheduled for \(DayruleDateFormat.relative(d, today: today))"
        case .ready: return "Moved to Backlog"
        case .later: return "Moved to Not now"
        case .inbox: return "Moved to Inbox"
        case .clear: return "Cleared When"
        }
    }

    private func parseAndApply() {
        let text = trimmedText
        guard !text.isEmpty else { return }
        guard let result = When.parseWhen(text, today: Date()) else {
            parseError = "Couldn’t understand that date."
            return
        }
        apply(Commands.When(result))
    }
}
