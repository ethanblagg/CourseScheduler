import Foundation

public enum PlanName {
    public static func upcomingTerm(on date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2000
        switch parts.month ?? 1 {
        case 10...12: return "Spring \(year + 1)"
        case 1: return "Spring \(year)"
        default: return "Fall \(year)"
        }
    }

    public static func unique(_ base: String, among existing: some Sequence<String>) -> String {
        let taken = Set(existing.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) (\(number))".lowercased()) { number += 1 }
        return "\(base) (\(number))"
    }
}
