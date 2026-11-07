import SwiftUI
import UIKit
import PhotosUI
import Charts

enum Theme {
    static let accent = Color(red: 0.10, green: 0.72, blue: 0.42)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let calorieGradient = LinearGradient(
        colors: [Color(red: 0.08, green: 0.68, blue: 0.39), Color(red: 0.22, green: 0.82, blue: 0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct ContentView: View {
    @State private var showManualEntry = false
    @State private var showSettings = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
        Group {
            switch selectedTab {
            case 0:
            NavigationStack { DashboardView(showManualEntry: $showManualEntry, showSettings: $showSettings) }
            case 1:
            NavigationStack { ScanView() }
            case 2:
            NavigationStack { ProgressViewScreen() }
            case 3:
            NavigationStack { FoodAssistantView() }
            default:
            NavigationStack { DiaryView() }
            }
        }
        HStack(spacing: 0) {
            BottomTab(title: "Сьогодні", icon: "chart.pie.fill", tag: 0, selected: $selectedTab)
            BottomTab(title: "Сканувати", icon: "camera.fill", tag: 1, selected: $selectedTab)
            BottomTab(title: "Прогрес", icon: "chart.xyaxis.line", tag: 2, selected: $selectedTab)
            BottomTab(title: "Асистент", icon: "sparkles", tag: 3, selected: $selectedTab)
            BottomTab(title: "Щоденник", icon: "list.bullet", tag: 4, selected: $selectedTab)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
        }
        .sheet(isPresented: $showManualEntry) { NavigationStack { ManualEntryView() } }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
    }
}

private struct BottomTab: View {
    let title: String
    let icon: String
    let tag: Int
    @Binding var selected: Int

    var body: some View {
        Button { selected = tag } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected == tag ? Color.green : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == tag ? .isSelected : [])
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Binding var showManualEntry: Bool
    @Binding var showSettings: Bool
    @StateObject private var health = HealthService()
    @State private var showNutritionPlan = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                calorieCard
                Button { showNutritionPlan = true } label: {
                    HStack {
                        Label("Розрахувати норму та меню", systemImage: "fork.knife.circle.fill").font(.headline)
                        Spacer(); Image(systemName: "chevron.right")
                    }.cardStyle()
                }.buttonStyle(.plain)
                macroGrid
                waterCard
                activityCard
                todayMeals
            }
            .padding()
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .task { await health.requestAndLoad() }
        .navigationDestination(isPresented: $showNutritionPlan) { NutritionPlanView() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Сьогодні").font(.system(size: 30, weight: .bold, design: .rounded))
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showManualEntry = true } label: {
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 50, height: 50)
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                }
            }.buttonStyle(.plain).accessibilityLabel("Додати страву вручну")
        }
    }

    private var calorieCard: some View {
        VStack(spacing: 14) {
            HStack { Label("Денна енергія", systemImage: "flame.fill"); Spacer(); Text("− \(max(0, Int(diary.goals.calories) - diary.caloriesToday)) ккал") }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
            HStack(alignment: .firstTextBaseline) {
                Text("\(diary.caloriesToday)").font(.system(size: 46, weight: .bold, design: .rounded))
                Text("/ \(Int(diary.goals.calories)) ккал").foregroundStyle(.white.opacity(0.78))
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .padding(20).background(Theme.calorieGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.22), radius: 18, y: 9)
    }

    private var macroGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MacroTile(title: "Білки", icon: "fish.fill", value: diary.proteinToday, goal: diary.goals.protein, color: .blue)
                MacroTile(title: "Вуглеводи", icon: "bolt.fill", value: diary.carbsToday, goal: diary.goals.carbs, color: .orange)
            }
            GridRow {
                MacroTile(title: "Жири", icon: "drop.fill", value: diary.fatToday, goal: diary.goals.fat, color: .purple)
                MacroTile(title: "Клітковина", icon: "leaf.fill", value: diary.fiberToday, goal: diary.goals.fiber, color: .green)
            }
        }
    }

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Вода", systemImage: "drop.fill").foregroundStyle(.blue)
                Spacer()
                Text("\(Int(diary.currentWater)) / \(Int(diary.goals.waterML)) мл").bold()
            }
            ProgressView(value: min(diary.currentWater / diary.goals.waterML, 1)).tint(.blue)
            HStack {
                ForEach([200.0, 300.0, 500.0], id: \.self) { amount in
                    Button("+\(Int(amount))") { diary.addWater(amount) }.buttonStyle(.bordered)
                }
            }
        }
        .cardStyle()
    }

    private var activityCard: some View {
        HStack {
            Label("\(health.steps) кроків", systemImage: "figure.walk").foregroundStyle(.green)
            Spacer()
            Label("\(health.activeCalories) ккал", systemImage: "bolt.heart.fill").foregroundStyle(.orange)
        }.font(.headline).cardStyle()
    }

    private var todayMeals: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Сьогодні").font(.headline); Spacer(); Text("\(diary.todayEntries.count) записів").foregroundStyle(.secondary) }
            if diary.todayEntries.isEmpty {
                Text("Сфотографуйте або додайте першу страву").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical)
            } else {
                ForEach(diary.todayEntries.prefix(5)) { entry in MealRow(entry: entry) }
            }
        }
        .cardStyle()
    }
}

