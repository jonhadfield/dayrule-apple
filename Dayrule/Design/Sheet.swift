import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Confirm button for a `DayruleSheet` toolbar.
struct SheetAction {
    var title: String
    var identifier: String?
    var isEnabled: Bool = true
    /// Voice Control spoken alternatives; defaults strip awkward phrasing.
    var inputLabels: [String]
    var action: () -> Void

    init(
        title: String,
        identifier: String? = nil,
        isEnabled: Bool = true,
        inputLabels: [String]? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.identifier = identifier
        self.isEnabled = isEnabled
        self.inputLabels = inputLabels ?? Self.defaultInputLabels(for: title)
        self.action = action
    }

    private static func defaultInputLabels(for title: String) -> [String] {
        switch title {
        case "Use this date":
            return ["Use this date", "Confirm date", "Done"]
        case "Save":
            return ["Save", "Done"]
        case "Done":
            return ["Done", "Close"]
        case "Remind me":
            return ["Remind me", "Reminder", "Save"]
        default:
            return [title]
        }
    }
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
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
                // Paper footer instead of the system white bottom toolbar strip.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    macSheetActionBar(colors: colors)
                }
                .background(MacSheetPaperChrome(fill: colors.bg))
                #endif
                #if os(iOS)
                .toolbar { toolbarContent }
                #endif
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
        #if os(macOS)
        // Escape — same path as Cancel (incl. dirty discard guard). Cancel also
        // uses `.keyboardShortcut(.cancelAction)`; this covers focus inside the
        // sheet body where the toolbar button may not be the target.
        .onExitCommand(perform: requestDismiss)
        #endif
        #if os(iOS)
        .modifier(SheetDetents(detents: detents, selection: detentSelection))
        .presentationDragIndicator(detents.count > 1 ? .visible : .automatic)
        #endif
    }

    private func requestDismiss() {
        if isDirty {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: dismissPlacement ?? .cancellationAction) {
            dismissButton
        }
        if let confirm {
            ToolbarItem(placement: .confirmationAction) {
                confirmButton(confirm)
            }
        }
    }
    #endif

    #if os(macOS)
    /// Cancel / Done on paper — avoids the system sheet’s white bottom toolbar.
    @ViewBuilder
    private func macSheetActionBar(colors: DayruleColors) -> some View {
        HStack(spacing: Tokens.Space.m) {
            if let confirm {
                // Cancel leading · confirm trailing (editors).
                dismissButton
                Spacer(minLength: 0)
                confirmButton(confirm)
            } else {
                // Done-only trailing (Settings, pickers).
                Spacer(minLength: 0)
                dismissButton
            }
        }
        .padding(.horizontal, Tokens.sheetInset)
        .padding(.vertical, Tokens.Space.m)
        .frame(maxWidth: .infinity)
        .background(colors.bg)
        .overlay(alignment: .top) {
            colors.hairline.frame(height: 1)
        }
    }
    #endif

    private var dismissButton: some View {
        Button(dismissTitle, action: requestDismiss)
            .keyboardShortcut(.cancelAction)
            .dayruleIdentifier(dismissIdentifier)
    }

    private func confirmButton(_ confirm: SheetAction) -> some View {
        Button(confirm.title, action: confirm.action)
            .fontWeight(.semibold)
            .disabled(!confirm.isEnabled)
            .keyboardShortcut(.defaultAction)
            .accessibilityInputLabels(confirm.inputLabels)
            .dayruleIdentifier(confirm.identifier)
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        Text(title)
            .font(DayruleType.sheetTitle)
            .foregroundStyle(colors.text)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tokens.sheetInset)
            .padding(.vertical, Tokens.Space.l)
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
    /// Hides system row + section separators so a `DayruleSectionHeader` hairline
    /// is the only rule (PLAN decision 53 / 71). Within-chapter rows breathe by
    /// spacing, not a second line.
    func dayruleSheetRow(colors: DayruleColors) -> some View {
        listRowBackground(colors.bg)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .foregroundStyle(colors.text)
    }

    /// Mac Forms default to the multi-column layout in wide sheets; paper
    /// Settings/pickers want a single column. Apply on `Form`, not on `List`
    /// (a List under `.formStyle(.grouped)` picks up inset “grouped” chrome).
    @ViewBuilder
    func dayruleMacFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }
}

/// Final "Clear …" section of an editor sheet.
struct SheetClearSection: View {
    let title: String
    var isVisible: Bool
    var identifier: String?
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if isVisible {
            Section {
                Button(title, role: .destructive, action: action)
                    .buttonStyle(.dayruleDestructive)
                    .dayruleIdentifier(identifier)
            }
            .listRowBackground(DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency).bg)
        }
    }
}

/// Trailing checkmark on the selected option row.
struct SelectionCheckmark: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency).accent)
            .accessibilityHidden(true)
    }
}

#if os(macOS)
/// Paints the Mac sheet window + bottom toolbar strip with paper (not system white).
struct MacSheetPaperChrome: NSViewRepresentable {
    var fill: Color

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(from: nsView) }
    }

    private func apply(from probe: NSView) {
        guard let window = probe.window else { return }
        let nsFill = NSColor(fill)
        if window.backgroundColor != nsFill {
            window.backgroundColor = nsFill
        }
        if let content = window.contentView {
            paintToolbarStrips(in: content, fill: nsFill)
        }
    }

    private func paintToolbarStrips(in root: NSView, fill: NSColor) {
        let name = String(describing: type(of: root))
        // Bottom toolbar host / material views AppKit inserts under sheet buttons.
        if name.contains("Toolbar") || name.contains("NSTitlebar") || name.contains("NSVisualEffect") {
            root.wantsLayer = true
            if root.layer?.backgroundColor != fill.cgColor {
                root.layer?.backgroundColor = fill.cgColor
            }
            if let effect = root as? NSVisualEffectView {
                effect.state = .followsWindowActiveState
                effect.material = .contentBackground
                effect.isEmphasized = false
            }
        }
        for child in root.subviews {
            paintToolbarStrips(in: child, fill: fill)
        }
    }
}
#endif
