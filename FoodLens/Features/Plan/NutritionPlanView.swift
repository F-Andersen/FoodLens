import SwiftUI

struct NutritionPlanView: View {
    @Environment(DiaryStore.self) private var diary
    @State private var profile: NutritionProfile
    @State private var goalsApplied = false
    @State private var planAdded = false
    @State private var showGoalsAlert = false
    @State private var showPlanAlert = false

    init(initialProfile: NutritionProfile) {
        _profile = State(initialValue: initialProfile)
    }

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
                Picker("Стать", selection: $profile.sex) { ForEach(NutritionProfile.Sex.allCases) { Text($0.title).tag($0) } }
                Stepper("Вік: \(profile.age)", value: $profile.age, in: 18...90)
                LabeledContent("Зріст") {
                    TextField("см", value: $profile.heightCM, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("см")
                }
                LabeledContent("Вага") {
                    TextField("кг", value: $profile.weightKG, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("кг")
                }
                Picker("Активність", selection: $profile.activity) { ForEach(NutritionProfile.Activity.allCases) { Text($0.title).tag($0) } }
                Picker("Мета", selection: $profile.goal) { ForEach(NutritionProfile.Goal.allCases) { Text($0.title).tag($0) } }
                Picker("Тип раціону", selection: $profile.diet) { ForEach(NutritionProfile.Diet.allCases) { Text($0.title).tag($0) } }
            }

            if profile.isValid {
                Section("Розрахована норма") {
                    LabeledContent("Базовий обмін", value: "\(Int(profile.bmr)) ккал")
                    LabeledContent("Підтримка ваги", value: "\(Int(profile.maintenanceCalories)) ккал")
                    LabeledContent("Ціль на день") { Text("\(Int(profile.targetCalories)) ккал").bold().foregroundStyle(Theme.accent) }
                    LabeledContent("Білки", value: "\(Int(profile.calculatedGoals.protein)) г")
                    LabeledContent("Жири", value: "\(Int(profile.calculatedGoals.fat)) г")
                    LabeledContent("Вуглеводи", value: "\(Int(profile.calculatedGoals.carbs)) г")
                    LabeledContent("ІМТ", value: String(format: "%.1f — %@", profile.bmi, bmiDescription))
                    Button {
                        diary.goals = profile.calculatedGoals
                        goalsApplied = true
                        showGoalsAlert = true
                    } label: {
                        Text(goalsApplied ? "Цілі застосовано" : "Застосувати як мої денні цілі").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(goalsApplied)
                }

                Section("Приклад меню на день") {
                    ForEach(plan) { meal in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(meal.mealType.title).font(.headline); Spacer(); Text("\(meal.calories) ккал").bold() }
                            Text(meal.foods).foregroundStyle(.secondary)
                            Text("Б \(meal.protein) г · Ж \(meal.fat) г · В \(meal.carbs) г").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    Button(planAdded ? "Меню додано" : "Додати це меню у щоденник") {
                        diary.add(plan.map { meal in
                            MealEntry(
                                name: meal.foods, grams: 0, calories: Double(meal.calories),
                                protein: Double(meal.protein), carbs: Double(meal.carbs), fat: Double(meal.fat),
                                fiber: meal.fiber, mealType: meal.mealType
                            )
                        })
                        planAdded = true
                        showPlanAlert = true
                    }
                    .disabled(planAdded)
                }
            } else {
                Section {
                    Text("Перевірте дані: зріст 120–230 см, вага 30–350 кг.").foregroundStyle(.orange)
                }
            }

            Section {
                Text("Розрахунок є орієнтовним і призначений для дорослих. Він не враховує захворювання, ліки, вагітність або грудне вигодовування. За високого ІМТ, діабету, підвищеного тиску чи інших станів узгодьте дефіцит і раціон із лікарем або дієтологом.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("План харчування")
        .onChange(of: profile) { _, newValue in
            diary.profile = newValue
            goalsApplied = false
        }
        .alert("Меню додано", isPresented: $showPlanAlert) { Button("OK") {} } message: {
            Text("Чотири прийоми їжі збережено у сьогоднішньому щоденнику.")
        }
        .alert("Денні цілі оновлено", isPresented: $showGoalsAlert) { Button("OK") {} } message: {
            Text("Калорії, БЖВ, клітковина та вода збережені на головному екрані.")
        }
    }
}
