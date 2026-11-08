import Foundation
import HealthKit
import Testing
@testable import FoodLens

@Suite("Activity")
struct ActivityTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 15))! }

    @Test func weekFillsMissingDaysOldestFirst() {
        let today = calendar.startOfDay(for: now)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let week = ActivitySnapshot.week(endingAt: now, steps: [today: 5000, twoDaysAgo: 8000],
                                         calories: [today: 300], calendar: calendar)
        #expect(week.count == 7)
        #expect(week.last?.day == today)
        #expect(week.first?.day == calendar.date(byAdding: .day, value: -6, to: today))
        #expect(week.map(\.steps) == [0, 0, 0, 0, 8000, 0, 5000])
        #expect(week.last?.activeCalories == 300)
    }

    @Test func averagesIgnoreEmptyDays() {
        var snapshot = ActivitySnapshot()
        let today = calendar.startOfDay(for: now)
        snapshot.week = ActivitySnapshot.week(endingAt: now, steps: [today: 6000, today.addingTimeInterval(-86_400): 10_000],
                                              calories: [today: 400], calendar: calendar)
        #expect(snapshot.weekAverageSteps == 8000)
        #expect(snapshot.weekAverageActiveCalories == 400)
        #expect(ActivitySnapshot().weekAverageSteps == 0)
    }

    @Test func emptySnapshotHasNoData() {
        #expect(!ActivitySnapshot().hasAnyData)
        var withWorkout = ActivitySnapshot()
        withWorkout.workouts = [WorkoutSummary(id: UUID(), kind: .yoga, start: now, duration: 600)]
        #expect(withWorkout.hasAnyData)
    }

    @Test func demoDataIsConsistent() {
        let demo = ActivitySnapshot.demo(now: now, calendar: calendar)
        #expect(demo.hasAnyData)
        #expect(demo.week.count == 7)
        #expect(demo.week.last?.steps == demo.steps)
        #expect(demo.distanceKilometers == 6.12)
    }

    @Test(arguments: [(28.0 * 60, "28 хв"), (90.0 * 60, "1 год 30 хв"), (60.0 * 60, "1 год 0 хв")])
    func workoutDuration(seconds: Double, text: String) {
        #expect(WorkoutSummary(id: UUID(), kind: .running, start: now, duration: seconds).durationText == text)
    }

    @Test func mapsHealthKitWorkoutTypes() {
        #expect(WorkoutKind(HKWorkoutActivityType.running) == .running)
        #expect(WorkoutKind(HKWorkoutActivityType.traditionalStrengthTraining) == .strength)
        #expect(WorkoutKind(HKWorkoutActivityType.highIntensityIntervalTraining) == .hiit)
        #expect(WorkoutKind(HKWorkoutActivityType.pilates) == .yoga)
        #expect(WorkoutKind(HKWorkoutActivityType.archery) == .other)
    }

    @Test func readsEverythingTheCardShows() {
        let expected: [HKObjectType] = [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.appleExerciseTime),
            HKCategoryType(.appleStandHour), HKObjectType.workoutType(), HKObjectType.activitySummaryType()
        ]
        #expect(expected.allSatisfy { HealthService.readTypes.contains($0) })
    }
}
