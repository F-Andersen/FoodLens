import Foundation
import Testing
@testable import FoodLens

@Suite("Diary grouping")
struct DiaryGroupingTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func groupsByDayNewestFirstWithTotals() {
        let entries = [
            MealEntry(date: date(6, 9), name: "Каша", grams: 250, calories: 300),
            MealEntry(date: date(7, 13), name: "Суп", grams: 300, calories: 200),
            MealEntry(date: date(7, 8), name: "Омлет", grams: 200, calories: 250),
        ]
        let days = DiaryDay.group(entries, calendar: calendar)
        #expect(days.map { $0.entries.map(\.name) } == [["Суп", "Омлет"], ["Каша"]])
        #expect(days.first?.totals.kcal == 450)
    }

    @Test func titlesForTodayAndYesterday() {
        let now = date(7, 18)
        let days = DiaryDay.group([
            MealEntry(date: date(7, 9), name: "a", grams: 0, calories: 1),
            MealEntry(date: date(6, 9), name: "b", grams: 0, calories: 1),
            MealEntry(date: date(3, 9), name: "c", grams: 0, calories: 1),
        ], calendar: calendar)
        #expect(days[0].title(now: now, calendar: calendar) == "Сьогодні")
        #expect(days[1].title(now: now, calendar: calendar) == "Вчора")
        #expect(days[2].title(now: now, calendar: calendar) != "Вчора")
    }

    @Test func uniqueFavoritesKeepTheMostRecentPerName() {
        let entries = [
            MealEntry(date: date(5, 9), name: "Сирники", grams: 150, calories: 300, isFavorite: true),
            MealEntry(date: date(7, 9), name: "сирники", grams: 200, calories: 400, isFavorite: true),
            MealEntry(date: date(6, 9), name: "Борщ", grams: 300, calories: 150, isFavorite: true),
            MealEntry(date: date(7, 12), name: "Салат", grams: 200, calories: 100),
        ]
        let favorites = entries.uniqueFavorites
        #expect(favorites.map(\.name) == ["сирники", "Борщ"])
        #expect(favorites.first?.calories == 400)
    }

    @MainActor
    @Test func profileWithLatestWeightUsesLoggedWeight() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults)
        #expect(store.profileWithLatestWeight == NutritionProfile())
        store.addWeight(88.4)
        #expect(store.profileWithLatestWeight.weightKG == 88.4)
    }
}
