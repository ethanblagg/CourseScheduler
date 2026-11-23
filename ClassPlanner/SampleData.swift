#if DEBUG
import ClassPlannerCore
import Foundation
import SwiftData

enum SampleData {
    static func seed(in context: ModelContext) {
        let plan = Plan(name: "Fall 2026", createdAt: Date(timeIntervalSince1970: 1_780_000_000))
        context.insert(plan)
        func set(_ fields: some WeeklyTimeFields, _ days: [Weekday], _ start: Int, _ end: Int) {
            fields.weekdays = Weekdays(days: days)
            fields.startMinute = start
            fields.endMinute = end
        }
        let chemistry = plan.addCourse()
        chemistry.code = "CHEM 101"
        chemistry.name = "Chemistry"
        let patterns: [([Weekday], Int, Int, [Weekday], Int, Int)] = [
            ([.tuesday], 900, 960, [.thursday], 600, 660),
            ([.monday, .wednesday], 540, 600, [.wednesday], 600, 630),
            ([.tuesday, .thursday], 540, 600, [.thursday], 600, 630)
        ]
        for (index, pattern) in patterns.enumerated() {
            let section = index == 0 ? chemistry.orderedSections[0] : chemistry.addSection()
            set(section.orderedMeetings[0], pattern.0, pattern.1, pattern.2)
            set(section.addMeeting(label: "Lab"), pattern.3, pattern.4, pattern.5)
        }
        let calculus = plan.addCourse()
        calculus.code = "MATH 120"
        calculus.name = "Calculus"
        set(calculus.orderedSections[0].orderedMeetings[0], [.monday, .wednesday], 660, 720)
        set(calculus.orderedSections[0].addMeeting(label: "Tutorial"), [.wednesday], 720, 735)
        let work = plan.addUnavailableTime()
        work.name = "Work"
        set(work.orderedSlots[0], [.tuesday], 840, 1020)
        let weekend = plan.addUnavailableTime()
        weekend.name = "Weekend shift"
        set(weekend.orderedSlots[0], [.saturday], 600, 720)
        try? context.save()
    }

    static func seedDisplay(in context: ModelContext) {
        let plan = Plan(name: "Display test", createdAt: Date(timeIntervalSince1970: 1_770_000_000))
        context.insert(plan)
        func set(_ fields: some WeeklyTimeFields, _ days: [Weekday], _ start: Int, _ end: Int) {
            fields.weekdays = Weekdays(days: days)
            fields.startMinute = start
            fields.endMinute = end
        }
        func course(_ code: String, _ name: String, _ meetings: [(String, [Weekday], Int, Int)]) {
            let course = plan.addCourse()
            course.code = code
            course.name = name
            let section = course.orderedSections[0]
            for (index, meeting) in meetings.enumerated() {
                let entry = index == 0 ? section.orderedMeetings[0] : section.addMeeting()
                entry.label = meeting.0
                set(entry, meeting.1, meeting.2, meeting.3)
            }
        }
        course("ENVS 1015", "Introduction to Environmental Science and Sustainability", [("Lecture", [.monday, .wednesday, .friday], 450, 500)])
        course("MATH 120", "Calculus", [("Lecture", [.monday, .wednesday], 660, 720), ("Tutorial", [.wednesday], 720, 735)])
        course("BIO 110", "Biology", [("Lecture", [.tuesday, .thursday], 570, 645), ("Lab", [.saturday], 540, 720)])
        course("ART 240", "Evening Studio", [("Studio", [.thursday], 1140, 1300)])
        let work = plan.addUnavailableTime()
        work.name = "Work"
        set(work.orderedSlots[0], [.tuesday, .thursday], 780, 1080)
        set(work.addSlot(), [.friday], 540, 780)
        let weekend = plan.addUnavailableTime()
        weekend.name = "Weekend shift"
        set(weekend.orderedSlots[0], [.sunday], 600, 840)
        try? context.save()
    }
}
#endif
