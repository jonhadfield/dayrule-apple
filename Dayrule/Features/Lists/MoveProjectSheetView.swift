import SwiftUI

/// Move a project into an area, or out to the loose list (web `moveProject`).
struct MoveProjectSheetView: View {
    @Bindable var model: AppModel
    let projectId: ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dayruleDenseLayout) private var denseLayout

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        DayruleSheet(title: "Move Project", size: .tall, detents: [.medium, .large]) {
            List {
                Section {
                    row(
                        title: "No area",
                        systemImage: "bookmark",
                        selected: currentAreaId == nil,
                        colors: colors
                    ) { apply(nil) }
                }
                if !liveAreas.isEmpty {
                    Section {
                        ForEach(liveAreas, id: \.id) { area in
                            row(
                                title: area.title.isEmpty ? "New Area" : area.title,
                                systemImage: "shippingbox",
                                selected: currentAreaId == area.id,
                                colors: colors
                            ) { apply(area.id) }
                            .accessibilityIdentifier("moveProject.area.\(area.id)")
                        }
                    } header: {
                        DayruleSectionHeader(title: "Areas", surface: .sheet)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var currentAreaId: ID? {
        model.entities.projects[projectId]?.areaId
    }

    private var liveAreas: [Area] {
        model.entities.areas.values
            .filter { $0.trashedAt == nil }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }
    }

    private func row(
        title: String,
        systemImage: String,
        selected: Bool,
        colors: DayruleColors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 20)
                Text(title)
                Spacer()
                if selected {
                    SelectionCheckmark()
                }
            }
            .frame(minHeight: Tokens.rowMinHeight(dense: denseLayout))
        }
        .buttonStyle(.dayruleRow)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .dayruleSheetRow(colors: colors)
    }

    private func apply(_ areaId: ID?) {
        let raw = model.entities.projects[projectId]?.title ?? ""
        let display = raw.isEmpty ? "Project" : raw
        do {
            try model.store.run("Move Project") { d, env in
                try Commands.moveProject(d, env, id: projectId, areaId: areaId)
            }
            model.noteEntitiesChanged()
            if let areaId {
                let areaTitle = model.entities.areas[areaId]?.title ?? ""
                model.undoNotice(
                    areaTitle.isEmpty
                        ? "Moved \(display) to area"
                        : "Moved \(display) to \(areaTitle)"
                )
            } else {
                model.undoNotice("Moved \(display) out of area")
            }
            dismiss()
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }
}
