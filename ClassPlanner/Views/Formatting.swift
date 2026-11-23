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

struct Stripes: View {
    let color: Color
    var spacing: CGFloat = 6
    var width: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            var lines = Path()
            var x = -size.height
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(lines, with: .color(color), lineWidth: width)
        }
        .accessibilityHidden(true)
    }
}

struct Swatch: View {
    let color: PlannerColor
    let striped: Bool

    var body: some View {
        if striped {
            GeometryReader { geometry in
                Circle()
                    .fill(color.swatch.opacity(0.18))
                    .overlay {
                        Stripes(color: color.swatch, spacing: max(3, geometry.size.width / 4), width: max(1, geometry.size.width / 10))
                            .clipShape(Circle())
                    }
                    .overlay { Circle().strokeBorder(color.swatch, lineWidth: 1.5) }
            }
        } else {
            Circle().fill(color.swatch)
        }
    }
}

enum TimeText {
    private static let usesMeridiem = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true

    static func clock(_ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func range(_ time: WeeklyTime) -> String {
        let start = time.startMinute
        let end = time.endMinute
        guard usesMeridiem else { return "\(clock(start))–\(clock(end))" }
        func short(_ minute: Int, suffix: Bool) -> String {
            let hour = minute / 60
            let digits = minute % 60 == 0 ? "\(hour % 12 == 0 ? 12 : hour % 12)" : "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute % 60))"
            return suffix ? "\(digits) \(hour < 12 ? "AM" : "PM")" : digits
        }
        let sameHalf = (start < 720) == (end < 720)
        return "\(short(start, suffix: !sameHalf))–\(short(end, suffix: true))"
    }

    static func days(_ weekdays: Weekdays, weekStart: Weekday) -> String {
        Weekday.week(startingOn: weekStart).filter(weekdays.includes).map(\.shortName).formatted(.list(type: .and, width: .narrow))
    }

    static func summary(_ time: WeeklyTime) -> String {
        "\(days(time.weekdays, weekStart: .monday)) \(range(time))"
    }

    static func hour(_ hour: Int) -> String {
        clock((hour % 24) * 60)
            .replacingOccurrences(of: ":00", with: "")
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

extension PlannerEvent {
    var title: String {
        if !code.isEmpty { return code }
        if !name.isEmpty { return name }
        return isClass ? "Course" : "Unavailable"
    }

    var meetingDetail: String {
        [sectionLabel.isEmpty ? "" : "Section \(sectionLabel)", meetingLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func accessibilityText(on day: Weekday) -> String {
        let what = isClass ? meetingDetail : "unavailable"
        return [title, what, "\(day.name) \(TimeText.range(time))", isConflict ? "conflict" : ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
