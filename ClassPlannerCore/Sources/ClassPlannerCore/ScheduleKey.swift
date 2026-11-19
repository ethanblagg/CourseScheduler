import Foundation

public struct ScheduleKey: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(sectionIDs: some Sequence<UUID>) {
        rawValue = sectionIDs.map(\.uuidString).sorted().joined(separator: "|")
    }
}
