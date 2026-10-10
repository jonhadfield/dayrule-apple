import SwiftUI

/// Round ink checkbox with pop + tick draw (PLAN §6.3–6.4).
struct DayruleCheckbox: View {
    var status: Status
    var label: String
    var onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 1
    @State private var showTick = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .fill(status == .completed ? colors.accent : Color.clear)
                    .overlay(
                        Circle().strokeBorder(borderColor(colors), lineWidth: 1.5)
                    )
                    .frame(width: 20, height: 20)
                    .scaleEffect(scale)

                if status == .completed, showTick {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(colors.bg)
                } else if status == .canceled {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(status == .completed ? .isSelected : [])
        .onChange(of: status) { _, new in
            animate(for: new)
        }
        .onAppear {
            showTick = status == .completed
            scale = 1
        }
    }

    private func borderColor(_ colors: DayruleColors) -> Color {
        switch status {
        case .completed: colors.accent
        case .canceled: colors.textSecondary
        case .open: colors.text.opacity(0.5)
        }
    }

    private func animate(for status: Status) {
        guard status == .completed else {
            showTick = false
            scale = 1
            return
        }
        if reduceMotion {
            scale = 1
            showTick = true
            return
        }
        scale = 0.8
        showTick = false
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1.12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.08)) {
                scale = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.22)) {
                showTick = true
            }
        }
    }
}
