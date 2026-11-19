import Foundation
import SwiftData
import Testing
@testable import ClassPlannerCore

@MainActor
struct PlanStoreTests {
    private func temporaryStore() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClassPlannerTests-\(UUID().uuidString).store")
    }

    private func set(_ fields: some WeeklyTimeFields, _ days: [Weekday], _ start: Int, _ end: Int) {
        fields.weekdays = Weekdays(days: days)
        fields.startMinute = start
        fields.endMinute = end
    }

    private func makeFallPlan(in context: ModelContext) throws -> Plan {
        let plan = Plan(name: "Fall 2026")
        context.insert(plan)
        let chemistry = plan.addCourse()
        chemistry.code = "CHEM 101"
        chemistry.name = "Chemistry"
        chemistry.color = .teal
        let first = chemistry.orderedSections[0]
        set(first.orderedMeetings[0], [.tuesday], 900, 960)
        set(first.addMeeting(label: "Lab"), [.thursday], 600, 660)
        let second = chemistry.addSection()
        set(second.orderedMeetings[0], [.monday, .wednesday], 540, 600)
        let calculus = plan.addCourse()
        calculus.code = "MATH 120"
        set(calculus.orderedSections[0].orderedMeetings[0], [.monday, .wednesday], 660, 720)
        let work = plan.addUnavailableTime()
        work.name = "Work"
        set(work.orderedSlots[0], [.tuesday], 840, 1020)
        set(work.addSlot(), [.saturday], 600, 720)
        plan.starredSchedules = [ScheduleKey(sectionIDs: [second.id, calculus.orderedSections[0].id])]
        try context.save()
        return plan
    }

    @Test func reopeningTheStoreRestoresEverything() throws {
        let url = temporaryStore()
        let original: (plan: UUID, chemistry: UUID, sections: [UUID], meetings: [UUID], starred: [ScheduleKey])
        do {
            let context = ModelContext(try PlannerStore.makeContainer(storeURL: url))
            let plan = try makeFallPlan(in: context)
            let chemistry = plan.orderedCourses[0]
            original = (plan.id, chemistry.id, chemistry.orderedSections.map(\.id), chemistry.orderedSections[0].orderedMeetings.map(\.id), plan.starredSchedules)
        }

        let context = ModelContext(try PlannerStore.makeContainer(storeURL: url))
        let plans = try context.fetch(FetchDescriptor<Plan>())
        #expect(plans.count == 1)
        let plan = try #require(plans.first)
        #expect(plan.id == original.plan)
        #expect(plan.name == "Fall 2026")
        #expect(plan.orderedCourses.map(\.code) == ["CHEM 101", "MATH 120"])
        let chemistry = plan.orderedCourses[0]
        #expect(chemistry.id == original.chemistry)
        #expect(chemistry.name == "Chemistry")
        #expect(chemistry.color == .teal)
        #expect(plan.orderedCourses[1].color == .blue)
        #expect(chemistry.orderedSections.map(\.label) == ["01", "02"])
        #expect(chemistry.orderedSections.map(\.id) == original.sections)
        let meetings = chemistry.orderedSections[0].orderedMeetings
        #expect(meetings.map(\.id) == original.meetings)
        #expect(meetings.map(\.label) == ["Lecture", "Lab"])
        #expect(meetings[1].weekdays.days == [.thursday])
        #expect(meetings[1].startMinute == 600 && meetings[1].endMinute == 660)
        let work = try #require(plan.orderedUnavailableTimes.first)
        #expect(work.name == "Work")
        #expect(work.color == .gray)
        #expect(work.orderedSlots.map(\.weekdays) == [Weekdays(days: [.tuesday]), Weekdays(days: [.saturday])])
        #expect(plan.starredSchedules == original.starred)
        #expect(plan.readiness != .empty)
    }

    @Test func plansStayIndependent() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let fall = try makeFallPlan(in: context)
        let spring = try Plan.create(in: context, on: Date(timeIntervalSince1970: 1_795_000_000))
        spring.addCourse().code = "BIO 110"
        try context.save()

        fall.orderedCourses[0].code = "CHEM 102"
        #expect(spring.orderedCourses.map(\.code) == ["BIO 110"])

        context.delete(fall)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Plan>()).map(\.name) == [spring.name])
        #expect(try context.fetch(FetchDescriptor<Course>()).map(\.code) == ["BIO 110"])
        #expect(try context.fetchCount(FetchDescriptor<Meeting>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TimeSlot>()) == 0)
    }

    @Test func newPlansGetUniqueUpcomingTermNames() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let november = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18)))
        let first = try Plan.create(in: context, on: november)
        let second = try Plan.create(in: context, on: november)
        #expect(first.name == "Spring 2027")
        #expect(second.name == "Spring 2027 (2)")
        #expect(first.id != second.id)
    }

    @Test func emptyAndIncompletePlansAreNotSchedulable() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let plan = Plan(name: "Spring 2027")
        context.insert(plan)
        #expect(plan.readiness == .empty)

        let course = plan.addCourse()
        #expect(course.isBlank)
        course.code = "BIO 110"
        #expect(plan.readiness == .incomplete([.course(course.id)]))

        let meeting = course.orderedSections[0].orderedMeetings[0]
        set(meeting, [.monday], 600, 570)
        #expect(!meeting.isComplete)
        #expect(plan.readiness == .incomplete([.course(course.id)]))

        meeting.endMinute = 650
        let blocked = plan.addUnavailableTime()
        blocked.name = "Work"
        #expect(plan.readiness == .incomplete([.unavailable(blocked.id)]))

        set(blocked.orderedSlots[0], [.friday], 780, 1020)
        guard case .ready(let input) = plan.readiness else {
            Issue.record("Expected a schedulable plan")
            return
        }
        #expect(input.courses.map(\.id) == [course.id])
        #expect(input.courses[0].sections[0].meetings[0].time.startMinute == 600)
        #expect(input.unavailable[0].times[0].time.weekdays.days == [.friday])
    }

    @Test func colorChangesDoNotChangeSchedulingInput() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let plan = try makeFallPlan(in: context)
        let before = plan.readiness
        let starred = plan.starredSchedules
        plan.orderedCourses[0].color = .pink
        plan.orderedUnavailableTimes[0].color = .orange
        #expect(plan.readiness == before)
        #expect(plan.starredSchedules == starred)
    }

    @Test func duplicatingASectionCopiesMeetingsWithNewIdentity() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let plan = try makeFallPlan(in: context)
        let chemistry = plan.orderedCourses[0]
        let original = chemistry.orderedSections[0]
        let copy = chemistry.duplicateSection(original)
        #expect(chemistry.orderedSections.map(\.label) == ["01", "02", "03"])
        #expect(copy.id != original.id)
        #expect(copy.orderedMeetings.map(\.label) == ["Lecture", "Lab"])
        #expect(copy.orderedMeetings.map(\.weeklyTime) == original.orderedMeetings.map(\.weeklyTime))
        #expect(Set(copy.orderedMeetings.map(\.id)).isDisjoint(with: original.orderedMeetings.map(\.id)))
        copy.orderedMeetings[0].startMinute = 840
        #expect(original.orderedMeetings[0].startMinute == 900)
    }

    @Test func blankEntriesAreRecognized() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let plan = Plan(name: "Spring 2027")
        context.insert(plan)
        let course = plan.addCourse()
        let blocked = plan.addUnavailableTime()
        #expect(course.isBlank && blocked.isBlank)
        course.orderedSections[0].orderedMeetings[0].weekdays = Weekdays(days: [.monday])
        blocked.name = "Practice"
        #expect(!course.isBlank && !blocked.isBlank)
    }
}
