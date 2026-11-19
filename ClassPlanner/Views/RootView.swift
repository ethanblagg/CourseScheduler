import ClassPlannerCore
import SwiftData
import SwiftUI

enum Route: Hashable {
    case plan(Plan)
    case course(Course)
    case unavailable(UnavailableTime)
}

@Observable
final class Router {
    var path: [Route] = []
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = Router()
    @State private var started = false

    var body: some View {
        NavigationStack(path: $router.path) {
            PlansView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .plan(let plan): PlanView(plan: plan)
                    case .course(let course): CourseView(course: course)
                    case .unavailable(let time): UnavailableView(time: time)
                    }
                }
        }
        .environment(router)
        .onAppear(perform: start)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { try? context.save() }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        guard (try? context.fetchCount(FetchDescriptor<Plan>())) == 0, let plan = try? Plan.create(in: context) else { return }
        router.path = [.plan(plan)]
    }
}
