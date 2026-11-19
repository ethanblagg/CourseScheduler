import Foundation

public struct TimeOverlap: Hashable, Sendable {
    public let days: Weekdays
    public let startMinute: Int
    public let endMinute: Int
}

extension WeeklyTime {
    public func overlap(with other: WeeklyTime) -> TimeOverlap? {
        let days = weekdays.intersection(other.weekdays)
        let start = max(startMinute, other.startMinute)
        let end = min(endMinute, other.endMinute)
        guard !days.isEmpty, start < end else { return nil }
        return TimeOverlap(days: days, startMinute: start, endMinute: end)
    }
}

public struct Selection: Hashable, Sendable {
    public let courseID: UUID
    public let sectionID: UUID
}

public struct ScheduleSummary: Hashable, Sendable {
    public let campusDays: Weekdays
    public let gapMinutes: Int
    public let firstStartMinute: Int
    public let lastEndMinute: Int

    public var campusDayCount: Int { campusDays.rawValue.nonzeroBitCount }

    init(campusDays: Weekdays, gapMinutes: Int, firstStartMinute: Int, lastEndMinute: Int) {
        self.campusDays = campusDays
        self.gapMinutes = gapMinutes
        self.firstStartMinute = firstStartMinute
        self.lastEndMinute = lastEndMinute
    }

    public init(classTimes: [WeeklyTime]) {
        var days = Weekdays()
        var gaps = 0
        for day in Weekday.allCases {
            let intervals = classTimes.filter { $0.weekdays.includes(day) }.map { ($0.startMinute, $0.endMinute) }.sorted { $0 < $1 }
            guard var end = intervals.first?.1 else { continue }
            days.insert(Weekdays(days: [day]))
            for (start, finish) in intervals.dropFirst() {
                if start > end { gaps += start - end }
                end = max(end, finish)
            }
        }
        campusDays = days
        gapMinutes = gaps
        firstStartMinute = classTimes.map(\.startMinute).min() ?? 0
        lastEndMinute = classTimes.map(\.endMinute).max() ?? 0
    }
}

public struct Schedule: Hashable, Sendable, Identifiable {
    public let key: ScheduleKey
    public let selections: [Selection]
    public let summary: ScheduleSummary

    public var id: ScheduleKey { key }
}

public enum ScheduleOrder: Hashable, Sendable, CaseIterable {
    case fewestDays
    case shortestGaps

    public func areInIncreasingOrder(_ a: Schedule, _ b: Schedule) -> Bool {
        let comparison = compare(a.summary, b.summary)
        return comparison == 0 ? a.key.rawValue < b.key.rawValue : comparison < 0
    }

    func compare(_ x: ScheduleSummary, _ y: ScheduleSummary) -> Int {
        let (days, gaps) = ((x.campusDayCount, y.campusDayCount), (x.gapMinutes, y.gapMinutes))
        for (left, right) in self == .fewestDays ? [days, gaps] : [gaps, days] where left != right { return left < right ? -1 : 1 }
        for (left, right) in [(x.firstStartMinute, y.firstStartMinute), (x.lastEndMinute, y.lastEndMinute)] where left != right { return left < right ? -1 : 1 }
        return 0
    }
}

public struct ScheduleResults: Hashable, Sendable {
    public let totalCount: Int
    public let isExhaustive: Bool
    let ranked: [ScheduleOrder: [Schedule]]

    public func schedules(by order: ScheduleOrder) -> [Schedule] {
        ranked[order] ?? []
    }

    public var keptCount: Int {
        ranked.values.first?.count ?? 0
    }
}

public struct ClassMeetingRef: Hashable, Sendable {
    public let courseID: UUID
    public let sectionID: UUID
    public let meetingID: UUID
}

public struct Clash: Hashable, Sendable {
    public enum Other: Hashable, Sendable {
        case meeting(ClassMeetingRef)
        case unavailable(id: UUID, slotID: UUID)
    }

