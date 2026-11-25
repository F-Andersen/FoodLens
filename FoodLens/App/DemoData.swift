#if DEBUG
import Foundation

/// Sample diary for screenshots and demos: launch with `-demoData` (together with `-demoHealth`).
/// Everything lives in memory and a throwaway defaults suite, so the real diary is never touched.
extension DiaryStore {
    static var launchStore: DiaryStore {
        ProcessInfo.processInfo.arguments.contains("-demoData") ? makeDemo() : makeDefault()
    }

    static func makeDemo(now: Date = .now, calendar: Calendar = .current) -> DiaryStore {
        let suite = "foodlens-demo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: LegacyStoreMigrator.migratedFlagKey)
        guard let container = try? FoodLensPersistence.makeContainer(inMemory: true) else { return makeDefault() }
        let store = DiaryStore(container: container, defaults: defaults, calendar: calendar, migrateLegacyData: false)

        var profile = NutritionProfile()
        profile.sex = .male; profile.age = 31; profile.heightCM = 182; profile.weightKG = 84.2
        profile.activity = .moderate; profile.goal = .lose; profile.weeklyRateKG = 0.5
        profile.diet = .highProtein; profile.targetWeightKG = 79
        // `-demoOnboarding` leaves the profile empty so the first-launch flow appears.
        if !ProcessInfo.processInfo.arguments.contains("-demoOnboarding") { store.profile = profile }
        store.goals = profile.calculatedGoals

        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        typealias Meal = (String, Double, Double, Double, Double, Double, Double, MealEntry.MealType, Int, Int)
        // name, grams, kcal, protein, carbs, fat, fiber, type, hour, minute
        let todayMeals: [Meal] = [
            ("Сирники зі сметаною та ягодами", 260, 468, 31, 44, 18, 3, .breakfast, 8, 15),
            ("Капучино на вівсяному молоці", 300, 96, 3, 13, 3.5, 1, .breakfast, 8, 20),
            ("Борщ із пампушкою", 450, 386, 14, 52, 13, 7, .lunch, 13, 5),
            ("Куряче філе на грилі з гречкою", 320, 512, 48, 54, 9, 5, .lunch, 13, 10),
            ("Грецький йогурт із горіхами", 180, 214, 16, 12, 11, 2, .snack, 16, 40)
        ]
        let pastDays: [[Meal]] = [
            [("Вівсянка з бананом і арахісовою пастою", 320, 512, 18, 70, 17, 9, .breakfast, 8, 0),
             ("Вареники з картоплею та цибулькою", 300, 618, 16, 92, 20, 5, .lunch, 13, 30),
             ("Лосось із запеченими овочами", 380, 548, 41, 22, 32, 7, .dinner, 19, 15),
             ("Яблуко", 180, 94, 0.5, 25, 0.3, 4, .snack, 16, 0)],
            [("Омлет зі шпинатом і фетою", 250, 402, 28, 5, 30, 2, .breakfast, 8, 30),
             ("Плов з куркою", 380, 645, 34, 78, 21, 4, .lunch, 13, 0),
             ("Салат із тунцем і квасолею", 320, 410, 33, 26, 18, 9, .dinner, 19, 40)],
            [("Гречка з молоком", 300, 342, 14, 52, 8, 5, .breakfast, 8, 10),
             ("Голубці зі сметаною", 400, 560, 30, 44, 28, 6, .lunch, 13, 20),
             ("Кисломолочний сир із медом", 200, 296, 32, 22, 9, 0, .snack, 17, 0),
             ("Індичка з булгуром", 340, 520, 46, 50, 12, 7, .dinner, 19, 30)],
            [("Тост з авокадо і яйцем пашот", 230, 428, 18, 32, 25, 8, .breakfast, 8, 45),
             ("Солянка", 400, 352, 20, 14, 24, 3, .lunch, 13, 15),
             ("Деруни зі сметаною", 300, 612, 12, 58, 37, 6, .dinner, 19, 0),
             ("Протеїновий батончик", 60, 210, 20, 18, 7, 3, .snack, 16, 20)],
            [("Сирники з медом", 240, 452, 28, 48, 16, 1, .breakfast, 9, 0),
             ("Курячий суп із локшиною", 450, 315, 24, 30, 10, 3, .lunch, 13, 40),
             ("Стейк із печеною картоплею", 420, 720, 52, 46, 34, 5, .dinner, 20, 0)],
            [("Мюслі з молоком", 280, 380, 13, 58, 10, 7, .breakfast, 8, 20),
             ("Паста з куркою та песто", 380, 690, 40, 72, 26, 5, .lunch, 13, 0),
             ("Овочевий салат із сиром", 260, 248, 12, 14, 16, 6, .dinner, 19, 10)]
        ]
        var entries = todayMeals.map { make($0, day: 0) }
        for (index, day) in pastDays.enumerated() {
            entries += day.map { make($0, day: index + 1) }
        }
        func make(_ meal: Meal, day: Int) -> MealEntry {
            MealEntry(date: at(day, meal.8, meal.9), name: meal.0, grams: meal.1, calories: meal.2,
                      protein: meal.3, carbs: meal.4, fat: meal.5, fiber: meal.6, mealType: meal.7,
                      isFavorite: meal.0.hasPrefix("Сирники"))
        }
        store.add(entries)

        let weights = [87.6, 87.1, 86.8, 86.2, 86.0, 85.5, 85.1, 84.9, 84.6, 84.2]
        for (index, kilograms) in weights.enumerated() {
            store.addWeight(kilograms, date: at((weights.count - 1 - index) * 4, 7, 30))
        }
        for (hour, amount) in [(9, 300.0), (11, 500), (14, 300), (16, 500)] {
            store.addWater(amount, date: at(0, hour))
        }
        return store
    }
}
#endif
