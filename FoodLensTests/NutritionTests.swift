import Foundation
import Testing
@testable import FoodLens

@Suite("Nutrition calculations")
struct NutritionTests {
    @Test func mifflinStJeor() {
        var profile = NutritionProfile()
        profile.sex = .male; profile.age = 30; profile.heightCM = 180; profile.weightKG = 80
        #expect(profile.bmr == 1_780) // 800 + 1125 − 150 + 5
        profile.sex = .female
        #expect(profile.bmr == 1_614) // 800 + 1125 − 150 − 161
    }

    @Test func targetNeverDropsBelowSafeFloor() {
        var profile = NutritionProfile()
        profile.sex = .female; profile.age = 80; profile.heightCM = 150; profile.weightKG = 40
        profile.activity = .sedentary; profile.goal = .lose
        #expect(profile.targetCalories == 1_200)
    }

    @Test func macroGoalsAddUpToTargetCalories() {
        let profile = NutritionProfile()
        let goals = profile.calculatedGoals
        let energy = goals.protein * 4 + goals.carbs * 4 + goals.fat * 9
        #expect(abs(energy - goals.calories) < 0.001)
    }

    @Test func mealPlanCoversAllMealTypes() {
        let plan = MealPlanBuilder.make(profile: NutritionProfile())
        #expect(plan.map(\.mealType) == [.breakfast, .lunch, .dinner, .snack])
        let total = plan.reduce(0) { $0 + $1.calories }
        #expect(abs(Double(total) - NutritionProfile().targetCalories) <= 4) // rounding per meal
    }

    @Test func goalsDecodeWithMissingKeys() throws {
        let goals = try JSONDecoder().decode(NutritionGoals.self, from: Data(#"{"calories": 1900}"#.utf8))
        #expect(goals.calories == 1900)
        #expect(goals.waterML == NutritionGoals().waterML)
    }

    @Test(arguments: [("82,5", 82.5), ("82.5", 82.5), (" 70 ", 70.0)])
    func weightParsingAcceptsCommaAndDot(input: String, expected: Double) {
        #expect(WeightRecord.parse(input) == expected)
    }

    @Test(arguments: ["", "abc", "29", "351"])
    func weightParsingRejectsInvalidValues(input: String) {
        #expect(WeightRecord.parse(input) == nil)
    }
}

@Suite("Portion scaling")
struct PortionTests {
    @Test func scalingAMealScalesEverything() {
        let rice = FoodComponent(name: "рис", grams: 100, calories: 130, protein: 3)
        let meal = MealEntry(name: "Рис", grams: 200, calories: 260, protein: 6, carbs: 56, fat: 1, fiber: 2, ingredients: [rice])
        let bigger = meal.scaled(toGrams: 300)
        #expect(bigger.calories == 390)
        #expect(bigger.protein == 9)
        #expect(bigger.carbs == 84)
        #expect(bigger.ingredients.first?.grams == 150)
        #expect(bigger.caloriesPer100g == meal.caloriesPer100g)
    }

    @Test func unknownWeightIsNotScaled() {
        let meal = MealEntry(name: "Меню", grams: 0, calories: 500, protein: 20)
        let scaled = meal.scaled(toGrams: 250)
        #expect(scaled.calories == 500)
        #expect(scaled.grams == 250)
    }

    @Test func trackerSurvivesPassingThroughZeroWhileTyping() {
        var tracker = PortionTracker(grams: 250)
        var protein = 20.0
        for typed in [25.0, 2.0, 0.0, 3.0, 30.0, 300.0] {
            if let factor = tracker.factor(for: typed) { protein *= factor }
        }
        #expect(abs(protein - 24) < 0.0001) // 20 g × 300 / 250
    }

    @Test func trackerResetMakesAppliedValueANoOp() {
        var tracker = PortionTracker(grams: 0)
        tracker.reset(to: 320)
        #expect(tracker.factor(for: 320) == nil)
        #expect(tracker.factor(for: 160) == 0.5)
    }

    @Test func suggestedMealTypeFollowsTimeOfDay() {
        let calendar = Calendar(identifier: .gregorian)
        func at(_ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour))! }
        #expect(MealEntry.MealType.suggested(for: at(8), calendar: calendar) == .breakfast)
        #expect(MealEntry.MealType.suggested(for: at(13), calendar: calendar) == .lunch)
        #expect(MealEntry.MealType.suggested(for: at(19), calendar: calendar) == .dinner)
        #expect(MealEntry.MealType.suggested(for: at(23), calendar: calendar) == .snack)
    }
}