    public let meeting: ClassMeetingRef
    public let other: Other
    public let overlap: TimeOverlap
}

public struct NoFitExplanation: Hashable, Sendable {
    public let conflictingCourseSets: [[UUID]]
    public let clashes: [Clash]
}

public enum ScheduleOutcome: Hashable, Sendable {
    case noCourses
    case schedules(ScheduleResults)
    case noneFit(NoFitExplanation)
    case inconclusive
}

public enum ScheduleSearch {
    public struct Options: Hashable, Sendable {
        public var keep: Int
        public var nodeBudget: Int
        public var largestConflictSet: Int

        public init(keep: Int = 500, nodeBudget: Int = 2_000_000, largestConflictSet: Int = 4) {
            self.keep = max(1, keep)
            self.nodeBudget = nodeBudget
            self.largestConflictSet = largestConflictSet
        }
    }

    public static func run(_ input: PlanInput, options: Options = Options(), isCancelled: () -> Bool = { false }) throws(CancellationError) -> ScheduleOutcome {
        guard !input.courses.isEmpty else { return .noCourses }
        if isCancelled() { throw CancellationError() }
        let space = SearchSpace(input)
        let blocked = space.courses.indices.filter { space.courses[$0].open.isEmpty }
        if !blocked.isEmpty { return .noneFit(space.explain(blocked.map { [$0] })) }
        var walker = Walker(space: space, options: options)
        try walker.visit(depth: 0, isCancelled: isCancelled)
        if walker.total > 0 {
            return .schedules(ScheduleResults(totalCount: walker.total, isExhaustive: !walker.exhausted, ranked: walker.ranked))
        }
        if walker.exhausted { return .inconclusive }
        return .noneFit(try space.explanation(options: options, isCancelled: isCancelled))
    }

    @concurrent
    public static func outcome(for input: PlanInput, options: Options = Options()) async throws -> ScheduleOutcome {
        try run(input, options: options) { Task.isCancelled }
    }
}

private struct SearchSpace {
    struct Section {
        let course: Int
        let id: UUID
        let meetings: [PlanInput.TimeInput]
        let blockers: [Clash]
        let days: [[(start: Int, end: Int)]]
        let first: Int
        let last: Int

        init(course: Int, id: UUID, meetings: [PlanInput.TimeInput], blockers: [Clash]) {
            self.course = course
            self.id = id
            self.meetings = meetings
            self.blockers = blockers
            days = Weekday.allCases.map { day in
                meetings.filter { $0.time.weekdays.includes(day) }.map { (start: $0.time.startMinute, end: $0.time.endMinute) }
            }
            first = meetings.map(\.time.startMinute).min() ?? 0
            last = meetings.map(\.time.endMinute).max() ?? 0
        }
    }

    struct Course {
        let id: UUID
        let sections: [Int]
        let open: [Int]
    }

    let courses: [Course]
    let sections: [Section]
    let clashes: [[Bool]]

