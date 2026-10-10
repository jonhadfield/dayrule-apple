import Testing
@testable import Dayrule

@Suite("RepeatMath")
struct RepeatTests {
    private func rule(
        freq: RepeatRule.Freq = .day,
        every: Int = 1,
        weekdays: [Int]? = nil,
        mode: RepeatRule.Mode = .fixed,
        anchor: LocalDate = "2026-10-04"
    ) -> RepeatRule {
        RepeatRule(
            freq: freq,
            every: every,
            weekdays: weekdays,
            mode: mode,
            anchor: anchor,
            next: nil,
            reminderTime: nil
        )
    }

    private func first(_ r: RepeatRule, _ n: Int) -> [LocalDate] {
        var out = [RepeatMath.occurrenceOnOrAfter(r, r.anchor)]
        while out.count < n {
            out.append(RepeatMath.occurrenceAfter(r, out.last!))
        }
        return out
    }

    @Test func everyNDays() {
        #expect(first(rule(every: 3), 3) == ["2026-10-04", "2026-10-07", "2026-10-10"])
        #expect(RepeatMath.occurrenceOnOrAfter(rule(every: 3), "2026-10-05") == "2026-10-07")
    }

    @Test func weeklyOnChosenWeekdays() {
        let monThu = rule(freq: .week, weekdays: [0, 3])
        #expect(first(monThu, 4) == ["2026-10-05", "2026-10-08", "2026-10-12", "2026-10-15"])
        #expect(first(rule(freq: .week), 2) == ["2026-10-04", "2026-10-11"])
    }

    @Test func monthlyClampsShortMonths() {
        #expect(first(rule(freq: .month, anchor: "2026-01-31"), 4) == [
            "2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30",
        ])
    }

    @Test func dueAfterCompletion() {
        #expect(
            RepeatMath.dueAfterCompletion(rule(every: 3, mode: .afterCompletion), "2026-10-04")
                == "2026-10-07"
        )
        #expect(
            RepeatMath.dueAfterCompletion(rule(freq: .week, mode: .afterCompletion), "2026-10-04")
                == "2026-10-11"
        )
        #expect(
            RepeatMath.dueAfterCompletion(rule(freq: .month, mode: .afterCompletion), "2026-01-31")
                == "2026-02-28"
        )
    }
}
