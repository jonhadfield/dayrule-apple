import Foundation

/// Quick Find (web `domain/find.ts`, PLAN §5 / M5). In-memory over decrypted entities.
enum Find {
    enum Kind: String, Sendable, Equatable {
        case list, project, area, todo
    }

    /// Where to jump in the native shell (paths on web become list selection / editor).
    enum Destination: Equatable, Sendable {
        case list(ListName)
        case project(ID)
        case area(ID)
        case todo(ID, home: ListName)
    }

    struct Result: Equatable, Sendable, Identifiable {
        var id: String
        var kind: Kind
        var title: String
        var detail: String
        var destination: Destination
        var todoId: ID?
    }

    struct Finder: Sendable {
        private let docs: [Doc]
        private let byId: [String: Doc]

        fileprivate init(docs: [Doc]) {
            self.docs = docs
            self.byId = Dictionary(uniqueKeysWithValues: docs.map { ($0.id, $0) })
        }

        func search(_ query: String) -> [Result] {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return [] }
            let terms = q.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            guard !terms.isEmpty else { return [] }

            var scored: [(Result, Double)] = []
            for doc in docs {
                guard let score = scoreDoc(doc, terms: terms) else { continue }
                scored.append((doc.asResult, score * kindBoost(doc.kind)))
            }
            scored.sort { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.id < b.0.id
            }
            return scored.prefix(30).map(\.0)
        }

        private func kindBoost(_ kind: Kind) -> Double {
            switch kind {
            case .list: 1.6
            case .area, .project: 1.3
            case .todo: 1
            }
        }

        /// Field boosts match MiniSearch defaults used on web (text 3, tags 1.5, notes 1).
        private func scoreDoc(_ doc: Doc, terms: [String]) -> Double? {
            var total = 0.0
            for term in terms {
                let textHit = bestTermScore(term, in: doc.text) * 3
                let tagsHit = bestTermScore(term, in: doc.tags) * 1.5
                let notesHit = bestTermScore(term, in: doc.notes)
                let best = max(textHit, tagsHit, notesHit)
                if best <= 0 { return nil } // AND
                total += best
            }
            return total
        }

        private func bestTermScore(_ term: String, in field: String) -> Double {
            guard !field.isEmpty else { return 0 }
            let words = field.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            var best = 0.0
            for word in words {
                if word.hasPrefix(term) {
                    best = max(best, 1.0)
                    continue
                }
                let maxDist = Int(floor(Double(term.count) * 0.2))
                if maxDist > 0 {
                    let d = levenshtein(term, word)
                    if d <= maxDist {
                        best = max(best, 1.0 - Double(d) / Double(max(term.count, 1)))
                    }
                }
            }
            // Also allow the whole field as one token (titles with spaces already split).
            if field.lowercased().hasPrefix(term) {
                best = max(best, 1.0)
            }
            return best
        }
    }

    static func buildFinder(_ e: Entities, _ ctx: Lists.Context) -> Finder {
        var docs: [Doc] = []
        for list in ListName.allCases {
            docs.append(Doc(
                id: "list:\(list.rawValue)",
                kind: .list,
                title: list.title,
                detail: "List",
                destination: .list(list),
                todoId: nil,
                text: list.title,
                notes: "",
                tags: ""
            ))
        }
        for a in e.areas.values where a.trashedAt == nil {
            docs.append(Doc(
                id: "area:\(a.id)",
                kind: .area,
                title: a.title.isEmpty ? "Untitled area" : a.title,
                detail: "Area",
                destination: .area(a.id),
                todoId: nil,
                text: a.title,
                notes: "",
                tags: ""
            ))
        }
        for p in e.projects.values where !Lists.isTrashed(e, .project(p)) {
            let area = p.areaId.flatMap { e.areas[$0] }
            let detail = area.map { "Project in \($0.title.isEmpty ? "Untitled area" : $0.title)" } ?? "Project"
            docs.append(Doc(
                id: "project:\(p.id)",
                kind: .project,
                title: p.title.isEmpty ? "Untitled project" : p.title,
                detail: detail,
                destination: .project(p.id),
                todoId: nil,
                text: p.title,
                notes: p.notes,
                tags: p.tagIds.compactMap { e.tags[$0]?.title }.joined(separator: " ")
            ))
        }
        for t in e.todos.values {
            let home = homeOf(e, t, ctx)
            docs.append(Doc(
                id: "todo:\(t.id)",
                kind: .todo,
                title: t.title.isEmpty ? "Untitled" : t.title,
                detail: home.label,
                destination: .todo(t.id, home: home.list),
                todoId: t.id,
                text: t.title,
                notes: t.notes,
                tags: t.tagIds.compactMap { e.tags[$0]?.title }.joined(separator: " ")
            ))
        }
        return Finder(docs: docs)
    }

    struct Home: Equatable, Sendable {
        var list: ListName
        var label: String
    }

    /// The list a to-do shows up in (web `homeOf`).
    static func homeOf(_ e: Entities, _ t: Todo, _ ctx: Lists.Context) -> Home {
        if Lists.isTrashed(e, .todo(t)) { return Home(list: .trash, label: "Trash") }
        if t.repeat != nil { return Home(list: .scheduled, label: "Repeating") }
        if Lists.isInDone(e, .todo(t), ctx) { return Home(list: .done, label: "Done") }
        if let project = Lists.projectOf(e, t) {
            return Home(list: .backlog, label: project.title.isEmpty ? "Untitled project" : project.title)
        }
        if let areaId = t.areaId, let area = e.areas[areaId] {
            return Home(list: .backlog, label: area.title.isEmpty ? "Untitled area" : area.title)
        }
        let start = Lists.effectiveStart(e, .todo(t))
        if start == .inbox { return Home(list: .inbox, label: "Inbox") }
        if start == .later { return Home(list: .notNow, label: "Not now") }
        let due =
            (t.startDate.map { $0 <= ctx.today } ?? false)
            || (t.deadline.map { $0 <= ctx.today } ?? false)
        if due { return Home(list: .today, label: "Today") }
        if t.startDate != nil { return Home(list: .scheduled, label: "Scheduled") }
        return Home(list: .backlog, label: "Backlog")
    }

    // MARK: - Internals

    fileprivate struct Doc: Sendable {
        var id: String
        var kind: Kind
        var title: String
        var detail: String
        var destination: Destination
        var todoId: ID?
        var text: String
        var notes: String
        var tags: String

        var asResult: Result {
            Result(
                id: id,
                kind: kind,
                title: title,
                detail: detail,
                destination: destination,
                todoId: todoId
            )
        }
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}

/// List names shared with the sidebar (kept fileprivate in ListsBrowserView before;
/// Find needs the same vocabulary).
enum ListName: String, CaseIterable, Hashable, Sendable {
    case inbox, today, scheduled, backlog, notNow, done, trash

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .backlog: "Backlog"
        case .notNow: "Not now"
        case .done: "Done"
        case .trash: "Trash"
        }
    }
}
