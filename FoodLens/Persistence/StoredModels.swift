import Foundation
import SwiftData

// Every property has a default value and nothing is `.unique`, so the schema stays compatible
// with CloudKit sync if it is turned on later.

enum FoodLensSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredMeal.self, StoredWeight.self, StoredWater.self] }
}

enum FoodLensMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FoodLensSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum FoodLensPersistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FoodLensSchemaV1.self)
        let configuration = inMemory
            ? ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, migrationPlan: FoodLensMigrationPlan.self, configurations: configuration)
    }
}

@Model
final class StoredMeal {
    var id: UUID = UUID()
    var date: Date = Date.now
    var name: String = ""
    var grams: Double = 0
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var mealType: String = MealEntry.MealType.lunch.rawValue
    var ingredientsData: Data?
    var isFavorite: Bool = false

    init(entry: MealEntry) {
        id = entry.id
        apply(entry)
    }

    func apply(_ entry: MealEntry) {
        date = entry.date; name = entry.name; grams = entry.grams; calories = entry.calories
        protein = entry.protein; carbs = entry.carbs; fat = entry.fat; fiber = entry.fiber
        mealType = entry.mealType.rawValue
        ingredientsData = entry.ingredients.isEmpty ? nil : try? JSONEncoder().encode(entry.ingredients)
        isFavorite = entry.isFavorite
    }

    var entry: MealEntry {
        let ingredients = ingredientsData.flatMap { try? JSONDecoder().decode([FoodComponent].self, from: $0) } ?? []
        return MealEntry(
            id: id, date: date, name: name, grams: grams, calories: calories,
            protein: protein, carbs: carbs, fat: fat, fiber: fiber,
            mealType: MealEntry.MealType(storageValue: mealType) ?? .lunch,
            ingredients: ingredients, isFavorite: isFavorite
        )
    }
}

@Model
final class StoredWeight {
    var id: UUID = UUID()
    var date: Date = Date.now
    var kilograms: Double = 0

    init(record: WeightRecord) {
        id = record.id; date = record.date; kilograms = record.kilograms
    }

    var record: WeightRecord { WeightRecord(id: id, date: date, kilograms: kilograms) }
}

@Model
final class StoredWater {
    var id: UUID = UUID()
    var date: Date = Date.now
    var milliliters: Double = 0

    init(log: WaterLog) {
        id = log.id; date = log.date; milliliters = log.milliliters
    }

    var log: WaterLog { WaterLog(id: id, date: date, milliliters: milliliters) }
}
