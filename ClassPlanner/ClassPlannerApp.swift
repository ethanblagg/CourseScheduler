import ClassPlannerCore
import SwiftData
import SwiftUI

@main
struct ClassPlannerApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try PlannerStore.makeContainer()
        } catch {
            fatalError("Could not open saved plans: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
