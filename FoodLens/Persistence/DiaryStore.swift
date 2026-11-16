import Foundation
import Observation
import SwiftData
import os

/// The app's single source of truth for the diary, weight and water.
///
/// Records live in SwiftData; the store keeps sorted value-type snapshots for the UI and
/// rolls back the context when a save fails, so the UI never shows unsaved state.
@MainActor
@Observable
final class DiaryStore {
    /// Newest first.
    private(set) var entries: [MealEntry] = []
    /// Newest first.
    private(set) var weights: [WeightRecord] = []
    /// Newest first.
    private(set) var waterLogs: [WaterLog] = []
    /// A user-facing description of a storage problem, if any.
    private(set) var storageIssue: String?

    var goals: NutritionGoals {
        didSet { if goals != oldValue { saveValue(goals, forKey: Keys.goals) } }
    }

    var profile: NutritionProfile? {
        didSet { if let profile, profile != oldValue { saveValue(profile, forKey: Keys.profile) } }
    }

    enum Keys {
        static let goals = "foodlens_goals_v1"
        static let profile = "foodlens_profile_v1"
    }

    /// Retained on purpose: a ModelContext does not keep its container alive.
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let logger = Logger(subsystem: "com.argusstrauf.foodlens", category: "DiaryStore")

    init(
        container: ModelContainer, defaults: UserDefaults = .standard, calendar: Calendar = .current,
        migrateLegacyData: Bool = true, storageIssue: String? = nil
    ) {
        self.container = container
        context = container.mainContext
        self.defaults = defaults
        self.calendar = calendar
        self.storageIssue = storageIssue
        goals = Self.loadValue(NutritionGoals.self, forKey: Keys.goals, from: defaults) ?? .standard
        profile = Self.loadValue(NutritionProfile.self, forKey: Keys.profile, from: defaults)
        if migrateLegacyData { migrateLegacyDataIfNeeded() }
        reload()
    }

    /// Opens the on-disk store. If it cannot be opened, falls back to memory and says so,
    /// without touching the legacy data so nothing is lost.
    static func makeDefault() -> DiaryStore {
        do {
            return DiaryStore(container: try FoodLensPersistence.makeContainer())
        } catch {
            Logger(subsystem: "com.argusstrauf.foodlens", category: "DiaryStore").fault("Cannot open store: \(error.localizedDescription, privacy: .public)")
            do {
                return DiaryStore(
                    container: try FoodLensPersistence.makeContainer(inMemory: true),
                    migrateLegacyData: false,
                    storageIssue: "Сховище недоступне. Нові записи не збережуться після закриття застосунку."
                )
            } catch {
                fatalError("In-memory SwiftData container failed: \(error)")
            }
        }
    }

    // MARK: Queries

