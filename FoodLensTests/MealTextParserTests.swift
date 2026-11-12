import Foundation
import Testing
@testable import FoodLens

@Suite("Meal text parser")
struct MealTextParserTests {
    /// The description from the phone screenshot.
    private let breakfast = "Сніданок: вівсянка на воді 50 г (суха вага), чорний хліб 2 скибки (~90 г), лосось ~140 г, варене яйце 1 шт. Разом орієнтовно 740 ккал; Б 46 г, Ж 31 г, В 72 г, клітковина 10 г. Без горіхового міксу."

    @Test func readsTheScreenshotDescription() {
        let result = MealTextParser.parse(breakfast)
        #expect(result.calories == 740)
        #expect(!result.caloriesFromMacros)
        #expect(result.protein == 46)
        #expect(result.fat == 31)
        #expect(result.carbs == 72)
        #expect(result.fiber == 10)
        #expect(result.grams == nil) // ingredient weights are not the portion weight
        #expect(result.mealType == .breakfast)
        #expect(result.name == "Вівсянка на воді 50 г (суха вага), чорний хліб 2 скибки (~90 г), лосось ~140 г, варене яйце 1 шт. Без горіхового міксу.")
    }

    @Test(arguments: [
        ("Борщ 320 ккал", 320.0),
        ("Борщ, калорійність: 320", 320),
        ("Піца ≈ 1 200 ккал", 1200),
        ("Салат 250,5 kcal", 250.5)
    ])
    func readsCalories(text: String, expected: Double) {
        #expect(MealTextParser.parse(text).calories == expected)
    }

    @Test func readsWordLabelsAndGramsFirst() {
        let result = MealTextParser.parse("Омлет: білки 24 г, жири 18, вуглеводи 3,5 г, 2 г клітковини")
        #expect(result.protein == 24)
        #expect(result.fat == 18)
        #expect(result.carbs == 3.5)
        #expect(result.fiber == 2)
    }

    @Test func readsSlashTriple() {
        let result = MealTextParser.parse("Гречка з куркою, Б/Ж/В 35/12/60, 450 ккал")
        #expect(result.protein == 35 && result.fat == 12 && result.carbs == 60)
        #expect(result.calories == 450)
        #expect(result.name == "Гречка з куркою")
    }

    @Test func computesCaloriesFromMacrosWhenMissing() {
        let result = MealTextParser.parse("Сирники Б 20 Ж 15 В 40")
        #expect(result.calories == 375) // 20 × 4 + 15 × 9 + 40 × 4
        #expect(result.caloriesFromMacros)
    }

    @Test func sumsItemsWithoutATotal() {
        let result = MealTextParser.parse("Яйце 80 ккал, тост 120 ккал")
        #expect(result.calories == 200)
    }

    @Test func totalWinsOverItems() {
        let result = MealTextParser.parse("Яйце 80 ккал, тост 120 ккал. Всього 210 ккал")
        #expect(result.calories == 210)
    }

    @Test func readsPortionWeight() {
        #expect(MealTextParser.parse("Плов, вага порції 350 г, 520 ккал").grams == 350)
    }

    @Test func prepositionIsNotCarbs() {
        let result = MealTextParser.parse("кава в 8 ранку")
        #expect(result.carbs == nil)
        #expect(!result.hasNutrition)
        #expect(result.name == "кава в 8 ранку")
    }

    @Test func plainNameStaysUntouched() {
        let result = MealTextParser.parse("сирники зі сметаною")
        #expect(!result.hasNutrition && result.mealType == nil)
        #expect(result.name == "сирники зі сметаною")
    }

    @Test func autofillNeverOverwritesManualValues() {
        var tracker = AutoFillTracker()
        var calories = 0.0
        calories = tracker.update(.calories, current: calories, parsed: 74)    // typing "74"
        calories = tracker.update(.calories, current: calories, parsed: 740)   // "740"
        #expect(calories == 740)
        calories = 700                                                          // edited by hand
        calories = tracker.update(.calories, current: calories, parsed: 750)
        #expect(calories == 700)
    }

    @Test func autofillClearsWhenTheNumberIsDeleted() {
        var tracker = AutoFillTracker()
        var protein = tracker.update(.protein, current: 0, parsed: 46)
        protein = tracker.update(.protein, current: protein, parsed: nil)
        #expect(protein == 0)
    }

    @Test func mealTypeFollowsTheTextUntilChangedByHand() {
        var tracker = AutoFillTracker()
        var type = tracker.updateMealType(current: .lunch, initial: .lunch, parsed: .breakfast)
        #expect(type == .breakfast)
        type = tracker.updateMealType(current: .dinner, initial: .lunch, parsed: .snack) // user picked dinner
        #expect(type == .dinner)
    }
}
