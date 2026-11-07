import Foundation

struct NutritionGoals: Codable, Equatable, Sendable {
    var calories = 2_000.0
    var protein = 120.0
    var carbs = 220.0
    var fat = 65.0
    var fiber = 30.0
    var waterML = 2_500.0

    init(
        calories: Double = 2_000, protein: Double = 120, carbs: Double = 220,
        fat: Double = 65, fiber: Double = 30, waterML: Double = 2_500
    ) {
        self.calories = calories; self.protein = protein; self.carbs = carbs
        self.fat = fat; self.fiber = fiber; self.waterML = waterML
    }

    enum CodingKeys: String, CodingKey { case calories, protein, carbs, fat, fiber, waterML }

    /// Missing keys fall back to defaults so adding a goal later never discards saved ones.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NutritionGoals()
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? d.calories
        protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? d.protein
        carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? d.carbs
        fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? d.fat
        fiber = try c.decodeIfPresent(Double.self, forKey: .fiber) ?? d.fiber
        waterML = try c.decodeIfPresent(Double.self, forKey: .waterML) ?? d.waterML
    }
}

struct NutritionProfile: Codable, Equatable, Sendable {
    enum Sex: String, CaseIterable, Identifiable, Codable, Sendable {
        case male, female
        var id: String { rawValue }
        var title: String { self == .male ? "Чоловік" : "Жінка" }
    }

    enum Activity: String, CaseIterable, Identifiable, Codable, Sendable {
        case sedentary, light, moderate, high
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sedentary: "Малорухливий"
            case .light: "Легка активність"
            case .moderate: "Середня активність"
            case .high: "Висока активність"
            }
        }
        var factor: Double {
            switch self {
            case .sedentary: 1.2
            case .light: 1.375
            case .moderate: 1.55
            case .high: 1.725
            }
        }
    }

    enum Goal: String, CaseIterable, Identifiable, Codable, Sendable {
        case lose, maintain, gain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lose: "Схуднення"
            case .maintain: "Підтримка"
            case .gain: "Набір маси"
            }
        }
    }

    enum Diet: String, CaseIterable, Identifiable, Codable, Sendable {
        case balanced, highProtein, vegetarian
        var id: String { rawValue }
        var title: String {
            switch self {
            case .balanced: "Збалансований"
            case .highProtein: "Більше білка"
            case .vegetarian: "Вегетаріанський"
            }
        }
    }

    var sex: Sex = .female
    var age = 30
    var heightCM = 170.0
    var weightKG = 70.0
    var activity: Activity = .light
    var goal: Goal = .maintain
    var diet: Diet = .balanced

    var isValid: Bool { (120...230).contains(heightCM) && WeightRecord.validRange.contains(weightKG) && (18...90).contains(age) }

    var bmi: Double { weightKG / pow(heightCM / 100, 2) }
    /// Mifflin–St Jeor basal metabolic rate.
    var bmr: Double { 10 * weightKG + 6.25 * heightCM - 5 * Double(age) + (sex == .male ? 5 : -161) }
    var maintenanceCalories: Double { bmr * activity.factor }
    var targetCalories: Double {
        let adjusted = maintenanceCalories + (goal == .lose ? -500 : goal == .gain ? 300 : 0)
        return max(adjusted, sex == .male ? 1_500 : 1_200)
    }

    var calculatedGoals: NutritionGoals {
        let proteinShare = diet == .highProtein ? 0.30 : 0.25
        let fatShare = 0.30
        return NutritionGoals(
            calories: targetCalories,
            protein: targetCalories * proteinShare / 4,
            carbs: targetCalories * (1 - proteinShare - fatShare) / 4,
            fat: targetCalories * fatShare / 9,
            fiber: 30,
            waterML: max(1_500, min(weightKG * 30, 4_000))
        )
    }
}

struct PlannedMeal: Identifiable, Sendable {
    let id = UUID()
    var mealType: MealEntry.MealType
    var foods: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var fiber: Double
}

enum MealPlanBuilder {
    static let shares: [(MealEntry.MealType, Double)] = [(.breakfast, 0.25), (.lunch, 0.35), (.dinner, 0.30), (.snack, 0.10)]

    static func make(profile: NutritionProfile) -> [PlannedMeal] {
        let goals = profile.calculatedGoals
        let balanced = [
            "Вівсянка, яйця, ягоди та натуральний йогурт",
            "Куряче філе, гречка та великий овочевий салат",
            "Запечена риба, картопля та зелені овочі",
            "Кисломолочний сир, яблуко та горіхи"
        ]
        let highProtein = [
            "Омлет із овочами, індичка та цільнозерновий хліб",
            "Яловичина, рис, салат і натуральний йогурт",
            "Куряче філе, сочевиця та запечені овочі",
            "Кисломолочний сир або грецький йогурт із ягодами"
        ]
        let vegetarian = [
            "Вівсянка, грецький йогурт, ягоди та насіння",
            "Сочевиця, гречка, тофу та овочевий салат",
            "Нут, запечені овочі, кіноа та авокадо",
            "Кисломолочний сир або соєвий йогурт із фруктом"
        ]
        let foods = switch profile.diet {
        case .balanced: balanced
        case .highProtein: highProtein
        case .vegetarian: vegetarian
        }
        return shares.enumerated().map { index, item in
            let (type, share) = item
            return PlannedMeal(
                mealType: type, foods: foods[index], calories: Int(goals.calories * share),
                protein: Int(goals.protein * share), carbs: Int(goals.carbs * share),
                fat: Int(goals.fat * share), fiber: goals.fiber * share
            )
        }
    }
}
