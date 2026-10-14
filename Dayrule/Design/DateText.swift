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

    /// "YYYY-MM" → "October 2026".
    static func month(
        _ ym: String,
        locale: Locale = .current,
        calendar: Calendar = When.calendar
    ) -> String {
        guard let date = When.fromLocalDate(ym + "-01", calendar: calendar) else { return ym }
        return date.formatted(style(locale, calendar).month(.wide).year())
    }

    /// Scheduled day header: the day number, with the weekday as secondary text.
    /// Tomorrow keeps its number and reads "Tomorrow" instead, as on the web.
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

    private static func style(_ locale: Locale, _ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
