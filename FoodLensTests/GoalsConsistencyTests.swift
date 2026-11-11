import Foundation
import Testing
@testable import FoodLens

@Suite("Goals and macro consistency")
struct GoalsConsistencyTests {
    /// The values reported from the phone: 187 / 100 / 337 g are 2 996 kcal against a 2 699 kcal goal.
    private let reported = NutritionGoals(calories: 2699, protein: 187, carbs: 337, fat: 100)

    /// Scenario 1: automatic macros add up to the calorie goal (whole grams, within 2 kcal).
    @Test(arguments: [1200.0, 1650, 2000, 2699, 3150, 4000])
    func automaticMacrosMatchCalories(calories: Double) {
        for split in MacroSplit.presets.map(\.split) {
            let goals = NutritionGoals(calories: calories, macroSplit: split)
            #expect(abs(goals.macroCalories - calories) <= 2)
            #expect(goals.macrosMatchCalories)
            #expect(goals.protein == goals.protein.rounded() && goals.fat == goals.fat.rounded())
        }
    }

    @Test func calculatedProfileGoalsAreConsistent() {
        var profile = NutritionProfile()
        profile.sex = .male; profile.age = 32; profile.heightCM = 186; profile.weightKG = 96
        profile.activity = .moderate; profile.goal = .lose; profile.diet = .highProtein
        let goals = profile.calculatedGoals
        #expect(goals.isAutomatic)
        #expect(abs(goals.macroCalories - goals.calories) <= 2)
    }

    @Test func reportedGoalsAreFlaggedAsInconsistent() {
        #expect(reported.macroCalories == 2996)
        #expect(reported.macroCalorieGap == 297)
        #expect(!reported.macrosMatchCalories)
        #expect(!reported.isAutomatic)
    }

    /// Scenario 2: changing the calorie goal updates automatic macros.
    @Test func changingCaloriesUpdatesAutomaticMacros() {
        var goals = NutritionGoals(calories: 2000, macroSplit: .balanced)
        goals.setCalories(2699)
        #expect(goals.protein == 169) // 2699 × 25 % / 4
        #expect(goals.fat == 90)      // 2699 × 30 % / 9
        #expect(goals.carbs == 303)   // (2699 − 676 − 810) / 4
        #expect(abs(goals.macroCalories - 2699) <= 2)
        goals.setMacroSplit(.highProtein)
        #expect(goals.protein == 202)
        #expect(abs(goals.macroCalories - 2699) <= 2)
    }

    /// Scenario 12: manual goals are never rewritten without the user's action.
    @Test func manualGoalsSurviveCalorieChanges() {
        var goals = reported
        goals.setCalories(2500)
        #expect(goals.protein == 187 && goals.fat == 100 && goals.carbs == 337)
        #expect(!goals.macrosMatchCalories) // reported, not fixed silently
    }

    @Test func aligningKeepsTheUsersProportions() {
        var goals = reported
        #expect(goals.impliedSplit == MacroSplit(protein: 0.25, fat: 0.30))
        goals.alignMacrosToCalories()
        #expect(goals.isAutomatic)
        #expect(goals.macrosMatchCalories)
        #expect(goals.protein == 169 && goals.fat == 90)
    }

    @Test func goalsSavedByOlderVersionsDecodeAsManual() throws {
        let json = #"{"calories": 2699, "protein": 187, "carbs": 337, "fat": 100, "fiber": 30, "waterML": 2500}"#
        let goals = try JSONDecoder().decode(NutritionGoals.self, from: Data(json.utf8))
        #expect(goals == reported)
        #expect(goals.macroSplit == nil)
    }

    @Test func automaticGoalsRoundTrip() throws {
        let goals = NutritionGoals(calories: 2350, macroSplit: .lowerCarb)
        let decoded = try JSONDecoder().decode(NutritionGoals.self, from: JSONEncoder().encode(goals))
        #expect(decoded == goals)
    }

    @Test func splitValidation() {
        #expect(MacroSplit.balanced.isValid)
        #expect(MacroSplit(protein: 0.40, fat: 0.45).isValid) // carbs exactly at the 15 % floor
        #expect(!MacroSplit(protein: 0.40, fat: 0.50).isValid)
        #expect(!MacroSplit(protein: 0.05, fat: 0.30).isValid)
        #expect(MacroSplit.balanced.percentText == "25 / 30 / 45 %")
    }

