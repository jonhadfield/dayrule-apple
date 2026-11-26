import SwiftUI

/// Bulk actions for the current selection (web `SelectionBar`, PLAN §6.5 / §7).
struct SelectionBarView: View {
    var count: Int
    var onCancel: () -> Void
    var onWhen: () -> Void
    var onDeadline: () -> Void
    var onMove: () -> Void
    var onComplete: () -> Void
    var onTrash: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        HStack(spacing: Tokens.Space.xs) {
            barButton("Cancel selection", systemImage: "xmark", colors: colors, action: onCancel)
            Text(count == 0 ? "Tap to-dos" : "\(count) selected")
                .font(DayruleType.meta)
                .foregroundStyle(colors.bg)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
            barButton("When", systemImage: "calendar", colors: colors, disabled: count == 0, action: onWhen)
            barButton("Deadline", systemImage: "flag", colors: colors, disabled: count == 0, action: onDeadline)
            barButton("Move", systemImage: "arrow.right.square", colors: colors, disabled: count == 0, action: onMove)
            barButton("Complete", systemImage: "checkmark.circle", colors: colors, disabled: count == 0, action: onComplete)
            barButton("Move to Trash", systemImage: "trash", colors: colors, disabled: count == 0, action: onTrash)
        }
        .padding(.horizontal, Tokens.Space.s)
        .padding(.vertical, Tokens.Space.xs)
        .background(colors.text, in: Capsule())
        #if os(macOS)
        .padding(.horizontal, Tokens.Space.s)
        #else
        .padding(.horizontal, Tokens.listChromeInset)
        #endif
        .padding(.vertical, Tokens.Space.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected to-dos")
        .accessibilityIdentifier("list.selectionBar")
    }

    private func barButton(
        _ label: String,
        systemImage: String,
        colors: DayruleColors,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(colors.bg.opacity(disabled ? 0.4 : 1))
                .frame(width: Tokens.minHit, height: Tokens.minHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityInputLabels(Self.inputLabels(for: label))
    }

    /// Spoken shortcuts for Voice Control (primary label can be long).
    private static func inputLabels(for label: String) -> [String] {
        switch label {
        case "Cancel selection":
            return ["Cancel", "Deselect", "Cancel selection"]
        case "When":
            return ["When", "Schedule"]
        case "Deadline":
            return ["Deadline", "Due date"]
        case "Move":
            return ["Move", "Move to"]
        case "Complete":
            return ["Complete", "Done"]
        case "Move to Trash":
            return ["Trash", "Delete", "Move to Trash"]
        default:
            return [label]
        }
    }
}
