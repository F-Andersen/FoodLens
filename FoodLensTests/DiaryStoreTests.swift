import Foundation
import Testing
@testable import FoodLens

@MainActor
@Suite("DiaryStore")
struct DiaryStoreTests {
    @Test func addUpdateFavoriteDelete() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults)
        var meal = MealEntry(name: "Омлет", grams: 200, calories: 300, protein: 20)

        store.add(meal)
        #expect(store.entries.map(\.name) == ["Омлет"])

        meal.name = "Омлет з сиром"
        meal.calories = 380
        store.update(meal)
        #expect(store.entries.first?.name == "Омлет з сиром")
        #expect(store.entries.first?.calories == 380)

        store.toggleFavorite(id: meal.id)
        #expect(store.entries.first?.isFavorite == true)

        store.deleteMeal(id: meal.id)
        #expect(store.entries.isEmpty)
    }

    @Test func ingredientsArePersisted() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults)
        let rice = FoodComponent(name: "рис", grams: 150, calories: 195, protein: 4)
        store.add(MealEntry(name: "Рис із куркою", grams: 350, calories: 500, ingredients: [rice]))

        #expect(store.entries.first?.ingredients == [rice])
    }

    @Test func todayTotalsIgnoreOtherDays() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        store.add(MealEntry(name: "Сьогодні", grams: 100, calories: 400, protein: 30, fiber: 5))
        store.add(MealEntry(date: yesterday, name: "Вчора", grams: 100, calories: 900, protein: 50))

        #expect(store.todayTotals.kcal == 400)
        #expect(store.todayTotals.protein == 30)
        #expect(store.todayTotals.fiber == 5)
        #expect(store.calories(on: yesterday) == 900)
        #expect(store.entries.map(\.name) == ["Сьогодні", "Вчора"]) // newest first
    }

    @Test func waterIsTrackedPerDayAndCanBeUndone() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!

        store.addWater(500, date: yesterday)
        store.addWater(200)
        store.addWater(300)
        #expect(store.waterToday == 500)
        #expect(store.water(on: yesterday) == 500)

        store.undoLastWater()
        #expect(store.waterToday == 200)
        #expect(store.water(on: yesterday) == 500)

        store.addWater(0)
        #expect(store.waterLogs.count == 2)
    }

    @Test func weightsAreSortedNewestFirstAndEditable() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults)
        store.addWeight(82, date: .now.addingTimeInterval(-86_400))
        store.addWeight(81.4)

        #expect(store.latestWeight?.kilograms == 81.4)
        let id = try #require(store.latestWeight?.id)
        store.updateWeight(id: id, kilograms: 81.2)
        #expect(store.latestWeight?.kilograms == 81.2)
        store.deleteWeight(id: id)
        #expect(store.weights.map(\.kilograms) == [82])
    }

    @Test func goalsAndProfilePersistAcrossLaunches() throws {
        let test = TestDefaults()
        let first = try makeStore(defaults: test.defaults)
        first.goals.calories = 2_150
        var profile = NutritionProfile()
        profile.heightCM = 182
        first.profile = profile

        let second = try makeStore(defaults: test.defaults)
        #expect(second.goals.calories == 2_150)
        #expect(second.profile?.heightCM == 182)
    }

    @Test func addingSeveralEntriesAtOnce() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults)
        let plan = MealPlanBuilder.make(profile: NutritionProfile())
        store.add(plan.map { MealEntry(name: $0.foods, grams: 0, calories: Double($0.calories), mealType: $0.mealType) })

        #expect(store.todayEntries.count == 4)
        #expect(Set(store.todayEntries.map(\.mealType)) == Set(MealEntry.MealType.allCases))
        // Plan entries have no real weight; it is stored as unknown, not as a fake 100 g.
        #expect(store.todayEntries.allSatisfy { $0.grams == 0 && $0.caloriesPer100g == nil })
    }
}
