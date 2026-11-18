import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct WhenTarget: Identifiable {
    var id: String { ids.joined(separator: ",") }
    var ids: [ID]
}

/// Phone stack routes (PLAN §6.5: home → list → project / area).
private enum PhoneRoute: Hashable {
    case list(ListName)
    case project(ID)
    case area(ID)
}

/// Split-view detail stack: a project or area opened from the sidebar.
private enum OrgRoute: Hashable {
    case project(ID)
    case area(ID)
}

/// Compact bottom bar: daily path + Browse (Backlog / Done / Trash / projects / areas).
private enum PhoneTab: Hashable, CaseIterable {
    case inbox, today, scheduled, browse

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .browse: "Browse"
        }
    }

    /// Same glyphs as `ListName` / web Lucide; Browse is native-only.
    var systemImage: String {
        switch self {
        case .inbox: ListName.inbox.systemImage
        case .today: ListName.today.systemImage
        case .scheduled: ListName.scheduled.systemImage
        case .browse: "folder"
        }
    }

    var listName: ListName? {
        switch self {
        case .inbox: .inbox
        case .today: .today
        case .scheduled: .scheduled
        case .browse: nil
        }
    }

    static func tab(for list: ListName) -> PhoneTab? {
        switch list {
        case .inbox: .inbox
        case .today: .today
        case .scheduled: .scheduled
        default: nil
        }
    }

    /// Lists shown under Browse (primary three live on the tab bar).
    static let browseLists: [ListName] = [.backlog, .done, .trash]
}

