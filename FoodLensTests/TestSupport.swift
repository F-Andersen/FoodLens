import Foundation
@testable import FoodLens

/// A throwaway UserDefaults suite so tests never touch the app's real data.
final class TestDefaults {
    let suiteName = "foodlens-tests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
func makeStore(defaults: UserDefaults, migrate: Bool = true) throws -> DiaryStore {
    DiaryStore(container: try FoodLensPersistence.makeContainer(inMemory: true), defaults: defaults, migrateLegacyData: migrate)
}

/// Seconds since the reference date, the default `Date` encoding of v0.2's JSONEncoder.
func legacyDate(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate }
