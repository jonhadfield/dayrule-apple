import SwiftUI
#if os(macOS)
import AppKit
#endif

extension ListName {
    /// SF Symbols aligned to web Lucide meanings (`web/src/ui/lists.ts`).
    var systemImage: String {
        switch self {
        // Lucide Mailbox — SF has no `mailbox`; `tray` is the inbox glyph.
        case .inbox: "tray"
        case .today: "sun.max"
        case .scheduled: "calendar"
        case .backlog: "checklist"
        case .notNow: "hourglass"
        case .done: "checkmark.circle"
        case .trash: "trash"
        }
    }

    /// Mirrors web `ui/lists.ts` list colours.
    func tint(_ c: DayruleColors) -> Color {
        switch self {
        case .today: c.today
        case .scheduled: c.scheduled
        case .backlog: c.ready
        case .done: c.done
        case .trash: c.textSecondary
        case .inbox: c.text
        case .notNow: c.later
        }
    }
}

extension SyncStatus {
    enum Tone {
        case ready, secondary, deadline
    }

    /// One- or two-word status for chrome; `label` stays the full sentence.
    var shortLabel: String {
        switch self {
        case .idle: "Not synced"
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .offline: "Offline"
        case .blocked: "Blocked"
        case .needsUpdate: "Update needed"
        }
    }

    var tone: Tone {
        switch self {
        case .synced: .ready
        case .idle, .syncing, .offline: .secondary
        case .blocked, .needsUpdate: .deadline
        }
    }
}

/// Dot + short label for sync state. The spinner only appears after 600ms of syncing,
/// so the routine poll doesn't flicker.
struct SyncStatusView: View {
    var status: SyncStatus
    var needsServerSignIn: Bool = false
    /// Dot only; the label stays available to VoiceOver.
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showSpinner = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        let chrome = HStack(spacing: Tokens.Space.s) {
            ZStack {
                if showSpinner, status == .syncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle()
                        .fill(toneColor(colors))
                        .frame(width: 8, height: 8)
                }
            }
            if !compact {
                Text(needsServerSignIn ? "On this device only" : status.shortLabel)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
            }
        }
        .dayruleAnimation(Motion.quick, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(needsServerSignIn ? "On this device only. \(status.label)" : status.label)
        .task(id: status) {
            showSpinner = false
            guard status == .syncing else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            showSpinner = true
        }
        // Compact Mac sidebar is colour-only. SwiftUI `.help` on a non-control in
        // a `safeAreaInset` often never shows — use a plain Button (hover target)
        // plus an AppKit `toolTip` backing view.
        if compact {
            let tip = needsServerSignIn ? "On this device only" : status.label
            Button {} label: {
                chrome
                    // Trailing-biased hit target so the dot lines up with badge column.
                    .frame(width: 28, height: 28, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tip)
            #if os(macOS)
            .background(MacTooltipHost(text: tip))
            #endif
            .accessibilityLabel(tip)
        } else {
            chrome
        }
    }

    private func toneColor(_ colors: DayruleColors) -> Color {
        switch status.tone {
        case .ready: colors.ready
        case .secondary: colors.textSecondary
        case .deadline: colors.deadline
        }
    }
}

#if os(macOS)
/// AppKit tooltip host — reliable where SwiftUI `.help` on decorative views fails.
private struct MacTooltipHost: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}
#endif
