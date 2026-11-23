import Foundation
import SwiftData
import Testing
@testable import ClassPlannerCore

private func event(_ kind: String, _ days: [Weekday], _ start: Int, _ end: Int, isClass: Bool = true) -> PlannerEvent {
    let time = try! WeeklyTime(weekdays: Weekdays(days: days), startMinute: start, endMinute: end)
    let kindValue: PlannerEvent.Kind = isClass ? .course(courseID: UUID(), sectionID: UUID(), meetingID: UUID()) : .unavailable(id: UUID(), slotID: UUID())
    return PlannerEvent(kind: kindValue, code: kind, name: kind, sectionLabel: "01", meetingLabel: "", color: .blue, time: time, isConflict: false)
}

struct CalendarLayoutTests {
    @Test func weekendsHideUnlessAClassMeetsThen() {
        let events = [event("ENVS", [.monday], 450, 500), event("Shift", [.sunday], 600, 840, isClass: false)]
        #expect(CalendarLayout(events: events, weekStart: .monday, showWeekends: true).days.map(\.shortName) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(CalendarLayout(events: events, weekStart: .monday, showWeekends: false).days.map(\.shortName) == ["Mon", "Tue", "Wed", "Thu", "Fri"])
        let saturdayLab = events + [event("BIO", [.saturday], 540, 720)]
        #expect(CalendarLayout(events: saturdayLab, weekStart: .monday, showWeekends: false).days.map(\.shortName) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(CalendarLayout(events: saturdayLab, weekStart: .sunday, showWeekends: false).days.map(\.shortName) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(CalendarLayout(events: saturdayLab, weekStart: .sunday, showWeekends: true).days.first == .sunday)
    }

    @Test func hoursSpanTheShownEventsOnly() {
        let events = [event("ENVS", [.monday], 450, 500), event("ART", [.thursday], 1140, 1300), event("Shift", [.sunday], 300, 360, isClass: false)]
        #expect(CalendarLayout(events: events, weekStart: .monday, showWeekends: false).hours == 7..<22)
        #expect(CalendarLayout(events: events, weekStart: .monday, showWeekends: true).hours == 5..<22)
        #expect(CalendarLayout(events: [], weekStart: .monday, showWeekends: false).hours == CalendarLayout.defaultHours)
        #expect(CalendarLayout(events: [event("A", [.monday], 600, 660)], weekStart: .monday, showWeekends: false).hours == 10..<11)
    }

    @Test func positionsMatchActualTimes() {
        let layout = CalendarLayout(events: [event("ENVS", [.monday], 450, 500), event("MATH", [.wednesday], 720, 735)], weekStart: .monday, showWeekends: false)
        #expect(layout.hours.lowerBound == 7)
        #expect(layout.hoursFromTop(450) == 0.5)
        #expect(layout.hoursFromTop(735) - layout.hoursFromTop(720) == 0.25)
    }

    @Test func overlapsSitSideBySideAndTouchingTimesDoNot() {
        let lecture = event("CHEM", [.tuesday], 900, 960)
        let work = event("Work", [.tuesday], 840, 1020, isClass: false)
        let practice = event("Practice", [.tuesday], 1020, 1080, isClass: false)
        let layout = CalendarLayout(events: [lecture, work, practice], weekStart: .monday, showWeekends: false)
        let tuesday = Dictionary(uniqueKeysWithValues: layout.placements(on: .tuesday).map { ($0.event.code.isEmpty ? $0.event.name : $0.event.code, $0) })
        #expect(tuesday["Work"]?.lane == 0 && tuesday["Work"]?.laneCount == 2)
        #expect(tuesday["CHEM"]?.lane == 1 && tuesday["CHEM"]?.laneCount == 2)
        #expect(tuesday["Practice"]?.lane == 0 && tuesday["Practice"]?.laneCount == 1)
        #expect(layout.placements(on: .monday).isEmpty)
    }

    @Test func multiDayMeetingsAppearOnEachDay() {
        let layout = CalendarLayout(events: [event("MATH", [.monday, .wednesday], 660, 720)], weekStart: .monday, showWeekends: false)
        #expect(layout.placements.map(\.day) == [.monday, .wednesday])
        #expect(Set(layout.placements.map(\.id)).count == 2)
    }

    @MainActor
    @Test func scheduleEventsCoverEveryMeetingAndUnavailableTime() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let plan = Plan(name: "Fall 2026")
        context.insert(plan)
        func set(_ fields: some WeeklyTimeFields, _ days: [Weekday], _ start: Int, _ end: Int) {
            fields.weekdays = Weekdays(days: days)
            fields.startMinute = start
            fields.endMinute = end
        }
        let math = plan.addCourse()
        math.code = "MATH 120"
        math.name = "Calculus"
        let section = math.orderedSections[0]
        set(section.orderedMeetings[0], [.monday, .wednesday], 660, 720)
        set(section.addMeeting(label: "Tutorial"), [.wednesday], 720, 735)
        let other = math.addSection()
        set(other.orderedMeetings[0], [.friday], 600, 660)
        let work = plan.addUnavailableTime()
        work.name = "Work"
        set(work.orderedSlots[0], [.tuesday], 840, 1020)
        set(work.addSlot(), [.thursday], 840, 1020)

        guard case .ready(let input) = plan.readiness, case .schedules(let results) = try ScheduleSearch.run(input),
              let schedule = results.schedules(by: .fewestDays).first(where: { $0.selections.first?.sectionID == section.id }) else {
            Issue.record("Expected a schedule using section 01")
            return
        }
        let events = plan.events(for: schedule)
        #expect(events.filter(\.isClass).map(\.meetingLabel) == ["Lecture", "Tutorial"])
        #expect(events.filter(\.isClass).allSatisfy { $0.code == "MATH 120" && $0.sectionLabel == "01" && $0.color == .blue })
        #expect(events.filter { !$0.isClass }.map(\.name) == ["Work", "Work"])
        #expect(events.filter { !$0.isClass }.allSatisfy { $0.color == .gray })

        math.color = .purple
        #expect(plan.events(for: schedule).filter(\.isClass).allSatisfy { $0.color == .purple })
        guard case .ready(let after) = plan.readiness, case .schedules(let again) = try ScheduleSearch.run(after) else {
            Issue.record("Expected schedules after a color change")
            return
        }
        #expect(again.schedules(by: .fewestDays).map(\.key) == results.schedules(by: .fewestDays).map(\.key))
    }
}
