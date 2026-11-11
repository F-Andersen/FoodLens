import Foundation
import Testing
@testable import FoodLens

@Suite("Energy balance")
struct EnergyBalanceTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func at(_ hour: Int, day: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private var profile: NutritionProfile {
        var profile = NutritionProfile()
        profile.sex = .male; profile.age = 30; profile.heightCM = 180; profile.weightKG = 80
        return profile // BMR 1780
    }

    @Test func usersExampleGivesAThousandDeficit() {
        // Resting 2000 + training 1000 burned, 2000 eaten.
        var snapshot = ActivitySnapshot()
        snapshot.restingCalories = 2000
        snapshot.activeCalories = 1000
        let balance = EnergyBalance.today(snapshot: snapshot, profile: nil, eaten: 2000, now: at(23), calendar: calendar)
        #expect(balance?.burnedSoFar == 3000)
        #expect(balance?.balanceNow == -1000)
        #expect(balance?.source == .health)
    }

    @Test func healthRestingEnergyIsPreferredAndYesterdayGivesTheFullDay() throws {
        var snapshot = ActivitySnapshot()
        snapshot.restingCalories = 1200
        snapshot.activeCalories = 500
        let today = calendar.startOfDay(for: at(18))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        snapshot.week = ActivitySnapshot.week(endingAt: at(18), steps: [:], calories: [:],
                                              resting: [yesterday: 1900, today: 1200], calendar: calendar)
        let balance = try #require(EnergyBalance.today(snapshot: snapshot, profile: profile, eaten: 1500,
                                                       now: at(18), calendar: calendar))
        #expect(balance.balanceNow == 1500 - 1700)
        #expect(balance.restingFullDay == 1900)
        #expect(balance.balanceEndOfDay == 1500 - 2400)
    }

    @Test func profileBMRIsSpreadOverTheDayWithoutHealthData() throws {
        var snapshot = ActivitySnapshot()
        snapshot.activeCalories = 300
        let balance = try #require(EnergyBalance.today(snapshot: snapshot, profile: profile, eaten: 1000,
                                                       now: at(12), calendar: calendar))
        #expect(balance.source == .profile)
        #expect(balance.restingSoFar == 890) // half of 1780
        #expect(balance.balanceNow == 1000 - 1190)
        #expect(balance.balanceEndOfDay == 1000 - 2080)
    }

    @Test func noBalanceWithoutHealthOrProfile() {
        #expect(EnergyBalance.today(snapshot: ActivitySnapshot(), profile: nil, eaten: 500, now: at(12),
                                    calendar: calendar) == nil)
    }

    @Test func weekSkipsDaysWithoutFoodAndUsesBMRWhenRestingIsMissing() {
        let now = at(20)
        let today = calendar.startOfDay(for: now)
        let day1 = calendar.date(byAdding: .day, value: -1, to: today)!
        let day2 = calendar.date(byAdding: .day, value: -2, to: today)!
        var snapshot = ActivitySnapshot()
        snapshot.restingCalories = 1500
        snapshot.activeCalories = 200
        snapshot.week = ActivitySnapshot.week(endingAt: now, steps: [:], calories: [day1: 400, day2: 100],
                                              resting: [day1: 1800, today: 1500], calendar: calendar)
        let eaten: [Date: Double] = [today: 1600, day1: 2500, day2: 1500]

        let week = DayBalance.week(snapshot: snapshot, profile: profile, eaten: { eaten[$0] ?? 0 },
                                   now: now, calendar: calendar)

        #expect(week.map(\.day) == [day2, day1, today])
        #expect(week[0].burned == 1780 + 100) // no Health resting → BMR
        #expect(week[1].balance == 2500 - 2200)
        #expect(week[2].isToday && week[2].burned == 1700)
    }
}
