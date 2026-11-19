public enum WeeklyTimeError: Error, Equatable, Sendable {
    case noDays
    case missingStart
    case missingEnd
    case outOfRange
    case endNotAfterStart
}

public struct WeeklyTime: Hashable, Codable, Sendable {
    public static let minutesPerDay = 24 * 60

    public let weekdays: Weekdays
    public let startMinute: Int
    public let endMinute: Int

    public init(weekdays: Weekdays, startMinute: Int, endMinute: Int) throws(WeeklyTimeError) {
        guard !weekdays.isEmpty else { throw .noDays }
        let day = 0..<Self.minutesPerDay
        guard day.contains(startMinute), day.contains(endMinute) else { throw .outOfRange }
        guard endMinute > startMinute else { throw .endNotAfterStart }
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public static func validate(weekdays: Weekdays, start: Int?, end: Int?) -> Result<WeeklyTime, WeeklyTimeError> {
        guard !weekdays.isEmpty else { return .failure(.noDays) }
        guard let start else { return .failure(.missingStart) }
        guard let end else { return .failure(.missingEnd) }
        return Result { () throws(WeeklyTimeError) in try WeeklyTime(weekdays: weekdays, startMinute: start, endMinute: end) }
    }
}