private struct MacroTile: View {
    let title: String; let icon: String; let value: Double; let goal: Double; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).foregroundStyle(color); Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            Text("\(Int(value)) / \(Int(goal)) г").font(.headline)
            ProgressView(value: min(value / goal, 1)).tint(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(color.opacity(0.10)) }
    }
}

private struct NutritionPlanView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var profile = NutritionProfile()
    @State private var planAdded = false
    @State private var goalsApplied = false

    private var plan: [PlannedMeal] { MealPlanBuilder.make(profile: profile) }
    private var bmiDescription: String {
        switch profile.bmi {
        case ..<18.5: "нижче рекомендованого діапазону"
        case 18.5..<25: "у рекомендованому діапазоні"
        case 25..<30: "вище рекомендованого діапазону"
        default: "значно вище рекомендованого діапазону"
        }
    }

    var body: some View {
        Form {
            Section("Ваші дані") {
                Picker("Стать", selection: $profile.sex) { ForEach(NutritionProfile.Sex.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("Вік: \(profile.age)", value: $profile.age, in: 18...90)
                LabeledContent("Зріст") {
                    TextField("см", value: $profile.heightCM, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("см")
                }
                LabeledContent("Вага") {
                    TextField("кг", value: $profile.weightKG, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("кг")
                }
                Picker("Активність", selection: $profile.activity) { ForEach(NutritionProfile.Activity.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Мета", selection: $profile.goal) { ForEach(NutritionProfile.Goal.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Тип раціону", selection: $profile.diet) { ForEach(NutritionProfile.Diet.allCases) { Text($0.rawValue).tag($0) } }
            }

            Section("Розрахована норма") {
                LabeledContent("Базовий обмін", value: "\(Int(profile.bmr)) ккал")
                LabeledContent("Підтримка ваги", value: "\(Int(profile.maintenanceCalories)) ккал")
                LabeledContent("Ціль на день") { Text("\(Int(profile.targetCalories)) ккал").bold().foregroundStyle(.green) }
                LabeledContent("Білки", value: "\(Int(profile.calculatedGoals.protein)) г")
                LabeledContent("Жири", value: "\(Int(profile.calculatedGoals.fat)) г")
                LabeledContent("Вуглеводи", value: "\(Int(profile.calculatedGoals.carbs)) г")
                LabeledContent("ІМТ", value: String(format: "%.1f — %@", profile.bmi, bmiDescription))
                Button {
                    diary.goals = profile.calculatedGoals
                    goalsApplied = true
                } label: {
                    Text(goalsApplied ? "Цілі застосовано" : "Застосувати як мої денні цілі")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(goalsApplied)
            }

            Section("Приклад меню на день") {
                ForEach(plan) { meal in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(meal.title).font(.headline); Spacer(); Text("\(meal.calories) ккал").bold() }
                        Text(meal.foods).foregroundStyle(.secondary)
                        Text("Б \(meal.protein) г · Ж \(meal.fat) г · В \(meal.carbs) г").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                Button("Додати це меню у щоденник") {
                    let types: [MealEntry.MealType] = [.breakfast, .lunch, .dinner, .snack]
                    for (index, meal) in plan.enumerated() {
                        diary.add(MealEntry(
                            name: "\(meal.title): \(meal.foods)", grams: 100,
                            caloriesPer100g: Double(meal.calories), protein: Double(meal.protein),
                            carbs: Double(meal.carbs), fat: Double(meal.fat),
                            fiber: profile.calculatedGoals.fiber * [0.25, 0.35, 0.30, 0.10][index],
                            mealType: types[index]
                        ))
                    }
                    planAdded = true
                }.disabled(planAdded)
            }

            Section {
                Text("Розрахунок є орієнтовним і призначений для дорослих. Він не враховує захворювання, ліки, вагітність або грудне вигодовування. За високого ІМТ, діабету, підвищеного тиску чи інших станів узгодьте дефіцит і раціон із лікарем або дієтологом.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("План харчування")
        .alert("Меню додано", isPresented: $planAdded) { Button("OK") {} } message: { Text("Чотири прийоми їжі збережено у сьогоднішньому щоденнику.") }
        .alert("Денні цілі оновлено", isPresented: $goalsApplied) { Button("OK") {} } message: { Text("Калорії, БЖВ, клітковина та вода збережені на головному екрані.") }
    }
}

private struct FoodAssistantView: View {
    @EnvironmentObject private var diary: DiaryStore
    @AppStorage("assistantPantry") private var pantry = ""
    @AppStorage("assistantMealFilter") private var mealFilter = "Увесь день"
    @AppStorage("assistantHasGenerated") private var hasGenerated = false
    @State private var selectedRecipe: AssistantRecipe?
    private let filters = ["Увесь день", "Сніданок", "Обід", "Вечеря", "Перекус"]

    private var caloriesLeft: Int { max(0, Int(diary.goals.calories) - diary.caloriesToday) }
    private var proteinLeft: Int { max(0, Int(diary.goals.protein - diary.proteinToday)) }
    private var result: AssistantResult? {
        guard hasGenerated, !pantry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return PantryAssistant.suggest(pantryText: pantry, mealFilter: mealFilter, caloriesLeft: caloriesLeft, proteinLeft: proteinLeft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Асистент харчування").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Рецепти з того, що вже є вдома").foregroundStyle(.secondary)
                }
                HStack {
                    Label("Залишок", systemImage: "flame.fill")
                    Spacer(); Text("\(caloriesLeft) ккал · \(proteinLeft) г білка").bold()
                }.cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Що є у холодильнику?", systemImage: "refrigerator.fill").font(.headline)
                    Text("Введіть через кому: яйця, курка, гречка, помідори…").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $pantry).frame(minHeight: 105).padding(8)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    Picker("Прийом їжі", selection: $mealFilter) {
                        ForEach(filters, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                    Button {
                        hasGenerated = true
                    } label: {
                        Label("Запропонувати рецепти", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(pantry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.cardStyle()

                if let result {
                    Text(result.message).font(.callout).padding(14)
                        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    Text("Що приготувати").font(.title2.bold())
                    ForEach(result.recipes) { recipe in
                        Button { selectedRecipe = recipe } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(recipe.meal).font(.caption.bold()).foregroundStyle(Theme.accent); Spacer(); Text("\(recipe.calories) ккал").bold() }
                                HStack { Text(recipe.title).font(.headline); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                                Text(recipe.ingredients.map { "\($0.name) \($0.grams) г" }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Label("\(recipe.protein) г білка", systemImage: "bolt.heart.fill").font(.caption).foregroundStyle(.secondary)
                            }.cardStyle()
                        }.buttonStyle(.plain)
                    }
                    Text("Що докупити").font(.title2.bold())
                    if result.shoppingList.isEmpty {
                        Label("Усе необхідне вже є", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).cardStyle()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(result.shoppingList, id: \.self) { item in Label(item.capitalized, systemImage: "cart.badge.plus") }
                        }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
                    }
                }
            }.padding()
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRecipe) { recipe in
            NavigationStack { AssistantRecipeDetailView(recipe: recipe) }
        }
    }
}

private struct AssistantRecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: AssistantRecipe
    private var totalGrams: Int { recipe.ingredients.reduce(0) { $0 + $1.grams } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(recipe.meal.uppercased()).font(.caption.bold()).foregroundStyle(Theme.accent)
                    Text(recipe.title).font(.system(size: 28, weight: .bold, design: .rounded))
                    HStack {
                        Label("\(recipe.calories) ккал", systemImage: "flame.fill")
                        Spacer(); Label("\(recipe.protein) г білка", systemImage: "bolt.heart.fill")
                    }.font(.subheadline.bold())
                    Text("Орієнтовна вага порції: \(totalGrams) г").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
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
                    }.padding(.vertical, 3)
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

private struct ScanView: View {
    @StateObject private var camera = CameraService()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Group {
            if camera.permissionDenied || camera.cameraUnavailable {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        camera.permissionDenied ? "Немає доступу до камери" : "Камера недоступна",
                        systemImage: "camera.fill",
                        description: Text(camera.permissionDenied ? "Дозвольте доступ у Налаштуваннях iPhone → FoodLens → Камера." : "Для тестування виберіть фото страви.")
                    )
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Вибрати фото", systemImage: "photo.on.rectangle") }
                        .buttonStyle(.borderedProminent)
                }
            } else if let image = camera.photo {
                MealResultView(image: image) { camera.photo = nil; camera.start() }
            } else {
                ZStack(alignment: .bottom) {
                    CameraPreview(session: camera.session).ignoresSafeArea(edges: .bottom)
                    VStack(spacing: 12) {
                        Text("Зніміть всю тарілку зверху").padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                        Button { camera.capture() } label: {
                            Circle().fill(.white).frame(width: 72, height: 72)
                                .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 3).padding(5))
                        }.accessibilityLabel("Зробити фото")
                    }.padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Сканування").navigationBarTitleDisplayMode(.inline)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                camera.photo = image
            }
        }
    }
}

private struct MealResultView: View {
    @EnvironmentObject private var diary: DiaryStore
    let image: UIImage; let retake: () -> Void
    @State private var name = ""
    @State private var details = ""
    @State private var grams = 0.0
    @State private var caloriesPer100g = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var fiber = 0.0
    @State private var mealType = MealEntry.MealType.lunch
    @State private var saved = false
    @State private var analyzing = false
    @State private var analysisError: String?
    @State private var analysisSource = ""
    @State private var confidence = 0.0
    @AppStorage("backendURL") private var backendURL = ""

    private var calories: Int { Int((grams * caloriesPer100g / 100).rounded()) }

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
                        TextField("Наприклад: рис із куркою", text: $name)
                            .font(.headline)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Уточніть склад").font(.caption).foregroundStyle(.secondary)
                        TextField("Наприклад: рис, курка, овочі, кукурудза", text: $details, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    Picker("Прийом їжі", selection: $mealType) { ForEach(MealEntry.MealType.allCases) { Text($0.rawValue).tag($0) } }
                    HStack {
                        Text("Точна вага")
                        Spacer()
                        TextField("г", value: $grams, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("г").foregroundStyle(.secondary)
                    }
                    NutritionSlider(title: "Порція", value: $grams, range: 50...1000, unit: "г")
                    NutritionSlider(title: "Ккал / 100 г", value: $caloriesPer100g, range: 0...500, unit: "")
                }
            }
            Section("КБЖВ усієї порції") {
                NutritionSlider(title: "Білки", value: $protein, range: 0...150, unit: "г")
                NutritionSlider(title: "Вуглеводи", value: $carbs, range: 0...250, unit: "г")
                NutritionSlider(title: "Жири", value: $fat, range: 0...150, unit: "г")
                NutritionSlider(title: "Клітковина", value: $fiber, range: 0...60, unit: "г")
                LabeledContent("Разом") { Text("\(calories) ккал").bold() }
            }
            Section {
                Button("Додати у щоденник") {
                    let diaryName = details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : "\(name) — \(details)"
                    diary.add(MealEntry(name: diaryName, grams: grams, caloriesPer100g: caloriesPer100g, protein: protein, carbs: carbs, fat: fat, fiber: fiber, mealType: mealType))
                    saved = true
                }.disabled(saved || analyzing || name.isEmpty || caloriesPer100g <= 0)
                Button("Перезняти", role: .cancel, action: retake)
            } footer: { Text("Оцінку AI завжди можна скоригувати — порція з одного фото є приблизною.") }
        }
        .task { await analyzePhoto() }
        .alert("Додано у щоденник", isPresented: $saved) { Button("OK") {} }
    }

    private func analyzePhoto() async {
        analyzing = true
        defer { analyzing = false }
        analysisError = nil
        if !backendURL.isEmpty {
            do {
                apply(try await FoodAIService.analyze(image, backendURL: backendURL), source: "AI-сервер")
                return
            } catch {
                analysisError = "AI-сервер недоступний, використано аналіз на iPhone."
            }
        }
        do {
            apply(try await OnDeviceFoodRecognitionService.analyze(image), source: "На пристрої")
        } catch {
            analysisError = error.localizedDescription
            name = ""; grams = 0; caloriesPer100g = 0
        }
    }

    private func apply(_ result: FoodAnalysis, source: String) {
        name = result.dish; grams = result.estimatedGrams; caloriesPer100g = result.caloriesPer100g
        details = result.ingredients.map(\.name).filter { $0.caseInsensitiveCompare(result.dish) != .orderedSame }.joined(separator: ", ")
        protein = result.protein; carbs = result.carbs; fat = result.fat; fiber = result.fiber
        confidence = result.confidence; analysisSource = source
    }
}

private struct NutritionSlider: View {
    let title: String; @Binding var value: Double; let range: ClosedRange<Double>; let unit: String
    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: "\(Int(value)) \(unit)")
            Slider(value: $value, in: range, step: 1)
        }
    }
}

private struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var diary: DiaryStore
    @State private var name = ""
    @State private var calories = 300.0
    @State private var grams = 250.0
    @State private var protein = 15.0
    @State private var carbs = 35.0
    @State private var fat = 10.0
    @State private var mealType = MealEntry.MealType.snack
    @StateObject private var voice = VoiceEntryService()

    var body: some View {
        Form {
            Section("Страва") {
                TextField("Наприклад: сирники", text: $name)
                Button {
                    Task { await voice.toggle() }
                } label: {
                    Label(voice.isRecording ? "Зупинити диктування" : "Описати голосом", systemImage: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                Picker("Прийом їжі", selection: $mealType) { ForEach(MealEntry.MealType.allCases) { Text($0.rawValue).tag($0) } }
                NutritionSlider(title: "Вага", value: $grams, range: 10...1500, unit: "г")
                NutritionSlider(title: "Калорії", value: $calories, range: 10...2000, unit: "ккал")
            }
            Section("Макронутрієнти") {
                NutritionSlider(title: "Білки", value: $protein, range: 0...200, unit: "г")
                NutritionSlider(title: "Вуглеводи", value: $carbs, range: 0...300, unit: "г")
                NutritionSlider(title: "Жири", value: $fat, range: 0...200, unit: "г")
            }
        }
        .navigationTitle("Додати вручну")
        .onChange(of: voice.transcript) { _, value in if !value.isEmpty { name = value } }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Зберегти") {
                    diary.add(MealEntry(name: name, grams: grams, caloriesPer100g: calories / grams * 100, protein: protein, carbs: carbs, fat: fat, mealType: mealType)); dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct ProgressViewScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var weightText = ""
    @State private var editingWeight: WeightRecord?
    @State private var weightError: String?
    @State private var reportURL: URL?
    private var days: [Date] { (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.reversed() }

    var body: some View {
        List {
            Section("Калорії за 7 днів") {
                Chart(days, id: \.self) { day in
                    BarMark(x: .value("День", day, unit: .day), y: .value("Ккал", diary.calories(on: day))).foregroundStyle(.orange.gradient)
                }.frame(height: 190)
            }
            Section("Вага") {
                if let latest = diary.weights.first {
                    LabeledContent("Поточна вага", value: "\(latest.kilograms.formatted(.number.precision(.fractionLength(0...1)))) кг")
                } else {
                    Text("Записів ваги ще немає").foregroundStyle(.secondary)
                }
                if !diary.weights.isEmpty {
                    Chart(diary.weights.reversed()) { record in
                        LineMark(x: .value("Дата", record.date), y: .value("кг", record.kilograms)).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Дата", record.date), y: .value("кг", record.kilograms))
                    }.frame(height: 190)
                }
                HStack {
                    TextField("Введіть вагу", text: $weightText)
                        .keyboardType(.decimalPad)
                    Text("кг").foregroundStyle(.secondary)
                    Button("Записати", action: addWeight)
                        .disabled(parsedWeight == nil)
                }
                if let weightError { Text(weightError).font(.caption).foregroundStyle(.red) }
                ForEach(diary.weights.prefix(10)) { record in
                    Button { editingWeight = record } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                Text("\(record.kilograms.formatted(.number.precision(.fractionLength(0...1)))) кг").foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(Theme.accent)
                        }
                    }
                    .swipeActions {
                        Button("Видалити", role: .destructive) { diary.deleteWeight(id: record.id) }
                    }
                }
            }
            Section("Звички сьогодні") {
                LabeledContent("Вода", value: "\(Int(diary.currentWater)) мл")
                LabeledContent("Записано страв", value: "\(diary.todayEntries.count)")
                LabeledContent("Клітковина", value: "\(Int(diary.fiberToday)) г")
            }
        }
        .navigationTitle("Мій прогрес")
        .sheet(item: $editingWeight) { record in
            WeightEditView(record: record)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let reportURL {
                    ShareLink(item: reportURL) { Image(systemName: "square.and.arrow.up") }
                } else {
                    Button { reportURL = FoodReport.make(entries: diary.entries, weights: diary.weights) } label: { Image(systemName: "doc.badge.plus") }
                }
            }
        }
    }

    private var parsedWeight: Double? {
        let value = Double(weightText.replacingOccurrences(of: ",", with: "."))
        guard let value, 30...350 ~= value else { return nil }
        return value
    }

    private func addWeight() {
        guard let value = parsedWeight else {
            weightError = "Введіть вагу від 30 до 350 кг"
            return
        }
        diary.addWeight(value)
        weightText = ""
        weightError = nil
    }
}

