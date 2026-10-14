import SwiftUI

/// Paper text field: plain style inside a cream card, 1pt boundary at ≥3:1, accent when focused.
/// Works for TextField and SecureField; callers pass
/// `prompt: Text(label).foregroundStyle(colors.textSecondary)`.
private struct DayruleFieldModifier: ViewModifier {
    var isFocused: Bool
    var colors: DayruleColors
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
        content
            .textFieldStyle(.plain)
            .foregroundStyle(colors.text)
            .padding(14)
            .background(colors.sidebar, in: shape)
            .overlay {
                shape.strokeBorder(
                    isFocused ? colors.accent : colors.fieldBorder,
                    lineWidth: 1
                )
            }
            .animation(Motion.quick, value: isFocused)
            #if os(macOS)
            .focusEffectDisabled()
            #endif
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension View {
    func dayruleField(isFocused: Bool, colors: DayruleColors) -> some View {
        modifier(DayruleFieldModifier(isFocused: isFocused, colors: colors))
    }

    /// Unboxed field for rows that already draw their own paper (PaperAddRow, sheet rows).
    /// The prompt is the visible label: Mac grouped forms would otherwise put the title
    /// on the left and push the field to the right. The title stays the accessibility label.
    func dayruleBareField(colors: DayruleColors) -> some View {
        textFieldStyle(.plain).foregroundStyle(colors.text).labelsHidden()
    }

    /// Keeps the paper showing through a focused field inside a Mac List row.
    /// No-op elsewhere.
    func dayruleClearFieldEditor(isFocused: Bool) -> some View {
        #if os(macOS)
        modifier(ClearFieldEditorModifier(isFocused: isFocused))
        #else
        self
        #endif
    }
}

#if os(macOS)
/// In a List row, AppKit's shared field editor paints an opaque text background
/// over the paper while editing. Clear it each time the field takes focus.
private struct ClearFieldEditorModifier: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content.onChange(of: isFocused, initial: true) { _, focused in
            guard focused else { return }
            // The field editor becomes first responder after the focus change lands.
            Task { @MainActor in
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
                    editor.drawsBackground = false
                }
            }
        }
    }
}
#endif
