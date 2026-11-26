import SwiftUI

/// List count. Overdue is shown as a glyph + number, never by colour alone.
struct DayruleCountBadge: View {
    enum Style {
        /// Phone Browse: hairline ring that grows into a capsule (PLAN §6.5 circular counts).
        case ring
        /// Sidebar: bare monospaced number.
        case plain
    }

    var count: Int
    var overdue: Int = 0
    var style: Style = .ring

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = Tokens.badgeSize

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        HStack(spacing: Tokens.Space.xs) {
            if overdue > 0 {
                Text("\(Image(systemName: "exclamationmark.circle.fill")) \(overdue)")
                    .font(DayruleType.count)
                    .imageScale(.small)
                    .foregroundStyle(colors.deadline)
                    .contentTransition(.numericText(value: Double(overdue)))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colors.deadlineTint, in: Capsule())
                    .transition(.opacity)
            }
            countText(colors)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .dayruleAnimation(Motion.quick, value: overdue)
        .dayruleAnimation(Motion.quick, value: count)
    }

    @ViewBuilder
    private func countText(_ colors: DayruleColors) -> some View {
        switch style {
        case .ring:
            Text(count, format: .number)
                .font(DayruleType.count)
                .foregroundStyle(colors.text)
                .contentTransition(.numericText(value: Double(count)))
                .padding(.horizontal, 6)
                .frame(minWidth: badge, minHeight: badge)
                .overlay(Capsule().stroke(colors.hairline))
        case .plain:
            Text(count, format: .number)
                .font(DayruleType.count)
                .foregroundStyle(colors.textSecondary)
                .contentTransition(.numericText(value: Double(count)))
        }
    }

    private var accessibilityLabel: String {
        overdue > 0 ? "\(count) items, \(overdue) overdue" : "\(count) items"
    }
}
