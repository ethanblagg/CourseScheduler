import Foundation
import SwiftData

public protocol WeeklyTimeFields: AnyObject {
    var weekdaysRawValue: Int { get set }
    var startMinute: Int? { get set }
    var endMinute: Int? { get set }
}

extension WeeklyTimeFields {
    public var weekdays: Weekdays {
        get { Weekdays(rawValue: weekdaysRawValue) }
        set { weekdaysRawValue = newValue.rawValue }
    }

    public var validation: Result<WeeklyTime, WeeklyTimeError> {
        WeeklyTime.validate(weekdays: weekdays, start: startMinute, end: endMinute)
    }

    public var weeklyTime: WeeklyTime? {
        try? validation.get()
    }

    public var isComplete: Bool {
        weeklyTime != nil
    }

    public var isBlank: Bool {
        weekdays.isEmpty && startMinute == nil && endMinute == nil
    }
}

private func nextPosition(after positions: [Int]) -> Int {
    (positions.max() ?? -1) + 1
}

@Model
public final class Plan {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Course.plan) public var courses: [Course]
    @Relationship(deleteRule: .cascade, inverse: \UnavailableTime.plan) public var unavailableTimes: [UnavailableTime]
    public var starredScheduleKeys: [String]

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        courses = []
        unavailableTimes = []
        starredScheduleKeys = []
    }

    public var orderedCourses: [Course] {
        courses.sorted { $0.position < $1.position }
    }

    public var orderedUnavailableTimes: [UnavailableTime] {
        unavailableTimes.sorted { $0.position < $1.position }
    }

    public var starredSchedules: [ScheduleKey] {
        get { starredScheduleKeys.map(ScheduleKey.init(rawValue:)) }
        set { starredScheduleKeys = newValue.map(\.rawValue) }
    }

    @discardableResult
    public func addCourse() -> Course {
        let course = Course(position: nextPosition(after: courses.map(\.position)))
        modelContext?.insert(course)
        courses.append(course)
        course.addSection()
        return course
    }

    @discardableResult
    public func addUnavailableTime() -> UnavailableTime {
        let time = UnavailableTime(position: nextPosition(after: unavailableTimes.map(\.position)))
        modelContext?.insert(time)
        unavailableTimes.append(time)
        time.addSlot()
        return time
    }

    public static func create(in context: ModelContext, on date: Date = .now) throws -> Plan {
        let names = try context.fetch(FetchDescriptor<Plan>()).map(\.name)
        let plan = Plan(name: PlanName.unique(PlanName.upcomingTerm(on: date), among: names), createdAt: date)
        context.insert(plan)
        return plan
    }
}

@Model
public final class Course {
    @Attribute(.unique) public var id: UUID
    public var code: String
    public var name: String
    public var colorName: String
    public var position: Int
    public var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \CourseSection.course) public var sections: [CourseSection]

    public init(id: UUID = UUID(), code: String = "", name: String = "", color: PlannerColor = .courseDefault, position: Int = 0) {
        self.id = id
        self.code = code
        self.name = name
        colorName = color.rawValue
        self.position = position
        sections = []
    }

    public var color: PlannerColor {
        get { PlannerColor(rawValue: colorName) ?? .courseDefault }
        set { colorName = newValue.rawValue }
    }

    public var orderedSections: [CourseSection] {
        sections.sorted { $0.position < $1.position }
    }

    public var hasIdentity: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty || !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var isComplete: Bool {
        hasIdentity && !sections.isEmpty && sections.allSatisfy(\.isComplete)
    }

    public var isBlank: Bool {
        !hasIdentity && sections.allSatisfy { $0.meetings.allSatisfy(\.isBlank) }
    }

    @discardableResult
    public func duplicateSection(_ original: CourseSection) -> CourseSection {
        appendCopy(of: original, label: nil)
    }

    func appendCopy(of original: CourseSection, label: String?) -> CourseSection {
        let copy = CourseSection(label: label ?? nextSectionLabel, position: nextPosition(after: sections.map(\.position)))
        modelContext?.insert(copy)
        sections.append(copy)
        for meeting in original.orderedMeetings {
            let duplicate = copy.addMeeting(label: meeting.label)
            duplicate.weekdays = meeting.weekdays
            duplicate.startMinute = meeting.startMinute
            duplicate.endMinute = meeting.endMinute
        }
        return copy
    }

    var nextSectionLabel: String {
        String(format: "%02d", (sections.compactMap { Int($0.label) }.max() ?? 0) + 1)
    }

    @discardableResult
    public func addSection() -> CourseSection {
        let section = CourseSection(label: nextSectionLabel, position: nextPosition(after: sections.map(\.position)))
        modelContext?.insert(section)
        sections.append(section)
        section.addMeeting(label: "Lecture")
        return section
    }
}

