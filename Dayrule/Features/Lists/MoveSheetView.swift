import SwiftUI

/// Move to-dos to Inbox, no project/area, an area, or a project (web `MovePicker`).
struct MoveSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayruleSheet(title: "Move", size: .tall, detents: [.medium, .large]) {
            List {
                Section {
                    moveRow(
                        title: "Inbox",
                        systemImage: "tray",
                        tint: colors.textSecondary,
                        selected: isSelected(.inbox),
                        colors: colors
                    ) { apply(.inbox) }
                    moveRow(
                        title: "No project or area",
                        systemImage: "checklist",
                        tint: colors.ready,
                        selected: isSelected(.none),
                        colors: colors
                    ) { apply(.none) }
                }
                if !orphanProjects.isEmpty || !liveAreas.isEmpty {
                    Section {
                        ForEach(orphanProjects, id: \.id) { project in
                            projectRow(project, indent: false, colors: colors)
                        }
                        ForEach(liveAreas, id: \.id) { area in
                            moveRow(
                                title: area.title.isEmpty ? "Untitled" : area.title,
                                systemImage: "shippingbox",
                                tint: colors.textSecondary,
                                selected: isSelected(.area(areaId: area.id)),
                                colors: colors
                            ) { apply(.area(areaId: area.id)) }
                            ForEach(projects(in: area.id), id: \.id) { project in
                                projectRow(project, indent: true, colors: colors)
                            }
                        }
                    } header: {
                        DayruleSectionHeader(title: "Projects and areas")
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var liveAreas: [Area] {
        model.entities.areas.values
            .filter { $0.trashedAt == nil }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }
    }

    private var orphanProjects: [Project] {
        let areas = model.entities.areas
        return model.entities.projects.values
            .filter { project in
                guard project.trashedAt == nil, project.status == .open else { return false }
                guard let areaId = project.areaId else { return true }
                guard let area = areas[areaId] else { return true }
                return area.trashedAt != nil
            }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }
    }

    private func projects(in areaId: ID) -> [Project] {
        model.entities.projects.values
            .filter { $0.areaId == areaId && $0.trashedAt == nil && $0.status == .open }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }
    }

    private func isSelected(_ target: Commands.MoveTarget) -> Bool {
        guard ids.count == 1, let id = ids.first, let todo = model.entities.todos[id] else {
            return false
        }
        switch target {
        case .inbox:
            return todo.start == .inbox && todo.projectId == nil && todo.areaId == nil
        case .none:
            return todo.start != .inbox && todo.projectId == nil && todo.areaId == nil
        case let .area(areaId):
            return todo.areaId == areaId && todo.projectId == nil
        case let .project(projectId, headingId):
            return todo.projectId == projectId && todo.headingId == headingId
        }
    }

    private func projectRow(_ project: Project, indent: Bool, colors: DayruleColors) -> some View {
        let progress = Lists.projectProgress(model.entities, project.id)
        return Button {
            apply(.project(projectId: project.id))
        } label: {
            HStack(spacing: Tokens.Space.s) {
                if indent {
                    Color.clear.frame(width: Tokens.Space.l)
                }
                ProjectProgressGlyph(progress: progress)
                Text(project.title.isEmpty ? "Untitled" : project.title)
                    .foregroundStyle(colors.text)
                Spacer()
                if isSelected(.project(projectId: project.id)) {
                    SelectionCheckmark()
                }
            }
            .frame(minHeight: Tokens.rowHeight)
        }
        .buttonStyle(.dayruleRow)
        .accessibilityAddTraits(isSelected(.project(projectId: project.id)) ? .isSelected : [])
        .accessibilityIdentifier("move.project.\(project.id)")
        .dayruleSheetRow(colors: colors)
    }

    private func moveRow(
        title: String,
        systemImage: String,
        tint: Color,
        selected: Bool,
        colors: DayruleColors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                Spacer()
                if selected {
                    SelectionCheckmark()
                }
            }
            .frame(minHeight: Tokens.rowHeight)
        }
        .buttonStyle(.dayruleRow)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .dayruleSheetRow(colors: colors)
    }

    private func apply(_ target: Commands.MoveTarget) {
        do {
            try model.store.run("Move") { d, env in
                try Commands.moveTodos(d, env, ids: ids, target: target)
            }
            model.noteEntitiesChanged()
            model.undoNotice(undoMessage(for: target))
            dismiss()
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func undoMessage(for target: Commands.MoveTarget) -> String {
        switch target {
        case .inbox: return "Moved to Inbox"
        case .none: return "Removed from project"
        case let .area(areaId):
            let title = model.entities.areas[areaId]?.title
            return title.map { "Moved to \($0)" } ?? "Moved to area"
        case let .project(projectId, _):
            let title = model.entities.projects[projectId]?.title
            return title.map { "Moved to \($0)" } ?? "Moved to project"
        }
    }
}

/// Slim terracotta progress disc used in the Move sheet (web `Progress`).
private struct ProjectProgressGlyph: View {
    var progress: Lists.Progress
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        let fraction = progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total)
        ZStack {
            Circle()
                .stroke(colors.hairline, lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(colors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
