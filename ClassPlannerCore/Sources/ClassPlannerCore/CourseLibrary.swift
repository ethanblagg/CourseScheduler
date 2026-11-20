import Foundation

public struct CourseSuggestion: Identifiable {
    public let source: Course
    public let planName: String

    public var id: UUID { source.id }
    public var code: String { source.code.trimmingCharacters(in: .whitespaces) }
    public var name: String { source.name.trimmingCharacters(in: .whitespaces) }
    public var color: PlannerColor { source.color }
    public var sectionCount: Int { source.sections.count }
}

extension Course {
    public func suggestions(from plans: [Plan], matching query: String) -> [CourseSuggestion] {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }
        let taken = Set((plan?.courses ?? []).filter { $0.id != id }.map { clean($0.code).lowercased() })
        var seen = Set<String>()
        var entries: [CourseSuggestion] = []
        for plan in plans.sorted(by: { $0.createdAt > $1.createdAt }) {
            for course in plan.orderedCourses where course.id != id && course.isComplete {
                let key = clean(course.code).lowercased()
                guard !key.isEmpty, !taken.contains(key), seen.insert(key).inserted else { continue }
                entries.append(CourseSuggestion(source: course, planName: plan.name))
            }
        }
        let currentCode = clean(code).lowercased()
        let currentName = clean(name)
        let search = clean(query).lowercased()
        return entries
            .filter { !($0.code.lowercased() == currentCode && $0.name == currentName) }
            .filter { search.isEmpty || $0.code.lowercased().contains(search) || $0.name.lowercased().contains(search) }
            .sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }

    public func adopt(_ suggestion: CourseSuggestion) {
        code = suggestion.code
        name = suggestion.name
        color = suggestion.color
    }

    @discardableResult
    public func copySections(from source: Course) -> [CourseSection] {
        let replacing = sections.allSatisfy { $0.meetings.allSatisfy(\.isBlank) }
        if replacing {
            for section in sections { modelContext?.delete(section) }
            sections.removeAll()
        }
        return source.orderedSections.map { appendCopy(of: $0, label: replacing ? $0.label : nil) }
    }
}
