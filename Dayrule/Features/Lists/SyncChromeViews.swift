import SwiftUI

/// Sync status chip that owns Observation of `syncStatus` so list bodies
/// don't rebuild when a quiet poll flips through syncing / synced.
struct SyncStatusChrome: View {
    @Bindable var model: AppModel
    var compact: Bool = false

    var body: some View {
        SyncStatusView(
            status: model.syncStatus,
            needsServerSignIn: model.needsServerSignIn,
            compact: compact
        )
    }
}

/// "Update Dayrule" banner; isolated so only this row tracks `needsUpdate`.
struct SyncNeedsUpdateBanner: View {
    @Bindable var model: AppModel
    var colors: DayruleColors
    /// Sidebar rows use a clear background; phone Browse uses paper `bg`.
    var rowBackground: Color?
    var hideSeparator: Bool = false

    var body: some View {
        if model.syncStatus == .needsUpdate {
            Text("\(Image(systemName: "exclamationmark.circle.fill")) \(model.syncStatus.label)")
                .dayruleMeta()
                .foregroundStyle(colors.deadline)
                .padding(.vertical, 6)
                .transition(.dayruleBanner)
                .listRowBackground(rowBackground ?? colors.bg)
                .listRowSeparator(hideSeparator ? .hidden : .automatic)
        }
    }
}

/// Empty-list placeholder; tracks first-sync / syncing without invalidating rows.
struct ListEmptyPlaceholder<VaultMissing: View>: View {
    @Bindable var model: AppModel
    var listTitle: String
    var systemImage: String
    @ViewBuilder var vaultMissing: () -> VaultMissing

    var body: some View {
        if !model.hasCompletedInitialSync, model.syncStatus == .syncing {
            DayruleNoteRow(text: "Syncing…", showsProgress: true)
        } else if model.vault == nil, model.errorMessage != nil {
            vaultMissing()
        } else {
            DayruleEmptyState(
                systemImage: systemImage,
                accessibilityLabel: "Nothing in \(listTitle)"
            )
        }
    }
}

/// Animates only when the update-needed flag flips (sidebar / Browse list).
struct SyncNeedsUpdateAnimationModifier: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content.dayruleAnimation(Motion.standard, value: model.syncStatus == .needsUpdate)
    }
}

/// Top sign-in banner as a `safeAreaInset` only while presented.
///
/// An always-on inset with an empty body still drew a Mac system rule under the
/// page title (stacked with the title hairline as a double underline).
struct SyncSignInBannerInset<Banner: View>: ViewModifier {
    var isPresented: Bool
    var colors: DayruleColors
    @ViewBuilder var banner: () -> Banner

    func body(content: Content) -> some View {
        if isPresented {
            content.safeAreaInset(edge: .top, spacing: 0) {
                banner()
                    .padding(.horizontal, Tokens.Space.m)
                    .padding(.vertical, Tokens.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.sidebar)
                    .overlay(alignment: .bottom) {
                        colors.hairline.frame(height: 1)
                    }
                    .transition(.dayruleBanner)
                    .clipped()
            }
            .dayruleAnimation(Motion.standard, value: isPresented)
        } else {
            content
                .dayruleAnimation(Motion.standard, value: isPresented)
        }
    }
}
