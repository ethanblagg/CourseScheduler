import ClassPlannerCore
import SwiftData
import SwiftUI

struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(UndoCenter.self) private var undoCenter
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]

    var body: some View {
        List {
            ForEach(plans) { plan in
                NavigationLink(value: Route.plan(plan)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                            .font(.headline)
                        Text("^[\(plan.courses.count) course](inflect: true)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for plan in offsets.map({ plans[$0] }) { delete(plan) }
            }
        }
        .navigationTitle("Plans")
        .toolbar {
            Button("New plan", systemImage: "plus", action: newPlan)
        }
        .overlay {
            if plans.isEmpty {
                Button("New plan", action: newPlan)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private func newPlan() {
        guard let plan = try? Plan.create(in: context) else { return }
        router.path.append(.plan(plan))
    }

    private func delete(_ plan: Plan) {
        let name = plan.name
        let snapshot = Plan.remove(plan, from: context)
        try? context.save()
        undoCenter.offer("Deleted \(name)") {
            Plan.restore(snapshot, in: context)
            try? context.save()
        }
    }
}
