import SwiftUI

struct DashboardView: View {
    @Environment(DiaryStore.self) private var diary
    @Binding var showManualEntry: Bool
    @Binding var showSettings: Bool
    @StateObject private var health = HealthService()
    @State private var showNutritionPlan = false

    var body: some View {
        let totals = diary.todayTotals
        ScrollView {
            VStack(spacing: 16) {
                header
                calorieCard(totals)
                Button { showNutritionPlan = true } label: {
                    HStack {
                        Label("Розрахувати норму та меню", systemImage: "fork.knife.circle.fill").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .cardStyle()
                }
                .buttonStyle(.plain)
                macroGrid(totals)
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
                    .accessibilityLabel("Налаштування")
            }
        }
        .task { await health.requestAndLoad() }
        .navigationDestination(isPresented: $showNutritionPlan) {
            NutritionPlanView(initialProfile: initialProfile)
        }
    }

    /// The saved profile, with the latest weight from Progress so the two never disagree.
    private var initialProfile: NutritionProfile {
        var profile = diary.profile ?? NutritionProfile()
        if let weight = diary.latestWeight?.kilograms { profile.weightKG = weight }
        return profile
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Сьогодні").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showManualEntry = true } label: {
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 50, height: 50)
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Додати страву вручну")
        }
    }

    private func calorieCard(_ totals: NutritionTotals) -> some View {
        let goal = Int(diary.goals.calories.rounded())
        let remaining = goal - totals.kcal
        return VStack(spacing: 14) {
            HStack {
                Label("Денна енергія", systemImage: "flame.fill")
                Spacer()
                Text(remaining >= 0 ? "Залишилось \(remaining) ккал" : "Понад норму на \(-remaining) ккал")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            HStack(alignment: .firstTextBaseline) {
                Text("\(totals.kcal)").font(.system(size: 46, weight: .bold, design: .rounded))
                Text("/ \(goal) ккал").foregroundStyle(.white.opacity(0.78))
                Spacer()
            }
            .foregroundStyle(.white)
            ProgressView(value: progress(totals.calories, of: diary.goals.calories))
                .tint(.white)
        }
        .padding(20)
        .background(Theme.calorieGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.22), radius: 18, y: 9)
        .accessibilityElement(children: .combine)
    }

    private func macroGrid(_ totals: NutritionTotals) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MacroTile(title: "Білки", icon: "fish.fill", value: totals.protein, goal: diary.goals.protein, color: .blue)
                MacroTile(title: "Вуглеводи", icon: "bolt.fill", value: totals.carbs, goal: diary.goals.carbs, color: .orange)
            }
            GridRow {
                MacroTile(title: "Жири", icon: "drop.fill", value: totals.fat, goal: diary.goals.fat, color: .purple)
                MacroTile(title: "Клітковина", icon: "leaf.fill", value: totals.fiber, goal: diary.goals.fiber, color: .green)
            }
        }
    }

    private var waterCard: some View {
        let water = diary.waterToday
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Вода", systemImage: "drop.fill").foregroundStyle(.blue)
                Spacer()
                Text("\(Int(water)) / \(Int(diary.goals.waterML)) мл").bold()
            }
            ProgressView(value: progress(water, of: diary.goals.waterML)).tint(.blue)
            HStack {
                ForEach([200.0, 300.0, 500.0], id: \.self) { amount in
                    Button("+\(Int(amount))") { diary.addWater(amount) }.buttonStyle(.bordered)
                }
                Spacer()
                if water > 0 {
                    Button { diary.undoLastWater() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .accessibilityLabel("Скасувати останнє додавання води")
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
        }
        .font(.headline)
        .cardStyle()
    }

    private var todayMeals: some View {
        let meals = diary.todayEntries
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Страви за день").font(.headline)
                Spacer()
                Text("\(meals.count) записів").foregroundStyle(.secondary)
            }
            if meals.isEmpty {
                Text("Сфотографуйте або додайте першу страву")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical)
            } else {
                ForEach(meals.prefix(5)) { entry in MealRow(entry: entry) }
            }
        }
        .cardStyle()
    }
}

private struct MacroTile: View {
    let title: String
    let icon: String
    let value: Double
    let goal: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text("\(Int(value)) / \(Int(goal)) г").font(.headline)
            ProgressView(value: progress(value, of: goal)).tint(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(color.opacity(0.10)) }
        .accessibilityElement(children: .combine)
    }
}
