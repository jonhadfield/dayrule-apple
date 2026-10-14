import SwiftUI

/// Value-only input for `DayruleTodoRow` (no AppModel dependency).
struct TodoRowModel {
    /// Trailing chip, e.g. a deadline or When date that opens its sheet.
    struct Chip {
        var label: String
        var systemImage: String
        var isOverdue: Bool
        var action: () -> Void
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
    var checklist: (done: Int, total: Int)?
    var chip: Chip?
    /// VoiceOver hint for tapping the row; `nil` when tapping does nothing (Trash),
    /// which also drops the button trait and default action.
    var openHint: String? = "Opens to-do"
}

/// Named VoiceOver action on a row (Move to Today, Trash, …).
struct RowAction {
    var name: String
    var action: () -> Void
}

/// Shared to-do row for list and project screens.
struct DayruleTodoRow: View {
    var model: TodoRowModel
    var identifier: String
    var onToggle: () -> Void
    var onOpen: () -> Void
    var accessibilityActions: [RowAction] = []

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var checkboxDiameter: CGFloat = 20
    /// Distance from the checkbox centre down to the first line's baseline.
    @ScaledMetric(relativeTo: .body) private var baselineDrop: CGFloat = 5

    private var leadingSlot: CGFloat { max(Tokens.rowLeadingSlot, checkboxDiameter + 8) }
    private var isClosed: Bool { model.status.map { $0 != .open } ?? false }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OpenAccessibility(hint: model.openHint, onOpen: onOpen))
        .accessibilityActions {
            if let status = model.status {
                Button(status == .open ? "Complete \(model.title)" : "Reopen \(model.title)", action: onToggle)
            }
            ForEach(accessibilityActions.indices, id: \.self) { i in
                Button(accessibilityActions[i].name, action: accessibilityActions[i].action)
            }
        }
        .accessibilityIdentifier(identifier)
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
            .font(DayruleType.rowTitle)
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
        Button(action: chip.action) {
            // Explicit icon + text: a `Label` in a row button can collapse to its icon.
            HStack(spacing: 4) {
                Image(systemName: chip.systemImage)
                    .imageScale(.small)
                Text(chip.label)
            }
            .font(DayruleType.meta)
            .foregroundStyle(chip.isOverdue ? colors.deadline : colors.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(minHeight: Tokens.minHit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            parts.append(chip.isOverdue ? "Overdue, \(chip.label)" : chip.label)
        }
        return parts.joined(separator: ", ")
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
