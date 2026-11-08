import Foundation
import HealthKit
import Observation

/// Reads activity from Apple Health (the same data the Fitness app shows) and keeps it fresh.
@MainActor
@Observable
final class HealthService {
    private(set) var snapshot = ActivitySnapshot()
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    let isAvailable = HKHealthStore.isHealthDataAvailable()

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var didRequestAuthorization = false

    nonisolated static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.flightsClimbed),
        HKCategoryType(.appleStandHour),
        HKObjectType.workoutType(),
        HKObjectType.activitySummaryType()
    ]

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoHealth") {
            snapshot = .demo()
            lastUpdated = .now
            return
        }
        #endif
        guard isAvailable, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if !didRequestAuthorization {
            // iOS shows the permission sheet only once; later calls return immediately.
            do {
                try await store.requestAuthorization(toShare: [], read: Self.readTypes)
                didRequestAuthorization = true
            } catch {
                return
            }
        }
        snapshot = await HealthReader(store: store).load(now: .now)
        lastUpdated = .now
    }
}

/// Runs the HealthKit queries off the main actor. HealthKit never reveals whether read access
/// was denied: denied types simply return no data, which the UI explains.
struct HealthReader: Sendable {
    let store: HKHealthStore

    func load(now: Date, calendar: Calendar = .current) async -> ActivitySnapshot {
        let start = calendar.startOfDay(for: now)
        async let steps = sum(.stepCount, .count(), from: start, to: now)
        async let distance = sum(.distanceWalkingRunning, .meter(), from: start, to: now)
        async let energy = sum(.activeEnergyBurned, .kilocalorie(), from: start, to: now)
        async let exercise = sum(.appleExerciseTime, .minute(), from: start, to: now)
        async let flights = sum(.flightsClimbed, .count(), from: start, to: now)
        async let stand = standHours(from: start, to: now)
        async let goals = ringGoals(for: now, calendar: calendar)
        async let workouts = workouts(from: start, to: now)
        async let weekSteps = daily(.stepCount, .count(), endingAt: now, calendar: calendar)
        async let weekEnergy = daily(.activeEnergyBurned, .kilocalorie(), endingAt: now, calendar: calendar)

        let ringGoals = await goals
        return await ActivitySnapshot(
            steps: steps, distanceMeters: distance, activeCalories: energy, exerciseMinutes: exercise,
            standHours: stand, flightsClimbed: flights,
            moveGoal: ringGoals.move, exerciseGoal: ringGoals.exercise, standGoal: ringGoals.stand,
            workouts: workouts,
            week: ActivitySnapshot.week(endingAt: now, steps: weekSteps, calories: weekEnergy, calendar: calendar)
        )
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum
        )
        return (try? await descriptor.result(for: store))?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func daily(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, endingAt now: Date, calendar: Calendar) async -> [Date: Double] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return [:] }
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: now)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: now) { statistics, _ in
            result[calendar.startOfDay(for: statistics.startDate)] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        return result
    }

    private func standHours(from start: Date, to end: Date) async -> Int {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.appleStandHour),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: []
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
    }

    private func workouts(from start: Date, to end: Date) async -> [WorkoutSummary] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 20
        )
        let workouts = (try? await descriptor.result(for: store)) ?? []
        return workouts.map { workout in
            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
            let distance = distanceTypes.lazy
                .compactMap { workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
                .first
            return WorkoutSummary(id: workout.uuid, kind: WorkoutKind(workout.workoutActivityType), start: workout.startDate,
                                  duration: workout.duration, activeCalories: energy, distanceMeters: distance)
        }
    }

    private func ringGoals(for date: Date, calendar: Calendar) async -> (move: Double?, exercise: Double?, stand: Double?) {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: components)
        let store = store
        return await withCheckedContinuation { continuation in
            // The handler runs on a HealthKit queue; only Sendable values leave it.
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: (nil, nil, nil))
                    return
                }
                func positive(_ quantity: HKQuantity, _ unit: HKUnit) -> Double? {
                    let value = quantity.doubleValue(for: unit)
                    return value > 0 ? value : nil
                }
                continuation.resume(returning: (
                    positive(summary.activeEnergyBurnedGoal, .kilocalorie()),
                    positive(summary.appleExerciseTimeGoal, .minute()),
                    positive(summary.appleStandHoursGoal, .count())
                ))
            }
            store.execute(query)
        }
    }
}

extension WorkoutKind {
    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .walking: self = .walking
        case .running: self = .running
        case .cycling, .handCycling: self = .cycling
        case .swimming, .swimBikeRun: self = .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: self = .strength
        case .highIntensityIntervalTraining, .crossTraining: self = .hiit
        case .yoga, .pilates, .mindAndBody: self = .yoga
        case .hiking: self = .hiking
        case .socialDance, .cardioDance, .barre: self = .dance
        case .elliptical: self = .elliptical
        case .rowing, .paddleSports: self = .rowing
        default: self = .other
        }
    }
}
