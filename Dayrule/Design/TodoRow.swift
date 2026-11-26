import SwiftUI

/// Value-only display input for `DayruleTodoRow` (no AppModel / closures).
/// Equatable so list rows can use `.equatable()` and skip unchanged bodies.
struct TodoRowModel: Equatable {
    /// Trailing chip chrome (action lives on `DayruleTodoRow.onChip`).
    struct Chip: Equatable {
        var label: String
        var systemImage: String
        var isOverdue: Bool
    }

    var id: ID
    var title: String
    /// `nil` for rows that are not to-dos (no checkbox, leading slot kept empty).
    var status: Status?
    var subtitle: String?
    var subtitleIsOverdue: Bool = false
    var hasReminder: Bool = false
    var repeats: Bool = false
    var hasNotes: Bool = false
    /// Labeled tuple is not `Equatable`-synthesizable; compare manually below.
    var checklist: (done: Int, total: Int)?
    var chip: Chip?
    /// VoiceOver hint for tapping the row; `nil` when tapping does nothing (Trash),
    /// which also drops the button trait and default action.
    var openHint: String? = "Opens to-do"

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.status == rhs.status
            && lhs.subtitle == rhs.subtitle
            && lhs.subtitleIsOverdue == rhs.subtitleIsOverdue
            && lhs.hasReminder == rhs.hasReminder
            && lhs.repeats == rhs.repeats
            && lhs.hasNotes == rhs.hasNotes
            && lhs.checklist?.done == rhs.checklist?.done
            && lhs.checklist?.total == rhs.checklist?.total
            && lhs.chip == rhs.chip
            && lhs.openHint == rhs.openHint
    }
}

/// Named VoiceOver action on a row (Move to Today, Trash, …).
struct RowAction {
    var name: String
    /// Shorter / alternate phrases for Voice Control (`accessibilityInputLabels`).
    var inputLabels: [String]
    var action: () -> Void

    init(name: String, inputLabels: [String]? = nil, action: @escaping () -> Void) {
        self.name = name
        self.inputLabels = inputLabels ?? Self.defaultInputLabels(for: name)
        self.action = action
    }

    /// Strip ellipsis and add common spoken shortcuts for sheet-opening actions.
    private static func defaultInputLabels(for name: String) -> [String] {
        let stripped = name
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
        var labels = [stripped]
        switch stripped {
        case "When":
            labels.append("Schedule")
        case "Deadline":
            labels.append("Due date")
        case "Tags":
            labels.append("Tag")
        case "Move":
            labels.append(contentsOf: ["Move to", "Move to list"])
        case "Repeat":
            labels.append("Repeating")
        case "Reminder":
            labels.append(contentsOf: ["Remind me", "Remind"])
        case "Trash", "Move to Trash":
            labels.append(contentsOf: ["Trash", "Delete"])
        case "Move up":
            labels.append("Up")
        case "Move down":
            labels.append("Down")
        case "Select":
            labels.append(contentsOf: ["Select to-do", "Multi-select"])
        case "Restore":
            labels.append("Undelete")
        default:
            break
        }
        var seen = Set<String>()
        return labels.filter { seen.insert($0).inserted }
    }
}

/// Shared to-do row for list and project screens.
///
/// `Equatable` ignores closures and compares display + selection-mode inputs so
/// `.equatable()` can skip re-renders when a parent list rebuilds unchanged rows.
/// Callers that close over multi-select must pass `selecting` so toggle/open
/// closures refresh when selection mode flips.
struct DayruleTodoRow: View {
    var model: TodoRowModel
    var identifier: String
    var onToggle: () -> Void
    var onOpen: () -> Void
    /// Chip tap; kept off `TodoRowModel` so the model stays value-Equatable.
    var onChip: (() -> Void)? = nil
    /// Multi-select highlight (PLAN §6.5 selection mode).
    var isSelected: Bool = false
    /// Closed over by list `onToggle` / `onOpen`; participates in `==`.
    var selecting: Bool = false
    var accessibilityActions: [RowAction] = []
    /// Parent-owned VoiceOver focus; restore target after sheet dismiss.
    var a11yFocus: AccessibilityFocusState<DayruleA11yFocus?>.Binding? = nil
    /// Current focus value — participates in `==` so `.equatable()` refreshes
    /// when VoiceOver focus returns to this row.
    var a11yFocusValue: DayruleA11yFocus? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var checkboxDiameter: CGFloat = 20
    /// Distance from the checkbox centre down to the first line's baseline.
    @ScaledMetric(relativeTo: .body) private var baselineDrop: CGFloat = 5

