import SwiftUI

// Paper button styles. None draws a system bezel on macOS, and each owns its disabled
// look (a caller-side `foregroundStyle` would hide the disabled state).

struct DayrulePrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .headline) private var vPad: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous)
        configuration.label
            .font(DayruleType.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, vPad)
            .padding(.horizontal, Tokens.Space.l)
            .foregroundStyle(isEnabled ? colors.bg : colors.textSecondary)
            .background(isEnabled ? colors.accent : colors.sidebar, in: shape)
            .overlay {
                if !isEnabled {
                    shape.strokeBorder(colors.hairline, lineWidth: 1)
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

struct DayruleSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .headline) private var vPad: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous)
        configuration.label
            .font(DayruleType.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, vPad)
            .padding(.horizontal, Tokens.Space.l)
            .foregroundStyle(isEnabled ? colors.accent : colors.textSecondary)
            .background(colors.sidebar, in: shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// A button in a multi-step form: filled while it is the current step, quiet otherwise,
/// so emphasis moves down the form as each step completes.
struct DayruleStepButtonStyle: ButtonStyle {
    var isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if isCurrent {
                DayrulePrimaryButtonStyle().makeBody(configuration: configuration)
            } else {
                DayruleSecondaryButtonStyle().makeBody(configuration: configuration)
            }
        }
        .animation(Motion.quick, value: isCurrent)
    }
}

struct DayruleLinkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dayruleDenseLayout) private var denseLayout

    func makeBody(configuration: Configuration) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        configuration.label
            .font(DayruleType.link(dense: denseLayout))
            .foregroundStyle(isEnabled ? colors.accent : colors.textSecondary)
            .frame(minHeight: Tokens.minHit)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Destructive text button in the deadline ink. Callers keep `role: .destructive`.
struct DayruleDestructiveButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dayruleDenseLayout) private var denseLayout

    func makeBody(configuration: Configuration) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        configuration.label
            .font(DayruleType.link(dense: denseLayout))
            .foregroundStyle(isEnabled ? colors.deadline : colors.textSecondary)
            .frame(minHeight: Tokens.minHit)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Full-width tappable row; only the background reacts to a press, never the label tint.
struct DayruleRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? colors.pressed : Color.clear)
    }
}

extension ButtonStyle where Self == DayrulePrimaryButtonStyle {
    static var dayrulePrimary: DayrulePrimaryButtonStyle { DayrulePrimaryButtonStyle() }
}

extension ButtonStyle where Self == DayruleSecondaryButtonStyle {
    static var dayruleSecondary: DayruleSecondaryButtonStyle { DayruleSecondaryButtonStyle() }
}

extension ButtonStyle where Self == DayruleStepButtonStyle {
    static func dayruleStep(isCurrent: Bool) -> DayruleStepButtonStyle { DayruleStepButtonStyle(isCurrent: isCurrent) }
}

extension ButtonStyle where Self == DayruleLinkButtonStyle {
    static var dayruleLink: DayruleLinkButtonStyle { DayruleLinkButtonStyle() }
}

extension ButtonStyle where Self == DayruleDestructiveButtonStyle {
    static var dayruleDestructive: DayruleDestructiveButtonStyle { DayruleDestructiveButtonStyle() }
}

extension ButtonStyle where Self == DayruleRowButtonStyle {
    static var dayruleRow: DayruleRowButtonStyle { DayruleRowButtonStyle() }
}

/// Button label that swaps to a spinner + busy title without changing height
/// (the button style supplies the padding).
struct DayruleBusyLabel: View {
    var title: String
    var busyTitle: String
    var busy: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            if busy {
                // Inherits the style's foreground, so the spinner matches the label ink.
                ProgressView()
                    .controlSize(.small)
                    .tint(HierarchicalShapeStyle.primary)
            }
            Text(busy ? busyTitle : title)
                .contentTransition(.opacity)
        }
        .dayruleAnimation(Motion.quick, value: busy)
    }
}