    init(_ input: PlanInput) {
        let slots = input.unavailable.flatMap { blocked in blocked.times.map { (owner: blocked.id, slot: $0) } }
        var sections: [Section] = []
        var courses: [Course] = []
        for (courseIndex, course) in input.courses.enumerated() {
            var indices: [Int] = []
            for section in course.sections.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let blockers = section.meetings.flatMap { meeting in
                    slots.compactMap { entry in
                        meeting.time.overlap(with: entry.slot.time).map {
                            Clash(meeting: ClassMeetingRef(courseID: course.id, sectionID: section.id, meetingID: meeting.id), other: .unavailable(id: entry.owner, slotID: entry.slot.id), overlap: $0)
                        }
                    }
                }
                indices.append(sections.count)
                sections.append(Section(course: courseIndex, id: section.id, meetings: section.meetings, blockers: blockers))
            }
            courses.append(Course(id: course.id, sections: indices, open: indices.filter { sections[$0].blockers.isEmpty }))
        }
        var clashes = Array(repeating: Array(repeating: false, count: sections.count), count: sections.count)
        for a in sections.indices {
            for b in sections.indices where b > a && sections[a].course != sections[b].course {
                let hit = sections[a].meetings.contains { m in sections[b].meetings.contains { m.time.overlap(with: $0.time) != nil } }
                clashes[a][b] = hit
                clashes[b][a] = hit
            }
        }
        self.courses = courses
        self.sections = sections
        self.clashes = clashes
    }

    func searchOrder(_ subset: [Int]) -> [Int] {
        subset.sorted { (courses[$0].open.count, courses[$0].id.uuidString) < (courses[$1].open.count, courses[$1].id.uuidString) }
    }

    func schedule(for chosen: [Int], summary: ScheduleSummary) -> Schedule {
        let picked = chosen.map { sections[$0] }.sorted { $0.course < $1.course }
        return Schedule(
            key: ScheduleKey(sectionIDs: picked.map(\.id)),
            selections: picked.map { Selection(courseID: courses[$0.course].id, sectionID: $0.id) },
            summary: summary
        )
    }

    func summary(of chosen: [Int], buffer: inout [(start: Int, end: Int)]) -> ScheduleSummary {
        var days = 0
        var gaps = 0
        var first = Int.max
        var last = Int.min
        for s in chosen {
            first = min(first, sections[s].first)
            last = max(last, sections[s].last)
        }
        for day in 0..<7 {
            buffer.removeAll(keepingCapacity: true)
            for s in chosen { buffer.append(contentsOf: sections[s].days[day]) }
            guard !buffer.isEmpty else { continue }
            days |= 1 << day
            buffer.sort { $0.start < $1.start }
            var end = buffer[0].end
            for interval in buffer.dropFirst() {
                if interval.start > end { gaps += interval.start - end }
                end = max(end, interval.end)
            }
        }
        return ScheduleSummary(campusDays: Weekdays(rawValue: days), gapMinutes: gaps, firstStartMinute: first, lastEndMinute: last)
    }

    func fits(_ subset: [Int], budget: Int, isCancelled: () -> Bool) throws(CancellationError) -> Bool? {
        let order = searchOrder(subset)
        var chosen = Array(repeating: -1, count: order.count)
        var nodes = 0
        func place(_ depth: Int) throws(CancellationError) -> Bool? {
            if depth == order.count { return true }
            for s in courses[order[depth]].open {
                nodes += 1
                if nodes > budget { return nil }
                if nodes % 4096 == 0, isCancelled() { throw CancellationError() }
                if chosen[..<depth].contains(where: { clashes[$0][s] }) { continue }
                chosen[depth] = s
                switch try place(depth + 1) {
                case true?: return true
                case nil: return nil
                case false?: continue
                }
            }
            return false
        }
        return try place(0)
    }

    func explanation(options: ScheduleSearch.Options, isCancelled: () -> Bool) throws(CancellationError) -> NoFitExplanation {
        let unknown = NoFitExplanation(conflictingCourseSets: [], clashes: [])
        guard courses.count >= 2 else { return unknown }
        for size in 2...min(courses.count, max(2, options.largestConflictSet)) {
            var found: [[Int]] = []
            for subset in combinations(Array(courses.indices), size) {
                guard let possible = try fits(subset, budget: options.nodeBudget, isCancelled: isCancelled) else { return unknown }
                if !possible { found.append(subset) }
            }
            if !found.isEmpty { return explain(found) }
        }
        return unknown
    }

    func explain(_ sets: [[Int]]) -> NoFitExplanation {
        var clashesFound: [Clash] = []
        var seen = Set<Clash>()
        func add(_ items: [Clash]) {
            for item in items where seen.insert(item).inserted { clashesFound.append(item) }
        }
        for set in sets {
            for course in set {
                for s in courses[course].sections { add(sections[s].blockers) }
            }
            for (i, first) in set.enumerated() {
                for second in set[(i + 1)...] {
                    let (lead, other) = courses[first].id.uuidString < courses[second].id.uuidString ? (first, second) : (second, first)
                    for a in courses[lead].open {
                        for b in courses[other].open where clashes[a][b] { add(meetingClashes(a, b)) }
                    }
                }
            }
        }
        return NoFitExplanation(conflictingCourseSets: sets.map { $0.map { courses[$0].id } }, clashes: clashesFound)
    }

    func meetingClashes(_ a: Int, _ b: Int) -> [Clash] {
        sections[a].meetings.flatMap { m in
            sections[b].meetings.compactMap { n in
                m.time.overlap(with: n.time).map {
                    Clash(
                        meeting: ClassMeetingRef(courseID: courses[sections[a].course].id, sectionID: sections[a].id, meetingID: m.id),
                        other: .meeting(ClassMeetingRef(courseID: courses[sections[b].course].id, sectionID: sections[b].id, meetingID: n.id)),
                        overlap: $0
                    )
                }
            }
        }
    }

    private func combinations(_ items: [Int], _ size: Int) -> [[Int]] {
        guard size > 0 else { return [[]] }
        guard items.count >= size else { return [] }
        let head = items[0]
        let rest = Array(items.dropFirst())
        return combinations(rest, size - 1).map { [head] + $0 } + combinations(rest, size)
    }
}