/// List shell (M3): Inbox → Trash over Entities from the vault / store.
struct ListsBrowserView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: ListName? = .inbox
    /// Compact: Browse root; push for Backlog / Done / Trash / projects / areas.
    @State private var phonePath: [PhoneRoute] = []
    @State private var phoneTab: PhoneTab = .inbox
    @State private var didApplyDefaultList = false
    /// Add drafts live in an `@Observable` store observed only by the pinned
    /// Add bar — typing must not invalidate this shell (and re-walk lists).
    @State private var addDrafts = ListAddDrafts()
    /// Bumped to ask the Add bar to focus (Home Screen / ⌘N).
    @State private var addFocusNonce = 0
    @State private var whenTarget: WhenTarget?
    @State private var deadlineTarget: WhenTarget?
    @State private var tagTarget: WhenTarget?
    @State private var moveTarget: WhenTarget?
    @State private var repeatTarget: EditTarget?
    @State private var reminderTarget: EditTarget?
    @State private var editTarget: EditTarget?
    @State private var orgPath: [OrgRoute] = []
    /// Find result held until the sheet has gone, so navigation isn't fought by the dismissal.
    @State private var pendingFind: Find.Result?
    @State private var confirmEmptyTrash = false
    @State private var keyboardVisible = false
    @State private var detailWidth: CGFloat = 0
    /// Multi-select mode (PLAN §6.5): bar replaces Add; taps toggle membership.
    @State private var selecting = false
    @State private var selectedIds: Set<ID> = []
    @State private var showNewList = false
    /// Split column visibility — owned so we can replace the system sidebar
    /// toggle (white Liquid Glass pill) with a plain paper toolbar button.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// Sidebar badges / org tree — refreshed on entity/linger changes only, so a
    /// sidebar click doesn’t re-walk every to-do just to flip the selection bar.
    @State private var cachedSidebarCounts = Lists.SidebarCounts(inbox: 0, today: 0, overdue: 0)
    @State private var cachedBrowseTree = Lists.BrowseTree(looseProjects: [], areaGroups: [])
    @State private var cachedTrashCount = 0
    @State private var cachedBacklogCount = 0
    @State private var cachedDoneCount = 0
    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var browseIconWidth: CGFloat = 22

    private struct EditTarget: Identifiable {
        var id: ID
    }

    private var activeList: ListName { selection ?? .inbox }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        // Split the modifier chain so the type checker can finish (CI Release).
        browserWithMacChrome
            .environment(\.dayruleDenseLayout, !isCompact)
            .modifier(DayruleDenseBodyFont(dense: !isCompact))
    }

    /// Phone vs split shell only (PLAN §6.2 / decision 48 dense on regular width).
    @ViewBuilder
    private var browserRoot: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        if isCompact {
            phoneBrowser(colors: colors)
        } else {
            // Duo book pose: keep the split entirely on one side of an
            // active fold (same FoldSafeContainer as Gate). Flat open is
            // a no-op (no division → full container).
            FoldSafeContainer {
                splitBrowser(colors: colors)
            }
        }
    }

    private var browserWithSidebarLifecycle: some View {
        browserRoot
            .onAppear {
                refreshSidebarCache()
                applyDefaultDestinationIfNeeded()
            }
            .onChange(of: model.entitiesEpoch) { _, _ in
                refreshSidebarCache()
            }
            .onChange(of: model.linger.ids) { _, _ in
                refreshSidebarCache()
            }
            .onChange(of: model.vaultLoading) { _, loading in
                if !loading { applyDefaultDestinationIfNeeded() }
            }
            .onChange(of: selection) { _, _ in
                if !isCompact { orgPath = [] }
                exitSelecting()
            }
            .onChange(of: phoneTab) { _, _ in
                exitSelecting()
            }
            .onChange(of: phonePath) { _, path in
                if let name = path.reversed().compactMap({ route -> ListName? in
                    if case .list(let n) = route { return n }
                    return nil
                }).first {
                    selection = name
                }
            }
    }

    private var browserWithSheets: some View {
        browserWithSidebarLifecycle
            .sheet(isPresented: $model.showSettings, onDismiss: {
                model.endSettingsPresentation()
            }) {
                SettingsView(model: model)
                    .onAppear { model.beginSettingsPresentation() }
            }
            .sheet(item: $whenTarget) { target in
                WhenSheetView(model: model, ids: target.ids)
            }
            .sheet(item: $deadlineTarget) { target in
                DeadlineSheetView(model: model, ids: target.ids)
            }
            .sheet(item: $tagTarget) { target in
                TagSheetView(model: model, ids: target.ids)
            }
            .sheet(item: $moveTarget) { target in
                MoveSheetView(model: model, ids: target.ids)
            }
            .sheet(item: $repeatTarget) { target in
                RepeatSheetView(model: model, todoId: target.id)
            }
            .sheet(item: $reminderTarget) { target in
                ReminderSheetView(model: model, todoId: target.id)
            }
            // PLAN §6.5: the editor is full screen on a phone, a sheet elsewhere.
            .sheet(item: editorSheetTarget) { target in
                ItemEditorSheet(model: model, id: target.id)
            }
            #if os(iOS)
            .fullScreenCover(item: editorCoverTarget) { target in
                ItemEditorSheet(model: model, id: target.id)
            }
            #endif
            .sheet(isPresented: $model.showFind, onDismiss: applyPendingFind) {
                QuickFindView(model: model) { result in
                    pendingFind = result
                }
            }
    }

    private var browserWithMacChrome: some View {
        browserWithSheets
            .onChange(of: model.pendingMacChromeAction) { _, action in
                guard let action else { return }
                model.pendingMacChromeAction = nil
                handleMacChromeAction(action)
            }
            .onChange(of: model.pendingFocusAdd) { _, pending in
                if pending { consumeFocusAddIfReady() }
            }
            .onChange(of: model.phase) { _, phase in
                if phase == .unlocked { consumeFocusAddIfReady() }
            }
            .onChange(of: model.vaultLoading) { _, loading in
                if !loading { consumeFocusAddIfReady() }
            }
            .onChange(of: model.dismissChromeEpoch) { _, _ in
                dismissLocalSheets()
            }
            .onChange(of: localSheetPresented) { _, presented in
                model.macLocalSheetPresented = presented
            }
            .onChange(of: selectedIds) { _, ids in
                model.hasMacListSelection = selecting && !ids.isEmpty
            }
            .onChange(of: selecting) { _, on in
                model.hasMacListSelection = on && !selectedIds.isEmpty
            }
            .onAppear {
                model.macLocalSheetPresented = localSheetPresented
                model.hasMacListSelection = selecting && !selectedIds.isEmpty
            }
            .onDisappear {
                model.macLocalSheetPresented = false
                model.hasMacListSelection = false
            }
    }

    /// Local list sheets (not Settings / Find / Help — those live on `AppModel`).
    private var localSheetPresented: Bool {
        whenTarget != nil
            || deadlineTarget != nil
            || tagTarget != nil
            || moveTarget != nil
            || repeatTarget != nil
            || reminderTarget != nil
            || editTarget != nil
            || showNewList
    }

    private func dismissLocalSheets() {
        whenTarget = nil
        deadlineTarget = nil
        tagTarget = nil
        moveTarget = nil
        repeatTarget = nil
        reminderTarget = nil
        editTarget = nil
        showNewList = false
        model.macLocalSheetPresented = false
    }

    private func handleMacChromeAction(_ action: AppModel.MacChromeAction) {
        switch action {
        case .trashSelection:
            trashSelection()
        case .newProject:
            addProject(areaId: areaIdForNewProject)
        case .newArea:
            addArea()
        }
    }

    /// Home Screen "New to-do" / menu New To-Do: Inbox Add after unlock (PLAN §1).
    private func consumeFocusAddIfReady() {
        guard model.pendingFocusAdd, model.phase == .unlocked, !model.vaultLoading else { return }
        model.pendingFocusAdd = false
        model.showSettings = false
        model.showFind = false
        model.showHelp = false
        exitSelecting()
        phonePath = []
        orgPath = []
        phoneTab = .inbox
        selection = .inbox
        // Wait a turn so the Inbox Add row is on screen before focusing.
        Task { @MainActor in
            addFocusNonce &+= 1
        }
    }

    /// Prefer the open area; otherwise the area of the open project (PLAN §6.6 New List).
    private var areaIdForNewProject: ID? {
        if case .area(let id) = orgPath.last { return id }
        if case .area(let id) = phonePath.last { return id }
        if case .project(let id) = orgPath.last {
            return model.entities.projects[id]?.areaId
        }
        if case .project(let id) = phonePath.last {
            return model.entities.projects[id]?.areaId
        }
        return nil
    }

    private var editorSheetTarget: Binding<EditTarget?> {
        Binding(
            get: { isCompact ? nil : editTarget },
            set: { editTarget = $0 }
        )
    }

    private var editorCoverTarget: Binding<EditTarget?> {
        Binding(
            get: { isCompact ? editTarget : nil },
            set: { editTarget = $0 }
        )
    }

    // MARK: - Phone (NavigationStack) / regular (NavigationSplitView)

    @ViewBuilder
    private func phoneBrowser(colors: DayruleColors) -> some View {
        VStack(spacing: 0) {
            NavigationStack(path: $phonePath) {
                // No transition on the stack root: it hides the large title on iOS 26.
                // Tabs switch instantly, as system tab bars do.
                phoneTabRoot(colors: colors)
                    .id(phoneTab)
                    .toolbar {
                        chromeToolbar(colors: colors)
                    }
                    .navigationDestination(for: PhoneRoute.self) { route in
                        switch route {
                        case .list(let name):
                            listDetail(list: name, colors: colors)
                        case .project(let projectId):
                            ProjectDetailView(model: model, projectId: projectId) { id in
                                phonePath.append(.project(id))
                            }
                            .toolbar { chromeToolbar(colors: colors) }
                        case .area(let areaId):
                            AreaDetailView(model: model, areaId: areaId) { projectId in
                                phonePath.append(.project(projectId))
                            }
                            .toolbar { chromeToolbar(colors: colors) }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NoticeBar(center: model.notices)
            }

            if !keyboardVisible {
                phoneTabBar(colors: colors)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(colors.bg)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(Motion.system(Motion.standard)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.system(Motion.standard)) { keyboardVisible = false }
        }
        .sensoryFeedback(.selection, trigger: phoneTab)
        #endif
    }

    @ViewBuilder
    private func phoneTabRoot(colors: DayruleColors) -> some View {
        switch phoneTab {
        case .browse:
            sidebarList(colors: colors, phoneLinks: true)
                .navigationTitle("Browse")
                .dayruleListNavChrome(colors: colors)
        case .inbox:
            listDetail(list: .inbox, colors: colors)
        case .today:
            listDetail(list: .today, colors: colors)
        case .scheduled:
            listDetail(list: .scheduled, colors: colors)
        }
    }

    private func phoneTabBar(colors: DayruleColors) -> some View {
        HStack(spacing: 0) {
            ForEach(PhoneTab.allCases, id: \.self) { tab in
                let selected = phoneTab == tab
                Button {
                    selectTab(tab)
                } label: {
                    VStack(spacing: Tokens.Space.xs) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: tabIconSize, weight: .medium))
                            .symbolVariant(selected ? .fill : .none)
                            .accessibilityHidden(true)
                        Text(tab.title)
                            .font(DayruleType.tabLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    // Top-align in the 44pt hit: centred layout put empty space
                    // under the label while icons kissed the hairline.
                    .frame(maxWidth: .infinity, minHeight: Tokens.minHit, alignment: .top)
                    .padding(.top, Tokens.Space.s)
                    .foregroundStyle(selected ? colors.accent : colors.textSecondary)
                    .dayruleAnimation(Motion.quick, value: selected)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityShowsLargeContentViewer()
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("phone.tab.\(String(describing: tab))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, Tokens.Space.xs)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // Paint into the home-indicator inset so the empty band under the
        // labels is tab chrome, not orphaned page paper.
        .background(colors.sidebar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            colors.hairline.frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    /// Single entry point for tab changes, so the tab and its path always move together.
    /// Re-tapping the active tab pops back to its root.
    private func selectTab(_ tab: PhoneTab, path: [PhoneRoute] = []) {
        if tab != phoneTab {
            phoneTab = tab
        }
        phonePath = path
        if let name = tab.listName {
            selection = name
        }
    }

    /// After unlock: Today if it has work, otherwise Inbox.
    private func applyDefaultDestinationIfNeeded() {
        guard !didApplyDefaultList else { return }
        guard !model.vaultLoading else { return }
        let preferToday = !Lists.today(model.entities, ctx).isEmpty
        let name: ListName = preferToday ? .today : .inbox
        selection = name
        if isCompact {
            selectTab(preferToday ? .today : .inbox)
        }
        didApplyDefaultList = true
    }

    /// Ideal Mac sidebar width — kept in sync with `MacSidebarChrome` / columnWidth.
    private static let macSidebarWidth: CGFloat = 270

    @ViewBuilder
    private func splitBrowser(colors: DayruleColors) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarList(colors: colors, phoneLinks: false)
                .navigationTitle("Dayrule")
                .navigationSplitViewColumnWidth(
                    min: 260,
                    ideal: Self.macSidebarWidth,
                    max: 360
                )
                // Drop the system sidebar toggle — its Liquid Glass pill reads as
                // a white disc on paper. Paper chip overlays this column’s
                // trailing edge so it tracks divider drags.
                .toolbar(removing: .sidebarToggle)
                #if os(macOS)
                .overlay(alignment: .topTrailing) {
                    if columnVisibility != .detailOnly {
                        sidebarCollapseButton()
                            .padding(.trailing, Tokens.rowInset)
                            // Titlebar centre ≈ detail toolbar row (Lock / Find).
                            .padding(.top, 10)
                            .help("Toggle Sidebar")
                            .ignoresSafeArea(edges: .top)
                    }
                }
                #endif
        } detail: {
            NavigationStack(path: $orgPath) {
                listDetail(list: activeList, colors: colors)
                    .toolbar {
                        // When the sidebar is collapsed, keep a toggle on detail
                        // so the rail can be opened again.
                        chromeToolbar(
                            colors: colors,
                            includeSidebarToggle: columnVisibility == .detailOnly
                        )
                    }
                    .navigationDestination(for: OrgRoute.self) { route in
                        switch route {
                        case .project(let projectId):
                            ProjectDetailView(model: model, projectId: projectId) { id in
                                orgPath.append(.project(id))
                            }
                            .toolbar {
                                chromeToolbar(
                                    colors: colors,
                                    includeSidebarToggle: columnVisibility == .detailOnly
                                )
                            }
                        case .area(let areaId):
                            AreaDetailView(model: model, areaId: areaId) { projectId in
                                orgPath.append(.project(projectId))
                            }
                            .toolbar {
                                chromeToolbar(
                                    colors: colors,
                                    includeSidebarToggle: columnVisibility == .detailOnly
                                )
                            }
                        }
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NoticeBar(center: model.notices)
            }
        }
    }

    /// Collapse control drawn in the sidebar column (titlebar trailing).
    @ViewBuilder
    private func sidebarCollapseButton() -> some View {
        Button {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        } label: {
            DayruleToolbarGlyph(systemImage: "sidebar.left")
        }
        .buttonStyle(.plain)
        .help("Toggle Sidebar")
        .accessibilityLabel("Toggle Sidebar")
    }

    /// Lock · Find · Settings (Refresh lives under Settings → Sync now).
    /// `includeSidebarToggle` is for collapsed-sidebar detail only.
    @ToolbarContentBuilder
    private func chromeToolbar(
        colors: DayruleColors,
        includeSidebarToggle: Bool = false
    ) -> some ToolbarContent {
        // Paper chips (sidebar fill + hairline) — hide Liquid Glass so it does
        // not replace them with white pills.
        if includeSidebarToggle {
            ToolbarItem(placement: .navigation) {
                sidebarCollapseButton()
            }
            .dayruleHideToolbarGlass()
        }
        ToolbarItem(placement: .navigation) {
            Button {
                model.lockNow()
            } label: {
                DayruleToolbarGlyph(systemImage: "lock")
            }
            .buttonStyle(.plain)
            .help("Lock (⇧⌘L)")
            .accessibilityLabel("Lock")
        }
        .dayruleHideToolbarGlass()
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showFind = true
            } label: {
                DayruleToolbarGlyph(systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Find (⌘F)")
            .accessibilityLabel("Find")
            .accessibilityIdentifier("sidebar.find")
        }
        .dayruleHideToolbarGlass()
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showSettings = true
            } label: {
                DayruleToolbarGlyph(systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .dayruleHideToolbarGlass()
    }

    @ViewBuilder
    private func sidebarList(colors: DayruleColors, phoneLinks: Bool) -> some View {
        if phoneLinks {
            List {
                phoneBrowseRows(colors: colors)
            }
            .listStyle(.plain)
            .dayrulePaperList()
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .modifier(SyncNeedsUpdateAnimationModifier(model: model))
        } else {
            sidebarColumnBody(colors: colors)
        }
    }

    /// Mac / iPad sidebar list + New List footer.
    @ViewBuilder
    private func sidebarColumnBody(colors: DayruleColors) -> some View {
        List(selection: $selection) {
            sidebarRows(colors: colors)
        }
        .listStyle(.sidebar)
        .dayrulePaperList()
        .listRowSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .background(colors.sidebar.ignoresSafeArea())
        #if os(macOS)
        .background(
            MacSidebarChrome(
                idealWidth: Self.macSidebarWidth,
                minWidth: 260,
                maxWidth: 360,
                fill: colors.sidebar
            )
        )
        #endif
        .modifier(SyncNeedsUpdateAnimationModifier(model: model))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // One footer row: New List shares the sidebar icon/title columns;
            // sync dot sits trailing where count badges live.
            // Same height as pinned Add so the two shelves share one baseline.
            HStack(alignment: .center, spacing: 0) {
                Color.clear
                    .frame(width: 3, height: 1)
                    .padding(.trailing, 8)
                newListMenu(colors: colors)
                Spacer(minLength: 0)
                SyncStatusChrome(model: model, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Leading matches the selection-bar gutter; trailing matches the
            // sidebar badge column (plain List trailing inset ≈ rowInset).
            .padding(.leading, Tokens.Space.s)
            .padding(.trailing, Tokens.rowInset)
            .frame(height: Tokens.macBottomChromeHeight)
            .background(colors.sidebar)
            .overlay(alignment: .top) {
                colors.hairline.frame(height: 1)
            }
        }
    }

    private func listImage(_ name: ListName) -> String {
        name.systemImage
    }

    /// Phone Browse: ALL-CAPS park lists with circular counts + PROJECTS / areas (PLAN §6.5).
    @ViewBuilder
    private func phoneBrowseRows(colors: DayruleColors) -> some View {
        if model.needsServerSignIn {
            syncSignInBanner(colors: colors)
                .listRowBackground(colors.bg)
                .listRowSeparator(.hidden)
        } else {
            SyncStatusChrome(model: model)
                .listRowBackground(colors.bg)
                .listRowSeparator(.hidden)
            SyncNeedsUpdateBanner(model: model, colors: colors, hideSeparator: true)
        }
        ForEach(PhoneTab.browseLists, id: \.self) { name in
            NavigationLink(value: PhoneRoute.list(name)) {
                HStack(spacing: 12) {
                    Image(systemName: listImage(name))
                        .font(.body)
                        .foregroundStyle(name.tint(colors))
                        .frame(width: browseIconWidth)
                        .accessibilityHidden(true)
                    Text(name.title)
                        .font(.body.weight(.medium))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(colors.text)
                    Spacer(minLength: 0)
                    if let count = browseCount(for: name) {
                        DayruleCountBadge(count: count, style: .ring)
                    }
                }
                .frame(minHeight: Tokens.rowMinHeight(dense: false))
            }
            .accessibilityIdentifier("list.sidebar.\(name.rawValue)")
            .listRowBackground(colors.bg)
            .dayruleDrawnRowRule(colors: colors)
            .modifier(sidebarDropModifier(SidebarDrop.action(for: name, today: ctx.today)))
        }
        newListTrigger(colors: colors, style: .browseRow)
            .listRowBackground(colors.bg)
            .dayruleDrawnRowRule(colors: colors)

        let tree = cachedBrowseTree
        if !tree.looseProjects.isEmpty {
            Section {
                ForEach(tree.looseProjects, id: \.id) { project in
                    phoneProjectLink(project, colors: colors)
                }
            } header: {
                DayruleSectionHeader(title: "Projects", tone: .muted, style: .caps)
            }
        }
        ForEach(tree.areaGroups) { group in
            Section {
                NavigationLink(value: PhoneRoute.area(group.area.id)) {
                    phoneOrgLabel(
                        title: areaTitle(group.area),
                        systemImage: "shippingbox",
                        colors: colors
                    )
                }
                .accessibilityIdentifier("list.sidebar.area.\(group.area.id)")
                .contextMenu { areaContextMenu(group.area) }
                .listRowBackground(colors.bg)
                .dayruleDrawnRowRule(colors: colors)
                .modifier(sidebarDropModifier(SidebarDrop.action(areaId: group.area.id)))
                ForEach(group.projects, id: \.id) { project in
                    phoneProjectLink(project, colors: colors)
                }
            }
        }
    }

    private func phoneProjectLink(_ project: Project, colors: DayruleColors) -> some View {
        NavigationLink(value: PhoneRoute.project(project.id)) {
            phoneOrgLabel(
                title: projectTitle(project),
                systemImage: "bookmark",
                colors: colors
            )
        }
        .accessibilityIdentifier("list.sidebar.project.\(project.id)")
        .contextMenu { projectContextMenu(project) }
        .listRowBackground(colors.bg)
        .dayruleDrawnRowRule(colors: colors)
        .modifier(sidebarDropModifier(SidebarDrop.action(projectId: project.id)))
    }

    private func phoneOrgLabel(title: String, systemImage: String, colors: DayruleColors) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .frame(width: browseIconWidth)
                .accessibilityHidden(true)
            Text(title)
                .dayruleRowTitle()
                .foregroundStyle(colors.text)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Tokens.rowMinHeight(dense: !isCompact))
    }

    @ViewBuilder
    private func sidebarRows(colors: DayruleColors) -> some View {
        SyncNeedsUpdateBanner(model: model, colors: colors, rowBackground: .clear, hideSeparator: true)
        let names = ListName.allCases.filter { $0 != .notNow }
        ForEach(names, id: \.self) { name in
            HStack(spacing: 0) {
                // 3pt terracotta bar marks the selection on iPad and Mac (PLAN §6.5 / §6.6).
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selection == name ? colors.accent : .clear)
                    .frame(width: 3)
                    .padding(.trailing, 8)
                Label {
                    Text(name.title)
                        .dayruleRowTitle()
                        .foregroundStyle(colors.text)
                } icon: {
                    Image(systemName: listImage(name))
                        .foregroundStyle(name.tint(colors))
                }
                Spacer()
                if let badge = badge(for: name) {
                    DayruleCountBadge(
                        count: badge,
                        overdue: name == .today ? counts.overdue : 0,
                        style: .plain
                    )
                }
            }
            .accessibilityIdentifier("list.sidebar.\(name.rawValue)")
            .tag(Optional(name))
            .listRowBackground(selection == name ? colors.selectedRow : Color.clear)
            .modifier(sidebarDropModifier(SidebarDrop.action(for: name, today: ctx.today)))
        }
        let tree = cachedBrowseTree
        if !tree.looseProjects.isEmpty {
            Section {
                ForEach(tree.looseProjects, id: \.id) { project in
                    sidebarProjectRow(project, colors: colors)
                }
            } header: {
                DayruleSectionHeader(title: "Projects", tone: .muted, style: .caps, surface: .sidebar)
            }
        }
        ForEach(tree.areaGroups) { group in
            Section {
                sidebarOrgRow(
                    title: areaTitle(group.area),
                    systemImage: "shippingbox",
                    selected: isSelected(.area(group.area.id)),
                    identifier: "list.sidebar.area.\(group.area.id)",
                    colors: colors
                ) {
                    orgPath = [.area(group.area.id)]
                }
                .contextMenu { areaContextMenu(group.area) }
                .modifier(sidebarDropModifier(SidebarDrop.action(areaId: group.area.id)))
                ForEach(group.projects, id: \.id) { project in
                    sidebarProjectRow(project, colors: colors)
                }
            }
        }
    }

    private func sidebarProjectRow(_ project: Project, colors: DayruleColors) -> some View {
        sidebarOrgRow(
            title: projectTitle(project),
            systemImage: "bookmark",
            selected: isSelected(.project(project.id)),
            identifier: "list.sidebar.project.\(project.id)",
            colors: colors
        ) {
            orgPath = [.project(project.id)]
        }
        .contextMenu { projectContextMenu(project) }
        .modifier(sidebarDropModifier(SidebarDrop.action(projectId: project.id)))
    }

    private func sidebarDropModifier(_ action: SidebarDropAction) -> SidebarDropDestination {
        SidebarDropDestination(action: action) { ids in
            applySidebarDrop(ids: ids, action: action)
        }
    }

    private func applySidebarDrop(ids: [ID], action: SidebarDropAction) {
        let todoIds = ids.filter { model.entities.todos[$0] != nil }
        guard !todoIds.isEmpty else { return }
        do {
            try model.store.run("Drop") { d, env in
                try SidebarDrop.perform(action, draft: d, env: env, ids: todoIds)
            }
            model.noteEntitiesChanged()
            exitSelecting()
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button {
            toggleSidebarProjectComplete(project)
        } label: {
            if project.status == .open {
                Label("Complete Project", systemImage: "checkmark.circle")
            } else {
                Label("Reopen Project", systemImage: "arrow.uturn.backward.circle")
            }
        }
        Menu {
            Button {
                moveSidebarProject(project, areaId: nil)
            } label: {
                Label("No area", systemImage: "bookmark")
            }
            let areas = model.entities.areas.values
                .filter { $0.trashedAt == nil }
                .sorted { Order.compareKeys($0.order, $1.order) < 0 }
            ForEach(areas, id: \.id) { area in
                Button {
                    moveSidebarProject(project, areaId: area.id)
                } label: {
                    Text(area.title.isEmpty ? "New Area" : area.title)
                }
            }
        } label: {
            Label("Move…", systemImage: "arrow.right.square")
        }
        Button(role: .destructive) {
            trashSidebarProject(project)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private func moveSidebarProject(_ project: Project, areaId: ID?) {
        let title = projectTitle(project)
        do {
            try model.store.run("Move Project") { d, env in
                try Commands.moveProject(d, env, id: project.id, areaId: areaId)
            }
            model.noteEntitiesChanged()
            if let areaId, let areaTitle = model.entities.areas[areaId]?.title, !areaTitle.isEmpty {
                model.undoNotice("Moved \(title) to \(areaTitle)")
            } else if areaId != nil {
                model.undoNotice("Moved \(title) to area")
            } else {
                model.undoNotice("Moved \(title) out of area")
            }
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    @ViewBuilder
    private func areaContextMenu(_ area: Area) -> some View {
        Button(role: .destructive) {
            trashSidebarArea(area)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private func toggleSidebarProjectComplete(_ project: Project) {
        let title = projectTitle(project)
        let status: Status = project.status == .open ? .completed : .open
        model.store.run(status == .completed ? "Complete Project" : "Reopen Project") { d, env in
            Commands.setStatus(d, env, ids: [project.id], status: status)
        }
        model.noteEntitiesChanged()
        if status == .completed {
            model.undoNotice("Completed \(title)")
        }
    }

    private func trashSidebarProject(_ project: Project) {
        let title = projectTitle(project)
        model.store.run("Trash Project") { d, env in
            Commands.trashItems(d, env, ids: [project.id])
        }
        model.noteEntitiesChanged()
        model.bumpHaptic(\.trash)
        model.undoNotice("Moved \(title) to Trash")
        clearOrgNavigation(matching: .project(project.id))
    }

    private func trashSidebarArea(_ area: Area) {
        let title = areaTitle(area)
        model.store.run("Trash Area") { d, env in
            Commands.trashItems(d, env, ids: [area.id])
        }
        model.noteEntitiesChanged()
        model.bumpHaptic(\.trash)
        model.undoNotice("Moved \(title) to Trash")
        clearOrgNavigation(matching: .area(area.id))
    }

    private func clearOrgNavigation(matching route: OrgRoute) {
        if orgPath.contains(route) {
            orgPath = []
        }
        phonePath.removeAll { phone in
            switch (phone, route) {
            case (.project(let a), .project(let b)), (.area(let a), .area(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private func sidebarOrgRow(
        title: String,
        systemImage: String,
        selected: Bool,
        identifier: String,
        colors: DayruleColors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selected ? colors.accent : .clear)
                    .frame(width: 3)
                    .padding(.trailing, 8)
                Label {
                    Text(title)
                        .dayruleRowTitle()
                        .foregroundStyle(colors.text)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .listRowBackground(selected ? colors.selectedRow : Color.clear)
    }

    private func isSelected(_ route: OrgRoute) -> Bool {
        orgPath.last == route
    }

    private func projectTitle(_ project: Project) -> String {
        project.title.isEmpty ? "New Project" : project.title
    }

    private func areaTitle(_ area: Area) -> String {
        area.title.isEmpty ? "New Area" : area.title
    }

    /// Paper New List control (web Sidebar). System `Menu` uses footnote-sized
    /// pull-downs on Mac and a compact List picker on iPhone — both too small
    /// next to 15pt / body rows.
    private enum NewListTriggerStyle {
        case browseRow
        case sidebarFooter
    }

    private func newListTrigger(colors: DayruleColors, style: NewListTriggerStyle) -> some View {
        Button {
            showNewList = true
        } label: {
            switch style {
            case .browseRow:
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .dayruleRowTitle()
                        .foregroundStyle(colors.textSecondary)
                        .frame(width: browseIconWidth)
                        .accessibilityHidden(true)
                    Text("New List")
                        .dayruleRowTitle(.medium)
                        .foregroundStyle(colors.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Tokens.rowMinHeight(dense: !isCompact))
            case .sidebarFooter:
                NewListFooterLabel(colors: colors)
            }
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
        .accessibilityIdentifier("browse.newList")
        .popover(isPresented: $showNewList, arrowEdge: style == .sidebarFooter ? .top : .bottom) {
            newListPicker(colors: colors)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func newListMenu(colors: DayruleColors) -> some View {
        newListTrigger(colors: colors, style: .sidebarFooter)
    }

    private func newListPicker(colors: DayruleColors) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            newListChoice(
                title: "New Project",
                systemImage: "bookmark",
                identifier: "browse.newProject",
                colors: colors,
                action: { addProject() }
            )
            newListChoice(
                title: "New Area",
                systemImage: "shippingbox",
                identifier: "browse.newArea",
                colors: colors,
                action: { addArea() }
            )
        }
        .padding(Tokens.Space.xs)
        .frame(minWidth: 176)
        .background(colors.bg)
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.hairline, lineWidth: 1))
        .presentationBackground(colors.bg)
    }

    private func newListChoice(
        title: String,
        systemImage: String,
        identifier: String,
        colors: DayruleColors,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            showNewList = false
            action()
        } label: {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: systemImage)
                    .dayruleRowTitle()
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .dayruleRowTitle()
                    .foregroundStyle(colors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Space.s)
            .frame(
                maxWidth: .infinity,
                minHeight: Tokens.rowMinHeight(dense: !isCompact),
                alignment: .leading
            )
        }
        .buttonStyle(.dayruleRow)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
        .accessibilityIdentifier(identifier)
    }

    private struct NewListFooterLabel: View {
        let colors: DayruleColors
        @State private var hovering = false

        var body: some View {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: "plus")
                    .dayruleRowTitle()
                    .frame(width: 18, alignment: .center)
                    .accessibilityHidden(true)
                Text("New List")
                    .dayruleRowTitle()
            }
            .foregroundStyle(colors.textSecondary)
            .padding(.vertical, Tokens.Space.xs)
            // Hover fill expands without shifting the glyph/title columns.
            .background {
                RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                    .fill(hovering ? colors.hairline.opacity(0.6) : Color.clear)
                    .padding(.horizontal, -Tokens.Space.s)
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
            .onHover { hovering = $0 }
        }
    }

    private func browseCount(for name: ListName) -> Int? {
        switch name {
        case .backlog: cachedBacklogCount
        case .done: cachedDoneCount
        case .trash: cachedTrashCount
        default: nil
        }
    }

    /// Centres the list in a reading column on wide windows (regular width and macOS).
    private var readingMargin: CGFloat {
        Tokens.readingMargin(width: detailWidth, compact: isCompact)
    }

    /// Inbox / Today / Backlog / Scheduled — same lists that used to host inline Add.
    private func listAllowsPinnedAdd(_ list: ListName) -> Bool {
        list == .inbox || list == .today || list == .backlog || list == .scheduled
    }

    /// Sticky paper Add under the scrolling rows; keeps checkbox alignment (decision 19).
    @ViewBuilder
    private func pinnedPaperAdd(list: ListName, colors: DayruleColors) -> some View {
        // Separate view observes `addDrafts` so keystrokes don’t rebuild `List`.
        PinnedListAddBar(
            drafts: addDrafts,
            list: list,
            colors: colors,
            focusNonce: addFocusNonce,
            keepFocusAfterSubmit: list != .scheduled
        ) { title in
            addTodo(to: list, title: title)
        }
    }

    @ViewBuilder
    private func listDetail(list: ListName, colors: DayruleColors) -> some View {
        List {
            if list == .backlog {
                backlogSections(colors: colors)
            } else if list == .scheduled {
                scheduledSections(colors: colors)
            } else {
                let listRows = rows(for: list)
                if listRows.isEmpty {
                    // Never replace existing rows with a sync banner — that races Add in e2e
                    // and hides todos for the whole push/pull.
                    emptyRow(list: list)
                } else {
                    let peers = listRows.filter(\.isTodo).map(\.id)
                    let onMoveOK = listRows.allSatisfy(\.isTodo)
                        && ListReorder.allowsDrag(in: list)
                        && !selecting
                    ForEach(listRows, id: \.id) { row in
                        reorderableListRow(row, list: list, colors: colors, peers: peers)
                    }
                    .onMove { source, destination in
                        moveTodos(peers: peers, source: source, destination: destination, list: list)
                    }
                    .moveDisabled(!onMoveOK)
                }
            }
        }
        .listStyle(.plain)
        .dayrulePaperList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(list.title)
        .dayruleListNavChrome(colors: colors)
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            detailWidth = width
        }
        // Mac plain Lists ignore scroll `contentMargins`, and `.padding` on the
        // List shifts safeAreaInset chrome (title / Add) without moving rows —
        // that desynced the title from the checkbox column. Leave Mac lists
        // unpadded; chrome uses `listChromeInset` alone.
        #if !os(macOS)
        .contentMargins(.horizontal, readingMargin, for: .scrollContent)
        #endif
        .dayrulePageTitle(list.title, systemImage: list.systemImage, iconTint: list.tint(colors))
        .refreshable {
            await model.syncNow()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Pin Add in the viewport (decision 64) so long Today/Inbox don’t
            // bury the paper row. Selection bar still replaces it.
            if selecting {
                SelectionBarView(
                    count: selectedIds.count,
                    onCancel: exitSelecting,
                    onWhen: {
                        whenTarget = WhenTarget(ids: Array(selectedIds))
                        exitSelecting()
                    },
                    onDeadline: {
                        deadlineTarget = WhenTarget(ids: Array(selectedIds))
                        exitSelecting()
                    },
                    onMove: {
                        moveTarget = WhenTarget(ids: Array(selectedIds))
                        exitSelecting()
                    },
                    onComplete: completeSelection,
                    onTrash: trashSelection
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if listAllowsPinnedAdd(list) {
                pinnedPaperAdd(list: list, colors: colors)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .dayruleAnimation(Motion.standard, value: selecting)
        .modifier(
            SyncSignInBannerInset(
                isPresented: model.needsServerSignIn,
                colors: colors,
                banner: { syncSignInBanner(colors: colors) }
            )
        )
        // After title / Add / banner insets so they inherit the reading column.
        .environment(\.dayruleReadingMargin, readingMargin)
        .toolbar {
            // Pushed Browse destinations replace the tab-root toolbar — repeat chrome.
            if isCompact, !phonePath.isEmpty {
                chromeToolbar(colors: colors)
            }
            ToolbarItem(placement: .primaryAction) {
                listActionsMenu(list: list)
            }
            .dayruleHideToolbarGlass()
        }
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $confirmEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) { emptyTrash() }
        } message: {
            Text("Deletes ^[\(trashCount) item](inflect: true) for good. You can’t undo this after you leave Trash.")
        }
    }

    private func listActionsMenu(list: ListName) -> some View {
        Menu {
            Button {
                model.undoLast()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.store.canUndo)
            Button {
                _ = model.store.redo()
                model.noteEntitiesChanged()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!model.store.canRedo)
            if list == .trash {
                Button(role: .destructive) {
                    confirmEmptyTrash = true
                } label: {
                    Label("Empty Trash", systemImage: "trash")
                }
                .accessibilityIdentifier("list.emptyTrash")
                .disabled(rows(for: .trash).isEmpty)
            }
            if list == .done, model.entities.settings.moveToDone == .manually {
                Button {
                    logCompleted()
                } label: {
                    Label("Move to Done now", systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier("list.logCompleted")
            }
        } label: {
            DayruleToolbarGlyph(systemImage: "ellipsis")
        }
        .buttonStyle(.plain)
        .help("List actions")
        // Identifier predates the rename to List actions; UI tests may still use it.
        .accessibilityIdentifier("list.find")
        .accessibilityLabel("List actions")
    }

    /// Empty list: a quiet glyph, or "Syncing…" only before the first sync has landed
    /// (the 15s poll must not flicker an empty list). With no vault and an error, say
    /// why and offer the way back to sign-in.
    @ViewBuilder
    private func emptyRow(list: ListName) -> some View {
        ListEmptyPlaceholder(
            model: model,
            listTitle: list.title,
            systemImage: listImage(list)
        ) {
            vaultMissingRow
        }
    }

    @ViewBuilder
    private func scheduledSections(colors: DayruleColors) -> some View {
        let scheduled = Lists.scheduled(model.entities, ctx)
        let progress = Self.checklistProgress(model.entities)
        let dayGroups = scheduled.days.filter { !$0.items.isEmpty }
        let monthGroups = scheduled.months.filter { !$0.items.isEmpty }
        if dayGroups.isEmpty, monthGroups.isEmpty, scheduled.waiting.isEmpty {
            emptyRow(list: .scheduled)
        } else {
            // Flat rows (not `Section` headers): a Section under the page title
            // stacked a system top rule on the page-title hairline (double
            // underline). Day number + “Tomorrow”/weekday still read as headers.
            ForEach(dayGroups, id: \.date) { day in
                scheduledDayHeader(day.date, colors: colors)
                ForEach(day.items, id: \.id) { item in
                    listRow(scheduledRow(item, progress: progress), list: .scheduled, colors: colors)
                }
            }
            ForEach(monthGroups, id: \.month) { month in
                DayruleSectionHeader(
                    title: DayruleDateFormat.month(month.month),
                    tone: .accent,
                    style: .caps
                )
                ForEach(month.items, id: \.id) { item in
                    listRow(scheduledRow(item, progress: progress), list: .scheduled, colors: colors)
                }
            }
            if !scheduled.waiting.isEmpty {
                DayruleSectionHeader(title: "Waiting", tone: .accent, style: .caps)
                ForEach(scheduled.waiting, id: \.id) { item in
                    listRow(scheduledRow(item, progress: progress), list: .scheduled, colors: colors)
                }
            }
        }
    }

    /// Day number + weekday (or "Tomorrow") on one baseline — matches web
    /// `pages.tsx` Scheduled (`text-[17px] font-bold` + secondary). Mac plain
    /// Lists ignore `listRowInsets` on these flat headers, so a figure-space
    /// spacer pushes the digit to the circle / title edge.
    private func scheduledDayHeader(_ date: LocalDate, colors: DayruleColors) -> some View {
        let header = DayruleDateFormat.dayHeader(date, today: ctx.today)
        return HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Mac plain List ignores `listRowInsets` / padding / `Color.clear`
                // on this flat header. A figure-space frame is the spacer that
                // retains width; tuned so digit ink meets the title / circle edge.
                Text(verbatim: "\u{2007}")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: Tokens.macScheduledDayLeading, alignment: .leading)
                    .accessibilityHidden(true)
                Text(header.primary)
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(colors.accent)
                    .accessibilityAddTraits(.isHeader)
            }
            if let secondary = header.secondary {
                Text(secondary)
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Tokens.Space.m)
        .padding(.bottom, Tokens.Space.s)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(
            DayrulePaperRowBackground(
                fill: colors.bg,
                hairline: colors.hairline,
                showsHairline: true
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            header.secondary.map { "\(header.primary) \($0)" } ?? header.primary
        )
    }

    private func scheduledRow(_ item: ListItem, progress: [ID: (done: Int, total: Int)]) -> Row {
        if item.isTodo, let t = model.entities.todos[item.id] {
            return todoRow(t, subtitle: nil, trailing: nil, overdue: false, progress: progress)
        }
        return Row(
            id: item.id,
            title: item.title,
            subtitle: nil,
            isTodo: false,
            status: item.status
        )
    }

    private var vaultMissingRow: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        return RuledRow(style: .note) {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Text(model.errorMessage ?? "Sign in again")
                    .font(.footnote)
                    .foregroundStyle(colors.deadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sign in") {
                    model.showSignInGate()
                }
                .buttonStyle(.dayruleLink)
                .fontWeight(.semibold)
                .accessibilityIdentifier("list.signInAgain")
            }
            .padding(.vertical, Tokens.Space.s)
        }
    }

    /// Local vault works offline; sync needs a Bearer session (password sign-in).
    @ViewBuilder
    private func syncSignInBanner(colors: DayruleColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On this device only")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.text)
            Text("Changes stay here until you sign in with your password. \(model.biometryLabel) unlocks your lists but does not connect to the server.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign in to sync") {
                model.showSignInGate()
            }
            .buttonStyle(.dayruleLink)
            .fontWeight(.semibold)
            .accessibilityIdentifier("list.signInToSync")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func backlogSections(colors: DayruleColors) -> some View {
        let main = rows(for: .backlog)
        let parked = rows(for: .notNow)
        if main.isEmpty, parked.isEmpty {
            emptyRow(list: .backlog)
        } else {
            let mainPeers = main.filter(\.isTodo).map(\.id)
            ForEach(main, id: \.id) { row in
                reorderableListRow(row, list: .backlog, colors: colors, peers: mainPeers)
            }
            .onMove { source, destination in
                moveTodos(peers: mainPeers, source: source, destination: destination, list: .backlog)
            }
            .moveDisabled(selecting)
            if !parked.isEmpty {
                let parkedPeers = parked.filter(\.isTodo).map(\.id)
                Section {
                    ForEach(parked, id: \.id) { row in
                        reorderableListRow(row, list: .notNow, colors: colors, peers: parkedPeers)
                    }
                    .onMove { source, destination in
                        moveTodos(
                            peers: parkedPeers,
                            source: source,
                            destination: destination,
                            list: .notNow
                        )
                    }
                    .moveDisabled(selecting)
                } header: {
                    DayruleSectionHeader(title: "Not now", tone: .later, style: .caps)
                }
            }
        }
    }

    private func rowModel(_ row: Row, list: ListName) -> TodoRowModel {
        TodoRowModel(
            id: row.id,
            title: row.title,
            // Trash rows get no live checkbox.
            status: row.isTodo && list != .trash ? row.status : nil,
            // Due dates use trailing chips (Today + Inbox); other lists keep subtitles.
            subtitle: (list == .today || list == .inbox) ? nil : row.subtitle,
            subtitleIsOverdue: row.deadlineOverdue,
            hasReminder: row.hasReminder,
            repeats: row.isRepeating,
            hasNotes: row.hasNotes,
            checklist: row.checklist,
            chip: row.trailing.map { trailing in
                TodoRowModel.Chip(
                    label: trailing.label,
                    systemImage: trailing.systemImage,
                    isOverdue: trailing.isOverdue
                )
            },
            openHint: list == .trash ? nil : (row.isTodo ? "Opens to-do" : "Opens project")
        )
    }

    private func rowActions(_ row: Row, list: ListName) -> [RowAction] {
        if list == .trash {
            return [RowAction(name: "Restore") { restore(row.id) }]
        }
        var actions: [RowAction] = []
        if list != .trash, row.isTodo {
            actions.append(RowAction(name: "Select") { beginSelecting(row.id) })
        }
        actions += [
            RowAction(name: "When…") { whenTarget = WhenTarget(ids: [row.id]) },
            RowAction(name: "Deadline…") { deadlineTarget = WhenTarget(ids: [row.id]) },
            RowAction(name: "Tags…") { tagTarget = WhenTarget(ids: [row.id]) },
        ]
        if row.isTodo {
            actions += [
                RowAction(name: "Move…") { moveTarget = WhenTarget(ids: [row.id]) },
                RowAction(name: "Repeat…") { repeatTarget = EditTarget(id: row.id) },
                RowAction(name: "Reminder…") { reminderTarget = EditTarget(id: row.id) },
                RowAction(name: "Move up") { moveTodo(row.id, dir: -1, in: list) },
                RowAction(name: "Move down") { moveTodo(row.id, dir: 1, in: list) },
            ]
        }
        actions.append(RowAction(name: "Trash") { trash(row.id, title: row.title) })
        return actions
    }

    private func openRow(_ row: Row, list: ListName) {
        guard list != .trash else { return }
        if selecting {
            guard row.isTodo else { return }
            toggleSelected(row.id)
            return
        }
        if !row.isTodo, model.entities.projects[row.id] != nil {
            openProject(row.id)
        } else {
            editTarget = EditTarget(id: row.id)
        }
    }

    /// Drag / drop / onMove reorder for to-do rows (PLAN §6.5; web long-press then drag).
    @ViewBuilder
    private func reorderableListRow(
        _ row: Row,
        list: ListName,
        colors: DayruleColors,
        peers: [ID]
    ) -> some View {
        let canDrag = !selecting && row.isTodo && ListReorder.allowsDrag(in: list) && peers.contains(row.id)
        if canDrag {
            listRow(row, list: list, colors: colors)
                .draggable(row.id) {
                    Text(row.title.isEmpty ? "Untitled" : row.title)
                        .font(DayruleType.rowTitle(dense: true))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(colors.bg)
                        .overlay(Rectangle().strokeBorder(colors.hairline, lineWidth: 1))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let from = items.first else { return false }
                    return dropTodo(dragging: from, onto: row.id, peers: peers, list: list)
                }
        } else {
            listRow(row, list: list, colors: colors)
                .moveDisabled(true)
        }
    }

    @ViewBuilder
    private func listRow(_ row: Row, list: ListName, colors: DayruleColors) -> some View {
        DayruleTodoRow(
            model: rowModel(row, list: list),
            identifier: "list.todo.\(row.id)",
            onToggle: {
                if selecting, row.isTodo {
                    toggleSelected(row.id)
                } else {
                    toggleComplete(row.id, title: row.title)
                }
            },
            onOpen: { openRow(row, list: list) },
            onChip: row.trailing == nil ? nil : { whenTarget = WhenTarget(ids: [row.id]) },
            isSelected: selecting && selectedIds.contains(row.id),
            selecting: selecting,
            accessibilityActions: rowActions(row, list: list)
        )
        .equatable()
        .opacity(model.linger.fading.contains(row.id) ? 0 : 1)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if list == .trash {
                Button {
                    restore(row.id)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(colors.ready)
            } else if row.isTodo {
                Button {
                    whenTarget = WhenTarget(ids: [row.id])
                } label: {
                    Label("When", systemImage: "calendar")
                }
                .tint(colors.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            if list != .trash, row.isTodo, !selecting {
                Button {
                    beginSelecting(row.id)
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .tint(colors.textSecondary)
            }
        }
        .contextMenu {
            rowContextMenu(row, list: list)
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ row: Row, list: ListName) -> some View {
        if list == .trash {
            Button {
                restore(row.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        } else {
            Section {
                if !row.isTodo, model.entities.projects[row.id] != nil {
                    Button {
                        openProject(row.id)
                    } label: {
                        Label("Open", systemImage: "arrow.forward.circle")
                    }
                }
                if row.isTodo, let pid = model.entities.todos[row.id]?.projectId {
                    Button {
                        openProject(pid)
                    } label: {
                        Label("Open Project", systemImage: "bookmark")
                    }
                }
                Button {
                    editTarget = EditTarget(id: row.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                if row.isTodo {
                    Button {
                        beginSelecting(row.id)
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                }
            }
            Section {
                Button {
                    whenTarget = WhenTarget(ids: [row.id])
                } label: {
                    Label("When…", systemImage: "calendar")
                }
                Button {
                    deadlineTarget = WhenTarget(ids: [row.id])
                } label: {
                    Label("Deadline…", systemImage: "flag")
                }
                Button {
                    tagTarget = WhenTarget(ids: [row.id])
                } label: {
                    Label("Tags…", systemImage: "tag")
                }
                if row.isTodo {
                    Button {
                        moveTarget = WhenTarget(ids: [row.id])
                    } label: {
                        Label("Move…", systemImage: "arrow.right.square")
                    }
                    Button {
                        repeatTarget = EditTarget(id: row.id)
                    } label: {
                        Label("Repeat…", systemImage: "repeat")
                    }
                    Button {
                        reminderTarget = EditTarget(id: row.id)
                    } label: {
                        Label("Reminder…", systemImage: "bell")
                    }
                }
            }
            if row.isTodo {
                Section {
                    if row.status == .open {
                        Button {
                            toggleComplete(row.id, title: row.title)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                        }
                        Button {
                            cancelTodo(row.id, title: row.title)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            toggleComplete(row.id, title: row.title)
                        } label: {
                            Label("Reopen", systemImage: "circle")
                        }
                    }
                    Button {
                        convertTodoToProject(row.id, title: row.title)
                    } label: {
                        Label("Convert to Project", systemImage: "bookmark")
                    }
                }
            }
            Button(role: .destructive) {
                trash(row.id, title: row.title)
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    private func convertTodoToProject(_ id: ID, title: String) {
        do {
            let project = try model.store.run("Convert to Project") { d, env in
                try Commands.convertTodoToProject(d, env, todoId: id)
            }
            model.noteEntitiesChanged()
            model.undoNotice("Converted \(title) to a project")
            openProject(project.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func openProject(_ id: ID) {
        if isCompact {
            phonePath.append(.project(id))
        } else {
            orgPath = [.project(id)]
        }
    }

    private func openArea(_ id: ID) {
        if isCompact {
            if phoneTab != .browse {
                selectTab(.browse, path: [.area(id)])
            } else {
                phonePath.append(.area(id))
            }
        } else {
            orgPath = [.area(id)]
        }
    }

    private func addProject(areaId: ID? = nil) {
        do {
            let project = try model.store.run("New Project") { d, env in
                try Commands.createProject(d, env, title: "", areaId: areaId)
            }
            model.noteEntitiesChanged()
            openProject(project.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func addArea() {
        do {
            let area = try model.store.run("New Area") { d, env in
                try Commands.createArea(d, env, title: "")
            }
            model.noteEntitiesChanged()
            openArea(area.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    /// `keepVisible` holds just-completed rows in place for the linger (PLAN §6.4).
    private var ctx: Lists.Context {
        Lists.Context(today: When.toLocalDate(Date()), keepVisible: model.linger.keepVisible)
    }

    private var counts: Lists.SidebarCounts { cachedSidebarCounts }

    private var trashCount: Int { cachedTrashCount }

    private func refreshSidebarCache() {
        let e = model.entities
        let context = ctx
        cachedSidebarCounts = Lists.sidebarCounts(e, context)
        cachedBrowseTree = Lists.browseTree(e)
        let trash = Lists.trash(e)
        cachedTrashCount = trash.areas.count + trash.items.count
        let backlogMain = Lists.backlog(e, context).reduce(0) { $0 + $1.todos.count }
        let parked = Lists.notNow(e, context)
        cachedBacklogCount = backlogMain + parked.todos.count + parked.projects.count
        cachedDoneCount = Lists.doneList(e, context).reduce(0) { $0 + $1.items.count }
    }

    private func badge(for name: ListName) -> Int? {
        let count: Int
        switch name {
        case .inbox: count = counts.inbox
        case .today: count = counts.today
        case .done, .trash: count = browseCount(for: name) ?? 0
        default: return nil
        }
        return count > 0 ? count : nil
    }

    private func rows(for name: ListName) -> [Row] {
        let progress = Self.checklistProgress(model.entities)
        switch name {
        case .inbox:
            return Lists.inbox(model.entities, ctx).map {
                // Trailing due chip (same layout as Today) — a deadline subtitle
                // made Inbox rows taller than Today’s single-line + chip rows.
                todoRow(
                    $0,
                    subtitle: nil,
                    trailing: inboxTrailing(for: $0),
                    overdue: Lists.isOverdue(.todo($0), ctx),
                    progress: progress
                )
            }
        case .today:
            return Lists.today(model.entities, ctx).map {
                let trailing = todayTrailing(for: $0)
                let kind = $0.isTodo ? nil : "Project"
                if $0.isTodo, let t = model.entities.todos[$0.id] {
                    return todoRow(
                        t,
                        subtitle: kind,
                        trailing: trailing,
                        overdue: Lists.isOverdue($0, ctx),
                        progress: progress
                    )
                }
                return Row(
                    id: $0.id,
                    title: $0.title,
                    subtitle: kind,
                    isTodo: false,
                    status: $0.status,
                    deadlineOverdue: Lists.isOverdue($0, ctx),
                    trailing: trailing
                )
            }
        case .scheduled:
            // Prefer `scheduledSections`; this path is unused for phone listDetail.
            return Lists.scheduled(model.entities, ctx).days.flatMap { day in
                day.items.map { scheduledRow($0, progress: progress) }
            }
        case .backlog:
            return Lists.backlog(model.entities, ctx).flatMap { g in
                g.todos.map {
                    todoRow(
                        $0,
                        subtitle: containerLabel(g.container),
                        trailing: nil,
                        overdue: false,
                        progress: progress
                    )
                }
            }
        case .notNow:
            let n = Lists.notNow(model.entities, ctx)
            return n.projects.map {
                Row(id: $0.id, title: $0.title, subtitle: "Project", isTodo: false, status: $0.status)
            } + n.todos.map {
                todoRow($0, subtitle: nil, trailing: nil, overdue: false, progress: progress)
            }
        case .done:
            return Lists.doneList(model.entities, ctx).flatMap { day in
                let when = DayruleDateFormat.relative(day.date, today: ctx.today)
                return day.items.map {
                    if $0.isTodo, let t = model.entities.todos[$0.id] {
                        return todoRow(t, subtitle: when, trailing: nil, overdue: false, progress: progress)
                    }
                    return Row(id: $0.id, title: $0.title, subtitle: when, isTodo: false, status: $0.status)
                }
            }
        case .trash:
            let t = Lists.trash(model.entities)
            return t.areas.map {
                Row(id: $0.id, title: $0.title, subtitle: "Area", isTodo: false, status: .open)
            } + t.items.map {
                if $0.isTodo, let todo = model.entities.todos[$0.id] {
                    return todoRow(todo, subtitle: nil, trailing: nil, overdue: false, progress: progress)
                }
                return Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: $0.isTodo, status: $0.status)
            }
        }
    }

    /// One pass over checklist items for a list snapshot (avoids per-row filters).
    private static func checklistProgress(_ e: Entities) -> [ID: (done: Int, total: Int)] {
        var map: [ID: (done: Int, total: Int)] = [:]
        map.reserveCapacity(min(e.checklistItems.count, e.todos.count))
        for item in e.checklistItems.values {
            var entry = map[item.todoId, default: (done: 0, total: 0)]
            entry.total += 1
            if item.done { entry.done += 1 }
            map[item.todoId] = entry
        }
        return map
    }

    private func todayTrailing(for item: ListItem) -> TrailingChip? {
        if Lists.isOverdue(item, ctx) {
            return TrailingChip(systemImage: "clock", label: overdueLabel(deadline: item.deadline), isOverdue: true)
        }
        if let start = item.startDate, start < ctx.today {
            return TrailingChip(systemImage: "clock", label: overdueLabel(startDate: start), isOverdue: true)
        }
        if item.startDate == ctx.today || item.deadline == ctx.today {
            return TrailingChip(systemImage: "calendar", label: "Today", isOverdue: false)
        }
        if item.deadline != nil {
            return TrailingChip(systemImage: "calendar", label: "Today", isOverdue: false)
        }
        return TrailingChip(systemImage: "calendar", label: "Today", isOverdue: false)
    }

    /// Inbox: only show a chip when there is a due date (no perpetual “Today”).
    private func inboxTrailing(for todo: Todo) -> TrailingChip? {
        guard let deadline = todo.deadline else { return nil }
        if Lists.isOverdue(.todo(todo), ctx) {
            return TrailingChip(
                systemImage: "clock",
                label: overdueLabel(deadline: deadline),
                isOverdue: true
            )
        }
        return TrailingChip(
            systemImage: "calendar",
            label: DayruleDateFormat.due(deadline, today: ctx.today),
            isOverdue: false
        )
    }

    private func overdueLabel(deadline: LocalDate? = nil, startDate: LocalDate? = nil) -> String {
        let anchor = deadline ?? startDate
        guard let anchor, let past = When.fromLocalDate(anchor) else { return "Overdue" }
        let hours = max(1, Int(Date().timeIntervalSince(past) / 3600))
        if hours < 48 { return "\(hours)h overdue" }
        let days = max(1, hours / 24)
        return "\(days)d overdue"
    }

    private func todoRow(
        _ todo: Todo,
        subtitle: String?,
        trailing: TrailingChip?,
        overdue: Bool,
        progress: [ID: (done: Int, total: Int)]
    ) -> Row {
        let checklist = progress[todo.id]
        return Row(
            id: todo.id,
            title: todo.title.isEmpty ? "Untitled" : todo.title,
            subtitle: subtitle,
            isTodo: true,
            status: todo.status,
            deadlineOverdue: overdue,
            hasReminder: todo.reminderAt != nil,
            isRepeating: todo.repeat != nil || todo.repeatTemplateId != nil,
            hasNotes: !todo.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            checklist: checklist.flatMap { $0.total > 0 ? $0 : nil },
            trailing: trailing
        )
    }

    private func addTodo(to list: ListName, title raw: String) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        // Use the list on screen, not `selection` — on phone those can diverge.
        do {
            let todo = try model.store.run("Add") { d, env in
                switch list {
                case .today:
                    return try Commands.createTodo(d, env, .init(title: title, placement: .today))
                case .backlog:
                    return try Commands.createTodo(d, env, .init(title: title, placement: .ready))
                case .scheduled:
                    let todo = try Commands.createTodo(d, env, .init(title: title, placement: .ready))
                    let tomorrow = When.addLocalDays(env.today, 1)
                    try Commands.setWhen(d, env, ids: [todo.id], when: .date(tomorrow))
                    return todo
                default:
                    return try Commands.createTodo(d, env, .init(title: title, placement: .inbox))
                }
            }
            addDrafts.clear(list)
            model.noteEntitiesChanged()
            model.bumpHaptic(\.add)
            // Scheduled defaults to tomorrow; open When so the date is choosable. Wait a
            // runloop so the Add field resigns before the sheet takes focus.
            if list == .scheduled {
                let id = todo.id
                Task { @MainActor in
                    whenTarget = WhenTarget(ids: [id])
                }
            }
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    /// Keyboard / VoiceOver reorder (web `useGlobalKeys` Move).
    private func moveTodo(_ id: ID, dir: Int, in list: ListName) {
        let visible = rows(for: list).filter(\.isTodo).map(\.id)
        guard let i = visible.firstIndex(of: id) else { return }
        // SwiftUI onMove `destination` is the pre-move insertion index.
        let destination = i + dir + (dir > 0 ? 1 : 0)
        guard destination >= 0, destination <= visible.count,
              let neighbours = ListReorder.neighbours(
                  peers: visible,
                  source: IndexSet(integer: i),
                  destination: destination
              )
        else { return }
        applyTodoReorder(
            id: neighbours.id,
            before: neighbours.before,
            after: neighbours.after,
            list: list
        )
    }

    private func moveTodos(peers: [ID], source: IndexSet, destination: Int, list: ListName) {
        guard !selecting, ListReorder.allowsDrag(in: list),
              let neighbours = ListReorder.neighbours(
                  peers: peers,
                  source: source,
                  destination: destination
              )
        else { return }
        applyTodoReorder(
            id: neighbours.id,
            before: neighbours.before,
            after: neighbours.after,
            list: list
        )
    }

    @discardableResult
    private func dropTodo(dragging: ID, onto: ID, peers: [ID], list: ListName) -> Bool {
        guard !selecting, ListReorder.allowsDrag(in: list),
              let neighbours = ListReorder.neighbours(peers: peers, dragging: dragging, onto: onto)
        else { return false }
        applyTodoReorder(id: dragging, before: neighbours.before, after: neighbours.after, list: list)
        return true
    }

    private func applyTodoReorder(id: ID, before: ID?, after: ID?, list: ListName) {
        do {
            try model.store.run("Reorder") { d, env in
                try Commands.reorder(
                    d,
                    env,
                    collection: .todos,
                    id: id,
                    field: ListReorder.orderField(for: list),
                    before: before,
                    after: after
                )
            }
            model.noteEntitiesChanged()
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func beginSelecting(_ id: ID) {
        selecting = true
        selectedIds = [id]
        AccessibilityNotification.Announcement("1 selected").post()
    }

    private func exitSelecting() {
        guard selecting || !selectedIds.isEmpty else { return }
        selecting = false
        selectedIds = []
    }

    private func toggleSelected(_ id: ID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        if selectedIds.isEmpty {
            selecting = false
        }
        let n = selectedIds.count
        AccessibilityNotification.Announcement(n == 0 ? "Selection cleared" : "\(n) selected").post()
    }

    private func completeSelection() {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return }
        model.store.run("Complete") { d, env in
            Commands.setStatus(d, env, ids: ids, status: .completed)
        }
        for id in ids { model.linger.hold(id) }
        model.noteEntitiesChanged()
        model.undoNotice(ids.count == 1 ? "Completed 1 to-do" : "Completed \(ids.count) to-dos")
        exitSelecting()
    }

    private func trashSelection() {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return }
        model.store.run("Trash") { d, env in
            Commands.trashItems(d, env, ids: ids)
        }
        model.noteEntitiesChanged()
        model.bumpHaptic(\.trash)
        model.undoNotice(ids.count == 1 ? "Moved 1 to-do to Trash" : "Moved \(ids.count) to-dos to Trash")
        exitSelecting()
    }

    private func toggleComplete(_ id: ID, title: String) {
        let open = model.entities.todos[id]?.status == .open
            || model.entities.projects[id]?.status == .open
        let status: Status = open ? .completed : .open
        model.store.run(status == .completed ? "Complete" : "Reopen") { d, env in
            Commands.setStatus(d, env, ids: [id], status: status)
        }
        // Hold the row so the pop and tick are seen before it folds away (PLAN §6.4).
        if status == .completed {
            model.linger.hold(id)
        } else {
            model.linger.release(id)
        }
        model.noteEntitiesChanged()
        if status == .completed {
            // The notice also announces it: the linger is too short for VoiceOver (PLAN §6.7).
            model.undoNotice("Completed \(title)")
        }
    }

    private func cancelTodo(_ id: ID, title: String) {
        model.store.run("Cancel") { d, env in
            Commands.setStatus(d, env, ids: [id], status: .canceled)
        }
        model.linger.hold(id)
        model.noteEntitiesChanged()
        model.undoNotice("Canceled \(title)")
    }

    private func trash(_ id: ID, title: String) {
        model.store.run("Trash") { d, env in
            Commands.trashItems(d, env, ids: [id])
        }
        model.noteEntitiesChanged()
        model.bumpHaptic(\.trash)
        model.undoNotice("Moved \(title) to Trash")
    }

    private func restore(_ id: ID) {
        model.store.run("Restore") { d, env in
            Commands.restoreItems(d, env, ids: [id])
        }
        model.noteEntitiesChanged()
    }

    private func emptyTrash() {
        model.store.run("Empty Trash") { d, _ in
            Commands.emptyTrash(d)
        }
        model.noteEntitiesChanged()
        model.undoNotice("Emptied Trash")
    }

    private func logCompleted() {
        model.moveToDoneNow()
        model.undoNotice("Moved completed to-dos to Done")
    }

    private func applyPendingFind() {
        guard let result = pendingFind else { return }
        pendingFind = nil
        applyFind(result)
    }

    private func applyFind(_ result: Find.Result) {
        switch result.destination {
        case .list(let name):
            selection = name
            orgPath = []
            if isCompact { navigatePhone(to: name) }
        case .todo(let id, let home):
            selection = home
            orgPath = []
            if isCompact { navigatePhone(to: home) }
            editTarget = EditTarget(id: id)
        case .project(let id):
            orgPath = isCompact ? [] : [.project(id)]
            if isCompact {
                selectTab(.browse, path: [.project(id)])
            }
        case .area(let id):
            orgPath = isCompact ? [] : [.area(id)]
            if isCompact {
                selectTab(.browse, path: [.area(id)])
            }
        }
    }

    private func navigatePhone(to name: ListName) {
        if let tab = PhoneTab.tab(for: name) {
            selectTab(tab)
        } else {
            // Not now lives inside Backlog on phone.
            let dest: ListName = name == .notNow ? .backlog : name
            selectTab(.browse, path: [.list(dest)])
        }
    }

    private func containerLabel(_ c: Lists.Container) -> String? {
        switch c {
        case .none: nil
        case .area(let a): a.title
        case .project(let p): p.title
        }
    }

    private struct TrailingChip: Equatable {
        var systemImage: String
        var label: String
        var isOverdue: Bool
    }

    private struct Row: Identifiable {
        var id: ID
        var title: String
        var subtitle: String?
        var isTodo: Bool
        var status: Status
        var deadlineOverdue: Bool = false
        var hasReminder: Bool = false
        var isRepeating: Bool = false
        var hasNotes: Bool = false
        var checklist: (done: Int, total: Int)?
        var trailing: TrailingChip?
    }
}

/// Per-list Add drafts. Observed only by `PinnedListAddBar` so keystrokes don’t
/// invalidate `ListsBrowserView` and re-run list selectors (perf review #1).
@Observable
@MainActor
final class ListAddDrafts {
    private var titles: [ListName: String] = [:]

    func title(for list: ListName) -> String {
        titles[list] ?? ""
    }

    func setTitle(_ value: String, for list: ListName) {
        if value.isEmpty {
            titles[list] = nil
        } else {
            titles[list] = value
        }
    }

    func clear(_ list: ListName) {
        titles[list] = nil
    }

    func binding(for list: ListName) -> Binding<String> {
        Binding(
            get: { self.title(for: list) },
            set: { self.setTitle($0, for: list) }
        )
    }
}

/// List-scoped draft Observation bridge into `PinnedPaperAddBar` (decision 64 / 76).
private struct PinnedListAddBar: View {
    @Bindable var drafts: ListAddDrafts
    var list: ListName
    var colors: DayruleColors
    var focusNonce: Int
    var keepFocusAfterSubmit: Bool
    var onSubmit: (String) -> Void

    var body: some View {
        PinnedPaperAddBar(
            title: drafts.binding(for: list),
            colors: colors,
            focusNonce: focusNonce,
            keepFocusAfterSubmit: keepFocusAfterSubmit
        ) {
            onSubmit(drafts.title(for: list))
        }
    }
}