@Model
public final class CourseSection {
    @Attribute(.unique) public var id: UUID
    public var label: String
    public var position: Int
    public var course: Course?
    @Relationship(deleteRule: .cascade, inverse: \Meeting.section) public var meetings: [Meeting]

    public init(id: UUID = UUID(), label: String, position: Int = 0) {
        self.id = id
        self.label = label
        self.position = position
        meetings = []
    }

    public var orderedMeetings: [Meeting] {
        meetings.sorted { $0.position < $1.position }
    }

    public var isComplete: Bool {
        !meetings.isEmpty && meetings.allSatisfy(\.isComplete)
    }

    @discardableResult
    public func addMeeting(label: String = "") -> Meeting {
        let meeting = Meeting(label: label, position: nextPosition(after: meetings.map(\.position)))
        modelContext?.insert(meeting)
        meetings.append(meeting)
        return meeting
    }
}

@Model
public final class Meeting: WeeklyTimeFields {
    @Attribute(.unique) public var id: UUID
    public var label: String
    public var weekdaysRawValue: Int
    public var startMinute: Int?
    public var endMinute: Int?
    public var position: Int
    public var section: CourseSection?

    public init(id: UUID = UUID(), label: String = "", weekdays: Weekdays = [], startMinute: Int? = nil, endMinute: Int? = nil, position: Int = 0) {
        self.id = id
        self.label = label
        weekdaysRawValue = weekdays.rawValue
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.position = position
    }
}

@Model
public final class UnavailableTime {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorName: String
    public var position: Int
    public var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \TimeSlot.owner) public var slots: [TimeSlot]

    public init(id: UUID = UUID(), name: String = "", color: PlannerColor = .unavailableDefault, position: Int = 0) {
        self.id = id
        self.name = name
        colorName = color.rawValue
        self.position = position
        slots = []
    }

    public var color: PlannerColor {
        get { PlannerColor(rawValue: colorName) ?? .unavailableDefault }
        set { colorName = newValue.rawValue }
    }

    public var orderedSlots: [TimeSlot] {
        slots.sorted { $0.position < $1.position }
    }

    public var isComplete: Bool {
        !slots.isEmpty && slots.allSatisfy(\.isComplete)
    }

    public var isBlank: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty && slots.allSatisfy(\.isBlank)
    }

    @discardableResult
    public func addSlot() -> TimeSlot {
        let slot = TimeSlot(position: nextPosition(after: slots.map(\.position)))
        modelContext?.insert(slot)
        slots.append(slot)
        return slot
    }
}

@Model
public final class TimeSlot: WeeklyTimeFields {
    @Attribute(.unique) public var id: UUID
    public var weekdaysRawValue: Int
    public var startMinute: Int?
    public var endMinute: Int?
    public var position: Int
    public var owner: UnavailableTime?

    public init(id: UUID = UUID(), weekdays: Weekdays = [], startMinute: Int? = nil, endMinute: Int? = nil, position: Int = 0) {
        self.id = id
        weekdaysRawValue = weekdays.rawValue
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.position = position
    }
}
