import Foundation
import UIKit
import Vision

enum FoodRecognitionError: LocalizedError {
    case invalidImage
    case noFoodDetected

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Не вдалося прочитати фото."
        case .noFoodDetected: "Не вдалося впевнено визначити страву. Спробуйте зняти тарілку зверху при хорошому освітленні."
        }
    }
}

struct FoodNutritionProfile: Sendable {
    let keywords: [String]
    let name: String
    let defaultGrams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
}

/// Category-level recognition with Apple Vision. Nutrition values come from a reference profile per category.
enum OnDeviceFoodRecognitionService {
    static let minimumConfidence: Float = 0.08

    static let catalog: [FoodNutritionProfile] = [
        .init(keywords: ["pizza"], name: "Піца", defaultGrams: 300, calories: 266, protein: 11, carbs: 33, fat: 10, fiber: 2.3),
        .init(keywords: ["hamburger", "burger", "cheeseburger"], name: "Бургер", defaultGrams: 250, calories: 260, protein: 13, carbs: 25, fat: 12, fiber: 1.5),
        .init(keywords: ["sandwich", "submarine sandwich", "hot dog"], name: "Сендвіч", defaultGrams: 220, calories: 240, protein: 12, carbs: 30, fat: 8, fiber: 2),
        .init(keywords: ["salad", "caesar salad"], name: "Овочевий салат", defaultGrams: 280, calories: 95, protein: 3, carbs: 9, fat: 6, fiber: 3),
        .init(keywords: ["soup", "stew", "chowder", "borscht"], name: "Суп", defaultGrams: 350, calories: 75, protein: 4, carbs: 9, fat: 3, fiber: 1.5),
        .init(keywords: ["pasta", "spaghetti", "noodle", "carbonara", "lasagna"], name: "Паста", defaultGrams: 320, calories: 158, protein: 6, carbs: 31, fat: 1.5, fiber: 1.8),
        .init(keywords: ["rice", "risotto", "pilaf", "fried rice"], name: "Рисова страва", defaultGrams: 300, calories: 150, protein: 4, carbs: 29, fat: 2, fiber: 1),
        .init(keywords: ["sushi", "maki", "sashimi"], name: "Суші", defaultGrams: 250, calories: 150, protein: 6, carbs: 28, fat: 2, fiber: 1),
        .init(keywords: ["steak", "beef", "roast beef", "meat"], name: "Яловичина", defaultGrams: 220, calories: 250, protein: 26, carbs: 0, fat: 16, fiber: 0),
        .init(keywords: ["chicken", "poultry", "fried chicken"], name: "Курка", defaultGrams: 220, calories: 190, protein: 27, carbs: 2, fat: 8, fiber: 0),
        .init(keywords: ["fish", "salmon", "trout", "tuna", "seafood"], name: "Риба", defaultGrams: 200, calories: 180, protein: 23, carbs: 0, fat: 10, fiber: 0),
        .init(keywords: ["omelet", "omelette", "egg"], name: "Омлет", defaultGrams: 200, calories: 154, protein: 11, carbs: 2, fat: 12, fiber: 0),
        .init(keywords: ["oatmeal", "porridge", "cereal"], name: "Каша", defaultGrams: 280, calories: 110, protein: 4, carbs: 19, fat: 2, fiber: 2.5),
        .init(keywords: ["bread", "toast", "bagel", "croissant"], name: "Випічка", defaultGrams: 100, calories: 270, protein: 9, carbs: 50, fat: 4, fiber: 2.5),
        .init(keywords: ["cake", "dessert", "pie", "pancake", "waffle", "donut", "cookie"], name: "Десерт", defaultGrams: 150, calories: 330, protein: 5, carbs: 48, fat: 14, fiber: 1.5),
        .init(keywords: ["french fries", "fries", "potato"], name: "Картопля", defaultGrams: 220, calories: 210, protein: 4, carbs: 32, fat: 8, fiber: 3),
        .init(keywords: ["apple"], name: "Яблуко", defaultGrams: 180, calories: 52, protein: 0.3, carbs: 14, fat: 0.2, fiber: 2.4),
        .init(keywords: ["banana"], name: "Банан", defaultGrams: 120, calories: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6),
        .init(keywords: ["fruit", "berry", "orange", "pineapple", "strawberry", "grape"], name: "Фрукти", defaultGrams: 200, calories: 55, protein: 0.8, carbs: 13, fat: 0.3, fiber: 2.5),
        .init(keywords: ["vegetable", "broccoli", "carrot", "cabbage", "cucumber", "tomato"], name: "Овочі", defaultGrams: 250, calories: 45, protein: 2, carbs: 8, fat: 0.5, fiber: 3)
    ]

    static func analyze(_ image: UIImage) async throws -> FoodAnalysis {
        guard let cgImage = image.cgImage else { throw FoodRecognitionError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let observations = try await Task.detached(priority: .userInitiated) { () throws -> [(String, Float)] in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            return (request.results ?? []).map { ($0.identifier, $0.confidence) }
        }.value
        guard let (profile, confidence) = bestMatch(in: observations) else { throw FoodRecognitionError.noFoodDetected }
        return analysis(for: profile, confidence: confidence)
    }

    /// Picks the most confident catalog category among the top 30 classifier labels.
    static func bestMatch(in observations: [(identifier: String, confidence: Float)]) -> (FoodNutritionProfile, Float)? {
        let matches: [(FoodNutritionProfile, Float)] = observations.prefix(30).compactMap { identifier, confidence in
            guard let profile = profile(for: identifier) else { return nil }
            return (profile, confidence)
        }
        guard let best = matches.max(by: { $0.1 < $1.1 }), best.1 >= minimumConfidence else { return nil }
        return best
    }

    /// Matches whole words, so "pineapple" is not mistaken for "apple" and "eggplant" not for "egg".
    static func profile(for identifier: String) -> FoodNutritionProfile? {
        let words = identifier.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        let phrase = " " + words.joined(separator: " ") + " "
        return catalog.first { profile in
            profile.keywords.contains { keyword in
                ["", "s", "es"].contains { phrase.contains(" \(keyword)\($0) ") }
            }
        }
    }

    static func analysis(for profile: FoodNutritionProfile, confidence: Float) -> FoodAnalysis {
        let factor = profile.defaultGrams / 100
        let component = FoodComponent(
            name: profile.name, grams: profile.defaultGrams, calories: profile.calories * factor,
            protein: profile.protein * factor, carbs: profile.carbs * factor,
            fat: profile.fat * factor, fiber: profile.fiber * factor
        )
        return FoodAnalysis(
            dish: profile.name, estimatedGrams: profile.defaultGrams, caloriesPer100g: profile.calories,
            protein: component.protein, carbs: component.carbs, fat: component.fat,
            fiber: component.fiber, confidence: Double(confidence), ingredients: [component]
        )
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
