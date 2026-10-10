import Foundation

/// Repeat schedule math (web `domain/repeat.ts`, PLAN §4.2).
enum RepeatMath {
    private static var calendar: Calendar { When.calendar }

    /// Monday = 0 … Sunday = 6.
    private static func weekday(_ d: Date) -> Int {
        let wd = calendar.component(.weekday, from: d) // 1=Sun … 7=Sat
        return (wd + 5) % 7
    }

    private static func mondayOf(_ d: Date) -> Date {
        calendar.date(byAdding: .day, value: -weekday(d), to: d)!
    }

    private static func daysInMonth(_ d: Date) -> Int {
        calendar.range(of: .day, in: .month, for: d)!.count
    }

    private static func clampedDay(month: Date, day: Int) -> Date {
        var c = calendar.dateComponents([.year, .month], from: month)
        c.day = min(day, daysInMonth(month))
        return calendar.date(from: c)!
    }

    private static func addMonths(_ d: Date, _ n: Int) -> Date {
        calendar.date(byAdding: .month, value: n, to: d)!
    }

    private static func addYears(_ d: Date, _ n: Int) -> Date {
        calendar.date(byAdding: .year, value: n, to: d)!
    }

    private static func differenceInCalendarDays(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: b), to: calendar.startOfDay(for: a)).day!
    }

    private static func isOccurrence(_ r: RepeatRule, date: Date, anchor: Date) -> Bool {
        if date < calendar.startOfDay(for: anchor) { return false }
        switch r.freq {
        case .day:
            return differenceInCalendarDays(date, anchor) % r.every == 0
        case .week:
            let days = r.weekdays?.isEmpty == false ? r.weekdays! : [weekday(anchor)]
            guard days.contains(weekday(date)) else { return false }
            let weeks = differenceInCalendarDays(mondayOf(date), mondayOf(anchor)) / 7
            return weeks % r.every == 0
        case .month:
            let months =
                (calendar.component(.year, from: date) - calendar.component(.year, from: anchor)) * 12
                + calendar.component(.month, from: date) - calendar.component(.month, from: anchor)
            let expected = clampedDay(month: date, day: calendar.component(.day, from: anchor))
            return months % r.every == 0
                && calendar.component(.day, from: date) == calendar.component(.day, from: expected)
        case .year:
            let years = calendar.component(.year, from: date) - calendar.component(.year, from: anchor)
            let expected = clampedDay(month: date, day: calendar.component(.day, from: anchor))
            return years % r.every == 0
                && calendar.component(.month, from: date) == calendar.component(.month, from: anchor)
                && calendar.component(.day, from: date) == calendar.component(.day, from: expected)
        }
    }

    /// First occurrence of a fixed schedule on or after `from`.
    static func occurrenceOnOrAfter(_ r: RepeatRule, _ from: LocalDate) -> LocalDate {
        guard let anchor = When.fromLocalDate(r.anchor) else { return from }
        var d = When.fromLocalDate(from < r.anchor ? r.anchor : from) ?? anchor
        if r.freq == .month || r.freq == .year {
            let step = r.freq == .month ? 1 : 12
            var start = calendar.date(
                from: DateComponents(
                    year: calendar.component(.year, from: d),
                    month: r.freq == .month
                        ? calendar.component(.month, from: d)
                        : calendar.component(.month, from: anchor),
                    day: 1
                )
            )!
            for i in stride(from: 0, to: 12 * 400, by: step) {
                let month = addMonths(start, i)
                let candidate = clampedDay(month: month, day: calendar.component(.day, from: anchor))
                if candidate >= d && isOccurrence(r, date: candidate, anchor: anchor) {
                    return When.toLocalDate(candidate)
                }
            }
        } else {
            for _ in 0..<(r.every * 7 + 7) {
                if isOccurrence(r, date: d, anchor: anchor) {
                    return When.toLocalDate(d)
                }
                d = calendar.date(byAdding: .day, value: 1, to: d)!
            }
        }
        return from
    }

    static func occurrenceAfter(_ r: RepeatRule, _ date: LocalDate) -> LocalDate {
        occurrenceOnOrAfter(r, When.addLocalDays(date, 1))
    }

    /// For after-completion: due date N units after `done`.
    static func dueAfterCompletion(_ r: RepeatRule, _ done: LocalDate) -> LocalDate {
        guard let d = When.fromLocalDate(done) else { return done }
        switch r.freq {
        case .day:
            return When.toLocalDate(calendar.date(byAdding: .day, value: r.every, to: d)!)
        case .week:
            return When.toLocalDate(calendar.date(byAdding: .day, value: 7 * r.every, to: d)!)
        case .month:
            return When.toLocalDate(addMonths(d, r.every))
        case .year:
            return When.toLocalDate(addYears(d, r.every))
        }
    }
}
