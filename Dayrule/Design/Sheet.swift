import SwiftUI

/// Confirm button for a `DayruleSheet` toolbar.
struct SheetAction {
    var title: String
    var identifier: String?
    var isEnabled: Bool = true
    var action: () -> Void
}

/// macOS ideal sheet sizes; iOS uses detents instead.
enum SheetSize {
    case compact, standard, tall, reading

    static let minWidth: CGFloat = 400
    static let minHeight: CGFloat = 280

    var width: CGFloat {
        switch self {
        case .compact: 420
        case .standard: 460
        case .tall: 480
        case .reading: 560
        }
    }

    var height: CGFloat {
        switch self {
        case .compact: 280
        case .standard: 480
        case .tall: 620
        case .reading: 640
        }
    }
}

/// Paper sheet scaffold: one title treatment, Cancel/confirm placement and shortcuts,
/// paper background behind Form/List, Mac sizing and a discard guard when dirty.
struct DayruleSheet<Content: View>: View {
    var title: String
    var dismissTitle: String = "Cancel"
    /// `nil` = `.cancellationAction`. Escape dismisses whatever the placement.
    /// (Placements aren't Equatable.)
    var dismissPlacement: ToolbarItemPlacement? = nil
    var dismissIdentifier: String?
    var confirm: SheetAction? = nil
    var size: SheetSize = .standard
    var detents: Set<PresentationDetent> = [.large]
    /// Lets the caller move between `detents` (e.g. grow to .large for a calendar).
    var detentSelection: Binding<PresentationDetent>?
    var isDirty: Bool = false
    var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDiscard = false

    init(
        title: String,
        dismissTitle: String = "Cancel",
        dismissPlacement: ToolbarItemPlacement? = nil,
        dismissIdentifier: String? = nil,
        confirm: SheetAction? = nil,
        size: SheetSize = .standard,
        detents: Set<PresentationDetent> = [.large],
        detentSelection: Binding<PresentationDetent>? = nil,
        isDirty: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.dismissTitle = dismissTitle
        self.dismissPlacement = dismissPlacement
        self.dismissIdentifier = dismissIdentifier
        self.confirm = confirm
        self.size = size
        self.detents = detents
        self.detentSelection = detentSelection
        self.isDirty = isDirty
        self.content = content
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            content()
                .scrollContentBackground(.hidden)
                .background(colors.bg)
                #if os(iOS)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(colors.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                #elseif os(macOS)
                // The Fraunces header is the only title; a toolbar title would repeat it.
                .safeAreaInset(edge: .top, spacing: 0) {
                    DayruleSheetHeader(title: title)
                }
                .formStyle(.grouped)
                #endif
                .toolbar { toolbarContent }
                .confirmationDialog(
                    "Discard changes?",
                    isPresented: $confirmingDiscard,
                    titleVisibility: .visible
                ) {
                    Button("Discard Changes", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) {}
                }
        }
        .tint(colors.accent)
        #if os(macOS)
        .frame(
            minWidth: SheetSize.minWidth,
            idealWidth: size.width,
            minHeight: SheetSize.minHeight,
            idealHeight: size.height
        )
        #endif
        .interactiveDismissDisabled(isDirty)
        .presentationBackground(colors.bg)
        #if os(iOS)
        .modifier(SheetDetents(detents: detents, selection: detentSelection))
        .presentationDragIndicator(detents.count > 1 ? .visible : .automatic)
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: dismissPlacement ?? .cancellationAction) {
            dismissButton
        }
        if let confirm {
            ToolbarItem(placement: .confirmationAction) {
                Button(confirm.title, action: confirm.action)
                    .fontWeight(.semibold)
                    .disabled(!confirm.isEnabled)
                    .keyboardShortcut(.defaultAction)
                    .dayruleIdentifier(confirm.identifier)
            }
        }
    }

    private var dismissButton: some View {
        Button(dismissTitle) {
            if isDirty {
                confirmingDiscard = true
            } else {
                dismiss()
            }
        }
        .keyboardShortcut(.cancelAction)
        .dayruleIdentifier(dismissIdentifier)
    }
}

#if os(iOS)
/// One `presentationDetents` per sheet, with the caller's selection when it has one.
private struct SheetDetents: ViewModifier {
    let detents: Set<PresentationDetent>
    let selection: Binding<PresentationDetent>?

    func body(content: Content) -> some View {
        if let selection {
            content.presentationDetents(detents, selection: selection)
        } else {
            content.presentationDetents(detents)
        }
    }
}
#endif

/// Mac sheet title: Fraunces over a hairline (the window has no visible title).
struct DayruleSheetHeader: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        Text(title)
            .font(DayruleType.sheetTitle)
            .foregroundStyle(colors.text)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                colors.hairline.frame(height: 1)
            }
            .background(colors.bg)
    }
}

extension View {
    /// Applies an accessibility identifier only when one is given.
    @ViewBuilder
    func dayruleIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    /// Paper row inside a sheet Form/List; apply per row or on a Section.
    func dayruleSheetRow(colors: DayruleColors) -> some View {
        listRowBackground(colors.bg)
            .listRowSeparatorTint(colors.hairline)
            .foregroundStyle(colors.text)
    }
}

/// Final "Clear …" section of an editor sheet.
struct SheetClearSection: View {
    let title: String
    var isVisible: Bool
    var identifier: String?
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isVisible {
            Section {
                Button(title, role: .destructive, action: action)
                    .buttonStyle(.dayruleDestructive)
                    .dayruleIdentifier(identifier)
            }
            .listRowBackground(DayruleColors.resolve(colorScheme: colorScheme).bg)
        }
    }
}

/// Trailing checkmark on the selected option row.
struct SelectionCheckmark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(DayruleColors.resolve(colorScheme: colorScheme).accent)
            .accessibilityHidden(true)
    }
}