    func entries(on date: Date) -> [MealEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    var todayEntries: [MealEntry] { entries(on: .now) }

    func totals(on date: Date) -> NutritionTotals { NutritionTotals(entries: entries(on: date)) }

    var todayTotals: NutritionTotals { totals(on: .now) }

    func calories(on date: Date) -> Int { totals(on: date).kcal }

    func water(on date: Date) -> Double {
        waterLogs.filter { calendar.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.milliliters }
    }

    var waterToday: Double { water(on: .now) }

    var latestWeight: WeightRecord? { weights.first }

    /// The saved profile (or defaults) with the most recently logged weight, so Progress and the calculator agree.
    var profileWithLatestWeight: NutritionProfile {
        var result = profile ?? NutritionProfile()
        if let weight = latestWeight?.kilograms { result.weightKG = weight }
        return result
    }

    /// The saved profile with the latest logged weight, or nil when the user has not set up a profile.
    /// Energy estimates use this so a new weigh-in updates the resting energy right away.
    var profileForEstimates: NutritionProfile? { profile == nil ? nil : profileWithLatestWeight }

    // MARK: Meals

    func add(_ entry: MealEntry) {
        context.insert(StoredMeal(entry: entry))
        commit()
    }

    func add(_ newEntries: [MealEntry]) {
        newEntries.forEach { context.insert(StoredMeal(entry: $0)) }
        commit()
    }

    func update(_ entry: MealEntry) {
        guard let stored = fetchMeal(id: entry.id) else { return }
        stored.apply(entry)
        commit()
    }

    func deleteMeal(id: UUID) {
        guard let stored = fetchMeal(id: id) else { return }
        context.delete(stored)
        commit()
    }

    func toggleFavorite(id: UUID) {
        guard let stored = fetchMeal(id: id) else { return }
        stored.isFavorite.toggle()
        commit()
    }

    // MARK: Weight

    func addWeight(_ kilograms: Double, date: Date = .now) {
        context.insert(StoredWeight(record: WeightRecord(date: date, kilograms: kilograms)))
        commit()
    }

    func updateWeight(id: UUID, kilograms: Double) {
        guard let stored = fetchWeight(id: id) else { return }
        stored.kilograms = kilograms
        commit()
    }

    func deleteWeight(id: UUID) {
        guard let stored = fetchWeight(id: id) else { return }
        context.delete(stored)
        commit()
    }

    // MARK: Water

    func addWater(_ milliliters: Double, date: Date = .now) {
        guard milliliters > 0 else { return }
        context.insert(StoredWater(log: WaterLog(date: date, milliliters: milliliters)))
        commit()
    }

    /// Removes the most recent water entry of the given day.
    func undoLastWater(on date: Date = .now) {
        guard let last = waterLogs.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { return }
        let id = last.id
        var descriptor = FetchDescriptor<StoredWater>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let stored = try? context.fetch(descriptor).first else { return }
        context.delete(stored)
        commit()
    }

    // MARK: Private

    private func fetchMeal(id: UUID) -> StoredMeal? {
        var descriptor = FetchDescriptor<StoredMeal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchWeight(id: UUID) -> StoredWeight? {
        var descriptor = FetchDescriptor<StoredWeight>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func commit() {
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            storageIssue = "Не вдалося зберегти зміни. Спробуйте ще раз."
        }
        reload()
    }

    private func reload() {
        do {
            entries = try context.fetch(FetchDescriptor<StoredMeal>(sortBy: [SortDescriptor(\.date, order: .reverse)])).map(\.entry)
            weights = try context.fetch(FetchDescriptor<StoredWeight>(sortBy: [SortDescriptor(\.date, order: .reverse)])).map(\.record)
            waterLogs = try context.fetch(FetchDescriptor<StoredWater>(sortBy: [SortDescriptor(\.date, order: .reverse)])).map(\.log)
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            storageIssue = "Не вдалося прочитати щоденник."
        }
    }

    private func migrateLegacyDataIfNeeded() {
        guard !defaults.bool(forKey: LegacyStoreMigrator.migratedFlagKey) else { return }
        switch LegacyStoreMigrator.load(from: defaults) {
        case .nothingToMigrate:
            defaults.set(true, forKey: LegacyStoreMigrator.migratedFlagKey)
        case .unreadable:
            logger.error("Legacy data exists but could not be decoded; keeping it untouched.")
            storageIssue = "Не вдалося перенести дані попередньої версії. Вони збережені на пристрої й не будуть видалені."
        case .data(let legacy):
            // Skip ids that are already present, in case an earlier migration saved but the flag did not.
            let existingMeals = Set(((try? context.fetch(FetchDescriptor<StoredMeal>())) ?? []).map(\.id))
            let existingWeights = Set(((try? context.fetch(FetchDescriptor<StoredWeight>())) ?? []).map(\.id))
            legacy.meals.filter { !existingMeals.contains($0.id) }.forEach { context.insert(StoredMeal(entry: $0)) }
            legacy.weights.filter { !existingWeights.contains($0.id) }.forEach { context.insert(StoredWeight(record: $0)) }
            if existingMeals.isEmpty { legacy.water.forEach { context.insert(StoredWater(log: $0)) } }
            do {
                try context.save()
                if defaults.data(forKey: Keys.goals) == nil, let legacyGoals = legacy.goals { goals = legacyGoals }
                defaults.set(true, forKey: LegacyStoreMigrator.migratedFlagKey)
                logger.info("Migrated \(legacy.meals.count) meals, \(legacy.weights.count) weights; skipped \(legacy.skippedRecords).")
                if legacy.skippedRecords > 0 {
                    storageIssue = "Перенесено дані попередньої версії. \(legacy.skippedRecords) пошкоджених записів пропущено."
                }
            } catch {
                context.rollback()
                logger.error("Legacy migration save failed: \(error.localizedDescription, privacy: .public)")
                storageIssue = "Не вдалося перенести дані попередньої версії. Вони збережені й будуть перенесені пізніше."
            }
        }
    }

    private func saveValue(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadValue<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func dismissStorageIssue() { storageIssue = nil }
}
