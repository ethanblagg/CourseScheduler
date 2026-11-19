public enum PlannerColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case blue, teal, green, purple, pink, red, orange, gray

    public static let courseDefault = PlannerColor.blue
    public static let unavailableDefault = PlannerColor.gray

    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
}
