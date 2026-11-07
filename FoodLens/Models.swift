import Foundation
import Combine

struct FoodComponent: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
}

struct MealEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date.now
    var name: String
    var grams: Double
    var caloriesPer100g: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var mealType: MealType
    var ingredients: [FoodComponent]
    var isFavorite: Bool

    enum MealType: String, Codable, CaseIterable, Identifiable {
        case breakfast = "Сніданок"
        case lunch = "Обід"
        case dinner = "Вечеря"
        case snack = "Перекус"
        var id: String { rawValue }
    }

    var calories: Int { Int((grams * caloriesPer100g / 100).rounded()) }

    init(
        id: UUID = UUID(), date: Date = .now, name: String, grams: Double,
        caloriesPer100g: Double, protein: Double = 0, carbs: Double = 0,
        fat: Double = 0, fiber: Double = 0, mealType: MealType = .lunch,
        ingredients: [FoodComponent] = [], isFavorite: Bool = false
    ) {
        self.id = id; self.date = date; self.name = name; self.grams = grams
        self.caloriesPer100g = caloriesPer100g; self.protein = protein
        self.carbs = carbs; self.fat = fat; self.fiber = fiber
        self.mealType = mealType; self.ingredients = ingredients; self.isFavorite = isFavorite
    }

    enum CodingKeys: String, CodingKey {
        case id, date, name, grams, caloriesPer100g, protein, carbs, fat, fiber, mealType, ingredients, isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        name = try c.decode(String.self, forKey: .name)
        grams = try c.decode(Double.self, forKey: .grams)
        caloriesPer100g = try c.decode(Double.self, forKey: .caloriesPer100g)
        protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        fiber = try c.decodeIfPresent(Double.self, forKey: .fiber) ?? 0
        mealType = try c.decodeIfPresent(MealType.self, forKey: .mealType) ?? .lunch
        ingredients = try c.decodeIfPresent([FoodComponent].self, forKey: .ingredients) ?? []
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

struct WeightRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date.now
    var kilograms: Double
}

struct NutritionGoals: Codable {
    var calories = 2_000.0
    var protein = 120.0
    var carbs = 220.0
    var fat = 65.0
    var fiber = 30.0
    var waterML = 2_500.0
}

struct NutritionProfile {
    enum Sex: String, CaseIterable, Identifiable { case male = "Чоловік", female = "Жінка"; var id: String { rawValue } }
    enum Activity: String, CaseIterable, Identifiable {
        case sedentary = "Малорухливий", light = "Легка активність", moderate = "Середня активність", high = "Висока активність"
        var id: String { rawValue }
        var factor: Double { switch self { case .sedentary: 1.2; case .light: 1.375; case .moderate: 1.55; case .high: 1.725 } }
    }
    enum Goal: String, CaseIterable, Identifiable { case lose = "Схуднення", maintain = "Підтримка", gain = "Набір маси"; var id: String { rawValue } }
    enum Diet: String, CaseIterable, Identifiable { case balanced = "Збалансований", highProtein = "Більше білка", vegetarian = "Вегетаріанський"; var id: String { rawValue } }

    var sex: Sex = .male
    var age = 30
    var heightCM = 190.0
    var weightKG = 120.0
    var activity: Activity = .light
    var goal: Goal = .lose
    var diet: Diet = .balanced

    /// Ключ для відстеження змін анкети (усі поля, що впливають на розрахунок).
    var goalsKey: String { "\(sex.rawValue)|\(age)|\(heightCM)|\(weightKG)|\(activity.rawValue)|\(goal.rawValue)|\(diet.rawValue)" }

