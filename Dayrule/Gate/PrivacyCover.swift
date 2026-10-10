import SwiftUI

/// Hides vault contents in the app switcher when the scene is inactive (PLAN §8.7).
struct PrivacyCover: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        ZStack {
            colors.bg.ignoresSafeArea()
            Text("Dayrule")
                .font(DayruleFont.brand())
                .foregroundStyle(colors.text)
        }
    }
}
