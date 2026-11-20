import Foundation
import SwiftData

public struct MeetingSnapshot: Hashable, Sendable {
    let id: UUID
    let label: String
    let weekdays: Int
    let startMinute: Int?
    let endMinute: Int?
    let position: Int
}

public struct SectionSnapshot: Hashable, Sendable {
    let id: UUID
    let label: String
    let position: Int
    let meetings: [MeetingSnapshot]
}

public struct CourseSnapshot: Hashable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let colorName: String
    let position: Int
    let sections: [SectionSnapshot]
}

public struct SlotSnapshot: Hashable, Sendable {
    let id: UUID
    let weekdays: Int
    let startMinute: Int?
    let endMinute: Int?
    let position: Int
}

public struct UnavailableSnapshot: Hashable, Sendable {
    let id: UUID
    let name: String
    let colorName: String
    let position: Int
    let slots: [SlotSnapshot]
}

public struct PlanSnapshot: Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let starredScheduleKeys: [String]
    let courses: [CourseSnapshot]
    let unavailable: [UnavailableSnapshot]
}

extension Meeting {
    var snapshot: MeetingSnapshot {
        MeetingSnapshot(id: id, label: label, weekdays: weekdaysRawValue, startMinute: startMinute, endMinute: endMinute, position: position)
    }
}

extension CourseSection {
    var snapshot: SectionSnapshot {
        SectionSnapshot(id: id, label: label, position: position, meetings: orderedMeetings.map(\.snapshot))
    }

    public func removeMeeting(_ meeting: Meeting) -> MeetingSnapshot {
        let snapshot = meeting.snapshot
        meetings.removeAll { $0.id == meeting.id }
        modelContext?.delete(meeting)
        return snapshot
    }

    @discardableResult
    public func restore(_ snapshot: MeetingSnapshot) -> Meeting {
        let meeting = Meeting(id: snapshot.id, label: snapshot.label, weekdays: Weekdays(rawValue: snapshot.weekdays), startMinute: snapshot.startMinute, endMinute: snapshot.endMinute, position: snapshot.position)
        modelContext?.insert(meeting)
        meetings.append(meeting)
        return meeting
    }
}

extension Course {
    var snapshot: CourseSnapshot {
        CourseSnapshot(id: id, code: code, name: name, colorName: colorName, position: position, sections: orderedSections.map(\.snapshot))
    }

    public var sectionSnapshots: [SectionSnapshot] {
        orderedSections.map(\.snapshot)
    }

    public func replaceSections(with snapshots: [SectionSnapshot]) {
        for section in sections { modelContext?.delete(section) }
        sections.removeAll()
        for snapshot in snapshots { restore(snapshot) }
    }

    public func removeSection(_ section: CourseSection) -> SectionSnapshot {
        let snapshot = section.snapshot
        sections.removeAll { $0.id == section.id }
        modelContext?.delete(section)
        return snapshot
    }

    @discardableResult
    public func restore(_ snapshot: SectionSnapshot) -> CourseSection {
        let section = CourseSection(id: snapshot.id, label: snapshot.label, position: snapshot.position)
        modelContext?.insert(section)
        sections.append(section)
        for meeting in snapshot.meetings { section.restore(meeting) }
        return section
    }
}

extension UnavailableTime {
    var snapshot: UnavailableSnapshot {
        UnavailableSnapshot(id: id, name: name, colorName: colorName, position: position, slots: orderedSlots.map(\.snapshot))
    }

    public func removeSlot(_ slot: TimeSlot) -> SlotSnapshot {
        let snapshot = slot.snapshot
        slots.removeAll { $0.id == slot.id }
        modelContext?.delete(slot)
        return snapshot
    }

    @discardableResult
    public func restore(_ snapshot: SlotSnapshot) -> TimeSlot {
        let slot = TimeSlot(id: snapshot.id, weekdays: Weekdays(rawValue: snapshot.weekdays), startMinute: snapshot.startMinute, endMinute: snapshot.endMinute, position: snapshot.position)
        modelContext?.insert(slot)
        slots.append(slot)
        return slot
    }
}

extension TimeSlot {
    var snapshot: SlotSnapshot {
        SlotSnapshot(id: id, weekdays: weekdaysRawValue, startMinute: startMinute, endMinute: endMinute, position: position)
    }
}

extension Plan {
    public var snapshot: PlanSnapshot {
        PlanSnapshot(id: id, name: name, createdAt: createdAt, starredScheduleKeys: starredScheduleKeys, courses: orderedCourses.map(\.snapshot), unavailable: orderedUnavailableTimes.map(\.snapshot))
    }

    public func removeCourse(_ course: Course) -> CourseSnapshot {
        let snapshot = course.snapshot
        courses.removeAll { $0.id == course.id }
        modelContext?.delete(course)
        return snapshot
    }

    @discardableResult
    public func restore(_ snapshot: CourseSnapshot) -> Course {
        let course = Course(id: snapshot.id, code: snapshot.code, name: snapshot.name, color: PlannerColor(rawValue: snapshot.colorName) ?? .courseDefault, position: snapshot.position)
        modelContext?.insert(course)
        courses.append(course)
        for section in snapshot.sections { course.restore(section) }
        return course
    }

    public func removeUnavailableTime(_ time: UnavailableTime) -> UnavailableSnapshot {
        let snapshot = time.snapshot
        unavailableTimes.removeAll { $0.id == time.id }
        modelContext?.delete(time)
        return snapshot
    }

    @discardableResult
    public func restore(_ snapshot: UnavailableSnapshot) -> UnavailableTime {
        let time = UnavailableTime(id: snapshot.id, name: snapshot.name, color: PlannerColor(rawValue: snapshot.colorName) ?? .unavailableDefault, position: snapshot.position)
        modelContext?.insert(time)
        unavailableTimes.append(time)
        for slot in snapshot.slots { time.restore(slot) }
        return time
    }

    public static func remove(_ plan: Plan, from context: ModelContext) -> PlanSnapshot {
        let snapshot = plan.snapshot
        context.delete(plan)
        return snapshot
    }

    @discardableResult
    public static func restore(_ snapshot: PlanSnapshot, in context: ModelContext) -> Plan {
        let plan = Plan(id: snapshot.id, name: snapshot.name, createdAt: snapshot.createdAt)
        context.insert(plan)
        plan.starredScheduleKeys = snapshot.starredScheduleKeys
        for course in snapshot.courses { plan.restore(course) }
        for time in snapshot.unavailable { plan.restore(time) }
        return plan
    }
}