    var bmi: Double { weightKG / pow(heightCM / 100, 2) }
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

struct PlannedMeal: Identifiable {
    let id = UUID()
    var title: String
    var foods: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
}

enum MealPlanBuilder {
    static func make(profile: NutritionProfile) -> [PlannedMeal] {
        let target = profile.targetCalories
        let goals = profile.calculatedGoals
        let shares = [0.25, 0.35, 0.30, 0.10]
        let titles = ["Сніданок", "Обід", "Вечеря", "Перекус"]
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
        let foods = profile.diet == .vegetarian ? vegetarian : profile.diet == .highProtein ? highProtein : balanced
        return shares.indices.map { index in
            PlannedMeal(
                title: titles[index], foods: foods[index], calories: Int(target * shares[index]),
                protein: Int(goals.protein * shares[index]), carbs: Int(goals.carbs * shares[index]), fat: Int(goals.fat * shares[index])
            )
        }
    }
}

struct RecipeIngredient: Identifiable {
    let id = UUID()
    var name: String
    var grams: Int
    var calories: Int
}

struct AssistantRecipe: Identifiable {
    let id = UUID()
    var title: String
    var meal: String
    var ingredients: [RecipeIngredient]
    var steps: String
    var calories: Int
    var protein: Int
}

struct AssistantResult {
    var message: String
    var recipes: [AssistantRecipe]
    var shoppingList: [String]
}

enum PantryAssistant {
    static func suggest(pantryText: String, mealFilter: String, caloriesLeft: Int, proteinLeft: Int) -> AssistantResult {
        let pantry = pantryText.lowercased()
        let all: [AssistantRecipe] = [
            AssistantRecipe(title: "Вівсянка з йогуртом і ягодами", meal: "Сніданок", ingredients: [i("вівсянка", 60, 228), i("йогурт", 200, 120), i("ягоди", 100, 50), i("горіхи", 10, 65)], steps: "1. Зваріть вівсянку у воді 5–7 хвилин.\n2. Дайте трохи охолонути та додайте йогурт.\n3. Зверху викладіть ягоди й подрібнені горіхи.", calories: 463, protein: 22),
            AssistantRecipe(title: "Омлет з овочами", meal: "Сніданок", ingredients: [i("яйця", 180, 210), i("помідори", 150, 27), i("перець", 100, 31), i("зелень", 30, 10)], steps: "1. Наріжте овочі.\n2. Збийте 3 яйця.\n3. Протушкуйте овочі 3 хвилини, залийте яйцями та готуйте під кришкою 7–8 хвилин.", calories: 278, protein: 25),
            AssistantRecipe(title: "Курка з гречкою та салатом", meal: "Обід", ingredients: [i("куряче філе", 200, 330), i("гречка суха", 80, 274), i("огірок", 150, 23), i("помідори", 150, 27)], steps: "1. Відваріть гречку.\n2. Курку приправте та запікайте 20–25 хвилин.\n3. Наріжте огірок і помідори, подайте разом.", calories: 654, protein: 58),
            AssistantRecipe(title: "Сочевиця з овочами", meal: "Обід", ingredients: [i("сочевиця суха", 100, 352), i("морква", 100, 41), i("цибуля", 80, 32), i("помідори", 80, 15)], steps: "1. Промийте сочевицю.\n2. Протушкуйте цибулю й моркву.\n3. Додайте сочевицю, помідори та воду, готуйте 20–25 хвилин.", calories: 440, protein: 29),
            AssistantRecipe(title: "Запечена риба з картоплею", meal: "Вечеря", ingredients: [i("риба", 200, 300), i("картопля", 250, 193), i("броколі", 200, 68), i("лимон", 30, 9)], steps: "1. Наріжте картоплю та запікайте 15 хвилин.\n2. Додайте рибу й броколі.\n3. Запікайте ще 20–25 хвилин, подайте з лимоном.", calories: 570, protein: 45),
            AssistantRecipe(title: "Сир із фруктом та горіхами", meal: "Перекус", ingredients: [i("кисломолочний сир", 200, 242), i("яблуко", 150, 78), i("горіхи", 15, 98)], steps: "1. Наріжте яблуко.\n2. Додайте до кисломолочного сиру.\n3. Посипте подрібненими горіхами.", calories: 418, protein: 34)
        ]
        let filtered = mealFilter == "Увесь день" ? all : all.filter { $0.meal == mealFilter }
        let ranked = filtered.sorted { lhs, rhs in
            availableCount(lhs.ingredients, in: pantry) > availableCount(rhs.ingredients, in: pantry)
        }
        let selected = Array(ranked.prefix(mealFilter == "Увесь день" ? 4 : 3))
        let missing = selected.flatMap(\.ingredients).map(\.name).filter { !contains($0, in: pantry) }
        let shopping = Array(Set(missing)).sorted()
        let message = proteinLeft > 30
            ? "Сьогодні варто добрати приблизно \(proteinLeft) г білка. Обирайте страви з рибою, куркою, яйцями, сиром або бобовими."
            : "До денної цілі залишилось близько \(max(0, caloriesLeft)) ккал. Раціон виглядає збалансовано — орієнтуйтесь на голод і розмір порції."
        return AssistantResult(message: message, recipes: selected, shoppingList: shopping)
    }

