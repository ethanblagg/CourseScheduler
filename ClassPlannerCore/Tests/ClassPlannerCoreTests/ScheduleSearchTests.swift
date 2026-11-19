import Foundation
import SwiftData
import Testing
@testable import ClassPlannerCore

private func time(_ days: [Weekday], _ start: String, _ end: String) -> WeeklyTime {
    func minutes(_ text: String) -> Int {
        let parts = text.split(separator: ":").map { Int($0)! }
        return parts[0] * 60 + parts[1]
    }
    return try! WeeklyTime(weekdays: Weekdays(days: days), startMinute: minutes(start), endMinute: minutes(end))
}

private struct Fixture {
    var courses: [PlanInput.CourseInput] = []
    var unavailable: [PlanInput.UnavailableInput] = []
    var names: [UUID: String] = [:]

    @discardableResult
    mutating func course(_ code: String, _ sections: [(String, [WeeklyTime])]) -> UUID {
        let id = UUID()
        names[id] = code
        var built: [PlanInput.SectionInput] = []
        for (label, times) in sections {
            let sectionID = UUID()
            names[sectionID] = "\(code)-\(label)"
            var meetings: [PlanInput.TimeInput] = []
            for (index, time) in times.enumerated() {
                let meetingID = UUID()
                names[meetingID] = "\(code)-\(label)#\(index)"
                meetings.append(.init(id: meetingID, time: time))
            }
            built.append(.init(id: sectionID, meetings: meetings))
        }
        courses.append(.init(id: id, sections: built))
        return id
    }

    @discardableResult
    mutating func unavailable(_ name: String, _ times: [WeeklyTime]) -> UUID {
        let id = UUID()
        names[id] = name
        unavailable.append(.init(id: id, times: times.map { .init(id: UUID(), time: $0) }))
        return id
    }

    var input: PlanInput { PlanInput(courses: courses, unavailable: unavailable) }

    func outcome(_ options: ScheduleSearch.Options = .init()) -> ScheduleOutcome {
        try! ScheduleSearch.run(input, options: options)
    }

    func results(_ options: ScheduleSearch.Options = .init()) -> ScheduleResults? {
        guard case .schedules(let results) = outcome(options) else { return nil }
        return results
    }

    func explanation() -> NoFitExplanation? {
        guard case .noneFit(let explanation) = outcome() else { return nil }
        return explanation
    }

    func labels(_ schedule: Schedule) -> Set<String> {
        Set(schedule.selections.map { names[$0.sectionID]! })
    }

    func labelSets(_ results: ScheduleResults?) -> Set<Set<String>> {
        Set((results?.schedules(by: .fewestDays) ?? []).map(labels))
    }

    func describe(_ clash: Clash) -> String {
        let meeting = names[clash.meeting.meetingID]!
        switch clash.other {
        case .meeting(let ref): return [meeting, names[ref.meetingID]!].sorted().joined(separator: " × ")
        case .unavailable(let id, _): return "\(meeting) × \(names[id]!)"
        }
    }
}

private func overlapping(_ a: WeeklyTime, _ b: WeeklyTime) -> Bool {
    a.weekdays.rawValue & b.weekdays.rawValue != 0 && a.startMinute < b.endMinute && b.startMinute < a.endMinute
}

