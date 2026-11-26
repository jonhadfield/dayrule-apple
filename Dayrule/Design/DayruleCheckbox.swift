import SwiftUI

/// Round ink checkbox with pop + tick draw (PLAN §6.3–6.4).
///
/// Lays out in the shared leading slot (so titles never move) but takes a 44pt hit area.
struct DayruleCheckbox: View {
    var status: Status
    var label: String
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 20
    @State private var completeCount = 0
    @State private var filled: Bool
    @State private var tickProgress: CGFloat

    init(status: Status, label: String, action: @escaping () -> Void) {
        self.status = status
        self.label = label
        self.action = action
        _filled = State(initialValue: status == .completed)
        _tickProgress = State(initialValue: status == .completed ? 1 : 0)
    }

    private var slot: CGFloat { max(Tokens.rowLeadingSlot, diameter + 8) }
    private var hitInset: CGFloat { max(0, (Tokens.minHit - slot) / 2) }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        let reduceMotion = reduceMotion
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(filled ? colors.accent : Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            filled ? colors.accent : colors.checkboxBorder,
                            lineWidth: 1.5
                        )
                    )
                CheckmarkShape()
                    .trim(from: 0, to: tickProgress)
                    .stroke(
                        colors.bg,
                        style: StrokeStyle(
                            lineWidth: max(1.5, diameter * 0.1),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: diameter * 0.55, height: diameter * 0.55)
                if status == .canceled {
                    Image(systemName: "xmark")
                        .font(.system(size: diameter * 0.5, weight: .bold))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .frame(width: diameter, height: diameter)
            .keyframeAnimator(initialValue: 1.0, trigger: completeCount) { content, scale in
                content.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(Motion.pop.start)
                    CubicKeyframe(Motion.pop.peak, duration: Motion.pop.up)
                    CubicKeyframe(Motion.pop.end, duration: Motion.pop.settle)
                }
            }
            .frame(width: slot, height: slot)
            .frame(width: Tokens.minHit, height: Tokens.minHit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -hitInset)
        .padding(.vertical, -hitInset)
        .accessibilityLabel(label)
        .accessibilityValue(
            status == .completed ? "Completed" : status == .canceled ? "Canceled" : "Not completed"
        )
        #if os(iOS)
        .sensoryFeedback(.success, trigger: completeCount)
        #endif
        .onChange(of: status) { old, new in
            transition(from: old, to: new)
        }
    }

    private func transition(from old: Status, to new: Status) {
        guard new == .completed else {
            withAnimation(reduceMotion ? Motion.fade : .easeOut(duration: 0.12)) {
                filled = false
                tickProgress = 0
            }
            return
        }
        if old == .open {
            completeCount += 1
        }
        withAnimation(reduceMotion ? Motion.fade : Motion.quick) {
            filled = true
        }
        withAnimation(reduceMotion ? Motion.fade : Motion.tick.delay(Motion.tickDelay)) {
            tickProgress = 1
        }
    }
}

/// Tick drawn short-stroke first, so `trim` reads as a pen stroke.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.9))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return p
    }
}