    private static func i(_ name: String, _ grams: Int, _ calories: Int) -> RecipeIngredient {
        RecipeIngredient(name: name, grams: grams, calories: calories)
    }

    private static func availableCount(_ ingredients: [RecipeIngredient], in pantry: String) -> Int {
        ingredients.filter { contains($0.name, in: pantry) }.count
    }

    private static func contains(_ ingredient: String, in pantry: String) -> Bool {
        let aliases: [String: [String]] = [
            "куряче філе": ["курка", "філе"], "кисломолочний сир": ["сир", "творог"],
            "помідори": ["помідор", "томат"], "яйця": ["яйце"], "вівсянка": ["овес", "пластівці"],
            "риба": ["лосось", "хек", "тунець"], "картопля": ["картошка"]
        ]
        return pantry.contains(ingredient) || aliases[ingredient, default: []].contains { pantry.contains($0) }
    }
}

@MainActor
final class DiaryStore: ObservableObject {
    @Published private(set) var entries: [MealEntry] = [] { didSet { save() } }
    @Published private(set) var weights: [WeightRecord] = [] { didSet { save() } }
    @Published var goals = NutritionGoals() { didSet { save() } }
    @Published private(set) var waterToday: Double = 0 { didSet { save() } }

    private let storageKey = "foodlens_store_v2"

    private struct Snapshot: Codable {
        var entries: [MealEntry]
        var weights: [WeightRecord]
        var goals: NutritionGoals
        var waterToday: Double
        var waterDate: Date
    }

    private var waterDate = Date.now

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let value = try? JSONDecoder().decode(Snapshot.self, from: data) {
            entries = value.entries; weights = value.weights; goals = value.goals
            waterDate = value.waterDate
            waterToday = Calendar.current.isDateInToday(value.waterDate) ? value.waterToday : 0
        } else if let old = UserDefaults.standard.data(forKey: "meal_diary_v1"),
                  let decoded = try? JSONDecoder().decode([MealEntry].self, from: old) {
            entries = decoded
        }
    }

    var todayEntries: [MealEntry] { entries.filter { Calendar.current.isDateInToday($0.date) } }
    var currentWater: Double { Calendar.current.isDateInToday(waterDate) ? waterToday : 0 }
    var caloriesToday: Int { todayEntries.reduce(0) { $0 + $1.calories } }
    var proteinToday: Double { todayEntries.reduce(0) { $0 + $1.protein } }
    var carbsToday: Double { todayEntries.reduce(0) { $0 + $1.carbs } }
    var fatToday: Double { todayEntries.reduce(0) { $0 + $1.fat } }
    var fiberToday: Double { todayEntries.reduce(0) { $0 + $1.fiber } }
    var favorites: [MealEntry] { entries.filter(\.isFavorite) }

    func add(_ entry: MealEntry) { entries.insert(entry, at: 0) }
    func update(_ entry: MealEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }
    func delete(at offsets: IndexSet) { entries.remove(atOffsets: offsets) }
    func delete(id: UUID) { entries.removeAll { $0.id == id } }
    func addWater(_ milliliters: Double) {
        if !Calendar.current.isDateInToday(waterDate) { waterToday = 0 }
        waterDate = .now
        waterToday += milliliters
    }
    func addWeight(_ kilograms: Double) { weights.insert(WeightRecord(kilograms: kilograms), at: 0) }
    func updateWeight(id: UUID, kilograms: Double) {
        guard let index = weights.firstIndex(where: { $0.id == id }) else { return }
        weights[index].kilograms = kilograms
    }
    func deleteWeight(id: UUID) { weights.removeAll { $0.id == id } }
    func toggleFavorite(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isFavorite.toggle()
    }

    func calories(on date: Date) -> Int {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.calories }
    }

    private func save() {
        let value = Snapshot(entries: entries, weights: weights, goals: goals, waterToday: waterToday, waterDate: waterDate)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: storageKey) }
    }
}
