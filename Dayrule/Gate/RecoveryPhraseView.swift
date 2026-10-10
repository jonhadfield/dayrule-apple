import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct RecoveryPhraseView: View {
    let words: [String]
    let onConfirmed: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmed = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Recovery phrase")
                    .font(DayruleFont.listTitle())
                    .foregroundStyle(colors.text)

                Text("Write these 24 words down and keep them offline. If you forget your password and lose this phrase, nobody — including Dayrule — can recover your data.")
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).")
                                .foregroundStyle(colors.textSecondary)
                                .frame(width: 28, alignment: .trailing)
                            Text(word)
                                .font(.body.monospaced())
                                .foregroundStyle(colors.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(12)
                .background(colors.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))

                Button("Copy phrase") {
                    copyRecoveryPhrase(words.joined(separator: " "))
                }
                .foregroundStyle(colors.accent)

                Toggle("I have saved this phrase somewhere safe", isOn: $confirmed)
                    .foregroundStyle(colors.text)

                Button {
                    onConfirmed()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(colors.bg)
                        .background(confirmed ? colors.accent : colors.hairline)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
                }
                .disabled(!confirmed)
            }
            .padding(24)
        }
        .background(colors.bg.ignoresSafeArea())
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
