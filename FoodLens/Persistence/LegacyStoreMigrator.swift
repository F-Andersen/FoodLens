import Foundation

/// Reads data written by v0.1–v0.2 (JSON blobs in UserDefaults).
///
/// The legacy blobs are never deleted: they stay in UserDefaults as a backup, and the migration
/// is only marked complete after the new store has saved successfully.
enum LegacyStoreMigrator {
    static let migratedFlagKey = "foodlens_swiftdata_migrated_v1"
    static let snapshotKey = "foodlens_store_v2"
    static let listKey = "meal_diary_v1"

    struct LegacyData {
        var meals: [MealEntry] = []
        var weights: [WeightRecord] = []
        var water: [WaterLog] = []
        var goals: NutritionGoals?
        /// Records that could not be decoded and were skipped (the rest are still migrated).
        var skippedRecords = 0
    }

    enum Outcome {
        case nothingToMigrate
        /// Legacy data exists but cannot be decoded at all. It must be kept, not overwritten.
        case unreadable
        case data(LegacyData)
    }

    static func load(from defaults: UserDefaults) -> Outcome {
        let decoder = JSONDecoder()
        if let blob = defaults.data(forKey: snapshotKey) {
            guard let snapshot = try? decoder.decode(Snapshot.self, from: blob) else { return .unreadable }
            var result = LegacyData()
            result.meals = snapshot.entries.compactMap { $0.value?.entry }
            result.weights = snapshot.weights.compactMap { $0.value?.record }
            result.skippedRecords = snapshot.entries.count - result.meals.count + snapshot.weights.count - result.weights.count
            result.goals = snapshot.goals
            if let water = snapshot.waterToday, water > 0 {
                result.water = [WaterLog(date: snapshot.waterDate ?? .now, milliliters: water)]
            }
            return .data(result)
        }
        if let blob = defaults.data(forKey: listKey) {
            guard let list = try? decoder.decode([Failable<LegacyMeal>].self, from: blob) else { return .unreadable }
            var result = LegacyData()
            result.meals = list.compactMap { $0.value?.entry }
            result.skippedRecords = list.count - result.meals.count
            return .data(result)
        }
        return .nothingToMigrate
    }

    private struct Snapshot: Decodable {
        var entries: [Failable<LegacyMeal>]
        var weights: [Failable<LegacyWeight>]
        var goals: NutritionGoals?
        var waterToday: Double?
        var waterDate: Date?

        enum CodingKeys: String, CodingKey { case entries, weights, goals, waterToday, waterDate }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entries = try c.decodeIfPresent([Failable<LegacyMeal>].self, forKey: .entries) ?? []
            weights = try c.decodeIfPresent([Failable<LegacyWeight>].self, forKey: .weights) ?? []
            goals = try? c.decodeIfPresent(NutritionGoals.self, forKey: .goals)
            waterToday = try? c.decodeIfPresent(Double.self, forKey: .waterToday)
            waterDate = try? c.decodeIfPresent(Date.self, forKey: .waterDate)
        }
    }

    /// Lets one corrupt element fail without discarding the whole array.
    private struct Failable<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
    }

    private struct LegacyMeal: Decodable {
        var id: UUID?
        var date: Date?
        var name: String
        var grams: Double
        var caloriesPer100g: Double
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var fiber: Double?
        var mealType: String?
        var ingredients: [FoodComponent]?
        var isFavorite: Bool?

        var entry: MealEntry {
            MealEntry(
                id: id ?? UUID(), date: date ?? .now, name: name, grams: grams,
                calories: grams * caloriesPer100g / 100,
                protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, fiber: fiber ?? 0,
                mealType: mealType.flatMap(MealEntry.MealType.init(storageValue:)) ?? .lunch,
                ingredients: ingredients ?? [], isFavorite: isFavorite ?? false
            )
        }
    }

    private struct LegacyWeight: Decodable {
        var id: UUID?
        var date: Date?
        var kilograms: Double

        var record: WeightRecord { WeightRecord(id: id ?? UUID(), date: date ?? .now, kilograms: kilograms) }
    }
}
