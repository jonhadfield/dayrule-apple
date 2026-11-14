import SwiftUI

/// Sticky paper Add under the scrolling rows (decision 64 / 76).
/// Owns focus so parent lists don’t rebuild on every keystroke when paired
/// with an `@Observable` draft store (list Add) or a local `@State` binding.
struct PinnedPaperAddBar: View {
    @Binding var title: String
    var colors: DayruleColors
    var readingMargin: CGFloat
    var focusNonce: Int = 0
    var keepFocusAfterSubmit: Bool = true
    var fieldIdentifier: String = "list.addField"
    var buttonIdentifier: String = "list.addButton"
    var onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        PaperAddRow(
            title: $title,
            canAdd: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            keepFocusAfterSubmit: keepFocusAfterSubmit,
            ruled: false,
            focus: $focused,
            fieldIdentifier: fieldIdentifier,
            buttonIdentifier: buttonIdentifier
        ) {
            onSubmit()
        }
        // `RuledRow.listRowInsets` are no-ops outside a List — restore rowInset
        // so the disc lines up with checkboxes (decision 19 / 68).
        .padding(.horizontal, readingMargin + Tokens.rowInset)
        // Sidebar-tinted shelf — the list’s last hairline is the only rule above
        // Add (a second top hairline stacked as a double line; decision 64 / 71).
        .background(colors.sidebar)
        .accessibilityElement(children: .contain)
        .onChange(of: focusNonce) { _, _ in
            focused = true
        }
    }
}
