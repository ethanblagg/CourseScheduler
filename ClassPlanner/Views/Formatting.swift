import ClassPlannerCore
import SwiftUI

extension PlannerColor {
    var swatch: Color {
        switch self {
        case .blue: Color(red: 0.18, green: 0.44, blue: 0.89)
        case .teal: Color(red: 0.09, green: 0.58, blue: 0.59)
        case .green: Color(red: 0.18, green: 0.62, blue: 0.31)
        case .purple: Color(red: 0.51, green: 0.31, blue: 0.87)
        case .pink: Color(red: 0.84, green: 0.23, blue: 0.51)
        case .red: Color(red: 0.83, green: 0.22, blue: 0.18)
        case .orange: Color(red: 0.88, green: 0.48, blue: 0.12)
        case .gray: Color(red: 0.52, green: 0.52, blue: 0.55)
        }
    }
}

enum TimeText {
    static func clock(_ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func summary(_ time: WeeklyTime) -> String {
        "\(time.weekdays.days.map(\.shortName).formatted(.list(type: .and, width: .narrow))) \(clock(time.startMinute))–\(clock(time.endMinute))"
    }
}

extension Course {
    var title: String {
        let code = code.trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        return code.isEmpty ? (name.isEmpty ? "New course" : name) : code
    }

    var detail: String {
        let name = name.trimmingCharacters(in: .whitespaces)
        let count = sections.count == 1 ? "1 section" : "\(sections.count) sections"
        return code.trimmingCharacters(in: .whitespaces).isEmpty || name.isEmpty ? count : "\(name) · \(count)"
    }
}

extension UnavailableTime {
    var title: String {
        let name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Unavailable" : name
    }

    var detail: String {
        orderedSlots.compactMap(\.weeklyTime).map(TimeText.summary).joined(separator: " · ")
    }
}
