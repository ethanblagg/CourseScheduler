import ClassPlannerCore
import SwiftData
import SwiftUI

struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]

    var body: some View {
        List(plans) { plan in
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
}
