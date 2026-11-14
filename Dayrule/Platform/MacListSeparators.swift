#if os(macOS)
import AppKit
import SwiftUI

/// Clears NSTableView grid lines under a SwiftUI `List`.
///
/// On macOS, `.listRowSeparator(.hidden)` is only a preference — AppKit still
/// draws horizontal rules that stack under our paper hairline as a double line
/// (decision 74).
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
            // Prefer walking up from this probe (inside the List). Fall back to
            // scanning the window — SwiftUI sometimes hosts the background view
            // beside the NSTableView rather than under it.
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
        }
    }
}
#endif
