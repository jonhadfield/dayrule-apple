import SwiftUI

/// Hides vault contents in the app switcher when the scene is inactive (PLAN §8.7).
/// Also used as the plain brand cover while a session is restored at launch; then
/// `showsProgress` adds a quiet spinner after a short delay, so a slow or offline
/// first sync doesn't look like a hang.
struct PrivacyCover: View {
    var showsProgress = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var progressVisible = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        ZStack {
            colors.bg.ignoresSafeArea()
            Text("Dayrule")
                .font(DayruleType.brand)
                .tracking(DayruleType.titleTracking)
                .foregroundStyle(colors.text)
                // Below the brand without moving it, so both covers match.
                .overlay(alignment: .bottom) {
                    if showsProgress {
                        ProgressView()
                            .tint(colors.textSecondary)
                            .opacity(progressVisible ? 1 : 0)
                            .alignmentGuide(.bottom) { d in d[.top] - Tokens.Space.l }
                            .accessibilityLabel("Opening")
                            .accessibilityHidden(!progressVisible)
                    }
                }
        }
        .task(id: showsProgress) {
            guard showsProgress else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.system(Motion.fade)) { progressVisible = true }
        }
    }
}
