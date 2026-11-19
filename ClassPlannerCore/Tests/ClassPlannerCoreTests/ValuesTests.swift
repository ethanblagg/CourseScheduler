import Foundation
import Testing
@testable import ClassPlannerCore

struct WeeklyTimeTests {
    private let tuesday = Weekdays(days: [.tuesday])

    @Test func acceptsAValidMeeting() throws {
        let time = try WeeklyTime.validate(weekdays: Weekdays(days: [.monday, .wednesday]), start: 9 * 60, end: 10 * 60).get()
        #expect(time.weekdays.days == [.monday, .wednesday])
        #expect(time.endMinute - time.startMinute == 60)
    }

    @Test func reportsWhatIsMissing() {
        #expect(WeeklyTime.validate(weekdays: [], start: 540, end: 600) == .failure(.noDays))
        #expect(WeeklyTime.validate(weekdays: tuesday, start: nil, end: 600) == .failure(.missingStart))
        #expect(WeeklyTime.validate(weekdays: tuesday, start: 540, end: nil) == .failure(.missingEnd))
    }

    @Test func rejectsEndsAtOrBeforeTheStart() {
        #expect(WeeklyTime.validate(weekdays: tuesday, start: 600, end: 600) == .failure(.endNotAfterStart))
        #expect(WeeklyTime.validate(weekdays: tuesday, start: 600, end: 570) == .failure(.endNotAfterStart))
    }

    @Test func handlesNoonAndMidnightAsPlainMinutes() throws {
        #expect(try WeeklyTime.validate(weekdays: tuesday, start: 0, end: 30).get().startMinute == 0)
        #expect(try WeeklyTime.validate(weekdays: tuesday, start: 11 * 60 + 30, end: 12 * 60 + 15).get().endMinute == 735)
        #expect(WeeklyTime.validate(weekdays: tuesday, start: 23 * 60, end: 0) == .failure(.endNotAfterStart))
        #expect(WeeklyTime.validate(weekdays: tuesday, start: -5, end: 30) == .failure(.outOfRange))
        #expect(WeeklyTime.validate(weekdays: tuesday, start: 600, end: 1440) == .failure(.outOfRange))
    }

    @Test func weekdaysToggleAndOrder() {
        var days = Weekdays(days: [.friday, .monday])
        days.toggle(.wednesday)
        days.toggle(.friday)
        #expect(days.days == [.monday, .wednesday])
        #expect(Weekday.week(startingOn: .sunday).map(\.shortName) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    @Test func scheduleKeyIgnoresSectionOrder() {
        let a = UUID(), b = UUID()
        #expect(ScheduleKey(sectionIDs: [a, b]) == ScheduleKey(sectionIDs: [b, a]))
        #expect(ScheduleKey(sectionIDs: [a]) != ScheduleKey(sectionIDs: [b]))
    }
}

struct PlanNameTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func namesTheUpcomingTerm() {
        #expect(PlanName.upcomingTerm(on: date(2026, 11, 18), calendar: calendar) == "Spring 2027")
        #expect(PlanName.upcomingTerm(on: date(2026, 10, 1), calendar: calendar) == "Spring 2027")
        #expect(PlanName.upcomingTerm(on: date(2027, 1, 15), calendar: calendar) == "Spring 2027")
        #expect(PlanName.upcomingTerm(on: date(2027, 2, 1), calendar: calendar) == "Fall 2027")
        #expect(PlanName.upcomingTerm(on: date(2027, 9, 30), calendar: calendar) == "Fall 2027")
    }

    @Test func numbersDuplicateNames() {
        #expect(PlanName.unique("Spring 2027", among: ["Fall 2026"]) == "Spring 2027")
        #expect(PlanName.unique("Spring 2027", among: ["spring 2027 "]) == "Spring 2027 (2)")
        #expect(PlanName.unique("Spring 2027", among: ["Spring 2027", "Spring 2027 (2)"]) == "Spring 2027 (3)")
    }
}
