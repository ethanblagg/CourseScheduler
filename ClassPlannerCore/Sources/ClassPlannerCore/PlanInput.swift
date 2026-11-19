import Foundation

public struct PlanInput: Hashable, Sendable {
    public struct CourseInput: Hashable, Sendable {
        public let id: UUID
        public let sections: [SectionInput]
    }

    public struct SectionInput: Hashable, Sendable {
        public let id: UUID
        public let meetings: [TimeInput]
    }

    public struct UnavailableInput: Hashable, Sendable {
        public let id: UUID
        public let times: [TimeInput]
    }

    public struct TimeInput: Hashable, Sendable {
        public let id: UUID
        public let time: WeeklyTime
    }

    public let courses: [CourseInput]
    public let unavailable: [UnavailableInput]
}

public enum PlanEntry: Hashable, Sendable {
    case course(UUID)
    case unavailable(UUID)
}

public enum PlanReadiness: Hashable, Sendable {
    case empty
    case incomplete([PlanEntry])
    case ready(PlanInput)
}

extension Plan {
    public var readiness: PlanReadiness {
        guard !courses.isEmpty else { return .empty }
        let unfinished = orderedCourses.filter { !$0.isComplete }.map { PlanEntry.course($0.id) }
            + orderedUnavailableTimes.filter { !$0.isComplete }.map { PlanEntry.unavailable($0.id) }
        guard unfinished.isEmpty else { return .incomplete(unfinished) }
        return .ready(PlanInput(
            courses: orderedCourses.map { course in
                .init(id: course.id, sections: course.orderedSections.map { section in
                    .init(id: section.id, meetings: section.orderedMeetings.compactMap { meeting in
                        meeting.weeklyTime.map { .init(id: meeting.id, time: $0) }
                    })
                })
            },
            unavailable: orderedUnavailableTimes.map { blocked in
                .init(id: blocked.id, times: blocked.orderedSlots.compactMap { slot in
                    slot.weeklyTime.map { .init(id: slot.id, time: $0) }
                })
            }
        ))
    }
}
