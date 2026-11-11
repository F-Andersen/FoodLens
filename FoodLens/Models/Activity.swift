import Foundation

/// Activity data read from Apple Health. Free of HealthKit types so it is easy to test and preview.
struct ActivitySnapshot: Equatable, Sendable {
    var steps = 0.0
    var distanceMeters = 0.0
    var activeCalories = 0.0
    /// Resting (basal) energy burned so far today, as estimated by iPhone or Apple Watch.
    var restingCalories = 0.0
    var exerciseMinutes = 0.0
    var standHours = 0
    var flightsClimbed = 0.0
    /// Ring goals from the Fitness app; nil when the user has not set them (or Health has no summary yet).
    var moveGoal: Double?
    var exerciseGoal: Double?
    var standGoal: Double?
    var workouts: [WorkoutSummary] = []
    /// The last seven days, oldest first, including today.
    var week: [DayActivity] = []

    var hasAnyData: Bool {
        steps > 0 || activeCalories > 0 || exerciseMinutes > 0 || standHours > 0 || !workouts.isEmpty
            || week.contains { $0.steps > 0 || $0.activeCalories > 0 }
    }

    var distanceKilometers: Double { distanceMeters / 1000 }

    /// Average over days that have any steps, so a new install does not drag the average to zero.
    var weekAverageSteps: Int {
        let active = week.filter { $0.steps > 0 }
        guard !active.isEmpty else { return 0 }
        return Int((active.reduce(0) { $0 + $1.steps } / Double(active.count)).rounded())
    }

    var weekAverageActiveCalories: Int {
        let active = week.filter { $0.activeCalories > 0 }
        guard !active.isEmpty else { return 0 }
        return Int((active.reduce(0) { $0 + $1.activeCalories } / Double(active.count)).rounded())
    }

    /// Builds the seven-day series from per-day sums, filling missing days with zero.
    static func week(endingAt now: Date, steps: [Date: Double], calories: [Date: Double],
                     resting: [Date: Double] = [:], calendar: Calendar = .current) -> [DayActivity] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayActivity(day: day, steps: steps[day] ?? 0, activeCalories: calories[day] ?? 0,
                               restingCalories: resting[day] ?? 0)
        }
    }

    /// Realistic sample data for screenshots and the simulator (launch argument `-demoHealth`).
    static func demo(now: Date = .now, calendar: Calendar = .current) -> ActivitySnapshot {
        let today = calendar.startOfDay(for: now)
        let stepsByDay = [6_420.0, 9_850, 4_310, 11_240, 7_980, 12_660, 8_214]
        let caloriesByDay = [310.0, 455, 220, 530, 380, 610, 412]
        var steps: [Date: Double] = [:], calories: [Date: Double] = [:], resting: [Date: Double] = [:]
        for (index, offset) in (0..<7).reversed().enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            steps[day] = stepsByDay[index]
            calories[day] = caloriesByDay[index]
            resting[day] = offset == 0 ? 1_420 : 1_780
        }
        return ActivitySnapshot(
            steps: 8_214, distanceMeters: 6_120, activeCalories: 412, restingCalories: 1_420, exerciseMinutes: 34, standHours: 9,
            flightsClimbed: 7, moveGoal: 500, exerciseGoal: 30, standGoal: 12,
            workouts: [
                WorkoutSummary(id: UUID(), kind: .running, start: today.addingTimeInterval(7.5 * 3600),
                               duration: 28 * 60, activeCalories: 286, distanceMeters: 4_300),
                WorkoutSummary(id: UUID(), kind: .strength, start: today.addingTimeInterval(18 * 3600),
                               duration: 40 * 60, activeCalories: 190, distanceMeters: nil)
            ],
            week: week(endingAt: now, steps: steps, calories: calories, resting: resting, calendar: calendar)
        )
    }
}

struct DayActivity: Identifiable, Hashable, Sendable {
    var day: Date
    var steps: Double
    var activeCalories: Double
    var restingCalories: Double = 0
    var id: Date { day }
}

struct WorkoutSummary: Identifiable, Hashable, Sendable {
    var id: UUID
    var kind: WorkoutKind
    var start: Date
    var duration: TimeInterval
    var activeCalories: Double?
    var distanceMeters: Double?

    var durationText: String {
        let minutes = Int((duration / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) год \(minutes % 60) хв" : "\(minutes) хв"
    }
}

enum WorkoutKind: String, Sendable, Hashable, CaseIterable {
    case walking, running, cycling, swimming, strength, hiit, yoga, hiking, dance, elliptical, rowing, other

    var title: String {
        switch self {
        case .walking: "Ходьба"
        case .running: "Біг"
        case .cycling: "Велосипед"
        case .swimming: "Плавання"
        case .strength: "Силове тренування"
        case .hiit: "HIIT"
        case .yoga: "Йога"
        case .hiking: "Похід"
        case .dance: "Танці"
        case .elliptical: "Еліпсоїд"
        case .rowing: "Веслування"
        case .other: "Тренування"
        }
    }

    var icon: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "dumbbell.fill"
        case .hiit: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .hiking: "figure.hiking"
        case .dance: "figure.dance"
        case .elliptical: "figure.elliptical"
        case .rowing: "figure.rower"
        case .other: "figure.mixed.cardio"
        }
    }
}
