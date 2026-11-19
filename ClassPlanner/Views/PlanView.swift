import ClassPlannerCore
import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Bindable var plan: Plan
    @FocusState private var editingName: Bool

    var body: some View {
        List {
            Section {
                TextField("Plan name", text: $plan.name)
                    .font(.largeTitle.bold())
                    .focused($editingName)
                    .submitLabel(.done)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            Section("Courses") {
                ForEach(plan.orderedCourses) { course in
                    NavigationLink(value: Route.course(course)) {
                        EntryRow(title: course.title, detail: course.detail, color: course.color, isComplete: course.isComplete)
                    }
                }
                Button("Add course", systemImage: "plus") {
                    router.path.append(.course(plan.addCourse()))
                }
            }

            Section("Unavailable") {
                ForEach(plan.orderedUnavailableTimes) { time in
                    NavigationLink(value: Route.unavailable(time)) {
                        EntryRow(title: time.title, detail: time.detail, color: time.color, isComplete: time.isComplete)
                    }
                }
                Button("Add time", systemImage: "plus") {
                    router.path.append(.unavailable(plan.addUnavailableTime()))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let entry = firstUnfinished {
                Button {
                    router.path.append(entry.route)
                } label: {
                    Text("Finish \(entry.title)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
        .onChange(of: editingName) { _, editing in
            if !editing { restoreBlankName() }
        }
        .onDisappear(perform: restoreBlankName)
    }

    private var firstUnfinished: (title: String, route: Route)? {
        guard case .incomplete(let entries) = plan.readiness, let entry = entries.first else { return nil }
        switch entry {
        case .course(let id):
            return plan.courses.first { $0.id == id }.map { ($0.title, .course($0)) }
        case .unavailable(let id):
            return plan.unavailableTimes.first { $0.id == id }.map { ($0.title, .unavailable($0)) }
        }
    }

    private func restoreBlankName() {
        guard plan.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let others = ((try? context.fetch(FetchDescriptor<Plan>())) ?? []).filter { $0.id != plan.id }.map(\.name)
        plan.name = PlanName.unique(PlanName.upcomingTerm(on: .now), among: others)
    }
}

struct EntryRow: View {
    let title: String
    let detail: String
    let color: PlannerColor
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.swatch)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !isComplete {
                Text("Incomplete")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}
