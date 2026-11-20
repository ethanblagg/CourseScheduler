import Foundation
import SwiftData
import Testing
@testable import ClassPlannerCore

@MainActor
struct EntryTests {
    private func set(_ fields: some WeeklyTimeFields, _ days: [Weekday], _ start: Int, _ end: Int) {
        fields.weekdays = Weekdays(days: days)
        fields.startMinute = start
        fields.endMinute = end
    }

    private func course(_ plan: Plan, _ code: String, _ name: String, sections: Int, color: PlannerColor = .blue) -> Course {
        let course = plan.addCourse()
        course.code = code
        course.name = name
        course.color = color
        for index in 0..<sections {
            let section = index == 0 ? course.orderedSections[0] : course.addSection()
            set(section.orderedMeetings[0], [.monday, .wednesday], 540 + index * 60, 590 + index * 60)
        }
        return course
    }

    private func history(_ context: ModelContext) -> (spring: Plan, fall: Plan) {
        let spring = Plan(name: "Spring 2026", createdAt: Date(timeIntervalSince1970: 1_760_000_000))
        let fall = Plan(name: "Fall 2026", createdAt: Date(timeIntervalSince1970: 1_780_000_000))
        context.insert(spring)
        context.insert(fall)
        _ = course(spring, "CHEM 203", "Organic Chemistry", sections: 1)
        _ = course(spring, "CHEM 101", "Old Chemistry", sections: 1)
        _ = course(fall, "CHEM 101", "Chemistry", sections: 3, color: .teal)
        _ = course(fall, "MATH 120", "Calculus", sections: 1)
        let unfinished = fall.addCourse()
        unfinished.code = "PHYS 211"
        return (spring, fall)
    }

