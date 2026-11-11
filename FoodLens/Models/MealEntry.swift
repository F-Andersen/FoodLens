import Foundation

/// One estimated component of a dish (for example, "рис 150 г").
struct FoodComponent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double

    init(
        id: UUID = UUID(), name: String, grams: Double, calories: Double,
        protein: Double = 0, carbs: Double = 0, fat: Double = 0, fiber: Double = 0
    ) {
        self.id = id; self.name = name; self.grams = grams; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.fiber = fiber
    }

    enum CodingKeys: String, CodingKey { case id, name, grams, calories, protein, carbs, fat, fiber }

    /// Tolerant decoding: the server may send non-UUID ids or omit optional values.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        grams = try c.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        fiber = try c.decodeIfPresent(Double.self, forKey: .fiber) ?? 0
    }

    func scaled(by factor: Double) -> FoodComponent {
        var copy = self
        copy.grams *= factor; copy.calories *= factor
        copy.protein *= factor; copy.carbs *= factor; copy.fat *= factor; copy.fiber *= factor
        return copy
    }
}

/// A diary record. All nutrition values describe the whole portion.
struct MealEntry: Identifiable, Hashable, Sendable {
    enum MealType: String, CaseIterable, Identifiable, Codable, Sendable {
        case breakfast, lunch, dinner, snack

        var id: String { rawValue }

        var title: String {
            switch self {
            case .breakfast: "Сніданок"
            case .lunch: "Обід"
            case .dinner: "Вечеря"
            case .snack: "Перекус"
            }
        }

        /// Accepts both the stable key and the Ukrainian titles that v0.2 stored as raw values.
        init?(storageValue: String) {
            if let value = MealType(rawValue: storageValue) { self = value; return }
            guard let value = MealType.allCases.first(where: { $0.title == storageValue }) else { return nil }
            self = value
        }

        /// A sensible default based on the time of day.
        static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
            switch calendar.component(.hour, from: date) {
            case 5..<11: .breakfast
            case 11..<16: .lunch
            case 16..<22: .dinner
            default: .snack
            }
        }
    }

    var id: UUID
    var date: Date
    var name: String
    /// Portion weight in grams; 0 means the weight is unknown.
    var grams: Double
    /// Energy of the whole portion, kcal.
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var mealType: MealType
    var ingredients: [FoodComponent]
    var isFavorite: Bool

    init(
        id: UUID = UUID(), date: Date = .now, name: String, grams: Double, calories: Double,
        protein: Double = 0, carbs: Double = 0, fat: Double = 0, fiber: Double = 0,
        mealType: MealType = .lunch, ingredients: [FoodComponent] = [], isFavorite: Bool = false
    ) {
        self.id = id; self.date = date; self.name = name; self.grams = grams; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.fiber = fiber
        self.mealType = mealType; self.ingredients = ingredients; self.isFavorite = isFavorite
    }

    var kcal: Int { Int(calories.rounded()) }

    var caloriesPer100g: Double? { grams > 0 ? calories / grams * 100 : nil }

    /// Returns the same food with a different portion size: energy, macros and ingredients scale proportionally.
    func scaled(toGrams newGrams: Double) -> MealEntry {
        var copy = self
        guard let factor = Portion.scaleFactor(from: grams, to: newGrams) else {
            copy.grams = newGrams
            return copy
        }
        copy.grams = newGrams
        copy.calories *= factor
        copy.protein *= factor; copy.carbs *= factor; copy.fat *= factor; copy.fiber *= factor
        copy.ingredients = ingredients.map { $0.scaled(by: factor) }
        return copy
    }
}

enum Portion {
    /// The multiplier that turns a portion of `old` grams into `new` grams, or nil when the old weight is unknown.
    static func scaleFactor(from old: Double, to new: Double) -> Double? {
        guard old > 0, new >= 0, old.isFinite, new.isFinite else { return nil }
        return new / old
    }
}

/// Turns successive weight edits into scale factors for the macros.
///
/// Remembers the last positive weight, so passing through 0 while typing ("250" → "" → "300")
/// does not wipe the macros: the factor is computed from 250 to 300.
struct PortionTracker: Equatable, Sendable {
    private(set) var reference: Double

    init(grams: Double) { reference = grams }

    mutating func reset(to grams: Double) { reference = grams }

    /// The factor to apply for the new weight, or nil when nothing should be rescaled.
    mutating func factor(for newGrams: Double) -> Double? {
        guard newGrams > 0, newGrams.isFinite else { return nil }
        defer { reference = newGrams }
        guard let factor = Portion.scaleFactor(from: reference, to: newGrams), factor != 1 else { return nil }
        return factor
    }
}

struct WeightRecord: Identifiable, Hashable, Sendable {
    var id = UUID()
    var date = Date.now
    var kilograms: Double

    static let validRange: ClosedRange<Double> = 30...350

    /// Parses user input such as "82,5" or "82.5" and checks that it is a plausible body weight.
    static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), validRange ~= value else { return nil }
        return value
    }
}

struct WaterLog: Identifiable, Hashable, Sendable {
    var id = UUID()
    var date = Date.now
    var milliliters: Double
}

struct NutritionTotals: Equatable, Sendable {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var fiber = 0.0

    init() {}

    init(entries: some Sequence<MealEntry>) {
        for entry in entries {
            calories += entry.calories; protein += entry.protein
            carbs += entry.carbs; fat += entry.fat; fiber += entry.fiber
        }
    }

    var kcal: Int { Int(calories.rounded()) }

    /// The per-day average of several days' totals; zero for an empty list.
    static func average(of days: [NutritionTotals]) -> NutritionTotals {
        var result = NutritionTotals()
        guard !days.isEmpty else { return result }
        let count = Double(days.count)
        for day in days {
            result.calories += day.calories / count; result.protein += day.protein / count
            result.carbs += day.carbs / count; result.fat += day.fat / count; result.fiber += day.fiber / count
        }
        return result
    }
}
