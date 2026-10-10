import Foundation

/// Local calendar date `yyyy-MM-dd` (web `LocalDate`).
typealias LocalDate = String

enum WhenResult: Equatable, Sendable {
    case today
    case later
    case date(LocalDate)
}

/// Natural-language When parser (web `domain/dates.ts`, decision 9).
enum When {
    private static let weekdays = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
    private static let months = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    ]

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        cal.timeZone = .current
        return cal
    }

    static func toLocalDate(_ d: Date, calendar: Calendar = calendar) -> LocalDate {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func fromLocalDate(_ s: LocalDate, calendar: Calendar = calendar) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comp = DateComponents()
        comp.year = parts[0]
        comp.month = parts[1]
        comp.day = parts[2]
        return calendar.date(from: comp)
    }

    static func addLocalDays(_ s: LocalDate, _ days: Int, calendar: Calendar = calendar) -> LocalDate {
        guard let d = fromLocalDate(s, calendar: calendar) else { return s }
        return toLocalDate(calendar.date(byAdding: .day, value: days, to: d)!, calendar: calendar)
    }

    /// Parse When field input. `today` is a local calendar day (time ignored).
    static func parseWhen(_ input: String, today: Date, calendar: Calendar = calendar) -> WhenResult? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if s.isEmpty { return nil }

        if s == "today" || s == "tod" { return .today }
        if s == "tonight" || s == "evening" || s == "this evening" { return .today }
        if s == "later" || s == "some" || s == "not now" { return .later }

        func dateResult(_ d: Date) -> WhenResult { .date(toLocalDate(d, calendar: calendar)) }

        if matchPrefix(s, ["tomorrow"]) == 0 {
            return dateResult(addDays(today, 1, calendar: calendar))
        }
        if s == "next week" {
            return dateResult(addDays(today, 7 - mondayIndex(today, calendar: calendar), calendar: calendar))
        }
        if s == "next month" {
            let c = calendar.dateComponents([.year, .month], from: today)
            var next = DateComponents()
            next.year = c.year
            next.month = (c.month ?? 1) + 1
            next.day = 1
            if let d = calendar.date(from: next) { return dateResult(d) }
            return nil
        }

        if let m = s.wholeMatch(of: /^in (\d{1,3}) (day|days|week|weeks|month|months)$/) {
            let n = Int(m.1)!
            let unit = String(m.2)
            if unit.hasPrefix("day") { return dateResult(addDays(today, n, calendar: calendar)) }
            if unit.hasPrefix("week") { return dateResult(addWeeks(today, n, calendar: calendar)) }
            return dateResult(addMonths(today, n, calendar: calendar))
        }

        let isNext = s.hasPrefix("next ")
        let weekdayWord = isNext ? String(s.dropFirst(5)) : s
        let weekday = matchPrefix(weekdayWord, weekdays)
        if weekday != -1 {
            if isNext {
                let nextMonday = addDays(today, 7 - mondayIndex(today, calendar: calendar), calendar: calendar)
                return dateResult(addDays(nextMonday, weekday, calendar: calendar))
            }
            var delta = (weekday - mondayIndex(today, calendar: calendar) + 7) % 7
            if delta == 0 { delta = 7 }
            return dateResult(addDays(today, delta, calendar: calendar))
        }

        if let m = s.wholeMatch(of: /^(\d{4})[\/.\-](\d{1,2})[\/.\-](\d{1,2})$/) {
            guard let d = validDate(Int(m.1)!, Int(m.2)!, Int(m.3)!, calendar: calendar) else { return nil }
            return .date(d)
        }

        if let m = s.wholeMatch(of: /^(\d{1,2})[\/.\-](\d{1,2})$/) {
            guard let d = nextMonthDay(today, month: Int(m.1)!, day: Int(m.2)!, calendar: calendar) else { return nil }
            return .date(d)
        }

        let dm = s.wholeMatch(of: /^(\d{1,2}) ([a-z]+)$/)
        let mdWords = s.wholeMatch(of: /^([a-z]+) (\d{1,2})$/)
        let dayNum = Int(dm?.1 ?? mdWords?.2 ?? "")
        let monthWord = dm.map { String($0.2) } ?? mdWords.map { String($0.1) }
        if let monthWord, let dayNum {
            let month = matchPrefix(monthWord, months)
            if month == -1 { return nil }
            guard let d = nextMonthDay(today, month: month + 1, day: dayNum, calendar: calendar) else { return nil }
            return .date(d)
        }

        return nil
    }

    // MARK: - helpers

    private static func matchPrefix(_ word: String, _ candidates: [String], min: Int = 3) -> Int {
        guard word.count >= min else { return -1 }
        return candidates.firstIndex(where: { $0.hasPrefix(word) }) ?? -1
    }

    private static func mondayIndex(_ d: Date, calendar: Calendar) -> Int {
        // Sunday=1 ... Saturday=7 in Gregorian; Monday-first → Mon=0.
        let wd = calendar.component(.weekday, from: d) // 1=Sun
        return (wd + 5) % 7
    }

    private static func addDays(_ d: Date, _ n: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: n, to: d)!
    }

    private static func addWeeks(_ d: Date, _ n: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: n, to: d)!
    }

    private static func addMonths(_ d: Date, _ n: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: n, to: d)!
    }

    private static func validDate(_ y: Int, _ m: Int, _ d: Int, calendar: Calendar) -> LocalDate? {
        var comp = DateComponents()
        comp.year = y
        comp.month = m
        comp.day = d
        guard let date = calendar.date(from: comp) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return toLocalDate(date, calendar: calendar)
    }

    private static func nextMonthDay(
        _ today: Date,
        month m: Int,
        day d: Int,
        calendar: Calendar
    ) -> LocalDate? {
        let year = calendar.component(.year, from: today)
        if let thisYear = validDate(year, m, d, calendar: calendar),
           thisYear >= toLocalDate(today, calendar: calendar)
        {
            return thisYear
        }
        return validDate(year + 1, m, d, calendar: calendar)
    }

    /// Round `HH:mm` to the nearest quarter hour (web `roundToQuarter`).
    static func roundToQuarter(_ time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return "09:00" }
        let h = parts[0]
        let m = parts[1]
        let quarters = min(Int(round(Double(h * 60 + m) / 15.0)), 24 * 4 - 1)
        let mins = quarters * 15
        return String(format: "%02d:%02d", mins / 60, mins % 60)
    }
}
