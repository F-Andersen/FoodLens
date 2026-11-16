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
        #expect(balance?.deficitNow == 1000)
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
        #expect(balance.deficitNow == 1700 - 1500)
        #expect(balance.restingFullDay == 1900)
        #expect(balance.deficitEndOfDay == 2400 - 1500)
    }

    @Test func profileBMRIsSpreadOverTheDayWithoutHealthData() throws {
        var snapshot = ActivitySnapshot()
        snapshot.activeCalories = 300
        let balance = try #require(EnergyBalance.today(snapshot: snapshot, profile: profile, eaten: 1000,
                                                       now: at(12), calendar: calendar))
        #expect(balance.source == .profile)
        #expect(balance.restingSoFar == 890) // half of 1780
        #expect(balance.deficitNow == 1190 - 1000)
        #expect(balance.deficitEndOfDay == 2080 - 1000)
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
        #expect(week[1].deficit == 2200 - 2500)
        #expect(week[2].isToday && week[2].burned == 1700)
    }

    // MARK: Scenarios from the calculation audit

    /// Scenario 3 and 4: 2336 + 999 = 3335 and 3335 − 2530 = 805 on screen, even when the
    /// unrounded parts would give 805.5 → 806.
    @Test func displayedNumbersAlwaysAddUp() throws {
        var snapshot = ActivitySnapshot()
        snapshot.restingCalories = 2335.6
        snapshot.activeCalories = 999.4
        let balance = try #require(EnergyBalance.today(snapshot: snapshot, profile: nil, eaten: 2529.5,
                                                       now: at(22), calendar: calendar))
        let shown = balance.display
        #expect(shown.resting == 2336)
        #expect(shown.active == 999)
        #expect(shown.burned == 3335)
        #expect(shown.eaten == 2530)
        #expect(shown.deficit == 805)
        #expect(shown.isDeficit)
        #expect(abs(balance.deficitNow - 805.5) < 1e-9) // full precision is kept underneath
    }

    @Test func surplusIsReportedAsNegativeDeficit() throws {
        var snapshot = ActivitySnapshot()
        snapshot.restingCalories = 1200
        snapshot.activeCalories = 100
        let balance = try #require(EnergyBalance.today(snapshot: snapshot, profile: nil, eaten: 2000,
                                                       now: at(15), calendar: calendar))
        #expect(balance.display.deficit == -700)
        #expect(!balance.display.isDeficit)
    }

    /// Scenario 9: workout energy is already inside Active Energy and is never added again.
    @Test func workoutsAreNotCountedTwice() throws {
        var snapshot = ActivitySnapshot()
        snapshot.restingCalories = 1500
        snapshot.activeCalories = 600
        snapshot.workouts = [WorkoutSummary(id: UUID(), kind: .running, start: at(8), duration: 1800,
                                            activeCalories: 400, distanceMeters: 5000)]
        let balance = try #require(EnergyBalance.today(snapshot: snapshot, profile: nil, eaten: 1000,
                                                       now: at(20), calendar: calendar))
        #expect(balance.burnedSoFar == 2100)
        #expect(balance.display.active == 600)
    }

    /// Scenario 10: missing data never produces nonsense.
    @Test func missingDataGivesSafeResults() throws {
        // No Health, no profile: nothing to show rather than a fake deficit.
        #expect(EnergyBalance.today(snapshot: ActivitySnapshot(), profile: nil, eaten: 0, now: at(9), calendar: calendar) == nil)
        // Profile only, nothing eaten yet, no active energy: a labelled estimate.
        let balance = try #require(EnergyBalance.today(snapshot: ActivitySnapshot(), profile: profile, eaten: 0,
                                                       now: at(0), calendar: calendar))
        #expect(balance.source == .profile)
        #expect(!balance.hasActiveData)
        #expect(balance.display.deficit == 0)
        #expect(balance.deficitNow.isFinite && balance.deficitEndOfDay.isFinite)
        // Negative inputs from a broken source are clamped.
        var odd = ActivitySnapshot()
        odd.activeCalories = -50
        let clamped = try #require(EnergyBalance.today(snapshot: odd, profile: profile, eaten: -10, now: at(12), calendar: calendar))
        #expect(clamped.active == 0 && clamped.eaten == 0)
        // An empty week has no averages.
        #expect(WeekEnergySummary([]) == nil)
    }

    /// Scenario 11: a snapshot read yesterday is not presented as today's data.
    @Test func snapshotFromYesterdayIsIgnoredAfterMidnight() throws {
        var snapshot = ActivitySnapshot()
        snapshot.day = calendar.startOfDay(for: at(12, day: 10))
        snapshot.restingCalories = 1900
        snapshot.activeCalories = 700
        let balance = try #require(EnergyBalance.today(snapshot: snapshot, profile: profile, eaten: 300,
                                                       now: at(6), calendar: calendar))
        #expect(balance.source == .profile)
        #expect(balance.active == 0)
    }

    /// Scenario 11: daylight-saving days are 23 or 25 hours long.
    @Test func dayFractionUsesTheRealLengthOfTheDay() throws {
        var kyiv = Calendar(identifier: .gregorian)
        kyiv.timeZone = try #require(TimeZone(identifier: "Europe/Kyiv"))
        // 29 March 2026: clocks go forward at 03:00, the day has 23 hours.
        let noon = try #require(kyiv.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12)))
        let fraction = EnergyBalance.dayFraction(at: noon, calendar: kyiv)
        #expect(abs(fraction - 11.0 / 23.0) < 1e-9)
        // 25 October 2026: clocks go back, the day has 25 hours.
        let lateEvening = try #require(kyiv.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 30)))
        #expect(EnergyBalance.dayFraction(at: lateEvening, calendar: kyiv) < 1)
    }

    @Test func weekSummaryAveragesOnlyFinishedDays() throws {
        let today = calendar.startOfDay(for: at(20))
        let d1 = calendar.date(byAdding: .day, value: -1, to: today)!
        let d2 = calendar.date(byAdding: .day, value: -2, to: today)!
        let days = [
            DayBalance(day: d2, eaten: 2000, burned: 2600, isToday: false, restingSource: .health),
            DayBalance(day: d1, eaten: 2400, burned: 2600, isToday: false, restingSource: .health),
            DayBalance(day: today, eaten: 500, burned: 1800, isToday: true, restingSource: .health)
        ]
        let week = try #require(WeekEnergySummary(days))
        #expect(week.days == 2)
        #expect(week.averageEaten == 2200)
        #expect(week.averageBurned == 2600)
        #expect(week.averageDeficit == 400)
        #expect(abs(week.estimatedWeightChangeKG - (-800.0 / 7700)) < 1e-9)
    }

    @Test func largeDeficitNoteNeedsLoggedFoodAndARealDeficit() throws {
        var snapshot = ActivitySnapshot()
        snapshot.restingCalories = 60
        let morning = try #require(EnergyBalance.today(snapshot: snapshot, profile: profile, eaten: 0, now: at(0), calendar: calendar))
        #expect(!morning.isLargeDeficit) // nothing eaten yet, only the end-of-day estimate is large
        snapshot.restingCalories = 1800
        snapshot.activeCalories = 900
        let evening = try #require(EnergyBalance.today(snapshot: snapshot, profile: profile, eaten: 1200, now: at(21), calendar: calendar))
        #expect(evening.isLargeDeficit)
    }
}