private struct WeightEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var diary: DiaryStore
    let record: WeightRecord
    @State private var weightText: String

    init(record: WeightRecord) {
        self.record = record
        _weightText = State(initialValue: record.kilograms.formatted(.number.precision(.fractionLength(0...1))))
    }

    private var value: Double? {
        let number = Double(weightText.replacingOccurrences(of: ",", with: "."))
        guard let number, 30...350 ~= number else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Вага") {
                    HStack {
                        TextField("Вага", text: $weightText).keyboardType(.decimalPad)
                        Text("кг").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Змінити запис")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") {
                        guard let value else { return }
                        diary.updateWeight(id: record.id, kilograms: value)
                        dismiss()
                    }.disabled(value == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct DiaryView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var query = ""

    private var filtered: [MealEntry] {
        query.isEmpty ? diary.entries : diary.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView("Нічого не знайдено", systemImage: "fork.knife", description: Text("Додайте страву зі сканера або вручну."))
            } else {
                ForEach(filtered) { entry in
                    NavigationLink {
                        EditMealEntryView(entry: entry)
                    } label: {
                        MealRow(entry: entry)
                    }.swipeActions(edge: .leading) {
                        Button { diary.toggleFavorite(entry.id) } label: { Label("Обране", systemImage: entry.isFavorite ? "star.slash" : "star") }.tint(.yellow)
                    }
                }.onDelete { offsets in
                    for index in offsets { diary.delete(id: filtered[index].id) }
                }
            }
        }.searchable(text: $query, prompt: "Пошук у щоденнику").navigationTitle("Щоденник")
    }
}

