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
            ProfileFormSection(profile: $profile)

            if profile.isValid {
                Section {
                    GoalsSummaryCard(goals: profile.calculatedGoals).padding(.vertical, Spacing.xs)
                    LabeledContent("Базовий обмін", value: "\(Int(profile.bmr)) ккал")
                    LabeledContent("Підтримка ваги", value: "\(Int(profile.maintenanceCalories)) ккал")
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
                } header: {
                    Text("Розрахована норма")
                }

                Section("Приклад меню на день") {
                    ForEach(plan) { meal in
                        HStack(alignment: .top, spacing: Spacing.m) {
                            MealTypeBadge(type: meal.mealType, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(meal.mealType.title).font(.headline); Spacer(); Text("\(meal.calories) ккал").bold() }
                                Text(meal.foods).font(.subheadline).foregroundStyle(.secondary)
                                Text("Б \(meal.protein) г · Ж \(meal.fat) г · В \(meal.carbs) г").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
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
            }

            Section {
                Text("Розрахунок є орієнтовним і призначений для дорослих. Він не враховує захворювання, ліки, вагітність або грудне вигодовування. За високого ІМТ, діабету, підвищеного тиску чи інших станів узгодьте дефіцит і раціон із лікарем або дієтологом.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Норма та меню")
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
