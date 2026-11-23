import Foundation

public struct PlannerEvent: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case course(courseID: UUID, sectionID: UUID, meetingID: UUID)
        case unavailable(id: UUID, slotID: UUID)
    }

    public let kind: Kind
    public let code: String
    public let name: String
    public let sectionLabel: String
    public let meetingLabel: String
    public let color: PlannerColor
    public let time: WeeklyTime
    public var isConflict: Bool

    public var id: UUID {
        switch kind {
        case .course(_, _, let meetingID): meetingID
        case .unavailable(_, let slotID): slotID
        }
    }

    public var isClass: Bool {
        if case .course = kind { true } else { false }
    }
}

extension Plan {
    public func events(for schedule: Schedule) -> [PlannerEvent] {
        let selected = Set(schedule.selections.map(\.sectionID))
        let classes = orderedCourses.flatMap { course in
            course.orderedSections.filter { selected.contains($0.id) }.flatMap { section in
                section.orderedMeetings.compactMap { meeting in
                    meeting.weeklyTime.map {
                        PlannerEvent(kind: .course(courseID: course.id, sectionID: section.id, meetingID: meeting.id), code: course.code.trimmingCharacters(in: .whitespaces), name: course.name.trimmingCharacters(in: .whitespaces), sectionLabel: section.label, meetingLabel: meeting.label, color: course.color, time: $0, isConflict: false)
                    }
                }
            }
        }
        return classes + unavailableEvents
    }

    public var unavailableEvents: [PlannerEvent] {
        orderedUnavailableTimes.flatMap { blocked in
            blocked.orderedSlots.compactMap { slot in
                slot.weeklyTime.map {
                    PlannerEvent(kind: .unavailable(id: blocked.id, slotID: slot.id), code: "", name: blocked.name.trimmingCharacters(in: .whitespaces), sectionLabel: "", meetingLabel: "", color: blocked.color, time: $0, isConflict: false)
                }
            }
        }
    }
}

public struct CalendarLayout: Sendable {
    public struct Placement: Hashable, Sendable, Identifiable {
        public let event: PlannerEvent
        public let day: Weekday
        public let lane: Int
        public let laneCount: Int

        public var id: String { "\(event.id.uuidString)-\(day.rawValue)" }
    }

    public static let defaultHours = 8..<17

    public let days: [Weekday]
    public let hours: Range<Int>
    public let placements: [Placement]

    public init(events: [PlannerEvent], weekStart: Weekday, showWeekends: Bool) {
        let classDays = events.filter(\.isClass).reduce(Weekdays()) { $0.union($1.time.weekdays) }
        let days = Weekday.week(startingOn: weekStart).filter { showWeekends || !$0.isWeekend || classDays.includes($0) }
        let visible = Weekdays(days: days)
        let shown = events.filter { !$0.time.weekdays.intersection(visible).isEmpty }
        if let first = shown.map(\.time.startMinute).min(), let last = shown.map(\.time.endMinute).max() {
            hours = (first / 60)..<max(first / 60 + 1, (last + 59) / 60)
        } else {
            hours = Self.defaultHours
        }
        self.days = days
        placements = days.flatMap { day in Self.lanes(for: shown.filter { $0.time.weekdays.includes(day) }, on: day) }
    }

    public func placements(on day: Weekday) -> [Placement] {
        placements.filter { $0.day == day }
    }

    public func hoursFromTop(_ minute: Int) -> Double {
        Double(minute - hours.lowerBound * 60) / 60
    }

    private static func lanes(for events: [PlannerEvent], on day: Weekday) -> [Placement] {
        let sorted = events.sorted { ($0.time.startMinute, -$0.time.endMinute, $0.id.uuidString) < ($1.time.startMinute, -$1.time.endMinute, $1.id.uuidString) }
        var result: [Placement] = []
        var cluster: [(event: PlannerEvent, lane: Int)] = []
        var laneEnds: [Int] = []
        var clusterEnd = Int.min
        func flush() {
            result += cluster.map { Placement(event: $0.event, day: day, lane: $0.lane, laneCount: laneEnds.count) }
            cluster.removeAll()
            laneEnds.removeAll()
        }
        for event in sorted {
            if !cluster.isEmpty, event.time.startMinute >= clusterEnd { flush() }
            let lane = laneEnds.firstIndex { $0 <= event.time.startMinute } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(event.time.endMinute) } else { laneEnds[lane] = event.time.endMinute }
            cluster.append((event, lane))
            clusterEnd = cluster.count == 1 ? event.time.endMinute : max(clusterEnd, event.time.endMinute)
        }
        flush()
        return result
    }
}
