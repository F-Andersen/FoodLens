import Foundation

/// Energy per gram of each macronutrient (Atwater factors).
enum MacroEnergy {
    static let protein = 4.0
    static let carbs = 4.0
    static let fat = 9.0
}

/// Shares of the daily energy goal that come from protein and fat; carbohydrates take the rest.
struct MacroSplit: Codable, Hashable, Sendable {
    var protein: Double
    var fat: Double

    init(protein: Double, fat: Double) {
        self.protein = protein; self.fat = fat
    }

    var carbs: Double { max(0, 1 - protein - fat) }

    static let proteinRange = 0.10...0.40
    static let fatRange = 0.20...0.45

    /// Carbohydrates keep at least 15 % so the split stays physiologically sensible.
    var isValid: Bool { Self.proteinRange.contains(protein) && Self.fatRange.contains(fat) && carbs >= 0.15 - 1e-9 }

    static let balanced = MacroSplit(protein: 0.25, fat: 0.30)
    static let highProtein = MacroSplit(protein: 0.30, fat: 0.30)
    static let lowerCarb = MacroSplit(protein: 0.30, fat: 0.40)

    static let presets: [(title: String, split: MacroSplit)] = [
        ("Збалансований", .balanced), ("Більше білка", .highProtein), ("Менше вуглеводів", .lowerCarb)
    ]

    var presetTitle: String? { Self.presets.first { $0.split == self }?.title }

    /// "25 / 30 / 45 %" — protein, fat, carbohydrates.
    var percentText: String {
        let p = Int((protein * 100).rounded()), f = Int((fat * 100).rounded())
        return "\(p) / \(f) / \(100 - p - f) %"
    }

    /// The split implied by gram goals, rounded to whole percent. Nil when the grams carry no energy.
    static func implied(protein: Double, carbs: Double, fat: Double) -> MacroSplit? {
        let p = protein * MacroEnergy.protein, f = fat * MacroEnergy.fat, c = carbs * MacroEnergy.carbs
        let total = p + f + c
        guard total > 0 else { return nil }
        return MacroSplit(protein: (p / total * 100).rounded() / 100, fat: (f / total * 100).rounded() / 100)
    }
}

struct NutritionGoals: Codable, Equatable, Sendable {
    var calories = 2_000.0
    var protein = 125.0
    var carbs = 224.0
    var fat = 67.0
    var fiber = 30.0
    var waterML = 2_500.0
    /// When set, protein, fat and carbohydrates follow the calorie goal. Nil means the user set grams by hand.
    var macroSplit: MacroSplit?

    init(
        calories: Double = 2_000, protein: Double = 125, carbs: Double = 224,
        fat: Double = 67, fiber: Double = 30, waterML: Double = 2_500, macroSplit: MacroSplit? = nil
    ) {
        self.calories = calories; self.protein = protein; self.carbs = carbs
        self.fat = fat; self.fiber = fiber; self.waterML = waterML; self.macroSplit = macroSplit
        if let macroSplit { applyMacros(macroSplit) }
    }

    /// Default goals for a new install: 2 000 kcal with a balanced split.
    static let standard = NutritionGoals(calories: 2_000, macroSplit: .balanced)

    enum CodingKeys: String, CodingKey { case calories, protein, carbs, fat, fiber, waterML, macroSplit }

