import SwiftUI

struct MealResultView: View {
    @Environment(DiaryStore.self) private var diary
    let image: UIImage
    let retake: () -> Void

    @AppStorage("backendURL") private var backendURL = ""
    @State private var name = ""
    @State private var details = ""
    @State private var grams = 0.0
    @State private var caloriesPer100g = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var fiber = 0.0
    @State private var ingredients: [FoodComponent] = []
    @State private var analysisGrams = 0.0
    @State private var portion = PortionTracker(grams: 0)
    @State private var mealType = MealEntry.MealType.suggested(for: .now)
    @State private var analyzing = false
    @State private var analysisError: String?
    @State private var analysisSource = ""
    @State private var confidence = 0.0
    @State private var saved = false
    @State private var showSavedAlert = false

    private var calories: Double { grams * caloriesPer100g / 100 }

    var body: some View {
        Form {
            Image(uiImage: image).resizable().scaledToFill().frame(height: 210).clipped().listRowInsets(EdgeInsets())
            Section("Результат аналізу") {
                if analyzing { HStack { ProgressView(); Text("Аналізуємо фото…") } }
                if let analysisError { Text(analysisError).font(.caption).foregroundStyle(.orange) }
                if !analyzing {
                    if !analysisSource.isEmpty {
                        LabeledContent("Режим", value: analysisSource)
                        LabeledContent("Впевненість", value: "\(Int(confidence * 100))%")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Розпізнана страва").font(.caption).foregroundStyle(.secondary)
                        TextField("Наприклад: рис із куркою", text: $name).font(.headline)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Уточніть склад").font(.caption).foregroundStyle(.secondary)
                        TextField("Наприклад: рис, курка, овочі, кукурудза", text: $details, axis: .vertical).lineLimit(2...4)
                    }
                    Picker("Прийом їжі", selection: $mealType) { ForEach(MealEntry.MealType.allCases) { Text($0.title).tag($0) } }
                    NumberFieldRow(title: "Точна вага", value: $grams, unit: "г")
                    NutritionSlider(title: "Порція", value: $grams, range: 0...1000, unit: "г")
                    NutritionSlider(title: "Ккал / 100 г", value: $caloriesPer100g, range: 0...900, unit: "")
                }
            }
            Section {
                NutritionSlider(title: "Білки", value: $protein, range: 0...150, unit: "г")
                NutritionSlider(title: "Вуглеводи", value: $carbs, range: 0...250, unit: "г")
                NutritionSlider(title: "Жири", value: $fat, range: 0...150, unit: "г")
                NutritionSlider(title: "Клітковина", value: $fiber, range: 0...60, unit: "г")
                LabeledContent("Разом") { Text("\(Int(calories.rounded())) ккал").bold() }
            } header: {
                Text("КБЖВ усієї порції")
            } footer: {
                Text("Зміна ваги порції пропорційно перераховує БЖВ і клітковину.")
            }
            Section {
                Button(saved ? "Додано" : "Додати у щоденник", action: save)
                    .disabled(saved || analyzing || name.trimmingCharacters(in: .whitespaces).isEmpty || grams <= 0 || caloriesPer100g <= 0)
                Button("Перезняти", role: .cancel, action: retake)
            } footer: {
                Text("Оцінку AI завжди можна скоригувати — порція з одного фото є приблизною.")
            }
        }
        .task { await analyzePhoto() }
        .onChange(of: grams) { _, newValue in
            // Keep macros consistent with the portion size.
            guard let factor = portion.factor(for: newValue) else { return }
            protein *= factor; carbs *= factor; fat *= factor; fiber *= factor
        }
        .alert("Додано у щоденник", isPresented: $showSavedAlert) { Button("OK") {} }
    }

    private func save() {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let diaryName = trimmedDetails.isEmpty ? name : "\(name) — \(trimmedDetails)"
        let factor = Portion.scaleFactor(from: analysisGrams, to: grams) ?? 1
        diary.add(MealEntry(
            name: diaryName, grams: grams, calories: calories,
            protein: protein, carbs: carbs, fat: fat, fiber: fiber,
            mealType: mealType, ingredients: ingredients.map { $0.scaled(by: factor) }
        ))
        saved = true
        showSavedAlert = true
    }

    private func analyzePhoto() async {
        analyzing = true
        defer { analyzing = false }
        analysisError = nil
        if let baseURL = AppConfig.apiBaseURL(override: backendURL) {
            do {
                apply(try await FoodLensAPI.shared.analyze(image, baseURL: baseURL), source: "AI-сервер")
                return
            } catch {
                analysisError = "\(error.localizedDescription) Використано аналіз на iPhone."
            }
        }
        do {
            apply(try await OnDeviceFoodRecognitionService.analyze(image), source: "На пристрої")
        } catch {
            analysisError = error.localizedDescription
        }
    }

    private func apply(_ result: FoodAnalysis, source: String) {
        // Resetting the tracker first makes the grams change below a no-op for scaling.
        portion.reset(to: result.estimatedGrams)
        name = result.dish
        caloriesPer100g = result.caloriesPer100g
        details = result.ingredients.map(\.name).filter { $0.caseInsensitiveCompare(result.dish) != .orderedSame }.joined(separator: ", ")
        protein = result.protein; carbs = result.carbs; fat = result.fat; fiber = result.fiber
        ingredients = result.ingredients
        analysisGrams = result.estimatedGrams
        grams = result.estimatedGrams
        confidence = result.confidence
        analysisSource = source
    }
}
