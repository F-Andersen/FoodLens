import Foundation

/// Calories in versus calories out: resting (basal) energy plus active energy against what was eaten.
///
/// Resting energy comes from Apple Health when iPhone or Apple Watch records it, otherwise from the
/// user's profile (Mifflin–St Jeor BMR), spread over the part of the day that has passed.
/// Active energy is Health's Active Energy only: it already contains workouts, so workouts are never added again.
/// All values keep full precision; `display` rounds them once for the screen.
struct EnergyBalance: Equatable, Sendable {
    enum RestingSource: Equatable, Sendable { case health, profile }

    /// Resting energy burned since midnight.
    var restingSoFar: Double
    /// Resting energy for the whole day, for the end-of-day estimate.
    var restingFullDay: Double
    var active: Double
    var eaten: Double
    var source: RestingSource
    /// False when Apple Health had no active energy for today (no permission, no device or no movement yet).
    var hasActiveData: Bool

    var burnedSoFar: Double { restingSoFar + active }
    /// Estimated deficit so far: positive is a deficit, negative a surplus.
    var deficitNow: Double { burnedSoFar - eaten }
    /// The deficit at midnight if nothing more is eaten and no more activity happens.
    var deficitEndOfDay: Double { restingFullDay + active - eaten }

    /// Whole-kcal values for the screen. Each part is rounded once and the totals are built from the
    /// rounded parts, so the numbers on screen always add up (2336 + 999 = 3335, 3335 − 2530 = 805).
    struct Display: Equatable, Sendable {
        var resting: Int
        var active: Int
        var eaten: Int
        var burned: Int { resting + active }
        /// Positive is a deficit, negative a surplus.
        var deficit: Int { burned - eaten }
        var isDeficit: Bool { deficit >= 0 }
    }

    var display: Display {
        Display(resting: Int(restingSoFar.rounded()), active: Int(active.rounded()), eaten: Int(eaten.rounded()))
    }

    /// More than 1 000 kcal of deficit already reached with food logged deserves a gentle note.
    /// Uses the deficit so far, not the end-of-day estimate, so an empty morning diary never triggers it.
    /// The user's data is never changed.
    var isLargeDeficit: Bool { eaten > 0 && deficitNow >= 1_000 }

    static func today(
        snapshot: ActivitySnapshot, profile: NutritionProfile?, eaten: Double,
        now: Date = .now, calendar: Calendar = .current
    ) -> EnergyBalance? {
        let start = calendar.startOfDay(for: now)
        // A snapshot read before midnight describes yesterday; never present it as today.
        let health = snapshot.describes(day: start, calendar: calendar) ? snapshot : ActivitySnapshot()
        let elapsed = dayFraction(at: now, calendar: calendar)
        let bmr = profile?.bmr
        let active = max(health.activeCalories, 0)
        let hasActive = health.activeCalories > 0

        if health.restingCalories > 0 {
            // A full day of resting energy: yesterday's measured total is the best guide, then the BMR.
            let yesterday = health.week.dropLast().last?.restingCalories ?? 0
            let fullDay = yesterday > 0 ? yesterday : (bmr ?? health.restingCalories / max(elapsed, 0.1))
            return EnergyBalance(
                restingSoFar: health.restingCalories, restingFullDay: max(fullDay, health.restingCalories),
                active: active, eaten: max(eaten, 0), source: .health, hasActiveData: hasActive
            )
        }
        guard let bmr, bmr > 0 else { return nil }
        return EnergyBalance(
            restingSoFar: bmr * elapsed, restingFullDay: bmr,
            active: active, eaten: max(eaten, 0), source: .profile, hasActiveData: hasActive
        )
    }

    /// The share of the calendar day that has passed. Uses the real length of the day, so the
    /// 23- and 25-hour days of daylight-saving changes are handled correctly.
    static func dayFraction(at now: Date, calendar: Calendar) -> Double {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / length, 0), 1)
    }
}

/// One day of the weekly balance chart.
struct DayBalance: Identifiable, Equatable, Sendable {
    var day: Date
    var eaten: Double
    var burned: Double
    var isToday: Bool
    var restingSource: EnergyBalance.RestingSource

    var id: Date { day }
    /// Positive is a deficit, negative a surplus.
    var deficit: Double { burned - eaten }

    /// Days without any logged food are skipped: an empty diary would look like a huge deficit.
    static func week(
        snapshot: ActivitySnapshot, profile: NutritionProfile?, eaten: (Date) -> Double,
        now: Date = .now, calendar: Calendar = .current
    ) -> [DayBalance] {
        let today = calendar.startOfDay(for: now)
        return snapshot.week.compactMap { day in
            let food = eaten(day.day)
            guard food > 0 else { return nil }
            if calendar.isDate(day.day, inSameDayAs: today) {
                guard let balance = EnergyBalance.today(snapshot: snapshot, profile: profile, eaten: food,
                                                        now: now, calendar: calendar) else { return nil }
                return DayBalance(day: day.day, eaten: food, burned: balance.burnedSoFar, isToday: true,
                                  restingSource: balance.source)
            }
            let fromHealth = day.restingCalories > 0
            let resting = fromHealth ? day.restingCalories : profile?.bmr
            guard let resting else { return nil }
            return DayBalance(day: day.day, eaten: food, burned: resting + day.activeCalories, isToday: false,
                              restingSource: fromHealth ? .health : .profile)
        }
    }
}

/// Seven-day averages for the Progress screen. Only finished days count: today is still going.
struct WeekEnergySummary: Equatable, Sendable {
    var days: Int
    var averageEaten: Double
    var averageBurned: Double
    var totalDeficit: Double

    var averageDeficit: Double { days > 0 ? totalDeficit / Double(days) : 0 }
    /// A rough guide (7 700 kcal ≈ 1 kg), not a forecast: water, glycogen and estimate errors dominate short periods.
    var estimatedWeightChangeKG: Double { -totalDeficit / NutritionProfile.kcalPerKilogram }

    init?(_ balances: [DayBalance]) {
        let finished = balances.filter { !$0.isToday }
        guard !finished.isEmpty else { return nil }
        days = finished.count
        averageEaten = finished.reduce(0) { $0 + $1.eaten } / Double(days)
        averageBurned = finished.reduce(0) { $0 + $1.burned } / Double(days)
        totalDeficit = finished.reduce(0) { $0 + $1.deficit }
    }
}
