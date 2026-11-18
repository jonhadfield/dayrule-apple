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
struct MacListHideSystemSeparators: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Inspector()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Inspector)?.stripSoon()
    }

    private final class Inspector: NSView {
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
        }
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
