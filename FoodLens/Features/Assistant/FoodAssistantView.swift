import SwiftUI

struct FoodAssistantView: View {
    @Environment(DiaryStore.self) private var diary
    @AppStorage("assistantPantry") private var pantry = ""
    @AppStorage("assistantMealFilterV2") private var mealFilter = ""
    @AppStorage("assistantHasGenerated") private var hasGenerated = false
    @State private var selectedRecipe: AssistantRecipe?

    private var selectedMealType: MealEntry.MealType? { MealEntry.MealType(rawValue: mealFilter) }
    private var caloriesLeft: Int { max(0, Int(diary.goals.calories) - diary.todayTotals.kcal) }
    private var proteinLeft: Int { max(0, Int(diary.goals.protein - diary.todayTotals.protein)) }
    private var pantryIsEmpty: Bool { pantry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var result: AssistantResult? {
        guard hasGenerated, !pantryIsEmpty else { return nil }
        return PantryAssistant.suggest(pantryText: pantry, mealType: selectedMealType, caloriesLeft: caloriesLeft, proteinLeft: proteinLeft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Рецепти з того, що вже є вдома").foregroundStyle(.secondary).padding(.top, -Spacing.s)
                HStack {
                    Label("Залишок", systemImage: "flame.fill")
                    Spacer()
                    Text("\(caloriesLeft) ккал · \(proteinLeft) г білка").bold()
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Що є у холодильнику?", systemImage: "refrigerator.fill").font(.headline)
                    Text("Введіть через кому: яйця, курка, гречка, помідори…").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $pantry)
                        .frame(minHeight: 105)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    Picker("Прийом їжі", selection: $mealFilter) {
                        Text("Увесь день").tag("")
                        ForEach(MealEntry.MealType.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    Button {
                        hasGenerated = true
                    } label: {
                        Label("Запропонувати рецепти", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pantryIsEmpty)
                }
                .cardStyle()

                if let result { resultView(result) }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Асистент")
        .sheet(item: $selectedRecipe) { recipe in
            NavigationStack { AssistantRecipeDetailView(recipe: recipe) }
        }
    }

    @ViewBuilder
    private func resultView(_ result: AssistantResult) -> some View {
        Text(result.message).font(.callout).padding(14)
            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        Text("Що приготувати").font(.title2.bold())
        ForEach(result.recipes) { recipe in
            Button { selectedRecipe = recipe } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(recipe.mealType.title).font(.caption.bold()).foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(recipe.calories) ккал").bold()
                    }
                    HStack {
                        Text(recipe.title).font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    Text(recipe.ingredients.map { "\($0.name) \($0.grams) г" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Label("\(recipe.protein) г білка", systemImage: "bolt.heart.fill").font(.caption).foregroundStyle(.secondary)
                }
                .cardStyle()
            }
            .buttonStyle(.plain)
        }
        Text("Що докупити").font(.title2.bold())
        if result.shoppingList.isEmpty {
            Label("Усе необхідне вже є", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).cardStyle()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(result.shoppingList, id: \.self) { item in Label(item.capitalized, systemImage: "cart.badge.plus") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}

struct AssistantRecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: AssistantRecipe

    private var totalGrams: Int { recipe.ingredients.reduce(0) { $0 + $1.grams } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(recipe.mealType.title.uppercased()).font(.caption.bold()).foregroundStyle(Theme.accent)
                    Text(recipe.title).font(.system(.title, design: .rounded, weight: .bold))
                    HStack {
                        Label("\(recipe.calories) ккал", systemImage: "flame.fill")
                        Spacer()
                        Label("\(recipe.protein) г білка", systemImage: "bolt.heart.fill")
                    }
                    .font(.subheadline.bold())
                    Text("Орієнтовна вага порції: \(totalGrams) г").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            Section("Інгредієнти") {
                ForEach(recipe.ingredients) { ingredient in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ingredient.name.capitalized).font(.headline)
                            Text("\(ingredient.grams) г").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(ingredient.calories) ккал").bold()
                    }
                    .padding(.vertical, 3)
                }
                HStack { Text("Разом").bold(); Spacer(); Text("\(recipe.calories) ккал").bold().foregroundStyle(Theme.accent) }
            }
            Section("Як приготувати") {
                Text(recipe.steps).lineSpacing(6).padding(.vertical, 5)
            }
        }
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}
