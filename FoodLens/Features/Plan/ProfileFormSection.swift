import SwiftUI

/// The body-data form shared by onboarding and the nutrition plan screen.
struct ProfileFormSection: View {
    @Binding var profile: NutritionProfile

    var body: some View {
        Section("Ваші дані") {
            Picker("Стать", selection: $profile.sex) {
                ForEach(NutritionProfile.Sex.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper(value: $profile.age, in: 18...90) {
                LabeledContent("Вік", value: "\(profile.age)")
            }
            NumberFieldRow(title: "Зріст", value: $profile.heightCM, unit: "см")
            NumberFieldRow(title: "Вага", value: $profile.weightKG, unit: "кг")
        }
        Section("Спосіб життя") {
            Picker("Активність", selection: $profile.activity) {
                ForEach(NutritionProfile.Activity.allCases) { Text($0.title).tag($0) }
            }
            Picker("Мета", selection: $profile.goal) {
                ForEach(NutritionProfile.Goal.allCases) { Text($0.title).tag($0) }
            }
            Picker("Тип раціону", selection: $profile.diet) {
                ForEach(NutritionProfile.Diet.allCases) { Text($0.title).tag($0) }
            }
        }
        if !profile.isValid {
            Section {
                Label("Перевірте дані: зріст 120–230 см, вага 30–350 кг.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}

/// Compact summary of the calculated daily goals.
struct GoalsSummaryCard: View {
    let goals: NutritionGoals

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(goals.calories.rounded()))").numberFont(.largeTitle, weight: .bold)
                Text("ккал на день").foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.s) {
                ForEach([Macro.protein, .fat, .carbs]) { macro in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(macro.title, systemImage: macro.icon)
                            .font(.caption).foregroundStyle(macro.color)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(Int(macro.goal(in: goals).rounded())) г").numberFont(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m)
                    .background(macro.color.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
            }
            Label("Вода: \(Int(goals.waterML)) мл", systemImage: "drop.fill")
                .font(.subheadline).foregroundStyle(Theme.water)
        }
    }
}
