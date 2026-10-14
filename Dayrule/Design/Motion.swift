import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Motion tokens (PLAN §6.4). Reduce Motion swaps every animation for `fade`.
enum Motion {
    static let quick: Animation = .easeOut(duration: 0.15)
    static let fade: Animation = .easeInOut(duration: 0.15)
    static let fadeDuration: Duration = .milliseconds(150)
    /// Sheets, banners and disclosures.
    static let standard: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
    static let list: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)
    static let screen: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)

    /// Checkbox pop: scale start → peak over `up`, then → end over `settle` (seconds).
    static let pop = (start: 0.8, peak: 1.12, end: 1.0, up: 0.12, settle: 0.08)

    static let tick: Animation = .easeOut(duration: 0.22)
    static let tickDelay: Double = 0.06
    static let fold: Animation = .easeIn(duration: 0.26)
    /// How long a completed row stays in place before folding away.
    static let linger: Duration = .seconds(1)

    static func resolve(_ a: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : a
    }

    /// The system Reduce Motion setting, for non-View code with no environment to read.
    @MainActor
    static var reduceMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }

    /// For non-View code (AppModel, stores) that has no environment to read.
    @MainActor
    static func system(_ a: Animation) -> Animation {
        resolve(a, reduceMotion: reduceMotion)
    }
}

private struct DayruleAnimationModifier<Value: Equatable>: ViewModifier {
    var animation: Animation
    var value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that honours Reduce Motion.
    func dayruleAnimation(_ a: Animation, value: some Equatable) -> some View {
        modifier(DayruleAnimationModifier(animation: a, value: value))
    }
}

extension AnyTransition {
    static var dayruleRowLeave: AnyTransition { .opacity.combined(with: .move(edge: .top)) }
    static var dayruleBanner: AnyTransition { .move(edge: .top).combined(with: .opacity) }
    static var dayruleNotice: AnyTransition { .move(edge: .bottom).combined(with: .opacity) }
    static var dayruleInlineError: AnyTransition { .opacity.combined(with: .move(edge: .top)) }
    static var dayruleScreen: AnyTransition { .opacity }
}