private struct EditMealEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var diary: DiaryStore
    let original: MealEntry
    @State private var name: String
    @State private var grams: Double
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var fiber: Double
    @State private var mealType: MealEntry.MealType

    init(entry: MealEntry) {
        original = entry
        _name = State(initialValue: entry.name)
        _grams = State(initialValue: entry.grams)
        _calories = State(initialValue: Double(entry.calories))
        _protein = State(initialValue: entry.protein)
        _carbs = State(initialValue: entry.carbs)
        _fat = State(initialValue: entry.fat)
        _fiber = State(initialValue: entry.fiber)
        _mealType = State(initialValue: entry.mealType)
    }

    var body: some View {
        Form {
            Section("Страва") {
                TextField("Назва страви", text: $name, axis: .vertical)
                    .lineLimit(1...3)
                Picker("Прийом їжі", selection: $mealType) {
                    ForEach(MealEntry.MealType.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Порція та калорії") {
                numberField("Вага", value: $grams, unit: "г")
                numberField("Калорії всієї порції", value: $calories, unit: "ккал")
                LabeledContent("На 100 г", value: grams > 0 ? "\(Int((calories / grams * 100).rounded())) ккал" : "—")
            }
            Section("КБЖВ усієї порції") {
                numberField("Білки", value: $protein, unit: "г")
                numberField("Вуглеводи", value: $carbs, unit: "г")
                numberField("Жири", value: $fat, unit: "г")
                numberField("Клітковина", value: $fiber, unit: "г")
            }
            Section {
                Button("Зберегти зміни") { save() }
                    .frame(maxWidth: .infinity)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || grams <= 0 || calories < 0)
            } footer: {
                Text("Зміни одразу оновлять денні калорії та показники БЖВ.")
            }
        }
        .navigationTitle("Редагування")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } } }
    }

    private func numberField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        var updated = original
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.grams = grams
        updated.caloriesPer100g = calories / grams * 100
        updated.protein = protein
        updated.carbs = carbs
        updated.fat = fat
        updated.fiber = fiber
        updated.mealType = mealType
        diary.update(updated)
        dismiss()
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var diary: DiaryStore
    @AppStorage("backendURL") private var backendURL = ""

    var body: some View {
        Form {
            Section("AI-сервер") {
                TextField("http://192.168.1.20:8000", text: $backendURL)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                Text("API-ключ зберігається на сервері, а не в застосунку.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Денні цілі") {
                Stepper("Калорії: \(Int(diary.goals.calories))", value: $diary.goals.calories, in: 1000...5000, step: 50)
                Stepper("Білки: \(Int(diary.goals.protein)) г", value: $diary.goals.protein, in: 20...300, step: 5)
                Stepper("Вуглеводи: \(Int(diary.goals.carbs)) г", value: $diary.goals.carbs, in: 20...500, step: 5)
                Stepper("Жири: \(Int(diary.goals.fat)) г", value: $diary.goals.fat, in: 20...250, step: 5)
                Stepper("Вода: \(Int(diary.goals.waterML)) мл", value: $diary.goals.waterML, in: 500...5000, step: 100)
            }
        }.navigationTitle("Налаштування").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}

private struct MealRow: View {
    let entry: MealEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(entry.name).font(.headline); if entry.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }; Spacer(); Text("\(entry.calories) ккал").bold() }
            Text("\(entry.mealType.rawValue) · \(Int(entry.grams)) г · Б \(Int(entry.protein))  Ж \(Int(entry.fat))  В \(Int(entry.carbs))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.primary.opacity(0.045)) }
    }
}

private enum FoodReport {
    static func make(entries: [MealEntry], weights: [WeightRecord]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FoodLens-звіт.pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                var y: CGFloat = 42
                func draw(_ text: String, size: CGFloat = 12, bold: Bool = false) {
                    let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                    text.draw(in: CGRect(x: 42, y: y, width: 511, height: 28), withAttributes: [.font: font, .foregroundColor: UIColor.label])
                    y += size + 10
                }
                draw("FoodLens — звіт про харчування", size: 22, bold: true)
                draw("Створено: \(Date.now.formatted(date: .long, time: .shortened))")
                draw("Записів: \(entries.count) · Всього: \(entries.reduce(0) { $0 + $1.calories }) ккал", bold: true)
                y += 10
                for entry in entries.prefix(24) {
                    if y > 790 { context.beginPage(); y = 42 }
                    draw("\(entry.date.formatted(date: .abbreviated, time: .shortened)) — \(entry.name): \(entry.calories) ккал")
                }
                if let latest = weights.first { y += 10; draw("Остання вага: \(latest.kilograms.formatted()) кг", bold: true) }
            }
            return url
        } catch { return nil }
    }
}
