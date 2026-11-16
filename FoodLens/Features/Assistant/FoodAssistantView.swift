import SwiftUI

struct FoodAssistantView: View {
    @Environment(DiaryStore.self) private var diary
    @AppStorage("assistantPantry") private var pantry = ""
    @AppStorage("assistantMealFilterV2") private var mealFilter = ""
    @AppStorage("assistantAvoid") private var avoid = ""
    @AppStorage("backendURL") private var backendURL = ""
    @State private var selectedRecipe: AssistantRecipe?
    @State private var result: AssistantResult?
    @State private var resultIsFromAI = false
    @State private var loading = false
    @State private var notice: String?

    private var selectedMealType: MealEntry.MealType? { MealEntry.MealType(rawValue: mealFilter) }
    private var caloriesLeft: Int { max(0, Int(diary.goals.calories) - diary.todayTotals.kcal) }
    private var proteinLeft: Int { max(0, Int(diary.goals.protein - diary.todayTotals.protein)) }
    private var pantryIsEmpty: Bool { pantry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// "курка, гречка\nпомідори" → ["курка", "гречка", "помідори"]
    nonisolated static func items(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func generate() async {
        loading = true
        notice = nil
        defer { loading = false }
        let local = PantryAssistant.suggest(pantryText: pantry, mealType: selectedMealType, caloriesLeft: caloriesLeft, proteinLeft: proteinLeft)
        guard let baseURL = AppConfig.apiBaseURL(override: backendURL) else {
            result = local
            resultIsFromAI = false
            return
        }
        let query = RecipeQuery(
            pantry: Array(Self.items(from: pantry).prefix(50)),
            mealType: selectedMealType?.rawValue,
            caloriesLeft: caloriesLeft,
            proteinLeft: proteinLeft,
            diet: (diary.profile?.diet ?? .balanced).rawValue,
            avoid: Array(Self.items(from: avoid).prefix(20))
        )
        do {
            result = try await FoodLensAPI.shared.recipes(query, baseURL: baseURL).assistantResult
            resultIsFromAI = true
        } catch {
            result = local
            resultIsFromAI = false
            notice = "\(error.localizedDescription) Показано рецепти з вбудованого каталогу."
        }
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
                    TextField("Не використовувати: горіхи, молоко…", text: $avoid)
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    Picker("Прийом їжі", selection: $mealFilter) {
                        Text("Увесь день").tag("")
                        ForEach(MealEntry.MealType.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            if loading { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                            Text(loading ? "Підбираємо рецепти…" : "Запропонувати рецепти")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pantryIsEmpty || loading)
                }
                .cardStyle()

                if let notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
                if let result { resultView(result) }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Асистент")
        .keyboardDismissal()
        .sheet(item: $selectedRecipe) { recipe in
            NavigationStack { AssistantRecipeDetailView(recipe: recipe) }
        }
    }

    @ViewBuilder
    private func resultView(_ result: AssistantResult) -> some View {
        Text(result.message).font(.callout).padding(14)
            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        HStack(alignment: .firstTextBaseline) {
            Text("Що приготувати").font(.title2.bold())
            Spacer()
            Label(resultIsFromAI ? "AI" : "Каталог", systemImage: resultIsFromAI ? "sparkles" : "book.closed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(resultIsFromAI ? Theme.accent : .secondary)
        }
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
                    HStack(spacing: Spacing.m) {
                        Label("\(recipe.protein) г білка", systemImage: "bolt.heart.fill")
                        if let minutes = recipe.minutes { Label("\(minutes) хв", systemImage: "clock") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
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
