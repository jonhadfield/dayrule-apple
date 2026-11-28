#if os(macOS)
import AppKit
import SwiftUI

/// Clears NSTableView grid lines and the system selection wash under a SwiftUI `List`.
///
/// On macOS, `.listRowSeparator(.hidden)` is only a preference — AppKit still
/// draws horizontal rules that stack under our paper hairline as a double line
/// (decision 74). Sidebar `List(selection:)` also paints the **system** accent
/// selection (often purple from System Settings), which fights our terracotta
/// `selectedRow` + leading accent bar — so selection highlight is cleared too.
///
/// When `scrollFill` is set (plain / detail lists), install paper-tinted
/// `NSScroller`s. Sidebar `.listStyle(.sidebar)` already composites a warm
/// taupe knob against the rail; plain lists get cool system grey instead —
/// AppKit will not warm them from `backgroundColor` alone.
struct MacListHideSystemSeparators: NSViewRepresentable {
    /// `nil` = separator/selection strip only (sidebar). Non-nil = also
    /// replace plain-list scrollers with warm paper knobs.
    var scrollFill: Color? = nil

    func makeNSView(context: Context) -> NSView {
        let view = Inspector()
        view.scrollFill = scrollFill.map(NSColor.init)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let inspector = nsView as? Inspector else { return }
        inspector.scrollFill = scrollFill.map(NSColor.init)
        inspector.stripSoon()
    }

    private final class Inspector: NSView {
        var scrollFill: NSColor?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stripSoon()
        }

        override func layout() {
            super.layout()
            stripSoon()
        }

        func stripSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.stripAncestors()
            }
        }

        private func stripAncestors() {
            var view: NSView? = self
            while let current = view {
                if let table = current as? NSTableView {
                    apply(to: table)
                    return
                }
                view = current.superview
            }
            guard let root = window?.contentView else { return }
            stripDescendants(of: root)
        }

        private func stripDescendants(of root: NSView) {
            if let table = root as? NSTableView {
                apply(to: table)
            }
            for child in root.subviews {
                stripDescendants(of: child)
            }
        }

        private func apply(to table: NSTableView) {
            if table.gridStyleMask != [] {
                table.gridStyleMask = []
            }
            if table.intercellSpacing.height != 0 {
                table.intercellSpacing = NSSize(width: table.intercellSpacing.width, height: 0)
            }
            if table.selectionHighlightStyle != .none {
                table.selectionHighlightStyle = .none
            }
            guard let fill = scrollFill, let scroll = table.enclosingScrollView else { return }
            DayrulePaperScroller.install(on: scroll, paperFill: fill)
        }
    }
}

/// Overlay / Always-show knobs tinted from Dayrule paper (light brown on dark
/// brown), matching the sidebar rail instead of system cool grey.
///
/// Drawing only — keep AppKit’s scroll-bar accessibility (role, value %,
/// increment / decrement) so VoiceOver can still scroll the list.
final class DayrulePaperScroller: NSScroller {
    var paperFill: NSColor = .windowBackgroundColor

    static func install(on scroll: NSScrollView, paperFill: NSColor) {
        func adopt(_ existing: NSScroller?) -> DayrulePaperScroller {
            if let current = existing as? DayrulePaperScroller {
                current.paperFill = paperFill
                return current
            }
            let next = DayrulePaperScroller(frame: existing?.frame ?? .zero)
            next.paperFill = paperFill
            if let existing {
                next.controlSize = existing.controlSize
                next.scrollerStyle = existing.scrollerStyle
                next.knobStyle = .default
                next.doubleValue = existing.doubleValue
                next.knobProportion = existing.knobProportion
                next.isEnabled = existing.isEnabled
                next.alphaValue = existing.alphaValue
            }
            return next
        }
        let vertical = adopt(scroll.verticalScroller)
        if scroll.verticalScroller !== vertical {
            scroll.verticalScroller = vertical
        }
        let horizontal = adopt(scroll.horizontalScroller)
        if scroll.horizontalScroller !== horizontal {
            scroll.horizontalScroller = horizontal
        }
    }