    /// Scenario 5: what is left to the food goal is not the energy deficit.
    @Test func remainingToGoalIsGoalMinusEaten() {
        let goal = 2699.0, eaten = 2530.0
        #expect(Int(goal.rounded()) - Int(eaten.rounded()) == 169)
    }

    @Test @MainActor func storeKeepsManualGoalsAcrossLaunches() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults, migrate: false)
        store.goals = reported
        let reopened = try makeStore(defaults: test.defaults, migrate: false)
        #expect(reopened.goals == reported)
    }

    @Test @MainActor func newInstallStartsWithConsistentGoals() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults, migrate: false)
        #expect(store.goals.isAutomatic && store.goals.macrosMatchCalories)
    }
}

@Suite("Personalisation")
struct PersonalisationTests {
    private var profile: NutritionProfile {
        var profile = NutritionProfile()
        profile.sex = .male; profile.age = 30; profile.heightCM = 180; profile.weightKG = 90
        profile.activity = .light
        return profile
    }

    @Test func paceSetsTheDailyDeficit() {
        var p = profile
        p.goal = .lose
        #expect(abs(p.dailyAdjustment - (-550)) < 1e-9) // 0.5 kg × 7700 / 7
        p.weeklyRateKG = 0.25
        #expect(abs(p.dailyAdjustment - (-275)) < 1e-9)
        #expect(abs(p.targetCalories - (p.maintenanceCalories - 275)) < 1e-9)
        p.goal = .maintain
        #expect(p.dailyAdjustment == 0)
    }

    @Test func weeksToTargetFollowsThePace() {
        var p = profile
        p.goal = .lose; p.targetWeightKG = 80; p.weeklyRateKG = 0.5
        #expect(p.weeksToTarget == 20)
        p.goal = .gain
        #expect(p.weeksToTarget == nil)
        #expect(p.targetWeightMismatch != nil)
    }

    @Test func aggressiveDeficitIsWarnedNotClamped() {
        let p = profile
        #expect(p.deficitWarning(forCalories: 1200) != nil) // below BMR
        #expect(p.deficitWarning(forCalories: p.maintenanceCalories - 300) == nil)
        var goals = NutritionGoals(calories: 2000, macroSplit: .balanced)
        goals.setCalories(1100)
        #expect(goals.calories == 1100) // the user's choice stays
    }

    @Test func oldProfilesDecodeWithoutLosingData() throws {
        let json = #"{"sex":"male","age":41,"heightCM":182,"weightKG":95.5,"activity":"moderate","goal":"lose","diet":"balanced"}"#
        let decoded = try JSONDecoder().decode(NutritionProfile.self, from: Data(json.utf8))
        #expect(decoded.age == 41 && decoded.weightKG == 95.5 && decoded.goal == .lose)
        #expect(decoded.targetWeightKG == nil && decoded.rate == 0.5)
    }

    @Test @MainActor func estimatesUseTheLatestWeight() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults, migrate: false)
        #expect(store.profileForEstimates == nil)
        store.profile = profile
        store.addWeight(84)
        #expect(store.profileForEstimates?.weightKG == 84)
    }
}

@Suite("Goal progress")
struct GoalProgressTests {
    /// Scenario 6: fat 159 / 100 g is shown as an excess of 59 g.
    @Test func fatOverTheGoalShowsTheExcess() {
        let fat = GoalProgress(value: 159.3, goal: 100, isUpperLimit: Macro.fat.isUpperLimit)
        #expect(fat.state == .overLimit)
        #expect(fat.excess == 59)
        #expect(fat.fraction == 1)
        #expect(fat.goalMarker.map { abs($0 - 100.0 / 159) < 1e-9 } == true)
    }

    @Test func proteinAndFiberAreNeverAlarming() {
        let lowProtein = GoalProgress(value: 60, goal: 169, isUpperLimit: Macro.protein.isUpperLimit)
        #expect(lowProtein.state == .below)
        #expect(lowProtein.remaining == 109)
        let extraFiber = GoalProgress(value: 40, goal: 30, isUpperLimit: Macro.fiber.isUpperLimit)
        #expect(extraFiber.state == .aboveMinimum)
        #expect(extraFiber.excess == 10)
    }

