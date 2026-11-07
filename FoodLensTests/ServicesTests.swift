import Foundation
import PDFKit
import Testing
import UIKit
@testable import FoodLens

@Suite("On-device recognition matching")
struct RecognitionMatchingTests {
    @Test(arguments: [
        ("pizza", "Піца"),
        ("french_fries", "Картопля"),
        ("fried_chicken", "Курка"),
        ("noodles", "Паста"),
        ("pineapple", "Фрукти")
    ])
    func matchesWholeWords(identifier: String, expected: String) {
        #expect(OnDeviceFoodRecognitionService.profile(for: identifier)?.name == expected)
    }

    @Test func doesNotConfusePartialWords() {
        #expect(OnDeviceFoodRecognitionService.profile(for: "eggplant")?.name != "Омлет")
        #expect(OnDeviceFoodRecognitionService.profile(for: "pineapple")?.name != "Яблуко")
    }

    @Test func picksMostConfidentFoodAboveThreshold() {
        let best = OnDeviceFoodRecognitionService.bestMatch(in: [("table", 0.9), ("salad", 0.3), ("pizza", 0.5)])
        #expect(best?.0.name == "Піца")
        #expect(OnDeviceFoodRecognitionService.bestMatch(in: [("pizza", 0.05)]) == nil)
    }

    @Test func analysisValuesDescribeTheWholePortion() {
        let profile = OnDeviceFoodRecognitionService.profile(for: "pizza")!
        let analysis = OnDeviceFoodRecognitionService.analysis(for: profile, confidence: 0.6)
        #expect(analysis.estimatedGrams == 300)
        #expect(analysis.protein == 33) // 11 g / 100 g × 300 g
    }
}

@Suite("AI service")
struct FoodAIServiceTests {
    @Test(arguments: [
        ("https://api.example.com", "https://api.example.com/analyze"),
        ("https://api.example.com/", "https://api.example.com/analyze"),
        ("http://192.168.1.20:8000", "http://192.168.1.20:8000/analyze"),
        (" https://api.example.com/v1/analyze ", "https://api.example.com/v1/analyze")
    ])
    func buildsEndpoint(base: String, expected: String) throws {
        #expect(try FoodAIService.endpoint(from: base).absoluteString == expected)
    }

    @Test(arguments: ["", "api.example.com", "ftp://example.com", "https://"])
    func rejectsInvalidAddresses(base: String) {
        #expect(throws: FoodAIError.invalidServerURL) { try FoodAIService.endpoint(from: base) }
    }

    @Test func decodesServerResponseWithNonUUIDIngredientIds() throws {
        let json = """
        {"dish": "Плов", "estimatedGrams": 350, "caloriesPer100g": 160, "protein": 20, "carbs": 60, "fat": 14,
         "fiber": 3, "confidence": 0.7,
         "ingredients": [{"id": "1", "name": "рис", "grams": 200, "calories": 260, "protein": 5, "carbs": 56, "fat": 1, "fiber": 1}]}
        """
        let analysis = try JSONDecoder().decode(FoodAnalysis.self, from: Data(json.utf8))
        #expect(analysis.ingredients.first?.name == "рис")
    }

    @Test func downscalesLargePhotos() {
        let size = CGSize(width: 4032, height: 3024)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.green.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        let small = image.downscaled(maxDimension: 1280)
        #expect(max(small.size.width * small.scale, small.size.height * small.scale) == 1280)
        #expect(image.downscaled(maxDimension: 5000) === image)
    }
}

@Suite("Pantry assistant")
struct PantryAssistantTests {
    @Test func ranksRecipesByAvailableIngredients() {
        let result = PantryAssistant.suggest(pantryText: "риба, картопля, броколі, лимон", mealType: nil, caloriesLeft: 800, proteinLeft: 10)
        #expect(result.recipes.first?.title == "Запечена риба з картоплею")
        #expect(result.recipes.count == 4)
    }

    @Test func filtersByMealTypeAndListsMissingItems() {
        let result = PantryAssistant.suggest(pantryText: "курка", mealType: .lunch, caloriesLeft: 800, proteinLeft: 60)
        #expect(result.recipes.allSatisfy { $0.mealType == .lunch })
        #expect(result.recipes.first?.title == "Курка з гречкою та салатом")
        #expect(!result.shoppingList.contains("куряче філе"))
        #expect(result.message.contains("60 г білка"))
    }
}

@Suite("PDF report")
struct FoodReportTests {
    @Test func includesOnlyRecentEntriesAndPaginates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = Calendar.current.date(byAdding: .day, value: -60, to: .now)!
        let entries = (0..<80).map { MealEntry(name: "Страва \($0)", grams: 100, calories: 200) }
            + [MealEntry(date: old, name: "Стара страва", grams: 100, calories: 999)]

        let url = try FoodReport.make(entries: entries, weights: [], goals: NutritionGoals(), directory: directory)

        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount >= 2) // long reports paginate instead of being cut at 24 rows
        let text = document.string ?? ""
        #expect(text.contains("Страва 79"))
        #expect(!text.contains("Стара страва"))
    }
}
