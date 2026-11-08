import HealthKit
import HealthKitUI
import SwiftUI

/// Today's activity from Apple Health: rings, steps, distance, floors and workouts.
struct ActivityCard: View {
    @Environment(HealthService.self) private var health
    @State private var showHelp = false

    private var snapshot: ActivitySnapshot { health.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack {
                Label("Активність", systemImage: "figure.run.circle.fill")
                    .font(.headline).foregroundStyle(Ring.move.color)
                Spacer()
                if health.isLoading { ProgressView().controlSize(.small) }
            }
            if !health.isAvailable {
                Text("Apple Health недоступний на цьому пристрої.").font(.subheadline).foregroundStyle(.secondary)
            } else if !snapshot.hasAnyData && !health.isLoading {
                emptyState
            } else {
                rings
                stats
                if !snapshot.workouts.isEmpty { workouts }
                if let updated = health.lastUpdated {
                    Text("Apple Health · оновлено \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .cardStyle()
        .sheet(isPresented: $showHelp) { HealthAccessHelp() }
    }

    private var rings: some View {
        HStack(spacing: Spacing.l) {
            ActivityRingsView(snapshot: snapshot)
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                RingLegend(ring: .move, value: snapshot.activeCalories, goal: snapshot.moveGoal, unit: "ккал")
                RingLegend(ring: .exercise, value: snapshot.exerciseMinutes, goal: snapshot.exerciseGoal, unit: "хв")
                RingLegend(ring: .stand, value: Double(snapshot.standHours), goal: snapshot.standGoal, unit: "год")
            }
        }
    }

    private var stats: some View {
        HStack(spacing: Spacing.s) {
            ActivityStat(icon: "shoeprints.fill", value: snapshot.steps.formatted(.number.precision(.fractionLength(0))), unit: "кроків")
            ActivityStat(icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                         value: snapshot.distanceKilometers.formatted(.number.precision(.fractionLength(1))), unit: "км")
            ActivityStat(icon: "figure.stairs", value: snapshot.flightsClimbed.formatted(.number.precision(.fractionLength(0))), unit: "поверхів")
        }
    }

    private var workouts: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Тренування").font(.subheadline.weight(.semibold))
            ForEach(snapshot.workouts) { workout in
                HStack(spacing: Spacing.m) {
                    Image(systemName: workout.kind.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ring.exercise.color)
                        .frame(width: 34, height: 34)
                        .background(Ring.exercise.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(workout.kind.title).font(.subheadline.weight(.medium))
                        Text(workoutDetails(workout)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let calories = workout.activeCalories {
                        Text("\(Text("\(Int(calories))").number(.subheadline)) ккал").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func workoutDetails(_ workout: WorkoutSummary) -> String {
        var parts = [workout.start.formatted(date: .omitted, time: .shortened), workout.durationText]
        if let meters = workout.distanceMeters, meters > 0 {
            parts.append("\((meters / 1000).formatted(.number.precision(.fractionLength(1)))) км")
        }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Немає даних про активність").font(.subheadline.weight(.semibold))
            Text("Дозвольте FoodLens читати кроки, тренування та кільця активності в Apple Health.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Як дозволити доступ") { showHelp = true }
                .font(.subheadline.weight(.semibold))
        }
    }
}

/// The three Activity rings, matching the colours people know from Apple's Fitness app.
enum Ring {
    case move, exercise, stand

    var title: String {
        switch self {
        case .move: "Рух"
        case .exercise: "Вправи"
        case .stand: "Стояння"
        }
    }

    var color: Color {
        switch self {
        case .move: Color(red: 0.98, green: 0.07, blue: 0.31)
        case .exercise: Color(red: 0.47, green: 0.85, blue: 0.0)
        case .stand: Color(red: 0.0, green: 0.78, blue: 0.85)
        }
    }

    var defaultGoal: Double {
        switch self {
        case .move: 500
        case .exercise: 30
        case .stand: 12
        }
    }
}

/// Apple's own ring view (HealthKitUI), fed from our snapshot.
struct ActivityRingsView: UIViewRepresentable {
    let snapshot: ActivitySnapshot

    func makeUIView(context: Context) -> HKActivityRingView {
        let view = HKActivityRingView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: HKActivityRingView, context: Context) {
        let summary = HKActivitySummary()
        summary.activeEnergyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: snapshot.activeCalories)
        summary.activeEnergyBurnedGoal = HKQuantity(unit: .kilocalorie(), doubleValue: snapshot.moveGoal ?? Ring.move.defaultGoal)
        summary.appleExerciseTime = HKQuantity(unit: .minute(), doubleValue: snapshot.exerciseMinutes)
        summary.appleExerciseTimeGoal = HKQuantity(unit: .minute(), doubleValue: snapshot.exerciseGoal ?? Ring.exercise.defaultGoal)
        summary.appleStandHours = HKQuantity(unit: .count(), doubleValue: Double(snapshot.standHours))
        summary.appleStandHoursGoal = HKQuantity(unit: .count(), doubleValue: snapshot.standGoal ?? Ring.stand.defaultGoal)
        view.setActivitySummary(summary, animated: true)
    }
}

private struct RingLegend: View {
    let ring: Ring
    let value: Double
    let goal: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ring.title).font(.caption).foregroundStyle(.secondary)
            Text("\(Text("\(Int(value.rounded()))").number(.headline).foregroundStyle(ring.color)) / \(Int(goal ?? ring.defaultGoal)) \(unit)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityStat: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).numberFont(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// HealthKit never tells an app whether reading was denied, so we explain where to check.
struct HealthAccessHelp: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Відкрийте застосунок «Здоров'я»", systemImage: "1.circle.fill")
                    Label("Торкніться фото профілю вгорі праворуч", systemImage: "2.circle.fill")
                    Label("Застосунки → FoodLens", systemImage: "3.circle.fill")
                    Label("Увімкніть «Увімкнути всі»", systemImage: "4.circle.fill")
                } footer: {
                    Text("Кільця активності та тренування з'являються, якщо їх записують iPhone або Apple Watch. Дані не залишають ваш пристрій.")
                }
                Section {
                    Button {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    } label: {
                        Label("Відкрити «Здоров'я»", systemImage: "heart.text.square.fill")
                    }
                }
            }
            .navigationTitle("Доступ до Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
