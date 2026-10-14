import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct RecoveryPhraseView: View {
    let words: [String]
    var busy: Bool = false
    let onConfirmed: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var indexWidth: CGFloat = 28
    @State private var confirmed = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?
    @AccessibilityFocusState private var titleFocused: Bool

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        GateScaffold { _ in
            Text("Recovery phrase")
                .font(DayruleType.pageTitle)
                .tracking(DayruleType.titleTracking)
                .foregroundStyle(colors.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)

            Text("Write these 24 words down and keep them offline. If you forget your password and lose this phrase, nobody — including Dayrule — can recover your data.")
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                            .frame(width: indexWidth, alignment: .trailing)
                        Text(word)
                            .font(.body.monospaced())
                            .foregroundStyle(colors.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Word \(index + 1): \(word)")
                }
            }
            .padding(12)
            .background(colors.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))

            Button {
                copyPhrase()
            } label: {
                HStack(spacing: Tokens.Space.s) {
                    if copied {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                    Text(copied ? "Copied — clears in 60s" : "Copy phrase")
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(.dayruleLink)
            .dayruleAnimation(Motion.quick, value: copied)

            Toggle(isOn: $confirmed) {
                Text("I have saved this phrase somewhere safe")
                    .foregroundStyle(colors.text)
            }
            .accessibilityIdentifier("recovery.savedToggle")
            .disabled(busy)

            Button {
                onConfirmed()
            } label: {
                DayruleBusyLabel(title: "Continue", busyTitle: "Working…", busy: busy)
            }
            .buttonStyle(.dayrulePrimary)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("recovery.continue")
            .disabled(!confirmed || busy)
        }
        .background(colors.bg.ignoresSafeArea())
        .task {
            // Arrives via a screen transition; move VoiceOver to the title once it lands.
            try? await Task.sleep(for: .milliseconds(350))
            titleFocused = true
        }
        .onDisappear { copyResetTask?.cancel() }
    }

    private func copyPhrase() {
        copyRecoveryPhrase(words.joined(separator: " "))
        copied = true
        AccessibilityNotification.Announcement("Recovery phrase copied. The clipboard clears in 60 seconds.").post()
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    /// Local-only, short-lived on iOS; plain pasteboard write on macOS (cleared after 60s).
    private func copyRecoveryPhrase(_ joined: String) {
        #if os(iOS)
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: joined]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60),
            ]
        )
        #elseif os(macOS)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(joined, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if board.string(forType: .string) == joined {
                board.clearContents()
            }
        }
        #endif
    }
}