    /// Missing keys fall back to defaults so adding a goal later never discards saved ones.
    /// Goals saved before `macroSplit` existed decode as manual, so nothing the user set is recalculated silently.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NutritionGoals.standard
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? d.calories
        protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? d.protein
        carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? d.carbs
        fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? d.fat
        fiber = try c.decodeIfPresent(Double.self, forKey: .fiber) ?? d.fiber
        waterML = try c.decodeIfPresent(Double.self, forKey: .waterML) ?? d.waterML
        macroSplit = try? c.decodeIfPresent(MacroSplit.self, forKey: .macroSplit)
    }

    // MARK: Consistency

    /// Energy the macronutrient goals add up to (4/9/4 kcal per gram).
    var macroCalories: Double { protein * MacroEnergy.protein + fat * MacroEnergy.fat + carbs * MacroEnergy.carbs }

    /// Positive when the macros add up to more than the calorie goal.
    var macroCalorieGap: Double { macroCalories - calories }

    /// Whole grams cost up to ~9 kcal of rounding; anything beyond 3 % (at least 30 kcal) is a real mismatch.
    var macroCalorieTolerance: Double { max(30, calories * 0.03) }

    var macrosMatchCalories: Bool { abs(macroCalorieGap) <= macroCalorieTolerance }

    var isAutomatic: Bool { macroSplit != nil }

    /// The split the current grams imply, used to keep the user's proportions when aligning them.
    var impliedSplit: MacroSplit? { MacroSplit.implied(protein: protein, carbs: carbs, fat: fat) }

    // MARK: Editing

    /// Sets the calorie goal. Automatic macros follow it; manual grams stay as the user set them.
    mutating func setCalories(_ value: Double) {
        calories = value
        if let macroSplit { applyMacros(macroSplit) }
    }

    /// Switches to automatic macros with the given split, or to manual grams (keeping the current values) with nil.
    mutating func setMacroSplit(_ split: MacroSplit?) {
        macroSplit = split
        if let split { applyMacros(split) }
    }

    /// Recalculates the grams for the current calorie goal, keeping the proportions the user already had.
    /// Only called from an explicit user action.
    mutating func alignMacrosToCalories() {
        setMacroSplit(impliedSplit.flatMap { $0.isValid ? $0 : nil } ?? .balanced)
    }

    /// Whole grams for protein and fat; carbohydrates take the remaining energy, so the total stays within ~2 kcal.
    private mutating func applyMacros(_ split: MacroSplit) {
        protein = (calories * split.protein / MacroEnergy.protein).rounded()
        fat = (calories * split.fat / MacroEnergy.fat).rounded()
        let rest = calories - protein * MacroEnergy.protein - fat * MacroEnergy.fat
        carbs = max(0, (rest / MacroEnergy.carbs).rounded())
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
        /// Kilograms per week offered for this goal.
        var rateOptions: [Double] {
            switch self {
            case .lose: [0.25, 0.5, 0.75, 1.0]
            case .maintain: []
            case .gain: [0.25, 0.5]
            }
        }
        var defaultRate: Double { self == .gain ? 0.25 : 0.5 }
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
        var macroSplit: MacroSplit { self == .highProtein ? .highProtein : .balanced }
    }

    /// Approximate energy in one kilogram of body fat.
    static let kcalPerKilogram = 7_700.0

    var sex: Sex = .female
    var age = 30
    var heightCM = 170.0
    var weightKG = 70.0
    var activity: Activity = .light
    var goal: Goal = .maintain
    var diet: Diet = .balanced
    var targetWeightKG: Double?
    /// Desired change in kg per week; nil uses the goal's default.
    var weeklyRateKG: Double?

    init() {}

    enum CodingKeys: String, CodingKey {
        case sex, age, heightCM, weightKG, activity, goal, diet, targetWeightKG, weeklyRateKG
    }

    /// Tolerant decoding: a profile saved by an older version must never be lost because a field was added.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NutritionProfile()
        sex = (try? c.decodeIfPresent(Sex.self, forKey: .sex)) ?? d.sex
        age = (try? c.decodeIfPresent(Int.self, forKey: .age)) ?? d.age
        heightCM = (try? c.decodeIfPresent(Double.self, forKey: .heightCM)) ?? d.heightCM
        weightKG = (try? c.decodeIfPresent(Double.self, forKey: .weightKG)) ?? d.weightKG
        activity = (try? c.decodeIfPresent(Activity.self, forKey: .activity)) ?? d.activity
        goal = (try? c.decodeIfPresent(Goal.self, forKey: .goal)) ?? d.goal
        diet = (try? c.decodeIfPresent(Diet.self, forKey: .diet)) ?? d.diet
        targetWeightKG = try? c.decodeIfPresent(Double.self, forKey: .targetWeightKG)
        weeklyRateKG = try? c.decodeIfPresent(Double.self, forKey: .weeklyRateKG)
    }

    var isValid: Bool { (120...230).contains(heightCM) && WeightRecord.validRange.contains(weightKG) && (18...90).contains(age) }

    var bmi: Double { weightKG / pow(heightCM / 100, 2) }
    /// Mifflin–St Jeor basal metabolic rate.
    var bmr: Double { 10 * weightKG + 6.25 * heightCM - 5 * Double(age) + (sex == .male ? 5 : -161) }
    /// Total daily energy expenditure estimate. It already includes typical activity, so Health's
    /// active energy must not be added on top of it.
    var maintenanceCalories: Double { bmr * activity.factor }

    var rate: Double { goal == .maintain ? 0 : (weeklyRateKG ?? goal.defaultRate) }

    /// Daily energy change that the chosen pace needs: negative for weight loss.
    var dailyAdjustment: Double {
        let perDay = rate * Self.kcalPerKilogram / 7
        return goal == .lose ? -perDay : goal == .gain ? perDay : 0
    }

    static func calorieFloor(for sex: Sex) -> Double { sex == .male ? 1_500 : 1_200 }

    /// The recommended intake, never below a safe floor for adults.
    var targetCalories: Double { max(maintenanceCalories + dailyAdjustment, Self.calorieFloor(for: sex)) }

    var calculatedGoals: NutritionGoals {
        NutritionGoals(
            calories: targetCalories.rounded(), fiber: 30,
            waterML: max(1_500, min(weightKG * 30, 4_000)), macroSplit: diet.macroSplit
        )
    }

    /// Rough number of weeks to the target weight at the chosen pace; nil when it does not apply.
    var weeksToTarget: Double? {
        guard let target = targetWeightKG, rate > 0 else { return nil }
        let difference = target - weightKG
        guard (goal == .lose && difference < 0) || (goal == .gain && difference > 0) else { return nil }
        return abs(difference) / rate
    }

    /// A caution when the target weight and goal point in different directions.
    var targetWeightMismatch: String? {
        guard let target = targetWeightKG, abs(target - weightKG) >= 0.5 else { return nil }
        if goal == .lose && target > weightKG { return "Цільова вага більша за поточну, а мета — схуднення." }
        if goal == .gain && target < weightKG { return "Цільова вага менша за поточну, а мета — набір маси." }
        return nil
    }

    /// Warns about an aggressive deficit for a calorie goal; never changes the goal itself.
    func deficitWarning(forCalories calories: Double) -> String? {
        let maintenance = maintenanceCalories
        if calories < bmr {
            return "Ціль \(Int(calories.rounded())) ккал нижча за базовий обмін (\(Int(bmr.rounded())) ккал). Такий дефіцит важко підтримувати безпечно — узгодьте його з лікарем."
        }
        if maintenance > 0, (maintenance - calories) / maintenance > 0.25 {
            return "Дефіцит понад 25 % від підтримки (\(Int(maintenance.rounded())) ккал). Це агресивний темп: стежте за самопочуттям і білком."
        }
        return nil
    }

    /// Explains that the calculated goal was raised to the safe floor.
    var floorNotice: String? {
        guard maintenanceCalories + dailyAdjustment < Self.calorieFloor(for: sex) else { return nil }
        return "Обраний темп дав би менше \(Int(Self.calorieFloor(for: sex))) ккал, тому ціль піднято до мінімуму. Оберіть повільніший темп."
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
                mealType: type, foods: foods[index], calories: Int((goals.calories * share).rounded()),
                protein: Int((goals.protein * share).rounded()), carbs: Int((goals.carbs * share).rounded()),
                fat: Int((goals.fat * share).rounded()), fiber: goals.fiber * share
            )
        }
    }
}
