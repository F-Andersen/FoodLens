import SwiftUI

struct DashboardView: View {
    @Environment(DiaryStore.self) private var diary
    @Binding var selectedTab: AppTab
    @Environment(HealthService.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var manualEntry: ManualEntryRequest?
    @State private var showSettings = false
    @State private var showNutritionPlan = false
    @State private var waterTick = 0

    var body: some View {
        let totals = diary.todayTotals
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirstLetter)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.top, -Spacing.s)
                summaryCard(totals)
                EnergyBalanceCard { showNutritionPlan = true }
                if diary.profile == nil { setupPrompt }
                quickActions
                ActivityCard()
                waterCard
                meals
                planLink
            }
            .padding(.horizontal)
            .padding(.bottom, Spacing.xl)
        }
        .background(Theme.background)
        .navigationTitle("Сьогодні")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Налаштування")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { manualEntry = ManualEntryRequest(mealType: .suggested(for: .now)) } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Додати страву")
            }
        }
        .task { await health.refresh() }
        .refreshable { await health.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Pick up steps and workouts recorded while the app was in the background.
            if phase == .active { Task { await health.refresh() } }
        }
        .navigationDestination(isPresented: $showNutritionPlan) {
            NutritionPlanView(initialProfile: diary.profileWithLatestWeight)
        }
        .sheet(item: $manualEntry) { request in
            NavigationStack { ManualEntryView(mealType: request.mealType) }
        }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sensoryFeedback(.increase, trigger: waterTick)
    }

    // MARK: Summary

    private func summaryCard(_ totals: NutritionTotals) -> some View {
        let goal = diary.goals.calories
        let remaining = Int(goal.rounded()) - totals.kcal
        return VStack(spacing: Spacing.l) {
            HStack(spacing: Spacing.l) {
                ProgressRing(value: totals.calories, goal: goal) {
                    VStack(spacing: 0) {
                        Text("\(abs(remaining))")
                            .numberFont(.title, weight: .bold)
                            .contentTransition(.numericText(value: Double(remaining)))
                            .animation(.smooth, value: remaining)
                            .minimumScaleFactor(0.6)
                        Text(remaining >= 0 ? "залишилось" : "понад норму")
                            .font(.caption)
                            .foregroundStyle(remaining >= 0 ? Color.secondary : Theme.warning)
                    }
                    .padding(.horizontal, Spacing.s)
                }
                .frame(width: 136, height: 136)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Калорії")
                .accessibilityValue(remaining >= 0 ? "Залишилось \(remaining) ккал" : "Понад норму на \(-remaining) ккал")

                VStack(alignment: .leading, spacing: Spacing.m) {
                    StatLine(icon: "flag.checkered", tint: .secondary, title: "Ціль", value: Int(goal.rounded()))
                    StatLine(icon: "fork.knife", tint: Theme.accent, title: "Спожито", value: totals.kcal)
                    if let burned = EnergyBalance.today(snapshot: health.snapshot, profile: diary.profileForEstimates,
                                                        eaten: totals.calories)?.display.burned {
                        StatLine(icon: "flame.fill", tint: Ring.move.color, title: "Витрати енергії", value: burned)
                    } else {
                        StatLine(icon: "flame.fill", tint: Ring.move.color, title: "Спалено (активність)",
                                 value: Int(health.snapshot.activeCalories.rounded()))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(spacing: Spacing.m) {
                ForEach(Macro.allCases) { macro in
                    MacroBar(macro: macro, value: macro.value(in: totals), goal: macro.goal(in: diary.goals))
                }
            }
            if !diary.goals.macrosMatchCalories { macroMismatchNotice }
        }
        .cardStyle()
    }

    /// Shown when the gram goals do not add up to the calorie goal. Nothing is changed until the user decides.
    private var macroMismatchNotice: some View {
        let goals = diary.goals
        return Button { showSettings = true } label: {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text("Цілі БЖВ дають \(Int(goals.macroCalories.rounded())) ккал, а денна ціль — \(Int(goals.calories.rounded())) ккал. Перевірте цілі в налаштуваннях.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var setupPrompt: some View {
        Button { showNutritionPlan = true } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Розрахуйте свою норму").font(.headline)
                    Text("Зараз використовується стандартна ціль 2 000 ккал").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: Spacing.m) {
            QuickAction(title: "Сфотографувати", icon: "camera.fill", tint: Theme.accent) { selectedTab = .scan }
            QuickAction(title: "Додати вручну", icon: "square.and.pencil", tint: Macro.protein.color) {
                manualEntry = ManualEntryRequest(mealType: .suggested(for: .now))
            }
        }
    }

    // MARK: Water

    private var waterCard: some View {
        let water = diary.waterToday
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Label("Вода", systemImage: "drop.fill").font(.headline).foregroundStyle(Theme.water)
                Spacer()
                Text("\(Text("\(Int(water))").number(.headline)) / \(Int(diary.goals.waterML)) мл")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.water.gradient)
                        .frame(width: proxy.size.width * progress(water, of: diary.goals.waterML))
                        .animation(.smooth, value: water)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            HStack(spacing: Spacing.s) {
                ForEach([200.0, 300.0, 500.0], id: \.self) { amount in
                    Button("+\(Int(amount))") {
                        diary.addWater(amount)
                        waterTick += 1
                    }
                    .accessibilityLabel("Додати \(Int(amount)) мілілітрів")
                }
                Spacer()
                if water > 0 {
                    Button { diary.undoLastWater() } label: { Image(systemName: "arrow.uturn.backward") }
                        .tint(.secondary)
                        .accessibilityLabel("Скасувати останнє додавання води")
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.water)
        }
        .cardStyle()
    }

    // MARK: Meals

    private var meals: some View {
        let todayEntries = diary.todayEntries
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionTitle(title: "Прийоми їжі", trailing: todayEntries.isEmpty ? nil : "\(todayEntries.count) записів")
            ForEach(MealEntry.MealType.allCases) { type in
                MealSectionCard(
                    type: type,
                    entries: todayEntries.filter { $0.mealType == type }.sorted { $0.date < $1.date },
                    add: { manualEntry = ManualEntryRequest(mealType: type) }
                )
            }
        }
    }

    private var planLink: some View {
        Button { showNutritionPlan = true } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: "list.bullet.clipboard.fill").font(.title3).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Норма та меню на день").font(.headline)
                    Text("Перерахувати ціль або додати готове меню").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

private struct StatLine: View {
    let icon: String
    let tint: Color
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon).font(.footnote).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text("\(Text("\(value)").number(.headline)) ккал").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickAction: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14), in: Circle())
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

private struct MealSectionCard: View {
    let type: MealEntry.MealType
    let entries: [MealEntry]
    let add: () -> Void

    private var kcal: Int { NutritionTotals(entries: entries).kcal }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                MealTypeBadge(type: type)
                VStack(alignment: .leading, spacing: 1) {
                    Text(type.title).font(.headline)
                    Text(entries.isEmpty ? "Ще нічого не додано" : "\(kcal) ккал")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: add) {
                    Image(systemName: "plus").font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Theme.accentSoft, in: Circle())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Додати до: \(type.title)")
            }
            ForEach(entries) { entry in
                NavigationLink {
                    EditMealEntryView(entry: entry)
                } label: {
                    MealRow(entry: entry, showsBadge: false)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }
}
