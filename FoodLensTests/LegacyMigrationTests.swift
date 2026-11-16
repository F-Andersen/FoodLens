import Foundation
import Testing
@testable import FoodLens

@MainActor
@Suite("Migration from v0.2 UserDefaults storage")
struct LegacyMigrationTests {
    private func snapshotJSON(entries: String, weights: String = "[]", water: Double = 0, waterDate: Date = .now) -> Data {
        """
        {"entries": \(entries),
         "weights": \(weights),
         "goals": {"calories": 1800, "protein": 110, "carbs": 190, "fat": 60, "fiber": 28, "waterML": 2200},
         "waterToday": \(water),
         "waterDate": \(legacyDate(waterDate))}
        """.data(using: .utf8)!
    }

    @Test func migratesMealsWeightsGoalsAndWater() throws {
        let test = TestDefaults()
        let mealID = UUID()
        let entries = """
        [{"id": "\(mealID.uuidString)", "date": \(legacyDate(.now)), "name": "Борщ", "grams": 300, "caloriesPer100g": 50,
          "protein": 9, "carbs": 18, "fat": 6, "fiber": 4, "mealType": "Вечеря", "ingredients": [], "isFavorite": true}]
        """
        let weights = """
        [{"id": "\(UUID().uuidString)", "date": \(legacyDate(.now)), "kilograms": 81.5}]
        """
        test.defaults.set(snapshotJSON(entries: entries, weights: weights, water: 700), forKey: LegacyStoreMigrator.snapshotKey)

        let store = try makeStore(defaults: test.defaults)

        #expect(store.entries.count == 1)
        let meal = try #require(store.entries.first)
        #expect(meal.id == mealID)
        #expect(meal.calories == 150) // 300 g × 50 kcal / 100 g
        #expect(meal.mealType == .dinner) // legacy Ukrainian raw value
        #expect(meal.isFavorite)
        #expect(store.weights.map(\.kilograms) == [81.5])
        #expect(store.goals.calories == 1800)
        #expect(store.waterToday == 700)
        #expect(store.storageIssue == nil)
        #expect(test.defaults.bool(forKey: LegacyStoreMigrator.migratedFlagKey))
        // The legacy blob is kept as a backup.
        #expect(test.defaults.data(forKey: LegacyStoreMigrator.snapshotKey) != nil)
    }

    @Test func unreadableLegacyDataIsKeptAndNotMarkedMigrated() throws {
        let test = TestDefaults()
        let garbage = Data("not json".utf8)
        test.defaults.set(garbage, forKey: LegacyStoreMigrator.snapshotKey)

        let store = try makeStore(defaults: test.defaults)

        #expect(store.entries.isEmpty)
        #expect(store.storageIssue != nil)
        #expect(!test.defaults.bool(forKey: LegacyStoreMigrator.migratedFlagKey))
        #expect(test.defaults.data(forKey: LegacyStoreMigrator.snapshotKey) == garbage)

        // Adding a meal afterwards must not overwrite the legacy blob (the v0.2 data-loss bug).
        store.add(MealEntry(name: "Тест", grams: 100, calories: 100))
        #expect(test.defaults.data(forKey: LegacyStoreMigrator.snapshotKey) == garbage)
    }

    @Test func oneCorruptEntryDoesNotDiscardTheOthers() throws {
        let test = TestDefaults()
        let entries = """
        [{"name": "Добрий запис", "grams": 200, "caloriesPer100g": 100},
         {"name": "Без ваги"},
         {"name": "Ще один", "grams": 100, "caloriesPer100g": 250, "mealType": "breakfast"}]
        """
        test.defaults.set(snapshotJSON(entries: entries), forKey: LegacyStoreMigrator.snapshotKey)

        let store = try makeStore(defaults: test.defaults)

        #expect(Set(store.entries.map(\.name)) == ["Добрий запис", "Ще один"])
        #expect(store.storageIssue?.contains("1") == true)
        #expect(test.defaults.bool(forKey: LegacyStoreMigrator.migratedFlagKey))
    }

    @Test func migratesTheOldestV1List() throws {
        let test = TestDefaults()
        let list = #"[{"name": "Сирники", "grams": 150, "caloriesPer100g": 220, "mealType": "Сніданок"}]"#
        test.defaults.set(Data(list.utf8), forKey: LegacyStoreMigrator.listKey)

        let store = try makeStore(defaults: test.defaults)

        let meal = try #require(store.entries.first)
        #expect(meal.calories == 330)
        #expect(meal.mealType == .breakfast)
    }

    @Test func migrationRunsOnlyOnce() throws {
        let test = TestDefaults()
        let entries = #"[{"name": "Каша", "grams": 250, "caloriesPer100g": 100}]"#
        test.defaults.set(snapshotJSON(entries: entries), forKey: LegacyStoreMigrator.snapshotKey)

        _ = try makeStore(defaults: test.defaults)
        #expect(test.defaults.bool(forKey: LegacyStoreMigrator.migratedFlagKey))
        #expect(test.defaults.data(forKey: LegacyStoreMigrator.snapshotKey) != nil)

        // A second store over a fresh (empty) container must not import again once the flag is set.
        let second = try makeStore(defaults: test.defaults)
        #expect(second.entries.isEmpty)
    }

    @Test func savedGoalsWinOverLegacyGoals() throws {
        let test = TestDefaults()
        test.defaults.set(try JSONEncoder().encode(NutritionGoals(calories: 2400)), forKey: DiaryStore.Keys.goals)
        test.defaults.set(snapshotJSON(entries: "[]"), forKey: LegacyStoreMigrator.snapshotKey)

        let store = try makeStore(defaults: test.defaults)

        #expect(store.goals.calories == 2400)
    }
}