    /// Custom `drawKnob` must not drop the scroll-bar AX element.
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .scrollBar }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard !knobRect.isEmpty else { return }
        let inset = knobRect.insetBy(dx: 3, dy: 3)
        guard inset.width > 0, inset.height > 0 else { return }
        let radius = min(4, min(inset.width, inset.height) / 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        warmKnobFill.setFill()
        path.fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Overlay: no track. Always-show: soft warm slot, not cool grey.
        guard scrollerStyle == .legacy else { return }
        let inset = slotRect.insetBy(dx: 4, dy: 4)
        guard inset.width > 0, inset.height > 0 else { return }
        let radius = min(4, min(inset.width, inset.height) / 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        warmKnobFill.withAlphaComponent(flag ? 0.22 : 0.14).setFill()
        path.fill()
    }

    /// Lighten paper toward white — reads as light brown on dark brown paper.
    private var warmKnobFill: NSColor {
        guard let rgb = paperFill.usingColorSpace(.deviceRGB) else {
            return NSColor(calibratedWhite: 0.55, alpha: 0.55)
        }
        let darkPaper = rgb.redComponent + rgb.greenComponent + rgb.blueComponent < 1.5
        let lift: CGFloat = darkPaper ? 0.48 : 0.28
        return NSColor(
            calibratedRed: rgb.redComponent + (1 - rgb.redComponent) * lift,
            green: rgb.greenComponent + (1 - rgb.greenComponent) * lift,
            blue: rgb.blueComponent + (1 - rgb.blueComponent) * lift,
            alpha: 0.58
        )
    }
}

/// Mac sidebar column chrome: ideal width + titlebar fill.
///
/// SwiftUI’s `navigationSplitViewColumnWidth(min:ideal:max:)` is only a hint —
/// AppKit autosaves `NSSplitView Subview Frames` and can keep a collapsed
/// ~144–200pt rail after `columnVisibility` is introduced. Apply the ideal
/// once the split has real bounds (first launch often runs before that — the
/// Settings appearance toggle was accidentally “fixing” it by re-running
/// this). After the first snap, only correct rails outside min/max so we
/// don’t fight a user drag.
/// Also lets the sidebar colour run under the traffic lights by making the
/// titlebar transparent and painting the leading split subview.
struct MacSidebarChrome: NSViewRepresentable {
    var idealWidth: CGFloat
    var minWidth: CGFloat = 260
    var maxWidth: CGFloat = 380
    var fill: Color

    final class Coordinator {
        var didApplyIdeal = false
        var retry: DispatchWorkItem?
        weak var probe: NSView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.probe = view
        DispatchQueue.main.async { self.apply(from: view, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.probe = nsView
        DispatchQueue.main.async { self.apply(from: nsView, coordinator: context.coordinator) }
    }

    private func apply(from probe: NSView, coordinator: Coordinator) {
        if let window = probe.window {
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            window.titleVisibility = .hidden
        }
        var view: NSView? = probe
        while let current = view {
            if let split = current as? NSSplitView, split.subviews.count >= 2 {
                setWidth(on: split, coordinator: coordinator)
                paintLeading(split.subviews[0])
                return
            }
            view = current.superview
        }
        guard let root = probe.window?.contentView else {
            scheduleRetry(coordinator: coordinator)
            return
        }
        if !findSplit(in: root, coordinator: coordinator) {
            scheduleRetry(coordinator: coordinator)
        }
    }

    @discardableResult
    private func findSplit(in root: NSView, coordinator: Coordinator) -> Bool {
        if let split = root as? NSSplitView, split.subviews.count >= 2 {
            setWidth(on: split, coordinator: coordinator)
            paintLeading(split.subviews[0])
            return true
        }
        for child in root.subviews {
            if findSplit(in: child, coordinator: coordinator) { return true }
        }
        return false
    }

    private func setWidth(on split: NSSplitView, coordinator: Coordinator) {
        if split.autosaveName != nil {
            split.autosaveName = nil
        }
        let minTotal = minWidth + 320
        guard split.bounds.width >= minTotal else {
            // First open: split often still has a stub width; retry after layout.
            scheduleRetry(coordinator: coordinator)
            return
        }
        let current = split.subviews[0].frame.width
        let target = min(max(idealWidth, minWidth), maxWidth)
        let outOfRange = current < minWidth - 1 || current > maxWidth + 1
        let needsFirstSnap = !coordinator.didApplyIdeal
        if outOfRange || needsFirstSnap {
            if abs(current - target) > 0.5 {
                split.setPosition(target, ofDividerAt: 0)
            }
            coordinator.didApplyIdeal = true
            coordinator.retry?.cancel()
            coordinator.retry = nil
        }
    }

    private func scheduleRetry(coordinator: Coordinator) {
        guard !coordinator.didApplyIdeal else { return }
        coordinator.retry?.cancel()
        let work = DispatchWorkItem { [weak coordinator] in
            guard let coordinator, let probe = coordinator.probe else { return }
            self.apply(from: probe, coordinator: coordinator)
        }
        coordinator.retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func paintLeading(_ sidebar: NSView) {
        let nsFill = NSColor(fill)
        sidebar.wantsLayer = true
        if sidebar.layer?.backgroundColor == nil
            || sidebar.layer?.backgroundColor != nsFill.cgColor
        {
            sidebar.layer?.backgroundColor = nsFill.cgColor
        }
    }
}
#endif
