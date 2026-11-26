import SwiftUI

/// One transient in-app notice (error, info or Undo). In-app UI only: never routed to
/// system notifications, so decrypted text never leaves the process.
struct Notice: Identifiable, Equatable {
    enum Kind: Equatable {
        case error, info, undo
    }

    let id = UUID()
    var kind: Kind
    var message: String
    var actionTitle: String?
    var action: (@MainActor () -> Void)?

    init(
        kind: Kind,
        message: String,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.kind = kind
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    static func undo(_ message: String, action: @escaping @MainActor () -> Void) -> Notice {
        Notice(kind: .undo, message: message, actionTitle: "Undo", action: action)
    }

    static func == (lhs: Notice, rhs: Notice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Single notice channel: a new post replaces the current one; each auto-dismisses.
@Observable
@MainActor
final class NoticeCenter {
    private(set) var current: Notice?
    /// Bumped on each error notice so iOS `.sensoryFeedback(.error)` can fire.
    private(set) var errorPulse = 0
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func post(_ n: Notice) {
        dismissTask?.cancel()
        current = n
        if n.kind == .error { errorPulse += 1 }
        AccessibilityNotification.Announcement(n.message).post()
        let seconds: Double = n.kind == .undo ? 5 : 4
        let id = n.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.current?.id == id else { return }
            self.current = nil
        }
    }

    /// Dismiss the visible notice (user tapped its action or swiped it away).
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }

    /// Drop a visible Undo notice: a later change means its Undo no longer names the top entry.
    func dismissUndo() {
        guard current?.kind == .undo else { return }
        dismiss()
    }

    /// Drop any notice without announcement, e.g. on lock.
    func clear() {
        dismiss()
    }
}

/// Bottom notice bar; the host places it with `.safeAreaInset(edge: .bottom)`.
struct NoticeBar: View {
    var center: NoticeCenter

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        ZStack {
            if let notice = center.current {
                bar(notice, colors: colors)
                    .transition(.dayruleNotice)
            }
        }
        .dayruleAnimation(Motion.standard, value: center.current)
    }

    private func bar(_ notice: Notice, colors: DayruleColors) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
        return HStack(spacing: Tokens.Space.m) {
            icon(for: notice.kind, colors: colors)
            Text(notice.message)
                .font(.footnote)
                .foregroundStyle(colors.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = notice.actionTitle, let action = notice.action {
                Button(title) {
                    action()
                    center.dismiss()
                }
                .buttonStyle(.dayruleLink)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(colors.sidebar, in: shape)
        .overlay(shape.strokeBorder(colors.hairline, lineWidth: 1))
        .frame(maxWidth: Tokens.formMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notice.message)
        .modifier(NoticeActionModifier(notice: notice, center: center))
    }

    @ViewBuilder
    private func icon(for kind: Notice.Kind, colors: DayruleColors) -> some View {
        switch kind {
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(colors.deadline)
                .accessibilityHidden(true)
        case .undo:
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(colors.textSecondary)
                .accessibilityHidden(true)
        case .info:
            EmptyView()
        }
    }
}

private struct NoticeActionModifier: ViewModifier {
    var notice: Notice
    var center: NoticeCenter

    func body(content: Content) -> some View {
        if let title = notice.actionTitle, let action = notice.action {
            content.accessibilityAction(named: title) {
                action()
                center.dismiss()
            }
        } else {
            content
        }
    }
}
