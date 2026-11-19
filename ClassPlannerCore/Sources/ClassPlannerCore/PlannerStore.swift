import Foundation
import SwiftData

public enum PlannerSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Plan.self, Course.self, CourseSection.self, Meeting.self, UnavailableTime.self, TimeSlot.self]
    }
}

public enum PlannerMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [PlannerSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum PlannerStore {
    public static func makeContainer(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PlannerSchemaV1.self)
        let configuration = if inMemory {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let storeURL {
            ModelConfiguration(schema: schema, url: storeURL)
        } else {
            ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, migrationPlan: PlannerMigrationPlan.self, configurations: configuration)
    }
}
