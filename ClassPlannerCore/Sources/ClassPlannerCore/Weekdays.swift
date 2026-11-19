public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: Int { rawValue }

    public var shortName: String {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][rawValue]
    }

    public var name: String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][rawValue]
    }

    public var isWeekend: Bool {
        self == .saturday || self == .sunday
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func week(startingOn first: Weekday) -> [Weekday] {
        Array(allCases[first.rawValue...] + allCases[..<first.rawValue])
    }
}

public struct Weekdays: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue & 0b111_1111
    }

    public init(days: some Sequence<Weekday>) {
        self.init(rawValue: days.reduce(0) { $0 | (1 << $1.rawValue) })
    }

    public func includes(_ day: Weekday) -> Bool {
        rawValue & (1 << day.rawValue) != 0
    }

    public var days: [Weekday] {
        Weekday.allCases.filter(includes)
    }

    public mutating func toggle(_ day: Weekday) {
        formSymmetricDifference(Weekdays(days: [day]))
    }
}