private struct Walker {
    let space: SearchSpace
    let options: ScheduleSearch.Options
    let order: [Int]
    var chosen: [Int]
    var buffer: [(start: Int, end: Int)] = []
    var nodes = 0
    var total = 0
    var exhausted = false
    var ranked: [ScheduleOrder: [Schedule]] = Dictionary(uniqueKeysWithValues: ScheduleOrder.allCases.map { ($0, []) })

    init(space: SearchSpace, options: ScheduleSearch.Options) {
        self.space = space
        self.options = options
        order = space.searchOrder(Array(space.courses.indices))
        chosen = Array(repeating: -1, count: order.count)
    }

    mutating func visit(depth: Int, isCancelled: () -> Bool) throws(CancellationError) {
        if depth == order.count {
            record()
            return
        }
        for s in space.courses[order[depth]].open {
            if exhausted { return }
            nodes += 1
            if nodes > options.nodeBudget {
                exhausted = true
                return
            }
            if nodes % 4096 == 0, isCancelled() { throw CancellationError() }
            if chosen[..<depth].contains(where: { space.clashes[$0][s] }) { continue }
            chosen[depth] = s
            try visit(depth: depth + 1, isCancelled: isCancelled)
        }
    }

    private mutating func record() {
        total += 1
        let summary = space.summary(of: chosen, buffer: &buffer)
        var schedule: Schedule?
        for order in ScheduleOrder.allCases {
            if let list = ranked[order], list.count == options.keep, let last = list.last {
                let comparison = order.compare(summary, last.summary)
                if comparison > 0 { continue }
                if comparison == 0 {
                    schedule = schedule ?? space.schedule(for: chosen, summary: summary)
                    if schedule!.key.rawValue >= last.key.rawValue { continue }
                }
            }
            schedule = schedule ?? space.schedule(for: chosen, summary: summary)
            Self.insert(schedule!, into: &ranked[order, default: []], order: order, keep: options.keep)
        }
    }

    private static func insert(_ schedule: Schedule, into list: inout [Schedule], order: ScheduleOrder, keep: Int) {
        if list.count == keep, let last = list.last, !order.areInIncreasingOrder(schedule, last) { return }
        var low = 0
        var high = list.count
        while low < high {
            let mid = (low + high) / 2
            if order.areInIncreasingOrder(schedule, list[mid]) { high = mid } else { low = mid + 1 }
        }
        list.insert(schedule, at: low)
        if list.count > keep { list.removeLast() }
    }
}