private func bruteForce(_ input: PlanInput, courses subset: [Int]? = nil) -> Set<ScheduleKey> {
    let chosenCourses = (subset ?? Array(input.courses.indices)).map { input.courses[$0] }
    let slots = input.unavailable.flatMap { $0.times.map(\.time) }
    var keys = Set<ScheduleKey>()
    func walk(_ index: Int, _ picked: [PlanInput.SectionInput]) {
        if index == chosenCourses.count {
            let times = picked.map { $0.meetings.map(\.time) }
            for (i, first) in times.enumerated() {
                if first.contains(where: { m in slots.contains { overlapping(m, $0) } }) { return }
                for second in times[(i + 1)...] where first.contains(where: { m in second.contains { overlapping(m, $0) } }) { return }
            }
            keys.insert(ScheduleKey(sectionIDs: picked.map(\.id)))
            return
        }
        for section in chosenCourses[index].sections { walk(index + 1, picked + [section]) }
    }
    walk(0, [])
    return keys
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private func randomFixture(seed: UInt64) -> Fixture {
    var generator = SeededGenerator(state: seed)
    var fixture = Fixture()
    let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    func randomTime() -> WeeklyTime {
        let days = (0..<Int.random(in: 1...2, using: &generator)).map { _ in weekdays.randomElement(using: &generator)! }
        let start = 8 * 60 + 30 * Int.random(in: 0...16, using: &generator)
        let length = 30 * Int.random(in: 1...3, using: &generator)
        return try! WeeklyTime(weekdays: Weekdays(days: days), startMinute: start, endMinute: start + length)
    }
    for course in 0..<Int.random(in: 1...5, using: &generator) {
        let sections = (0..<Int.random(in: 1...3, using: &generator)).map { section in
            (String(format: "%02d", section + 1), (0..<Int.random(in: 1...2, using: &generator)).map { _ in randomTime() })
        }
        fixture.course("C\(course)", sections)
    }
    for blocked in 0..<Int.random(in: 0...2, using: &generator) {
        fixture.unavailable("U\(blocked)", [randomTime()])
    }
    return fixture
}

struct OverlapTests {
    @Test func sameDayOverlapsAndOtherDaysDoNot() {
        #expect(time([.tuesday], "15:00", "16:00").overlap(with: time([.tuesday], "15:30", "16:30")) == TimeOverlap(days: Weekdays(days: [.tuesday]), startMinute: 930, endMinute: 960))
        #expect(time([.tuesday], "15:00", "16:00").overlap(with: time([.wednesday], "15:00", "16:00")) == nil)
        #expect(time([.monday, .wednesday], "09:00", "10:00").overlap(with: time([.wednesday, .friday], "09:30", "11:00"))?.days == Weekdays(days: [.wednesday]))
    }

    @Test func containmentAndEqualTimesOverlapInEitherOrder() {
        let outer = time([.monday], "09:00", "12:00")
        let inner = time([.monday], "10:00", "11:00")
        #expect(outer.overlap(with: inner)?.startMinute == 600)
        #expect(inner.overlap(with: outer) == outer.overlap(with: inner))
        let same = time([.monday], "09:00", "10:00")
        #expect(same.overlap(with: same) == TimeOverlap(days: Weekdays(days: [.monday]), startMinute: 540, endMinute: 600))
    }

    @Test func touchingTimesFitButOneMinuteOverlaps() {
        #expect(time([.monday], "09:00", "10:00").overlap(with: time([.monday], "10:00", "11:00")) == nil)
        #expect(time([.monday], "10:00", "11:00").overlap(with: time([.monday], "09:00", "10:00")) == nil)
        #expect(time([.monday], "09:00", "10:01").overlap(with: time([.monday], "10:00", "11:00"))?.endMinute == 601)
    }

    @Test func noonAndMidnightArePlainMinutes() {
        #expect(time([.friday], "11:30", "12:30").overlap(with: time([.friday], "12:00", "13:00"))?.startMinute == 720)
        #expect(time([.friday], "00:00", "00:30").overlap(with: time([.friday], "00:30", "01:00")) == nil)
    }
}

struct ScheduleSearchTests {
    @Test func picksOneSectionPerCourseAndAllowsTouchingTimes() {
        var f = Fixture()
        f.course("ENGL", [("01", [time([.monday], "09:00", "10:00")])])
        f.course("MATH", [("01", [time([.monday], "10:00", "11:00")]), ("02", [time([.monday], "09:59", "10:30")])])
        #expect(f.labelSets(f.results()) == [["ENGL-01", "MATH-01"]])
    }

    @Test func aConflictingLabRejectsItsWholeSection() {
        var f = Fixture()
        f.unavailable("Work", [time([.tuesday], "14:00", "17:00")])
        f.course("CHEM", [
            ("01", [time([.monday], "09:00", "10:00"), time([.tuesday], "15:00", "16:00")]),
            ("02", [time([.wednesday], "10:00", "11:00"), time([.thursday], "10:00", "11:00")])
        ])
        #expect(f.labelSets(f.results()) == [["CHEM-02"]])
    }

    @Test func workBlocksTuesdayChemistryAndNamesTheConflictWhenNothingElseFits() throws {
        var f = Fixture()
        let work = f.unavailable("Work", [time([.tuesday], "14:00", "17:00")])
        f.course("CHEM", [("01", [time([.tuesday], "15:00", "16:00")]), ("02", [time([.wednesday], "10:00", "11:00")])])
        #expect(f.labelSets(f.results()) == [["CHEM-02"]])

        var g = Fixture()
        g.unavailable("Work", [time([.tuesday], "14:00", "17:00")])
        let chemistry = g.course("CHEM", [("01", [time([.tuesday], "15:00", "16:00")])])
        g.names[work] = "Work"
        let explanation = try #require(g.explanation())
        #expect(explanation.conflictingCourseSets == [[chemistry]])
        #expect(explanation.clashes.map(g.describe) == ["CHEM-01#0 × Work"])
        #expect(explanation.clashes.first?.overlap == TimeOverlap(days: Weekdays(days: [.tuesday]), startMinute: 900, endMinute: 960))
    }

    @Test func sectionsWithIdenticalTimesStayDistinct() throws {
        var f = Fixture()
        f.course("CHEM", [("01", [time([.monday], "09:00", "10:00")]), ("02", [time([.monday], "09:00", "10:00")])])
        f.course("MATH", [("01", [time([.tuesday], "09:00", "10:00")])])
        let results = try #require(f.results())
        #expect(results.totalCount == 2)
        #expect(f.labelSets(results) == [["CHEM-01", "MATH-01"], ["CHEM-02", "MATH-01"]])
    }

    @Test func matchesAnIndependentBruteForceSearch() throws {
        for seed in UInt64(1)...60 {
            let f = randomFixture(seed: seed)
            let expected = bruteForce(f.input)
            switch f.outcome() {
            case .schedules(let results):
                let found = results.schedules(by: .fewestDays)
                #expect(Set(found.map(\.key)) == expected, "seed \(seed)")
                #expect(results.totalCount == expected.count && results.isExhaustive, "seed \(seed)")
                let sections = Dictionary(uniqueKeysWithValues: f.courses.flatMap(\.sections).map { ($0.id, $0) })
                for schedule in found {
                    #expect(schedule.selections.map(\.courseID) == f.courses.map(\.id), "seed \(seed)")
                    #expect(schedule.summary == ScheduleSummary(classTimes: schedule.selections.flatMap { sections[$0.sectionID]!.meetings.map(\.time) }), "seed \(seed)")
                }
                #expect(Set(results.schedules(by: .shortestGaps).map(\.key)) == expected, "seed \(seed)")
            case .noneFit(let explanation):
                #expect(expected.isEmpty, "seed \(seed)")
                for set in explanation.conflictingCourseSets {
                    let indices = set.map { id in f.courses.firstIndex { $0.id == id }! }
                    #expect(bruteForce(f.input, courses: indices).isEmpty, "seed \(seed)")
                    for dropped in indices.indices where indices.count > 1 {
                        var smaller = indices
                        smaller.remove(at: dropped)
                        #expect(!bruteForce(f.input, courses: smaller).isEmpty, "seed \(seed) set is not minimal")
                    }
                }
            default:
                Issue.record("Unexpected outcome for seed \(seed)")
            }
        }
    }

    @Test func reorderingTheInputGivesTheSameSchedules() throws {
        for seed in UInt64(100)...120 {
            let f = randomFixture(seed: seed)
            var shuffled = f
            shuffled.courses = f.courses.reversed().map { .init(id: $0.id, sections: $0.sections.reversed().map { .init(id: $0.id, meetings: $0.meetings.reversed()) }) }
            shuffled.unavailable = f.unavailable.reversed()
            switch (f.outcome(), shuffled.outcome()) {
            case (.schedules(let a), .schedules(let b)):
                for order in ScheduleOrder.allCases {
                    #expect(a.schedules(by: order).map(\.key) == b.schedules(by: order).map(\.key), "seed \(seed)")
                    #expect(a.schedules(by: order).map(\.summary) == b.schedules(by: order).map(\.summary), "seed \(seed)")
                }
            case (.noneFit(let a), .noneFit(let b)):
                #expect(Set(a.conflictingCourseSets.map(Set.init)) == Set(b.conflictingCourseSets.map(Set.init)), "seed \(seed)")
                #expect(Set(a.clashes.map(f.describe)) == Set(b.clashes.map(f.describe)), "seed \(seed)")
            default:
                Issue.record("Outcome changed with input order for seed \(seed)")
            }
        }
    }

    @Test func summariesMatchHandWorkedExamples() throws {
        var f = Fixture()
        f.unavailable("Work", [time([.tuesday], "14:00", "17:00")])
        f.unavailable("Weekend shift", [time([.saturday], "10:00", "12:00")])
        f.course("CHEM", [
            ("01", [time([.tuesday], "15:00", "16:00"), time([.thursday], "10:00", "11:00")]),
            ("02", [time([.monday, .wednesday], "09:00", "10:00"), time([.wednesday], "10:00", "10:30")]),
            ("03", [time([.tuesday, .thursday], "09:00", "10:00"), time([.thursday], "10:00", "10:30")])
        ])
        f.course("MATH", [("01", [time([.monday, .wednesday], "11:00", "12:00"), time([.wednesday], "12:00", "12:15")])])
        let results = try #require(f.results())
        #expect(results.totalCount == 2)

        let compact = try #require(results.schedules(by: .fewestDays).first)
        #expect(f.labels(compact) == ["CHEM-02", "MATH-01"])
        #expect(compact.summary.campusDays == Weekdays(days: [.monday, .wednesday]))
        #expect(compact.summary.gapMinutes == 90)
        #expect(compact.summary.firstStartMinute == 540 && compact.summary.lastEndMinute == 735)

        let noGaps = try #require(results.schedules(by: .shortestGaps).first)
        #expect(f.labels(noGaps) == ["CHEM-03", "MATH-01"])
        #expect(noGaps.summary.campusDays == Weekdays(days: [.monday, .tuesday, .wednesday, .thursday]))
        #expect(noGaps.summary.gapMinutes == 0)

        let day = ScheduleSummary(classTimes: [time([.monday], "09:00", "10:00"), time([.monday], "10:00", "10:30"), time([.monday], "11:00", "12:00"), time([.friday], "13:00", "14:00")])
        #expect(day.campusDayCount == 2)
        #expect(day.gapMinutes == 30)
    }

    @Test func emptyPlansAndCoursesWithoutSectionsHaveExplicitOutcomes() throws {
        #expect(Fixture().outcome() == .noCourses)
        var f = Fixture()
        let empty = f.course("BIO", [])
        f.course("MATH", [("01", [time([.monday], "09:00", "10:00")])])
        let explanation = try #require(f.explanation())
        #expect(explanation.conflictingCourseSets == [[empty]])
        #expect(explanation.clashes.isEmpty)
    }

    @Test func coursesThatAlwaysOverlapAreNamedWithEveryReason() throws {
        var f = Fixture()
        f.unavailable("Work", [time([.tuesday], "14:00", "17:00")])
        let chemistry = f.course("CHEM", [("01", [time([.tuesday], "15:00", "16:00")]), ("02", [time([.monday], "09:00", "10:00")])])
        let math = f.course("MATH", [("01", [time([.monday], "09:30", "10:30")])])
        let explanation = try #require(f.explanation())
        #expect(explanation.conflictingCourseSets == [[chemistry, math]])
        #expect(Set(explanation.clashes.map(f.describe)) == ["CHEM-01#0 × Work", "CHEM-02#0 × MATH-01#0"])
    }

    @Test func findsAThreeWayConflictWhenEveryPairFits() throws {
        var f = Fixture()
        let slots = [time([.monday], "09:00", "10:00"), time([.monday], "10:00", "11:00")]
        let ids = ["A", "B", "C"].map { f.course($0, [("01", [slots[0]]), ("02", [slots[1]])]) }
        let explanation = try #require(f.explanation())
        #expect(explanation.conflictingCourseSets == [ids])
        #expect(explanation.clashes.count == 6)
    }

    @Test func keepsTheBestSchedulesAndCountsAll() throws {
        var f = Fixture()
        for (course, hour) in [("A", 8), ("B", 10), ("C", 12)] {
            f.course(course, [Weekday.monday, .tuesday, .wednesday, .thursday].enumerated().map { index, day in
                (String(format: "%02d", index + 1), [time([day], "\(hour):00", "\(hour):50")])
            })
        }
        let results = try #require(f.results(.init(keep: 5)))
        #expect(results.totalCount == 64 && results.isExhaustive && results.keptCount == 5)

        let everything = try #require(f.results(.init(keep: 100)))
        for order in ScheduleOrder.allCases {
            let all = everything.schedules(by: order)
            #expect(all.count == 64)
            #expect(zip(all, all.dropFirst()).allSatisfy { order.areInIncreasingOrder($0, $1) })
            #expect(results.schedules(by: order).map(\.key) == all.prefix(5).map(\.key))
        }
        #expect(everything.schedules(by: .fewestDays).first?.summary.campusDayCount == 1)
    }

    @Test func stopsAtItsBudgetWithoutClaimingCompleteness() throws {
        var f = Fixture()
        for (course, hour) in [("A", 8), ("B", 10), ("C", 12)] {
            f.course(course, [Weekday.monday, .tuesday, .wednesday].enumerated().map { index, day in
                (String(format: "%02d", index + 1), [time([day], "\(hour):00", "\(hour):50")])
            })
        }
        let partial = try #require(f.results(.init(nodeBudget: 10)))
        #expect(!partial.isExhaustive)
        #expect(partial.totalCount > 0 && partial.totalCount < 27)
        #expect(f.outcome(.init(nodeBudget: 2)) == .inconclusive)
    }

    @Test func cancellingStopsTheSearch() async {
        var f = Fixture()
        for course in 0..<7 {
            f.course("C\(course)", (0..<8).map { section in
                (String(section), [time([Weekday.allCases[section % 7]], "\(8 + course):00", "\(8 + course):50")])
            })
        }
        let input = f.input
        let task = Task { try await ScheduleSearch.outcome(for: input) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @MainActor
    @Test func savedPlansFeedTheEngine() throws {
        let context = ModelContext(try PlannerStore.makeContainer(inMemory: true))
        let plan = Plan(name: "Fall 2026")
        context.insert(plan)
        func set(_ fields: some WeeklyTimeFields, _ days: [Weekday], _ start: Int, _ end: Int) {
            fields.weekdays = Weekdays(days: days)
            fields.startMinute = start
            fields.endMinute = end
        }
        let chemistry = plan.addCourse()
        chemistry.code = "CHEM 101"
        set(chemistry.orderedSections[0].orderedMeetings[0], [.tuesday], 900, 960)
        let second = chemistry.addSection()
        set(second.orderedMeetings[0], [.monday, .wednesday], 540, 600)
        let math = plan.addCourse()
        math.code = "MATH 120"
        set(math.orderedSections[0].orderedMeetings[0], [.monday, .wednesday], 660, 720)
        set(plan.addUnavailableTime().orderedSlots[0], [.tuesday], 840, 1020)

        guard case .ready(let input) = plan.readiness, case .schedules(let results) = try ScheduleSearch.run(input) else {
            Issue.record("Expected schedules")
            return
        }
        #expect(results.schedules(by: .fewestDays).map(\.key) == [ScheduleKey(sectionIDs: [second.id, math.orderedSections[0].id])])
        #expect(results.schedules(by: .fewestDays).first?.selections.map(\.courseID) == [chemistry.id, math.id])
    }
}
