import SwiftUI

extension ListName {
    /// Stable SF Symbol per list (Browse rows, sidebar).
    var systemImage: String {
        switch self {
        case .backlog: "sparkle"
        case .done: "checkmark.circle"
        case .trash: "trash"
        default: "list.bullet"
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
    @State private var showSpinner = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
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
        // Compact Mac sidebar is colour-only; hover matches Lock/Find/Settings chrome.
        if compact {
            chrome.help(needsServerSignIn ? "On this device only" : status.shortLabel)
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
