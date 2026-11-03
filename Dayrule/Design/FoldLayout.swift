import SwiftUI

/// Unobstructed rectangle beside an active fold (iPhone Duo book pose).
///
/// `divisions` are `ReservedRegion.frame` values for `.division`. An empty list
/// means the display is flat: use the whole container. When both sides of a
/// vertical fold are equal, prefer the leading side so the column sits away
/// from the trailing vertical status bar.
enum FoldLayout {
    static func contentSlot(in container: CGSize, divisions: [CGRect]) -> CGRect {
        var slot = CGRect(origin: .zero, size: container)
        guard container.width > 0, container.height > 0 else { return slot }
        for frame in divisions {
            let cut = frame.intersection(slot)
            guard !cut.isNull, !cut.isEmpty else { continue }
            if cut.width <= cut.height {
                let left = CGRect(
                    x: slot.minX,
                    y: slot.minY,
                    width: max(0, cut.minX - slot.minX),
                    height: slot.height
                )
                let right = CGRect(
                    x: cut.maxX,
                    y: slot.minY,
                    width: max(0, slot.maxX - cut.maxX),
                    height: slot.height
                )
                slot = larger(left, right, preferFirstWhenTied: true)
            } else {
                let top = CGRect(
                    x: slot.minX,
                    y: slot.minY,
                    width: slot.width,
                    height: max(0, cut.minY - slot.minY)
                )
                let bottom = CGRect(
                    x: slot.minX,
                    y: cut.maxY,
                    width: slot.width,
                    height: max(0, slot.maxY - cut.maxY)
                )
                slot = larger(top, bottom, preferFirstWhenTied: true)
            }
        }
        return slot
    }

    private static func larger(_ a: CGRect, _ b: CGRect, preferFirstWhenTied: Bool) -> CGRect {
        let areaA = a.width * a.height
        let areaB = b.width * b.height
        if areaA > areaB { return a }
        if areaB > areaA { return b }
        return preferFirstWhenTied ? a : b
    }
}

/// Hosts gate (and similar) columns so an active fold does not bisect fields.
struct FoldSafeContainer<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        #if os(iOS) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            FoldRegionContainer { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS) && compiler(>=6.4)
@available(iOS 27.1, *)
private struct FoldRegionContainer<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let divisions = proxy.reservedRegions(kind: .division)
                .filter(\.isActive)
                .map(\.frame)
            let slot = FoldLayout.contentSlot(in: proxy.size, divisions: divisions)
            content
                .frame(width: slot.width, height: slot.height)
                .position(x: slot.midX, y: slot.midY)
        }
    }
}
#endif
