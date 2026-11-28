import Foundation

/// Human date text for LocalDate values (never raw ISO on screen). Port of web
/// `pages.tsx` day-header logic; locale and calendar are injectable for tests.
enum DayruleDateFormat {
    static func relative(
        _ d: LocalDate,
        today: LocalDate,
        locale: Locale = .current,
        calendar: Calendar = When.calendar
    ) -> String {
        guard let date = When.fromLocalDate(d, calendar: calendar),
              let now = When.fromLocalDate(today, calendar: calendar)
        else { return d }
        let days = calendar.dateComponents([.day], from: now, to: date).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6:
            return date.formatted(style(locale, calendar).weekday(.wide))
        default:
            var fmt = style(locale, calendar).day().month(.abbreviated)
            if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
                fmt = fmt.year()
            }
            return date.formatted(fmt)
        }
    }

    static func due(
        _ d: LocalDate,
        today: LocalDate,
        locale: Locale = .current,
        calendar: Calendar = When.calendar
    ) -> String {
        "Due " + relative(d, today: today, locale: locale, calendar: calendar)
    }

    /// Day-granularity past-date chip (web `daysPastLabel`): `1d overdue` / `2d late`.
    enum PastChipWord: String, Sendable {
        case overdue
        case late
    }

    static func daysPast(
        _ anchor: LocalDate,
        today: LocalDate,
        word: PastChipWord,
        calendar: Calendar = When.calendar
    ) -> String {
        guard let past = When.fromLocalDate(anchor, calendar: calendar),
              let now = When.fromLocalDate(today, calendar: calendar)
        else { return word == .overdue ? "Overdue" : "Late" }
        let days = max(1, calendar.dateComponents([.day], from: past, to: now).day ?? 1)
        let n = days == 1 ? "1d" : "\(days)d"
        return "\(n) \(word.rawValue)"
    }

    /// "YYYY-MM" → "October 2026".
    static func month(
        _ ym: String,
        locale: Locale = .current,
        calendar: Calendar = When.calendar
    ) -> String {
        guard let date = When.fromLocalDate(ym + "-01", calendar: calendar) else { return ym }
        return date.formatted(style(locale, calendar).month(.wide).year())
    }

    /// Scheduled day header: day-of-month plus weekday (or "Tomorrow") beside it.
    /// Callers must keep those two adjacent — a trailing-edge Spacer on a wide
    /// reading column leaves the number looking orphaned.
    static func dayHeader(
        _ d: LocalDate,
        today: LocalDate,
        locale: Locale = .current,
        calendar: Calendar = When.calendar
    ) -> (primary: String, secondary: String?) {
        guard let date = When.fromLocalDate(d, calendar: calendar) else { return (d, nil) }
        let primary = date.formatted(style(locale, calendar).day())
        if d == When.addLocalDays(today, 1, calendar: calendar) {
            return (primary, "Tomorrow")
        }
        let secondary = date.formatted(style(locale, calendar).weekday(.wide))
        return (primary, secondary)
    }

    /// Clock from a local `YYYY-MM-DDTHH:mm` reminder (Scheduled “has a time” chip).
    static func clock(
        _ reminderAt: String,
        locale: Locale = .current,
        calendar: Calendar = When.calendar
    ) -> String? {
        guard reminderAt.count >= 16 else { return nil }
        let day = String(reminderAt.prefix(10))
        let hm = String(reminderAt.dropFirst(11).prefix(5))
        guard hm.count == 5, hm[hm.index(hm.startIndex, offsetBy: 2)] == ":",
              let date = When.fromLocalDate(day, calendar: calendar)
        else { return nil }
        let parts = hm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute),
              let stamped = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
        else { return nil }
        return stamped.formatted(style(locale, calendar).hour().minute())
    }

    private static func style(_ locale: Locale, _ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
