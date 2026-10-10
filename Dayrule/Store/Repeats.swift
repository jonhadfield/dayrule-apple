import Foundation

/// Repeat instance helpers (web `store/repeats.ts`). Full generateRepeats lands with M5 UI.
enum Repeats {
    /// An after-completion instance was done: schedule the template's next.
    static func onInstanceDone(_ d: Draft, _ env: EntityStore.Env, instance: Todo) {
        guard let templateId = instance.repeatTemplateId else { return }
        guard var template = d.getTodo(templateId), var r = template.repeat else { return }
        guard r.mode == .afterCompletion, r.next == nil else { return }
        r.next = RepeatMath.dueAfterCompletion(r, env.today)
        template.repeat = r
        template.updatedAt = ISOStamp.format(env.now)
        d.putTodo(template)
    }
}
