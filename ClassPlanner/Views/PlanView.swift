import ClassPlannerCore
import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(UndoCenter.self) private var undoCenter
    @Bindable var plan: Plan
    @FocusState private var editingName: Bool
    @State private var deleting = false

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
                    NavigationLink(value: Route.course(course, isNew: false)) {
                        EntryRow(title: course.title, detail: course.detail, color: course.color, striped: false, isComplete: course.isComplete)
                    }
                }
                Button("Add course", systemImage: "plus") {
                    router.path.append(.course(plan.addCourse(), isNew: true))
                }
            }

            Section("Unavailable") {
                ForEach(plan.orderedUnavailableTimes) { time in
                    NavigationLink(value: Route.unavailable(time, isNew: false)) {
                        EntryRow(title: time.title, detail: time.detail, color: time.color, striped: true, isComplete: time.isComplete)
                    }
                }
                Button("Add time", systemImage: "plus") {
                    router.path.append(.unavailable(plan.addUnavailableTime(), isNew: true))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu("Plan options", systemImage: "ellipsis") {
                Button("Delete plan", systemImage: "trash", role: .destructive) {
                    deleting = true
                    router.path.removeAll()
                }
            }
        }
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
        .onDisappear {
            if deleting { delete() } else { restoreBlankName() }
        }
    }

    private var firstUnfinished: (title: String, route: Route)? {
        guard case .incomplete(let entries) = plan.readiness, let entry = entries.first else { return nil }
        switch entry {
        case .course(let id):
            return plan.courses.first { $0.id == id }.map { ($0.title, .course($0, isNew: false)) }
        case .unavailable(let id):
            return plan.unavailableTimes.first { $0.id == id }.map { ($0.title, .unavailable($0, isNew: false)) }
        }
    }

    private func restoreBlankName() {
        guard plan.modelContext != nil, plan.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let others = ((try? context.fetch(FetchDescriptor<Plan>())) ?? []).filter { $0.id != plan.id }.map(\.name)
        plan.name = PlanName.unique(PlanName.upcomingTerm(on: .now), among: others)
    }

    private func delete() {
        restoreBlankName()
        let name = plan.name
        let snapshot = Plan.remove(plan, from: context)
        try? context.save()
        undoCenter.offer("Deleted \(name)") {
            Plan.restore(snapshot, in: context)
            try? context.save()
        }
    }
}

struct EntryRow: View {
    let title: String
    let detail: String
    let color: PlannerColor
    let striped: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            Swatch(color: color, striped: striped)
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
