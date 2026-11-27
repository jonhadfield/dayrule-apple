import SwiftUI

/// Hides vault contents in the app switcher when the scene is inactive (PLAN §8.7).
/// Also used as the plain brand cover while a session is restored at launch; then
/// `showsProgress` adds a quiet spinner after a short delay, so a slow or offline
/// first sync doesn't look like a hang.
struct PrivacyCover: View {
    var showsProgress = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var progressVisible = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        ZStack {
            colors.bg.ignoresSafeArea()
            // Full-width centred column — the old overlay + alignmentGuide put the
            // spinner on the wordmark and let Fraunces look shifted.
            VStack(spacing: Tokens.Space.l) {
                Text("Dayrule")
                    .font(DayruleType.brand)
                    .tracking(DayruleType.titleTracking)
                    .foregroundStyle(colors.text)
                    .multilineTextAlignment(.center)
                if showsProgress {
                    // Reserved even while invisible so the brand doesn’t jump
                    // when the spinner fades in after the delay.
                    ProgressView()
                        .tint(colors.textSecondary)
                        .opacity(progressVisible ? 1 : 0)
                        .accessibilityLabel("Opening")
                        .accessibilityHidden(!progressVisible)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: showsProgress) {
            guard showsProgress else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.system(Motion.fade)) { progressVisible = true }
        }
    }
}