    @Test func suggestsCompletePreviousCoursesNewestFirst() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let (spring, fall) = history(context)
        let next = Plan(name: "Spring 2027")
        context.insert(next)
        let entry = next.addCourse()
        let all = entry.suggestions(from: [spring, fall, next], matching: "")
        #expect(all.map(\.code) == ["CHEM 101", "CHEM 203", "MATH 120"])
        #expect(all[0].name == "Chemistry" && all[0].planName == "Fall 2026" && all[0].sectionCount == 3)
        #expect(entry.suggestions(from: [spring, fall, next], matching: "organic").map(\.code) == ["CHEM 203"])
        #expect(entry.suggestions(from: [spring, fall, next], matching: "chem 1").map(\.code) == ["CHEM 101"])
    }

    @Test func leavesOutCoursesAlreadyInThePlanAndTheCurrentPick() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let (spring, fall) = history(context)
        let entry = fall.addCourse()
        #expect(entry.suggestions(from: [spring, fall], matching: "").map(\.code) == ["CHEM 203"])

        let next = Plan(name: "Spring 2027")
        context.insert(next)
        let picked = next.addCourse()
        let chemistry = try #require(picked.suggestions(from: [spring, fall, next], matching: "").first)
        picked.adopt(chemistry)
        #expect(picked.code == "CHEM 101" && picked.name == "Chemistry" && picked.color == .teal)
        #expect(picked.suggestions(from: [spring, fall, next], matching: "").map(\.code) == ["CHEM 203", "MATH 120"])
    }

    @Test func copyingSectionsReplacesBlankOnesWithNewIdentities() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let (_, fall) = history(context)
        let source = fall.orderedCourses[0]
        let next = Plan(name: "Spring 2027")
        context.insert(next)
        let copy = next.addCourse()
        copy.copySections(from: source)
        #expect(copy.orderedSections.map(\.label) == ["01", "02", "03"])
        #expect(copy.orderedSections.map { $0.orderedMeetings.map(\.weeklyTime) } == source.orderedSections.map { $0.orderedMeetings.map(\.weeklyTime) })
        #expect(Set(copy.orderedSections.map(\.id)).isDisjoint(with: source.orderedSections.map(\.id)))
        copy.orderedSections[0].orderedMeetings[0].startMinute = 480
        #expect(source.orderedSections[0].orderedMeetings[0].startMinute == 540)
    }

    @Test func copyingSectionsKeepsWorkAlreadyEntered() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let (spring, _) = history(context)
        let next = Plan(name: "Spring 2027")
        context.insert(next)
        let course = next.addCourse()
        set(course.orderedSections[0].orderedMeetings[0], [.friday], 600, 650)
        course.copySections(from: spring.orderedCourses[0])
        #expect(course.orderedSections.map(\.label) == ["01", "02"])
        #expect(course.orderedSections[0].orderedMeetings[0].weekdays.days == [.friday])
    }

    @Test func undoingACopyRestoresTheEarlierSections() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let (_, fall) = history(context)
        let next = Plan(name: "Spring 2027")
        context.insert(next)
        let course = next.addCourse()
        course.orderedSections[0].orderedMeetings[0].label = "Seminar"
        let before = course.sectionSnapshots
        course.copySections(from: fall.orderedCourses[0])
        #expect(course.sections.count == 3)
        course.replaceSections(with: before)
        try context.save()
        #expect(course.sectionSnapshots == before)
        #expect(course.orderedSections[0].orderedMeetings[0].label == "Seminar")
    }

    @Test func removedEntriesComeBackExactlyAfterReopening() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EntryTests-\(UUID().uuidString).store")
        var snapshots: (course: CourseSnapshot, section: SectionSnapshot, meeting: MeetingSnapshot, time: UnavailableSnapshot, slot: SlotSnapshot)
        let before: PlanSnapshot
        do {
            let context = ModelContext(try PlannerStore.makeContainer(storeURL: url))
            let (_, fall) = history(context)
            let work = fall.addUnavailableTime()
            work.name = "Work"
            work.color = .orange
            set(work.orderedSlots[0], [.tuesday], 840, 1020)
            set(work.addSlot(), [.saturday], 600, 720)
            let chemistry = fall.orderedCourses[0]
            chemistry.orderedSections[1].addMeeting(label: "Lab")
            try context.save()
            before = fall.snapshot

            snapshots.meeting = chemistry.orderedSections[1].removeMeeting(chemistry.orderedSections[1].orderedMeetings[1])
            snapshots.section = chemistry.removeSection(chemistry.orderedSections[0])
            snapshots.slot = work.removeSlot(work.orderedSlots[0])
            snapshots.time = fall.removeUnavailableTime(work)
            snapshots.course = fall.removeCourse(fall.orderedCourses[1])
            try context.save()
            #expect(fall.orderedCourses.map(\.code) == ["CHEM 101", "PHYS 211"])
            #expect(try context.fetchCount(FetchDescriptor<TimeSlot>()) == 0)
        }

        let context = ModelContext(try PlannerStore.makeContainer(storeURL: url))
        let fall = try #require(try context.fetch(FetchDescriptor<Plan>()).first { $0.name == "Fall 2026" })
        let chemistry = fall.orderedCourses[0]
        chemistry.orderedSections[0].restore(snapshots.meeting)
        chemistry.restore(snapshots.section)
        fall.restore(snapshots.course)
        let work = fall.restore(snapshots.time)
        #expect(work.orderedSlots.count == 1)
        work.restore(snapshots.slot)
        try context.save()
        #expect(fall.snapshot == before)
    }

    @Test func aDeletedPlanComesBackWithItsStars() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let (_, fall) = history(context)
        let chemistry = fall.orderedCourses[0]
        fall.starredSchedules = [ScheduleKey(sectionIDs: [chemistry.orderedSections[1].id, fall.orderedCourses[1].orderedSections[0].id])]
        try context.save()
        let before = fall.snapshot
        let snapshot = Plan.remove(fall, from: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Plan>()).map(\.name) == ["Spring 2026"])
        let restored = Plan.restore(snapshot, in: context)
        try context.save()
        #expect(restored.snapshot == before)
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 5)
    }

    @Test func undoWorksEvenBeforeTheDeleteIsSaved() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let (_, fall) = history(context)
        try context.save()
        let before = fall.snapshot
        let snapshot = fall.removeCourse(fall.orderedCourses[0])
        fall.restore(snapshot)
        try context.save()
        #expect(fall.snapshot == before)
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 5)
    }
}
