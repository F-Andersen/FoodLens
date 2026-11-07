import Foundation
import HealthKit

@MainActor
final class HealthService: ObservableObject {
    @Published private(set) var steps = 0
    @Published private(set) var activeCalories = 0

    private let store = HKHealthStore()

    func requestAndLoad() async {
        #if targetEnvironment(simulator)
        // HealthKit has no data on the simulator.
        #else
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let stepsType = HKQuantityType(.stepCount)
        let energyType = HKQuantityType(.activeEnergyBurned)
        do {
            try await store.requestAuthorization(toShare: [], read: [stepsType, energyType])
        } catch {
            return
        }
        steps = Int(await todaySum(of: stepsType, unit: .count()))
        activeCalories = Int(await todaySum(of: energyType, unit: .kilocalorie()))
        #endif
    }

    private func todaySum(of type: HKQuantityType, unit: HKUnit) async -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }
}
