import SwiftUI

/// Paper Add: leading terracotta + (focus or submit) + title field. The disc sits in the
/// same leading slot as the checkbox, so "Add" lines up with to-do titles.
struct PaperAddRow: View {
    @Binding var title: String
    var canAdd: Bool
    var keepFocusAfterSubmit: Bool = true
    /// Pinned Add sits on a tinted shelf — no second rule under the field (decision 71).
    var ruled: Bool = true
    var focus: FocusState<Bool>.Binding?
    var fieldIdentifier: String = "list.addField"
    var buttonIdentifier: String = "list.addButton"
    var onSubmit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var checkboxDiameter: CGFloat = 20
    @FocusState private var ownFocus: Bool

    init(
        title: Binding<String>,
        canAdd: Bool,
        keepFocusAfterSubmit: Bool = true,
        ruled: Bool = true,
        focus: FocusState<Bool>.Binding? = nil,
        fieldIdentifier: String = "list.addField",
        buttonIdentifier: String = "list.addButton",
        onSubmit: @escaping () -> Void
    ) {
        _title = title
        self.canAdd = canAdd
        self.keepFocusAfterSubmit = keepFocusAfterSubmit
        self.ruled = ruled
        self.focus = focus
        self.fieldIdentifier = fieldIdentifier
        self.buttonIdentifier = buttonIdentifier
        self.onSubmit = onSubmit
    }

    private var focusBinding: FocusState<Bool>.Binding { focus ?? $ownFocus }
    private var disc: CGFloat { checkboxDiameter + 4 }
    private var slot: CGFloat { max(Tokens.rowLeadingSlot, checkboxDiameter + 8) }
    private var hitInset: CGFloat { max(0, (Tokens.minHit - slot) / 2) }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        RuledRow(style: ruled ? .ruled : .note) {
            HStack(spacing: Tokens.rowGlyphSpacing) {
                Button {
                    if canAdd {
                        onSubmit()
                    } else {
                        focusBinding.wrappedValue = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: disc * 0.55, weight: .semibold))
                        .foregroundStyle(colors.bg)
                        .frame(width: disc, height: disc)
                        .background(colors.accent, in: Circle())
                        .opacity(canAdd ? 1 : 0.55)
                        .animation(Motion.quick, value: canAdd)
                        .frame(width: slot, height: slot)
                        .frame(width: Tokens.minHit, height: Tokens.minHit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AddDiscButtonStyle())
                .padding(.horizontal, -hitInset)
                .padding(.vertical, -hitInset)
                .accessibilityIdentifier(buttonIdentifier)
                .accessibilityLabel(canAdd ? "Add to-do" : "New to-do")
                .accessibilityInputLabels(
                    canAdd
                        ? ["Add", "Add to-do", "New to-do"]
                        : ["New to-do", "Add", "Add to-do"]
                )

                TextField("", text: $title, prompt: Text("Add").foregroundStyle(colors.textSecondary))
                    .dayruleBareField(colors: colors)
                    .focused(focusBinding)
                    .dayruleClearFieldEditor(isFocused: focusBinding.wrappedValue)
                    // Mac AppKit field editor sits a couple of points past a plain
                    // `Text` in the same HStack — nudge so "Add" shares the to-do
                    // title column (Impeccable layout optical pass).
                    #if os(macOS)
                    .padding(.leading, -2)
                    #endif
                    .submitLabel(.done)
                    .accessibilityLabel("New to-do")
                    .accessibilityInputLabels(["New to-do", "Add", "Title"])
                    .accessibilityIdentifier(fieldIdentifier)
                    .onSubmit(submitFromField)
            }
        }
        #if os(iOS)
        // Phone hides the tab bar while the keyboard is up (§6.5); Done is how
        // you leave Add and get the tabs back. Scroll-to-dismiss also works.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusBinding.wrappedValue = false
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("list.addDone")
            }
        }
        #endif
    }

    private func submitFromField() {
        // Empty Done/Return ends adding and dismisses the keyboard (tabs return).
        guard canAdd else {
            focusBinding.wrappedValue = false
            return
        }
        onSubmit()
        guard keepFocusAfterSubmit else {
            focusBinding.wrappedValue = false
            return
        }
        let binding = focusBinding
        // Land on the next runloop, after the field resigns on Return.
        Task { @MainActor in
            binding.wrappedValue = true
        }
    }
}

/// Press feedback for the Add disc: a slight shrink, no tint change.
private struct AddDiscButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
