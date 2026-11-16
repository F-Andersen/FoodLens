import Foundation

/// Diary entries of one calendar day, newest day first.
struct DiaryDay: Identifiable, Equatable, Sendable {
    let day: Date
    let entries: [MealEntry]

    var id: Date { day }
    var totals: NutritionTotals { NutritionTotals(entries: entries) }

    static func group(_ entries: [MealEntry], calendar: Calendar = .current) -> [DiaryDay] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
            .map { DiaryDay(day: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// "Сьогодні", "Вчора" or a full date such as "четвер, 5 листопада".
    func title(now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Сьогодні" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Вчора"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

extension Array where Element == MealEntry {
    /// Unique favourite meals by name, most recent first — used for one-tap re-adding.
    var uniqueFavorites: [MealEntry] {
        var seen = Set<String>()
        return filter { $0.isFavorite }
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.name.lowercased()).inserted }
    }
}
