import Foundation

struct RecipeIngredient: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var grams: Int
    var calories: Int
}

struct AssistantRecipe: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var mealType: MealEntry.MealType
    var ingredients: [RecipeIngredient]
    var steps: String
    var calories: Int
    var protein: Int
}

struct AssistantResult: Sendable {
    var message: String
    var recipes: [AssistantRecipe]
    var shoppingList: [String]
}

/// Local recipe matcher. A placeholder until the assistant is backed by the server.
enum PantryAssistant {
    static let catalog: [AssistantRecipe] = [
        AssistantRecipe(title: "Вівсянка з йогуртом і ягодами", mealType: .breakfast, ingredients: [i("вівсянка", 60, 228), i("йогурт", 200, 120), i("ягоди", 100, 50), i("горіхи", 10, 65)], steps: "1. Зваріть вівсянку у воді 5–7 хвилин.\n2. Дайте трохи охолонути та додайте йогурт.\n3. Зверху викладіть ягоди й подрібнені горіхи.", calories: 463, protein: 22),
        AssistantRecipe(title: "Омлет з овочами", mealType: .breakfast, ingredients: [i("яйця", 180, 210), i("помідори", 150, 27), i("перець", 100, 31), i("зелень", 30, 10)], steps: "1. Наріжте овочі.\n2. Збийте 3 яйця.\n3. Протушкуйте овочі 3 хвилини, залийте яйцями та готуйте під кришкою 7–8 хвилин.", calories: 278, protein: 25),
        AssistantRecipe(title: "Курка з гречкою та салатом", mealType: .lunch, ingredients: [i("куряче філе", 200, 330), i("гречка суха", 80, 274), i("огірок", 150, 23), i("помідори", 150, 27)], steps: "1. Відваріть гречку.\n2. Курку приправте та запікайте 20–25 хвилин.\n3. Наріжте огірок і помідори, подайте разом.", calories: 654, protein: 58),
        AssistantRecipe(title: "Сочевиця з овочами", mealType: .lunch, ingredients: [i("сочевиця суха", 100, 352), i("морква", 100, 41), i("цибуля", 80, 32), i("помідори", 80, 15)], steps: "1. Промийте сочевицю.\n2. Протушкуйте цибулю й моркву.\n3. Додайте сочевицю, помідори та воду, готуйте 20–25 хвилин.", calories: 440, protein: 29),
        AssistantRecipe(title: "Запечена риба з картоплею", mealType: .dinner, ingredients: [i("риба", 200, 300), i("картопля", 250, 193), i("броколі", 200, 68), i("лимон", 30, 9)], steps: "1. Наріжте картоплю та запікайте 15 хвилин.\n2. Додайте рибу й броколі.\n3. Запікайте ще 20–25 хвилин, подайте з лимоном.", calories: 570, protein: 45),
        AssistantRecipe(title: "Сир із фруктом та горіхами", mealType: .snack, ingredients: [i("кисломолочний сир", 200, 242), i("яблуко", 150, 78), i("горіхи", 15, 98)], steps: "1. Наріжте яблуко.\n2. Додайте до кисломолочного сиру.\n3. Посипте подрібненими горіхами.", calories: 418, protein: 34)
    ]

    private static let aliases: [String: [String]] = [
        "куряче філе": ["курка", "курятина", "філе"], "кисломолочний сир": ["сир", "творог"],
        "помідори": ["помідор", "томат"], "яйця": ["яйце"], "вівсянка": ["овес", "пластівці"],
        "риба": ["лосось", "хек", "тунець", "скумбрія"], "картопля": ["картошка"],
        "гречка суха": ["гречка"], "сочевиця суха": ["сочевиця"]
    ]

    /// - Parameter mealType: nil means the whole day.
    static func suggest(pantryText: String, mealType: MealEntry.MealType?, caloriesLeft: Int, proteinLeft: Int) -> AssistantResult {
        let pantry = pantryText.lowercased()
        let filtered = mealType.map { type in catalog.filter { $0.mealType == type } } ?? catalog
        let ranked = filtered.enumerated().sorted { lhs, rhs in
            let l = availableCount(lhs.element.ingredients, in: pantry), r = availableCount(rhs.element.ingredients, in: pantry)
            return l != r ? l > r : lhs.offset < rhs.offset
        }.map(\.element)
        let selected = Array(ranked.prefix(mealType == nil ? 4 : 3))
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

    static func availableCount(_ ingredients: [RecipeIngredient], in pantry: String) -> Int {
        ingredients.filter { contains($0.name, in: pantry) }.count
    }

    static func contains(_ ingredient: String, in pantry: String) -> Bool {
        pantry.contains(ingredient) || aliases[ingredient, default: []].contains { pantry.contains($0) }
    }
}