    @Test func zeroGoalNeverDividesByZero() {
        let progress = GoalProgress(value: 50, goal: 0, isUpperLimit: true)
        #expect(progress.fraction == 0)
        #expect(progress.goalMarker == nil)
        #expect(progress.state == .below)
    }

    @Test func exactGoalIsReached() {
        #expect(GoalProgress(value: 99.6, goal: 100, isUpperLimit: true).state == .reached)
    }
}

@Suite("Diary updates the day")
struct DiaryDayTotalsTests {
    /// Scenario 7: changing the portion recalculates its nutrition.
    @Test func changingThePortionRecalculatesNutrition() {
        let meal = MealEntry(name: "Гречка з куркою", grams: 250, calories: 412.5, protein: 31.25, carbs: 45, fat: 11.5, fiber: 4)
        let smaller = meal.scaled(toGrams: 180)
        #expect(abs(smaller.calories - 297) < 1e-9)
        #expect(abs(smaller.protein - 22.5) < 1e-9)
        #expect(smaller.caloriesPer100g == meal.caloriesPer100g)
        let back = smaller.scaled(toGrams: 250)
        #expect(abs(back.calories - 412.5) < 1e-9) // no rounding drift
    }

    /// Scenario 8: editing or deleting a meal updates today's totals and the balance.
    @Test @MainActor func editingAndDeletingUpdateTheDay() throws {
        let test = TestDefaults()
        let store = try makeStore(defaults: test.defaults, migrate: false)
        let lunch = MealEntry(name: "Борщ", grams: 400, calories: 320.4, protein: 12, carbs: 30, fat: 15)
        let snack = MealEntry(name: "Сало", grams: 30, calories: 237.9, fat: 26.7)
        store.add([lunch, snack])
        #expect(abs(store.todayTotals.calories - 558.3) < 1e-9)

        store.update(lunch.scaled(toGrams: 200))
        #expect(abs(store.todayTotals.calories - 398.1) < 1e-9)

        store.deleteMeal(id: snack.id)
        #expect(abs(store.todayTotals.calories - 160.2) < 1e-9)
        #expect(store.todayTotals.fat == 7.5)

        var health = ActivitySnapshot()
        health.restingCalories = 1000
        let balance = try #require(EnergyBalance.today(snapshot: health, profile: nil, eaten: store.todayTotals.calories))
        #expect(balance.display.deficit == 1000 - 160)
    }

    /// Scenario 11: meals are assigned to calendar days, including across time zones.
    @Test @MainActor func mealsAreGroupedByTheStoresCalendarDay() throws {
        var kyiv = Calendar(identifier: .gregorian)
        kyiv.timeZone = try #require(TimeZone(identifier: "Europe/Kyiv"))
        let test = TestDefaults()
        let store = DiaryStore(container: try FoodLensPersistence.makeContainer(inMemory: true), defaults: test.defaults,
                               calendar: kyiv, migrateLegacyData: false)
        // 23:30 in Kyiv is 21:30 UTC on the same day; 00:30 Kyiv is still the previous day in UTC.
        let late = try #require(kyiv.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 23, minute: 30)))
        let early = try #require(kyiv.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 0, minute: 30)))
        store.add([MealEntry(date: late, name: "Вечеря", grams: 0, calories: 600),
                   MealEntry(date: early, name: "Нічний перекус", grams: 0, calories: 200)])
        #expect(store.totals(on: late).calories == 600)
        #expect(store.totals(on: early).calories == 200)
    }

    @Test func weeklyAveragesOfMacros() {
        var a = NutritionTotals(); a.protein = 150; a.fat = 80; a.calories = 2000
        var b = NutritionTotals(); b.protein = 100; b.fat = 120; b.calories = 2600
        let average = NutritionTotals.average(of: [a, b])
        #expect(average.protein == 125 && average.fat == 100 && average.calories == 2300)
        #expect(NutritionTotals.average(of: []) == NutritionTotals())
    }
}