    private var leadingSlot: CGFloat { max(Tokens.rowLeadingSlot, checkboxDiameter + 8) }
    private var isClosed: Bool { model.status.map { $0 != .open } ?? false }
    private var todoFocus: DayruleA11yFocus { .todo(model.id) }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        let baselineDrop = baselineDrop
        RuledRow {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.rowGlyphSpacing) {
                leading
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[VerticalAlignment.center] + baselineDrop
                    }
                VStack(alignment: .leading, spacing: 2) {
                    titleText(colors)
                    if let subtitle = model.subtitle {
                        subtitleText(subtitle, colors: colors)
                    }
                    if let checklist = model.checklist {
                        Text("\(checklist.done) of \(checklist.total)")
                            .font(DayruleType.meta)
                            .monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                            .contentTransition(.numericText(value: Double(checklist.done)))
                    }
                    if dynamicTypeSize.isAccessibilitySize, let chip = model.chip {
                        chipButton(chip, colors: colors)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                if !dynamicTypeSize.isAccessibilitySize, let chip = model.chip {
                    chipButton(chip, colors: colors)
                }
            }
        }
        // Must keep the paper hairline — a plain fill here wiped RuledRow’s
        // background and left only AppKit’s double grid on Mac (decision 74).
        .listRowBackground(
            DayrulePaperRowBackground(
                fill: isSelected ? colors.selectedRow : colors.bg,
                hairline: colors.hairline,
                showsHairline: true
            )
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OpenAccessibility(hint: model.openHint, onOpen: onOpen))
        .accessibilityActions {
            if let status = model.status {
                let completeName = status == .open
                    ? "Complete \(model.title)"
                    : "Reopen \(model.title)"
                let shortVerb = status == .open ? "Complete" : "Reopen"
                Button(completeName, action: onToggle)
                    .accessibilityInputLabels([shortVerb, completeName, model.title])
            }
            ForEach(accessibilityActions.indices, id: \.self) { i in
                let rowAction = accessibilityActions[i]
                Button(rowAction.name, action: rowAction.action)
                    .accessibilityInputLabels(rowAction.inputLabels)
            }
        }
        // Voice Control: speak the title without Reminder / Repeats / notes fluff.
        .accessibilityInputLabels([model.title])
        .accessibilityIdentifier(identifier)
        .modifier(TodoA11yFocusModifier(binding: a11yFocus, equals: todoFocus))
    }

    @ViewBuilder
    private var leading: some View {
        if let status = model.status {
            DayruleCheckbox(
                status: status,
                label: status == .open ? "Complete \(model.title)" : "Reopen \(model.title)",
                action: onToggle
            )
        } else {
            Color.clear.frame(width: leadingSlot, height: leadingSlot)
        }
    }

    private func titleText(_ colors: DayruleColors) -> some View {
        var glyphs: [String] = []
        if model.hasReminder, model.status == .open { glyphs.append("bell") }
        if model.repeats { glyphs.append("repeat") }
        if model.hasNotes { glyphs.append("note.text") }
        var text = Text(model.title).strikethrough(isClosed)
        for glyph in glyphs {
            text = Text("\(text) \(Text(Image(systemName: glyph)).foregroundStyle(colors.textSecondary))")
        }
        return text
            .dayruleRowTitle()
            .foregroundStyle(colors.text)
            .imageScale(.small)
            .lineLimit(3)
    }

    @ViewBuilder
    private func subtitleText(_ subtitle: String, colors: DayruleColors) -> some View {
        if model.subtitleIsOverdue {
            Text("\(Image(systemName: "exclamationmark.circle.fill")) \(subtitle)")
                .font(DayruleType.meta)
                .foregroundStyle(colors.deadline)
        } else {
            Text(subtitle)
                .font(DayruleType.meta)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func chipButton(_ chip: TodoRowModel.Chip, colors: DayruleColors) -> some View {
        // Keep a 44pt hit target without growing dense 36pt rows (same negative
        // inset pattern as DayruleCheckbox / PaperAddRow).
        let chipHitInset = max(0, (Tokens.minHit - 28) / 2)
        return Button(action: { onChip?() }) {
            // Explicit icon + text: a `Label` in a row button can collapse to its icon.
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: chip.systemImage)
                    .imageScale(.small)
                Text(chip.label)
            }
            .font(DayruleType.meta)
            .foregroundStyle(chip.isOverdue ? colors.deadline : colors.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, Tokens.Space.xs)
            .padding(.horizontal, Tokens.Space.s)
            .frame(minHeight: Tokens.minHit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -chipHitInset)
        .layoutPriority(1)
    }

    private var accessibilityLabel: String {
        var parts = [model.title]
        if model.hasReminder, model.status == .open { parts.append("Reminder") }
        if model.repeats { parts.append("Repeats") }
        if model.hasNotes { parts.append("Has notes") }
        if let subtitle = model.subtitle {
            parts.append(model.subtitleIsOverdue ? "Overdue, \(subtitle)" : subtitle)
        }
        if let checklist = model.checklist {
            parts.append("\(checklist.done) of \(checklist.total) checklist items")
        }
        if let chip = model.chip {
            // Label already carries “overdue” / “late” / “Today” — don’t prefix.
            parts.append(chip.label)
        }
        return parts.joined(separator: ", ")
    }
}

extension DayruleTodoRow: Equatable {
    /// `nonisolated` so Swift 6 allows `Equatable` on a `@MainActor` `View`.
    /// Skip `accessibilityActions` — its closures are MainActor-isolated and action
    /// *names* almost never change without a model / selection update.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model == rhs.model
            && lhs.identifier == rhs.identifier
            && lhs.isSelected == rhs.isSelected
            && lhs.selecting == rhs.selecting
            && lhs.a11yFocusValue == rhs.a11yFocusValue
    }
}

/// Button trait, hint and default action for a row that opens something.
private struct OpenAccessibility: ViewModifier {
    var hint: String?
    var onOpen: () -> Void

    func body(content: Content) -> some View {
        if let hint {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(hint)
                .accessibilityAction(.default, onOpen)
        } else {
            content
        }
    }
}

private struct TodoA11yFocusModifier: ViewModifier {
    var binding: AccessibilityFocusState<DayruleA11yFocus?>.Binding?
    var equals: DayruleA11yFocus

    func body(content: Content) -> some View {
        if let binding {
            content.accessibilityFocused(binding, equals: equals)
        } else {
            content
        }
    }
}
