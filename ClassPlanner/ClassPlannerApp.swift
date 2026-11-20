import ClassPlannerCore
import SwiftData
import SwiftUI

@main
struct ClassPlannerApp: App {
    private let container: ModelContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        do {
            container = try PlannerStore.makeContainer(inMemory: arguments.contains("-ui-testing"))
        } catch {
            fatalError("Could not open saved plans: \(error)")
        }
        #if DEBUG
        if arguments.contains("-seed-sample") { SampleData.seed(in: container.mainContext) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
