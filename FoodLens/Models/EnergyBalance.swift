import Foundation

/// Calories in versus calories out: resting (basal) energy plus active energy against what was eaten.
///
/// Resting energy comes from Apple Health when iPhone or Apple Watch records it, otherwise from the
/// user's profile (Mifflin–St Jeor BMR), spread evenly over the day so far.
struct EnergyBalance: Equatable, Sendable {
    enum RestingSource: Equatable, Sendable { case health, profile }

    /// Resting energy burned since midnight.
    var restingSoFar: Double
    /// Resting energy for the whole day, for the end-of-day estimate.
    var restingFullDay: Double
    var active: Double
    var eaten: Double
    var source: RestingSource

    var burnedSoFar: Double { restingSoFar + active }
    /// Negative is a deficit, positive a surplus.
    var balanceNow: Double { eaten - burnedSoFar }
    /// The balance at midnight if nothing more is eaten and no more activity happens.
    var balanceEndOfDay: Double { eaten - (restingFullDay + active) }

    static func today(
        snapshot: ActivitySnapshot, profile: NutritionProfile?, eaten: Double,
        now: Date = .now, calendar: Calendar = .current
    ) -> EnergyBalance? {
        let start = calendar.startOfDay(for: now)
        let elapsed = min(max(now.timeIntervalSince(start) / 86_400, 0), 1)
        let bmr = profile?.bmr

        if snapshot.restingCalories > 0 {
            // A full day of resting energy: yesterday's measured total is the best guide, then the BMR.
            let yesterday = snapshot.week.dropLast().last?.restingCalories ?? 0
            let fullDay = yesterday > 0 ? yesterday : (bmr ?? snapshot.restingCalories / max(elapsed, 0.1))
            return EnergyBalance(
                restingSoFar: snapshot.restingCalories, restingFullDay: max(fullDay, snapshot.restingCalories),
                active: snapshot.activeCalories, eaten: eaten, source: .health
            )
        }
        guard let bmr else { return nil }
        return EnergyBalance(
            restingSoFar: bmr * elapsed, restingFullDay: bmr,
            active: snapshot.activeCalories, eaten: eaten, source: .profile
        )
    }
}

/// One day of the weekly balance chart.
struct DayBalance: Identifiable, Equatable, Sendable {
    var day: Date
    var eaten: Double
    var burned: Double
    var isToday: Bool

    var id: Date { day }
    var balance: Double { eaten - burned }

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
                return DayBalance(day: day.day, eaten: food, burned: balance.burnedSoFar, isToday: true)
            }
            let resting = day.restingCalories > 0 ? day.restingCalories : profile?.bmr
            guard let resting else { return nil }
            return DayBalance(day: day.day, eaten: food, burned: resting + day.activeCalories, isToday: false)
        }
    }
}
